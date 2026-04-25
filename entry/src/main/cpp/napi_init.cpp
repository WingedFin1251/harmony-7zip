// 在包含 hilog/log.h 之前定义 LOG_DOMAIN 和 LOG_TAG
// 这样头文件中的默认宏定义 (#define LOG_DOMAIN 0, #define LOG_TAG NULL) 就不会生效
#define LOG_DOMAIN 0xFF00
#define LOG_TAG "P7ZipBridge"

#include <atomic>
#include <thread>
#include <vector>
#include <string>
#include <cstdlib>
#include <mutex>
#include <unordered_set>
#include <sys/stat.h>
#include <errno.h>
#include <hilog/log.h>
#include "napi/native_api.h"
#include <dlfcn.h>

// 定义 p7zip main 函数类型
typedef int (*p7zip_main_t)(int argc, const char* argv[]);

// 全局互斥锁，保护 p7zipMain 调用
static std::mutex g_p7zipMutex;

// 全局库句柄和函数指针，避免频繁 dlopen/dlclose
static void* g_p7zipHandle = nullptr;
static p7zip_main_t g_p7zipMain = nullptr;
static std::once_flag g_initFlag;
static std::atomic<bool> g_libraryLoaded{false};

// 原子标志，用于跟踪是否有操作正在进行
static std::atomic<int> g_activeOperations{0};

/**
 * 确保库只被加载一次（线程安全）
 */
static void EnsureLibraryLoaded() {
    std::call_once(g_initFlag, [](){
        g_p7zipHandle = dlopen("lib7za.so", RTLD_NOW);
        if (!g_p7zipHandle) {
            OH_LOG_ERROR(LOG_APP, "Failed to load lib7za.so: %{public}s", dlerror());
            return;
        }
        
        g_p7zipMain = (p7zip_main_t)dlsym(g_p7zipHandle, "main");
        if (!g_p7zipMain) {
            OH_LOG_ERROR(LOG_APP, "Failed to find 'main' function: %{public}s", dlerror());
            dlclose(g_p7zipHandle);
            g_p7zipHandle = nullptr;
            return;
        }
        
        g_libraryLoaded = true;
        OH_LOG_INFO(LOG_APP, "Loaded lib7za.so successfully");
    });
}

/**
 * 递归创建目录（类似 mkdir -p）
 */
static bool CreateDirectoryRecursive(const std::string& path) {
    if (path.empty()) {
        return false;
    }
    
    // 检查目录是否已存在
    struct stat st;
    if (stat(path.c_str(), &st) == 0) {
        if (S_ISDIR(st.st_mode)) {
            return true; // 目录已存在
        }
        return false; // 路径存在但不是目录
    }
    
    // 创建父目录
    size_t pos = path.find_last_of('/');
    if (pos != std::string::npos) {
        std::string parent = path.substr(0, pos);
        if (!parent.empty() && !CreateDirectoryRecursive(parent)) {
            return false;
        }
    }
    
    // 创建当前目录
    if (mkdir(path.c_str(), 0755) != 0) {
        if (errno == EEXIST) {
            // 检查是否真的是目录
            if (stat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode)) {
                return true;
            }
            return false; // 存在但不是目录
        }
        return false; // 创建失败
    }
    
    return true;
}

/**
 * 异步工作上下文
 */
struct AsyncWorkContext {
    napi_env env;
    napi_async_work work;
    napi_deferred deferred;

    // 操作类型
    std::string operation; // "compress" 或 "extract"
    
    // 参数（使用 std::string 持久化存储，避免悬空指针）
    std::vector<std::string> srcPaths; // 源路径（压缩时为多个，解压时为一个）
    std::string destPath;              // 目标路径（压缩包路径或解压目录）
    std::string format;                // 压缩格式，如 "7z", "zip"
    std::string password;              // 密码（可选）
    std::string level;                 // 压缩级别，如 "-mx=9"

    // 结果
    int exitCode;
    std::string errorMsg;
};

/**
 * 工作线程函数：执行实际的压缩或解压
 */
