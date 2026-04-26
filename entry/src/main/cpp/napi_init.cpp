// 在包含 hilog/log.h 之前定义 LOG_DOMAIN 和 LOG_TAG
// 这样头文件中的默认宏定义 (#define LOG_DOMAIN 0, #define LOG_TAG NULL) 就不会生效
#define LOG_DOMAIN 0xFF00
#define LOG_TAG "P7ZipBridge"

#include <atomic>
#include <chrono>
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

// 原子标志，用于跟踪是否有操作正在进行（用于安全卸载）
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
    
    // --- 参数验证 ---
    // 密码不能包含空格
    if (!ctx->password.empty() && ctx->password.find(' ') != std::string::npos) {
        ctx->exitCode = -20;
        ctx->errorMsg = "Password must not contain spaces";
        OH_LOG_ERROR(LOG_APP, "%{public}s", ctx->errorMsg.c_str());
        return;
    }
    
    // level 参数不能包含空格
    if (!ctx->level.empty() && ctx->level.find(' ') != std::string::npos) {
        ctx->exitCode = -21;
        ctx->errorMsg = "Level must not contain spaces";
        OH_LOG_ERROR(LOG_APP, "%{public}s", ctx->errorMsg.c_str());
        return;
    }
    
    // 如果是解压操作，先确保目标目录存在（递归创建多级目录）
    if (ctx->operation == "extract") {
        if (!CreateDirectoryRecursive(ctx->destPath)) {
            ctx->exitCode = -10;
            ctx->errorMsg = "Failed to create destination directory: " + ctx->destPath + 
                            ", error: " + std::to_string(errno);
            OH_LOG_ERROR(LOG_APP, "%{public}s", ctx->errorMsg.c_str());
            return;
        }
        OH_LOG_INFO(LOG_APP, "Created or verified destination directory: %{public}s", ctx->destPath.c_str());
    }
    
    // 确保库已加载（线程安全）
    EnsureLibraryLoaded();
    if (!g_libraryLoaded || g_p7zipHandle == nullptr || g_p7zipMain == nullptr) {
        ctx->exitCode = -1;
        ctx->errorMsg = "Failed to load lib7za.so library";
        OH_LOG_ERROR(LOG_APP, "%{public}s", ctx->errorMsg.c_str());
        return;
    }

    // --- 构建命令行参数 ---
    std::vector<std::string> argStorage;
    std::vector<const char*> argv;
    
    argStorage.push_back("7za"); // 程序名占位符
    
    if (ctx->operation == "compress") {
        // 压缩命令: 7za a [options] archive.7z file1 file2 ...
        argStorage.push_back("a");
        
        // 格式
        if (!ctx->format.empty()) {
            argStorage.push_back("-t" + ctx->format);
        }
        
        // 压缩级别
        if (!ctx->level.empty()) {
            argStorage.push_back(ctx->level);
        }
        
        // 密码
        if (!ctx->password.empty()) {
            argStorage.push_back("-p" + ctx->password);
        }
        
        // 目标压缩包
        argStorage.push_back(ctx->destPath);
        
        // 源文件
        for (const auto& src : ctx->srcPaths) {
            argStorage.push_back(src);
        }
        
    } else if (ctx->operation == "extract") {
        // 解压命令: 7za x [options] archive.7z -ooutputDir
        argStorage.push_back("x");
        argStorage.push_back("-y");  // 自动同意覆盖
        
        if (!ctx->password.empty()) {
            argStorage.push_back("-p" + ctx->password);
        }
        
        if (!ctx->srcPaths.empty()) {
            argStorage.push_back(ctx->srcPaths[0]);
        }
        
        argStorage.push_back("-o" + ctx->destPath);
    }
    
    // 获取 C 字符串指针
    for (const auto& arg : argStorage) {
        argv.push_back(arg.c_str());
    }

    // --- 安全日志打印（隐藏密码） ---
    OH_LOG_INFO(LOG_APP, "Executing p7zip with %{public}zu args for operation: %{public}s", 
                argv.size(), ctx->operation.c_str());
    OH_LOG_INFO(LOG_APP, "argStorage contents (sanitized):");
    for (size_t i = 0; i < argStorage.size(); i++) {
        if (argStorage[i].size() > 2 && argStorage[i][0] == '-' && argStorage[i][1] == 'p') {
            OH_LOG_INFO(LOG_APP, "  argStorage[%{public}zu] = \"-p****\"", i);
        } else {
            OH_LOG_INFO(LOG_APP, "  argStorage[%{public}zu] = \"%{public}s\"", i, argStorage[i].c_str());
        }
    }
    
    // --- 加锁并调用 p7zip main ---
    {
        std::lock_guard<std::mutex> lock(g_p7zipMutex);
        (void)lock; // 消除未使用变量警告
        // 或者使用 C++17 属性：[[maybe_unused]] std::lock_guard<std::mutex> lock(...);
        // 再次检查库句柄，防止卸载竞态
        if (!g_p7zipMain || !g_p7zipHandle) {
            ctx->exitCode = -1;
            ctx->errorMsg = "Library has been unloaded";
            OH_LOG_ERROR(LOG_APP, "%{public}s", ctx->errorMsg.c_str());
            return;
        }
        
        g_activeOperations++;
        ctx->exitCode = g_p7zipMain(static_cast<int>(argv.size()), argv.data());
        g_activeOperations--;
    }

    // --- 处理结果 ---
    if (ctx->exitCode != 0) {
        ctx->errorMsg = "p7zip operation failed with exit code: " + std::to_string(ctx->exitCode);
        OH_LOG_ERROR(LOG_APP, "%{public}s", ctx->errorMsg.c_str());
        if (ctx->exitCode == 7) {
            OH_LOG_ERROR(LOG_APP, "Exit code 7 indicates command line parameter error");
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

    if (status != napi_ok) {
        // 异步工作被取消或失败，必须 settle promise，否则会导致 Promise 永久悬挂
        OH_LOG_ERROR(LOG_APP, "Async work cancelled or failed, status: %{public}d", status);
        napi_value errorMsg;
        napi_status napiStatus = napi_create_string_utf8(env, "Operation cancelled or failed", 
                                                          NAPI_AUTO_LENGTH, &errorMsg);
        if (napiStatus == napi_ok) {
            napi_reject_deferred(env, ctx->deferred, errorMsg);
        } else {
            // 创建默认错误消息失败，再尝试一次简短的
            OH_LOG_ERROR(LOG_APP, "Failed to create error message for cancelled operation");
            napiStatus = napi_create_string_utf8(env, "Cancel", NAPI_AUTO_LENGTH, &errorMsg);
            if (napiStatus == napi_ok) {
                napi_reject_deferred(env, ctx->deferred, errorMsg);
            }
            // 若仍然失败，则无法 settle promise，但已无更好的办法，只记录日志
        }
        napi_delete_async_work(env, ctx->work);
        delete ctx;
        return;
    }
    
    // 正常完成，根据 exitCode 处理结果
    if (ctx->exitCode == 0) {
        napi_value result;
        napi_status napiStatus = napi_get_boolean(env, true, &result);
        if (napiStatus == napi_ok) {
            napiStatus = napi_resolve_deferred(env, ctx->deferred, result);
            if (napiStatus != napi_ok) {
                OH_LOG_ERROR(LOG_APP, "Failed to resolve promise, status: %{public}d", napiStatus);
            }
        } else {
            OH_LOG_ERROR(LOG_APP, "Failed to create boolean result");
            napi_value errorMsg;
            napiStatus = napi_create_string_utf8(env, "Internal error: failed to create result", 
                                                  NAPI_AUTO_LENGTH, &errorMsg);
            if (napiStatus == napi_ok) {
                napi_reject_deferred(env, ctx->deferred, errorMsg);
            }
        }
    } else {
        napi_value errorMsg;
        napi_status napiStatus = napi_create_string_utf8(env, ctx->errorMsg.c_str(), 
                                                          NAPI_AUTO_LENGTH, &errorMsg);
        if (napiStatus == napi_ok) {
            napiStatus = napi_reject_deferred(env, ctx->deferred, errorMsg);
            if (napiStatus != napi_ok) {
                OH_LOG_ERROR(LOG_APP, "Failed to reject promise, status: %{public}d", napiStatus);
            }
        } else {
            OH_LOG_ERROR(LOG_APP, "Failed to create error message");
            napiStatus = napi_create_string_utf8(env, "Operation failed with unknown error", 
                                                  NAPI_AUTO_LENGTH, &errorMsg);
            if (napiStatus == napi_ok) {
                napi_reject_deferred(env, ctx->deferred, errorMsg);
            }
        }
    }
    
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
 * 从 NAPI 值安全获取 std::string
 */
static std::string GetStringFromNapiValue(napi_env env, napi_value value) {
    if (value == nullptr) return "";
    
    napi_valuetype type;
    if (napi_typeof(env, value, &type) != napi_ok) {
        return "";
    }
    
    if (type != napi_string) {
        napi_value strValue;
        if (napi_coerce_to_string(env, value, &strValue) != napi_ok) {
            return "";
        }
        value = strValue;
    }
    
    size_t len = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &len) != napi_ok) {
        return "";
    }
    
    std::string result(len, '\0');
    if (len > 0) {
        if (napi_get_value_string_utf8(env, value, &result[0], len + 1, &len) != napi_ok) {
            return "";
        }
    }
    return result;
}