static void ExecuteP7ZipOperation(napi_env env, void* data) {
    (void)env; // 避免未使用参数警告
    AsyncWorkContext* ctx = static_cast<AsyncWorkContext*>(data);
    
    // 0. 验证参数：密码不能包含空格
    if (!ctx->password.empty() && ctx->password.find(' ') != std::string::npos) {
        ctx->exitCode = -20;
        ctx->errorMsg = "Password must not contain spaces";
        OH_LOG_ERROR(LOG_APP, "%{public}s", ctx->errorMsg.c_str());
        return;
    }
    
    // 1. 如果是解压操作，先确保目标目录存在
    if (ctx->operation == "extract") {
        // 7-Zip 的 x 命令要求 -o 指定的顶层目录必须已经存在
        // 使用递归创建目录，确保多级目录都能被创建
        if (!CreateDirectoryRecursive(ctx->destPath)) {
            ctx->exitCode = -10;
            ctx->errorMsg = "Failed to create destination directory: " + ctx->destPath + ", error: " + std::to_string(errno);
            OH_LOG_ERROR(LOG_APP, "%{public}s", ctx->errorMsg.c_str());
            return;
        }
        OH_LOG_INFO(LOG_APP, "Created or verified destination directory: %{public}s", ctx->destPath.c_str());
    }
    
    // 1. 确保库已加载（线程安全）
    EnsureLibraryLoaded();
    if (!g_libraryLoaded || g_p7zipHandle == nullptr || g_p7zipMain == nullptr) {
        ctx->exitCode = -1;
        ctx->errorMsg = "Failed to load lib7za.so library";
        OH_LOG_ERROR(LOG_APP, "%{public}s", ctx->errorMsg.c_str());
        return;
    }

    // 3. 根据操作类型构建命令行参数
    // 使用 std::vector<std::string> 持久化存储所有字符串，避免悬空指针
    std::vector<std::string> argStorage;
    std::vector<const char*> argv;
    
    // 先构建所有字符串到 argStorage
    argStorage.push_back("7za"); // 程序名占位符
    
    if (ctx->operation == "compress") {
        // 压缩命令: 7za a [options] archive.7z file1 file2 ...
        argStorage.push_back("a");
        
        // 添加格式选项，例如 "-t7z" 或 "-tzip"
        if (!ctx->format.empty()) {
            argStorage.push_back("-t" + ctx->format);
        }
        
        // 添加压缩级别，例如 "-mx=9"
        if (!ctx->level.empty()) {
            argStorage.push_back(ctx->level);
        }
        
        // 添加密码选项
        if (!ctx->password.empty()) {
            argStorage.push_back("-p" + ctx->password);
        }
        
        // 目标压缩包路径
        argStorage.push_back(ctx->destPath);
        
        // 所有源文件路径
        for (const auto& src : ctx->srcPaths) {
            argStorage.push_back(src);
        }
        
    } else if (ctx->operation == "extract") {
        // 解压命令: 7za x [options] archive.7z -ooutputDir
        argStorage.push_back("x");
        
        // 添加覆盖选项 (-y 表示全部同意)
        argStorage.push_back("-y");
        
        // 添加密码选项
        if (!ctx->password.empty()) {
            argStorage.push_back("-p" + ctx->password);
        }
        
        // 源压缩包路径（解压时只有一个源）
        if (!ctx->srcPaths.empty()) {
            argStorage.push_back(ctx->srcPaths[0]);
        }
        
        // 输出目录选项
        argStorage.push_back("-o" + ctx->destPath);
    }
    
    // 现在所有字符串都在 argStorage 中，获取它们的 C 字符串指针
    for (const auto& arg : argStorage) {
        argv.push_back(arg.c_str());
    }
    
    // 注意：p7zipMain 接收 argc 参数，不需要 NULL 哨兵
    // argv.push_back(nullptr); // 参数数组结尾（不再需要）

    // 4. 打印所有参数用于调试（避免输出密码等敏感信息）
    OH_LOG_INFO(LOG_APP, "Executing p7zip with %{public}d args for operation: %{public}s", 
                (int)(argv.size() - 1), ctx->operation.c_str());
    
    // 安全地打印参数，隐藏密码信息
    OH_LOG_INFO(LOG_APP, "argStorage contents (sanitized):");
    for (size_t i = 0; i < argStorage.size(); i++) {
        // 检查是否是密码参数，如果是则隐藏
        if (argStorage[i].size() > 2 && argStorage[i][0] == '-' && argStorage[i][1] == 'p') {
            // 密码参数，只显示前2个字符
            OH_LOG_INFO(LOG_APP, "  argStorage[%{public}zu] = \"-p****\"", i);
        } else {
            OH_LOG_INFO(LOG_APP, "  argStorage[%{public}zu] = \"%{public}s\"", i, argStorage[i].c_str());
        }
    }
    
    // 5. 调用 p7zip main 函数，使用互斥锁保护，防止并发访问
    // p7zipMain 是 C 函数，不应该抛出 C++ 异常，但我们仍然使用互斥锁保护
    std::lock_guard<std::mutex> lock(g_p7zipMutex);
    g_activeOperations++;  // 增加活动操作计数
    ctx->exitCode = g_p7zipMain(static_cast<int>(argv.size()), argv.data());
    g_activeOperations--;  // 减少活动操作计数

    if (ctx->exitCode != 0) {
        ctx->errorMsg = "p7zip operation failed with exit code: " + std::to_string(ctx->exitCode);
        OH_LOG_ERROR(LOG_APP, "%{public}s", ctx->errorMsg.c_str());
        // 如果是 exit code 7 (kUserError = 命令行参数错误)，打印详细参数信息
        if (ctx->exitCode == 7) {
            OH_LOG_ERROR(LOG_APP, "Exit code 7 indicates command line parameter error (CArcCmdLineException)");
            OH_LOG_ERROR(LOG_APP, "Operation: %{public}s", ctx->operation.c_str());
            OH_LOG_ERROR(LOG_APP, "DestPath: %{public}s", ctx->destPath.c_str());
            for (size_t i = 0; i < ctx->srcPaths.size(); i++) {
                OH_LOG_ERROR(LOG_APP, "  srcPaths[%{public}zu] = \"%{public}s\"", i, ctx->srcPaths[i].c_str());
            }
        }
    } else {
        OH_LOG_INFO(LOG_APP, "p7zip operation succeeded.");
    }
}

/**
 * 操作完成回调（在主JS线程执行）
 */
static void OnP7ZipOperationComplete(napi_env env, napi_status status, void* data) {
    AsyncWorkContext* ctx = static_cast<AsyncWorkContext*>(data);

    // 如果异步工作被取消或失败，直接清理资源，不操作 Promise
    if (status != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "Async work cancelled or failed, status: %{public}d", status);
        // 不操作 deferred，Promises 由引擎处理
        napi_delete_async_work(env, ctx->work);
        delete ctx;
        return;
    }
    
    // 只有 status == napi_ok 时才处理结果
    if (ctx->exitCode == 0) {
        napi_value result;
        napi_status napiStatus = napi_get_boolean(env, true, &result);
        if (napiStatus == napi_ok) {
            napiStatus = napi_resolve_deferred(env, ctx->deferred, result);
            if (napiStatus != napi_ok) {
                OH_LOG_ERROR(LOG_APP, "Failed to resolve promise, status: %{public}d", napiStatus);
            }
        } else {
            OH_LOG_ERROR(LOG_APP, "Failed to create boolean result, status: %{public}d", napiStatus);
            // 创建错误消息并拒绝Promise
            napi_value errorMsg;
            napiStatus = napi_create_string_utf8(env, "Internal error: failed to create result", NAPI_AUTO_LENGTH, &errorMsg);
            if (napiStatus == napi_ok) {
                napi_reject_deferred(env, ctx->deferred, errorMsg);
            }
        }
    } else {
        napi_value errorMsg;
        napi_status napiStatus = napi_create_string_utf8(env, ctx->errorMsg.c_str(), NAPI_AUTO_LENGTH, &errorMsg);
        if (napiStatus == napi_ok) {
            napiStatus = napi_reject_deferred(env, ctx->deferred, errorMsg);
            if (napiStatus != napi_ok) {
                OH_LOG_ERROR(LOG_APP, "Failed to reject promise, status: %{public}d", napiStatus);
            }
        } else {
            OH_LOG_ERROR(LOG_APP, "Failed to create error message, status: %{public}d", napiStatus);
            // 创建默认错误消息
            napiStatus = napi_create_string_utf8(env, "Operation failed with unknown error", NAPI_AUTO_LENGTH, &errorMsg);
            if (napiStatus == napi_ok) {
                napi_reject_deferred(env, ctx->deferred, errorMsg);
            }
        }
    }
    
    // 清理异步工作资源
    napi_status deleteStatus = napi_delete_async_work(env, ctx->work);
    if (deleteStatus != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "Failed to delete async work, status: %{public}d", deleteStatus);
    }
    
    delete ctx;
}