/**
 * compress - 压缩文件或目录
 */
static napi_value Compress(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok) {
        napi_throw_error(env, nullptr, "Failed to get callback info");
        return nullptr;
    }
    if (argc < 2) {
        napi_throw_error(env, nullptr, "Wrong number of arguments");
        return nullptr;
    }

    bool isArray = false;
    if (napi_is_array(env, args[0], &isArray) != napi_ok || !isArray) {
        napi_throw_type_error(env, nullptr, "First argument must be an array");
        return nullptr;
    }

    uint32_t arrayLength = 0;
    if (napi_get_array_length(env, args[0], &arrayLength) != napi_ok) {
        napi_throw_error(env, nullptr, "Failed to get array length");
        return nullptr;
    }

    std::vector<std::string> srcPaths;
    for (uint32_t i = 0; i < arrayLength; i++) {
        napi_value element;
        if (napi_get_element(env, args[0], i, &element) != napi_ok) {
            napi_throw_error(env, nullptr, "Failed to get array element");
            return nullptr;
        }
        srcPaths.push_back(GetStringFromNapiValue(env, element));
    }
    if (srcPaths.empty()) {
        napi_throw_error(env, nullptr, "Source paths array must not be empty");
        return nullptr;
    }

    std::string destPath = GetStringFromNapiValue(env, args[1]);
    if (destPath.empty()) {
        napi_throw_error(env, nullptr, "Destination path cannot be empty");
        return nullptr;
    }

    // 解析选项
    std::string format = "7z";
    std::string password;
    std::string level = "-mx=5";
    
    if (argc >= 3) {
        napi_valuetype type;
        if (napi_typeof(env, args[2], &type) == napi_ok && type == napi_object) {
            napi_value val;
            bool hasProp = false;

            if (napi_has_named_property(env, args[2], "format", &hasProp) == napi_ok && hasProp) {
                if (napi_get_named_property(env, args[2], "format", &val) == napi_ok) {
                    format = GetStringFromNapiValue(env, val);
                }
            }
            
            if (napi_has_named_property(env, args[2], "password", &hasProp) == napi_ok && hasProp) {
                if (napi_get_named_property(env, args[2], "password", &val) == napi_ok) {
                    password = GetStringFromNapiValue(env, val);
                }
            }
            
            if (napi_has_named_property(env, args[2], "level", &hasProp) == napi_ok && hasProp) {
                if (napi_get_named_property(env, args[2], "level", &val) == napi_ok) {
                    std::string levelStr = GetStringFromNapiValue(env, val);
                    // 仅当非空时才覆盖默认值，避免产生无效的 "-mx="
                    if (!levelStr.empty()) {
                        level = "-mx=" + levelStr;
                    }
                }
            }
        }
    }

    // 验证
    if (!password.empty() && password.find(' ') != std::string::npos) {
        napi_throw_error(env, nullptr, "Password must not contain spaces");
        return nullptr;
    }
    if (!format.empty() && format.find(' ') != std::string::npos) {
        napi_throw_error(env, nullptr, "Format must not contain spaces");
        return nullptr;
    }
    if (!format.empty() && !IsSupportedFormat(format)) {
        napi_throw_error(env, nullptr, ("Unsupported compression format: " + format).c_str());
        return nullptr;
    }

    // 创建 Promise
    napi_deferred deferred;
    napi_value promise;
    if (napi_create_promise(env, &deferred, &promise) != napi_ok) {
        napi_throw_error(env, nullptr, "Failed to create promise");
        return nullptr;
    }

    AsyncWorkContext* ctx = new (std::nothrow) AsyncWorkContext();
    if (!ctx) {
        napi_throw_error(env, nullptr, "Failed to allocate memory");
        return nullptr;
    }
    ctx->env = env;
    ctx->deferred = deferred;
    ctx->operation = "compress";
    ctx->srcPaths = std::move(srcPaths);
    ctx->destPath = std::move(destPath);
    ctx->format = std::move(format);
    ctx->password = std::move(password);
    ctx->level = std::move(level);

    napi_value resourceName;
    if (napi_create_string_utf8(env, "CompressOperation", NAPI_AUTO_LENGTH, &resourceName) != napi_ok) {
        delete ctx;
        napi_throw_error(env, nullptr, "Failed to create resource name");
        return nullptr;
    }
    if (napi_create_async_work(env, nullptr, resourceName,
                               ExecuteP7ZipOperation,
                               OnP7ZipOperationComplete,
                               ctx, &ctx->work) != napi_ok) {
        delete ctx;
        napi_throw_error(env, nullptr, "Failed to create async work");
        return nullptr;
    }
    if (napi_queue_async_work(env, ctx->work) != napi_ok) {
        napi_delete_async_work(env, ctx->work);
        delete ctx;
        napi_throw_error(env, nullptr, "Failed to queue async work");
        return nullptr;
    }
    return promise;
}