/**
 * 检查压缩格式是否受支持
 */
static bool IsSupportedFormat(const std::string& format) {
    // 7-Zip 支持的主要格式
    static const std::unordered_set<std::string> supportedFormats = {
        "7z", "zip", "gzip", "bzip2", "tar", "xz", "lzma", "cab", "arj",
        "z", "lzh", "rar", "iso", "chm", "msi", "wim", "udf", "fat",
        "ntfs", "exfat", "apfs", "hfs", "hfsx", "ext", "ext2", "ext3",
        "ext4", "squashfs", "cramfs", "vhd", "vmdk", "vdi", "qcow",
        "qcow2", "dmg", "hdd", "mbr", "gpt", "apm", "mac", "udf",
        "xar", "rpm", "deb", "cpio", "swf", "flv", "swfc", "lit"
    };
    return supportedFormats.find(format) != supportedFormats.end();
}

/**
 * 工具函数：从NAPI值获取字符串
 */
static std::string GetStringFromNapiValue(napi_env env, napi_value value) {
    if (value == nullptr) {
        return "";
    }
    
    napi_valuetype type;
    napi_status status = napi_typeof(env, value, &type);
    if (status != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "napi_typeof failed with status: %{public}d", status);
        return "";
    }
    
    if (type != napi_string) {
        // 如果不是字符串，尝试自动转换
        napi_value strValue;
        status = napi_coerce_to_string(env, value, &strValue);
        if (status != napi_ok) {
            OH_LOG_ERROR(LOG_APP, "napi_coerce_to_string failed with status: %{public}d", status);
            return "";
        }
        value = strValue;
    }
    
    size_t len = 0;
    status = napi_get_value_string_utf8(env, value, nullptr, 0, &len);
    if (status != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "napi_get_value_string_utf8 (length) failed with status: %{public}d", status);
        return "";
    }
    
    std::string result(len, '\0');
    if (len > 0) {
        size_t actualLen = 0;
        status = napi_get_value_string_utf8(env, value, &result[0], len + 1, &actualLen);
        if (status != napi_ok) {
            OH_LOG_ERROR(LOG_APP, "napi_get_value_string_utf8 failed with status: %{public}d", status);
            return "";
        }
    }
    return result;
}

/**
 * NAPI函数：compress - 压缩文件或目录
 */
static napi_value Compress(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_valuetype argTypes[3];
    
    // 获取函数参数信息
    napi_status status = napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (status != napi_ok) {
        napi_throw_error(env, nullptr, "Failed to get callback info");
        return nullptr;
    }

    if (argc < 2) {
        napi_throw_error(env, nullptr, "Wrong number of arguments. Expected at least: srcPaths[], destArchive");
        return nullptr;
    }

    // 检查第一个参数是否为数组
    status = napi_typeof(env, args[0], &argTypes[0]);
    if (status != napi_ok || argTypes[0] != napi_object) {
        napi_throw_type_error(env, nullptr, "First argument must be an array");
        return nullptr;
    }
    
    bool isArray = false;
    status = napi_is_array(env, args[0], &isArray);
    if (status != napi_ok || !isArray) {
        napi_throw_type_error(env, nullptr, "First argument must be an array");
        return nullptr;
    }

    // 1. 解析源路径数组
    uint32_t arrayLength = 0;
    status = napi_get_array_length(env, args[0], &arrayLength);
    if (status != napi_ok) {
        napi_throw_error(env, nullptr, "Failed to get array length");
        return nullptr;
    }
    
    std::vector<std::string> srcPaths;
    for (uint32_t i = 0; i < arrayLength; i++) {
        napi_value element;
        status = napi_get_element(env, args[0], i, &element);
        if (status != napi_ok) {
            napi_throw_error(env, nullptr, "Failed to get array element");
            return nullptr;
        }
        srcPaths.push_back(GetStringFromNapiValue(env, element));
    }

    // 检查源路径数组不能为空
    if (srcPaths.empty()) {
        napi_throw_error(env, nullptr, "Source paths array must not be empty");
        return nullptr;
    }

    // 2. 解析目标压缩包路径
    std::string destPath = GetStringFromNapiValue(env, args[1]);
    if (destPath.empty()) {
        napi_throw_error(env, nullptr, "Destination path cannot be empty");
        return nullptr;
    }

    // 3. 解析选项对象（第三个参数，可选）
    std::string format = "7z";
    std::string password;
    std::string level = "-mx=5"; // 默认中等压缩
    
    if (argc >= 3) {
        napi_valuetype type;
        status = napi_typeof(env, args[2], &type);
        if (status == napi_ok && type == napi_object) {
            napi_value formatVal, passwordVal, levelVal;
            bool hasProp = false;
            
            status = napi_has_named_property(env, args[2], "format", &hasProp);
            if (status == napi_ok && hasProp) {
                status = napi_get_named_property(env, args[2], "format", &formatVal);
                if (status == napi_ok) {
                    format = GetStringFromNapiValue(env, formatVal);
                }
            }
            
            status = napi_has_named_property(env, args[2], "password", &hasProp);
            if (status == napi_ok && hasProp) {
                status = napi_get_named_property(env, args[2], "password", &passwordVal);
                if (status == napi_ok) {
                    password = GetStringFromNapiValue(env, passwordVal);
                }
            }
            
            status = napi_has_named_property(env, args[2], "level", &hasProp);
            if (status == napi_ok && hasProp) {
                status = napi_get_named_property(env, args[2], "level", &levelVal);
                if (status == napi_ok) {
                    level = "-mx=" + GetStringFromNapiValue(env, levelVal);
                }
            }
        }
    }
    
    // 验证密码不能包含空格
    if (!password.empty() && password.find(' ') != std::string::npos) {
        napi_throw_error(env, nullptr, "Password must not contain spaces");
        return nullptr;
    }
    
    // 验证压缩格式不能包含空格
    if (!format.empty() && format.find(' ') != std::string::npos) {
        napi_throw_error(env, nullptr, "Format must not contain spaces");
        return nullptr;
    }
    
    // 验证压缩格式是否受支持
    if (!format.empty() && !IsSupportedFormat(format)) {
        napi_throw_error(env, nullptr, ("Unsupported compression format: " + format).c_str());
        return nullptr;
    }

    // 4. 创建异步工作和Promise
    napi_deferred deferred;
    napi_value promise;
    status = napi_create_promise(env, &deferred, &promise);
    if (status != napi_ok) {
        napi_throw_error(env, nullptr, "Failed to create promise");
        return nullptr;
    }

    AsyncWorkContext* ctx = new (std::nothrow) AsyncWorkContext();
    if (ctx == nullptr) {
        napi_throw_error(env, nullptr, "Failed to allocate memory for async context");
        return nullptr;
    }
    
    ctx->env = env;
    ctx->deferred = deferred;
    ctx->operation = "compress";
    ctx->srcPaths = srcPaths;
    ctx->destPath = destPath;
    ctx->format = format;
    ctx->password = password;
    ctx->level = level;

    napi_value resourceName;
    status = napi_create_string_utf8(env, "CompressOperation", NAPI_AUTO_LENGTH, &resourceName);
    if (status != napi_ok) {
        delete ctx;
        napi_throw_error(env, nullptr, "Failed to create resource name");
        return nullptr;
    }
    
    status = napi_create_async_work(env, nullptr, resourceName,
                                   ExecuteP7ZipOperation,
                                   OnP7ZipOperationComplete,
                                   ctx, &ctx->work);
    if (status != napi_ok) {
        delete ctx;
        napi_throw_error(env, nullptr, "Failed to create async work");
        return nullptr;
    }
    
    status = napi_queue_async_work(env, ctx->work);
    if (status != napi_ok) {
        napi_delete_async_work(env, ctx->work);
        delete ctx;
        napi_throw_error(env, nullptr, "Failed to queue async work");
        return nullptr;
    }

    return promise;
}

/**
 * NAPI函数：extract - 解压压缩包
 */