/**
 * extract - 解压压缩包
 */
static napi_value Extract(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok) {
        napi_throw_error(env, nullptr, "Failed to get callback info");
        return nullptr;
    }
    if (argc < 2) {
        napi_throw_error(env, nullptr, "Wrong number of arguments");
        return nullptr;
    }

    std::string archivePath = GetStringFromNapiValue(env, args[0]);
    if (archivePath.empty()) {
        napi_throw_error(env, nullptr, "Archive path cannot be empty");
        return nullptr;
    }
    std::string destDir = GetStringFromNapiValue(env, args[1]);
    if (destDir.empty()) {
        napi_throw_error(env, nullptr, "Destination directory cannot be empty");
        return nullptr;
    }
    std::string password;
    if (argc >= 3) {
        password = GetStringFromNapiValue(env, args[2]);
    }
    if (!password.empty() && password.find(' ') != std::string::npos) {
        napi_throw_error(env, nullptr, "Password must not contain spaces");
        return nullptr;
    }

    napi_deferred deferred;
    napi_value promise;
    if (napi_create_promise(env, &deferred, &promise) != napi_ok) {
        napi_throw_error(env, nullptr, "Failed to create promise");
        return nullptr;
    }

    AsyncWorkContext* ctx = new (std::nothrow) AsyncWorkContext();
    if (!ctx) {
        napi_throw_error(env, nullptr, "Failed to allocate memory");
        return nullptr;
    }
    ctx->env = env;
    ctx->deferred = deferred;
    ctx->operation = "extract";
    ctx->srcPaths.push_back(archivePath);
    ctx->destPath = destDir;
    ctx->password = password;

    napi_value resourceName;
    if (napi_create_string_utf8(env, "ExtractOperation", NAPI_AUTO_LENGTH, &resourceName) != napi_ok) {
        delete ctx;
        napi_throw_error(env, nullptr, "Failed to create resource name");
        return nullptr;
    }
    if (napi_create_async_work(env, nullptr, resourceName,
                               ExecuteP7ZipOperation,
                               OnP7ZipOperationComplete,
                               ctx, &ctx->work) != napi_ok) {
        delete ctx;
        napi_throw_error(env, nullptr, "Failed to create async work");
        return nullptr;
    }
    if (napi_queue_async_work(env, ctx->work) != napi_ok) {
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
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
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
 * 模块卸载时安全清理
 */
static void CleanupP7ZipLibrary() {
    // 等待所有正在进行的操作完成（最多5秒）
    int maxWaitMs = 5000;
    int waited = 0;
    while (g_activeOperations > 0 && waited < maxWaitMs) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        waited += 100;
    }
    if (g_activeOperations > 0) {
        OH_LOG_WARN(LOG_APP, "Unloading library with %{public}d active operations", 
                    g_activeOperations.load());
    }
    
    // 加锁后清理
    {
        std::lock_guard<std::mutex> lock(g_p7zipMutex);
        (void)lock;
        if (g_p7zipHandle) {
            dlclose(g_p7zipHandle);
            g_p7zipHandle = nullptr;
            g_p7zipMain = nullptr;
            g_libraryLoaded = false;
            OH_LOG_INFO(LOG_APP, "Unloaded lib7za.so");
        }
    }
}

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
    napi_module_register(&demoModule);
}

extern "C" __attribute__((destructor)) void UnregisterEntryModule(void) {
    CleanupP7ZipLibrary();
}