static napi_value Extract(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_valuetype argTypes[3];
    
    // 获取函数参数信息
    napi_status status = napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (status != napi_ok) {
        napi_throw_error(env, nullptr, "Failed to get callback info");
        return nullptr;
    }

    if (argc < 2) {
        napi_throw_error(env, nullptr, "Wrong number of arguments. Expected at least: archivePath, destDir");
        return nullptr;
    }

    // 1. 解析源压缩包路径
    std::string archivePath = GetStringFromNapiValue(env, args[0]);
    if (archivePath.empty()) {
        napi_throw_error(env, nullptr, "Archive path cannot be empty");
        return nullptr;
    }

    // 2. 解析目标目录
    std::string destDir = GetStringFromNapiValue(env, args[1]);
    if (destDir.empty()) {
        napi_throw_error(env, nullptr, "Destination directory cannot be empty");
        return nullptr;
    }

    // 3. 解析密码（第三个参数，可选）
    std::string password;
    if (argc >= 3) {
        password = GetStringFromNapiValue(env, args[2]);
    }
    
    // 验证密码不能包含空格
    if (!password.empty() && password.find(' ') != std::string::npos) {
        napi_throw_error(env, nullptr, "Password must not contain spaces");
        return nullptr;
    }

    // 4. 创建异步工作和Promise
    napi_deferred deferred;
    napi_value promise;
    status = napi_create_promise(env, &deferred, &promise);
    if (status != napi_ok) {
        napi_throw_error(env, nullptr, "Failed to create promise");
        return nullptr;
    }

    AsyncWorkContext* ctx = new (std::nothrow) AsyncWorkContext();
    if (ctx == nullptr) {
        napi_throw_error(env, nullptr, "Failed to allocate memory for async context");
        return nullptr;
    }
    
    ctx->env = env;
    ctx->deferred = deferred;
    ctx->operation = "extract";
    ctx->srcPaths.push_back(archivePath);
    ctx->destPath = destDir;
    ctx->password = password;

    napi_value resourceName;
    status = napi_create_string_utf8(env, "ExtractOperation", NAPI_AUTO_LENGTH, &resourceName);
    if (status != napi_ok) {
        delete ctx;
        napi_throw_error(env, nullptr, "Failed to create resource name");
        return nullptr;
    }
    
    status = napi_create_async_work(env, nullptr, resourceName,
                                   ExecuteP7ZipOperation,
                                   OnP7ZipOperationComplete,
                                   ctx, &ctx->work);
    if (status != napi_ok) {
        delete ctx;
        napi_throw_error(env, nullptr, "Failed to create async work");
        return nullptr;
    }
    
    status = napi_queue_async_work(env, ctx->work);
    if (status != napi_ok) {
        napi_delete_async_work(env, ctx->work);
        delete ctx;
        napi_throw_error(env, nullptr, "Failed to queue async work");
        return nullptr;
    }

    return promise;
}

/**
 * 模块初始化
 */
EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"compress", nullptr, Compress, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"extract", nullptr, Extract, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    
    napi_status status = napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    if (status != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "Failed to define properties, status: %{public}d", status);
        // 返回原始exports，不抛出错误，因为这是模块初始化
    }
    
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void*)0),
    .reserved = {0},
};

/**
 * 模块卸载清理函数
 */
static void CleanupP7ZipLibrary() {
    // 等待所有活动操作完成
    int maxWaitTime = 5000; // 最多等待5秒
    int waitInterval = 100; // 每次等待100毫秒
    int totalWaited = 0;
    
    while (g_activeOperations > 0 && totalWaited < maxWaitTime) {
        // 使用简单的忙等待，在模块卸载时这是可以接受的
        std::this_thread::sleep_for(std::chrono::milliseconds(waitInterval));
        totalWaited += waitInterval;
    }
    
    if (g_activeOperations > 0) {
        OH_LOG_WARN(LOG_APP, "Force unloading library while %{public}d operations are still active", 
                   g_activeOperations.load());
    }
    
    // 获取互斥锁以确保没有并发访问
    std::lock_guard<std::mutex> lock(g_p7zipMutex);
    
    if (g_p7zipHandle != nullptr) {
        dlclose(g_p7zipHandle);
        g_p7zipHandle = nullptr;
        g_p7zipMain = nullptr;
        g_libraryLoaded = false;
        
        OH_LOG_INFO(LOG_APP, "Unloaded lib7za.so");
    }
}

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
    napi_module_register(&demoModule);
}

// 注册模块卸载时的清理函数
extern "C" __attribute__((destructor)) void UnregisterEntryModule(void) {
    CleanupP7ZipLibrary();
}
