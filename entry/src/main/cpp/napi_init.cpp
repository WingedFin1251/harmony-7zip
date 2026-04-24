// 在包含 hilog/log.h 之前定义 LOG_DOMAIN 和 LOG_TAG
// 这样头文件中的默认宏定义 (#define LOG_DOMAIN 0, #define LOG_TAG NULL) 就不会生效
#define LOG_DOMAIN 0xFF00
#define LOG_TAG "P7ZipBridge"

#include <thread>
#include <vector>
#include <string>
#include <hilog/log.h>
#include "napi/native_api.h"
#include <dlfcn.h>

// 定义 p7zip main 函数类型
typedef int (*p7zip_main_t)(int argc, const char* argv[]);

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
    AsyncWorkContext* ctx = static_cast<AsyncWorkContext*>(data);
    
    // 0. 如果是解压操作，先确保目标目录存在
    if (ctx->operation == "extract") {
        // 使用 mkdir 创建目标目录（如果不存在）
        std::string mkdirCmd = "mkdir -p " + ctx->destPath;
        int mkdirRet = system(mkdirCmd.c_str());
        if (mkdirRet != 0) {
            OH_LOG_WARN(LOG_APP, "mkdir returned %{public}d for path: %{public}s", mkdirRet, ctx->destPath.c_str());
        }
    }
    
    // 1. 动态加载 p7zip 库
    void* libHandle = dlopen("lib7za.so", RTLD_LAZY);
    if (libHandle == nullptr) {
        ctx->exitCode = -1;
        ctx->errorMsg = "Failed to load lib7za.so: ";
        ctx->errorMsg += dlerror();
        OH_LOG_ERROR(LOG_APP, "%{public}s", ctx->errorMsg.c_str());
        return;
    }

    // 2. 获取 main 函数
    auto p7zipMain = (p7zip_main_t)dlsym(libHandle, "main");
    if (p7zipMain == nullptr) {
        ctx->exitCode = -2;
        ctx->errorMsg = "Failed to find 'main' function: ";
        ctx->errorMsg += dlerror();
        dlclose(libHandle);
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
    
    argv.push_back(nullptr); // 参数数组结尾

    // 4. 打印所有参数用于调试
    OH_LOG_INFO(LOG_APP, "Executing p7zip with %{public}d args:", (int)(argv.size() - 1));
    // 先打印 argStorage 的内容
    OH_LOG_INFO(LOG_APP, "argStorage contents:");
    for (size_t i = 0; i < argStorage.size(); i++) {
        OH_LOG_INFO(LOG_APP, "  argStorage[%{public}zu] = \"%{public}s\"", i, argStorage[i].c_str());
    }
    // 再打印 argv 的内容
    OH_LOG_INFO(LOG_APP, "argv contents:");
    for (int i = 0; i < static_cast<int>(argv.size() - 1); i++) {
        OH_LOG_INFO(LOG_APP, "  argv[%{public}d] = \"%{public}s\"", i, argv[i]);
    }
    
    // 5. 调用 p7zip main 函数，使用 try-catch 保护
    try {
        ctx->exitCode = p7zipMain(static_cast<int>(argv.size() - 1), argv.data());
    } catch (const std::exception& e) {
        ctx->exitCode = -3;
        ctx->errorMsg = "p7zip main threw exception: ";
        ctx->errorMsg += e.what();
        OH_LOG_ERROR(LOG_APP, "%{public}s", ctx->errorMsg.c_str());
        dlclose(libHandle);
        return;
    } catch (...) {
        ctx->exitCode = -4;
        ctx->errorMsg = "p7zip main threw unknown exception";
        OH_LOG_ERROR(LOG_APP, "%{public}s", ctx->errorMsg.c_str());
        dlclose(libHandle);
        return;
    }
    
    // 5. 清理库句柄
    dlclose(libHandle);

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
    
    if (ctx->exitCode == 0) {
        napi_value result;
        napi_get_boolean(env, true, &result);
        napi_resolve_deferred(env, ctx->deferred, result);
    } else {
        napi_value errorMsg;
        napi_create_string_utf8(env, ctx->errorMsg.c_str(), NAPI_AUTO_LENGTH, &errorMsg);
        napi_reject_deferred(env, ctx->deferred, errorMsg);
    }
    
    napi_delete_async_work(env, ctx->work);
    delete ctx;
}

/**
 * 工具函数：从NAPI值获取字符串
 */
static std::string GetStringFromNapiValue(napi_env env, napi_value value) {
    if (value == nullptr) {
        return "";
    }
    size_t len = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &len);
    std::string result(len, '\0');
    if (len > 0) {
        napi_get_value_string_utf8(env, value, &result[0], len + 1, &len);
    }
    return result;
}

/**
 * NAPI函数：compress - 压缩文件或目录
 */
static napi_value Compress(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 2) {
        napi_throw_error(env, nullptr, "Wrong number of arguments. Expected at least: srcPaths[], destArchive");
        return nullptr;
    }

    // 1. 解析源路径数组
    uint32_t arrayLength = 0;
    napi_get_array_length(env, args[0], &arrayLength);
    std::vector<std::string> srcPaths;
    for (uint32_t i = 0; i < arrayLength; i++) {
        napi_value element;
        napi_get_element(env, args[0], i, &element);
        srcPaths.push_back(GetStringFromNapiValue(env, element));
    }

    // 2. 解析目标压缩包路径
    std::string destPath = GetStringFromNapiValue(env, args[1]);

    // 3. 解析选项对象（第三个参数，可选）
    std::string format = "7z";
    std::string password;
    std::string level = "-mx=5"; // 默认中等压缩
    
    if (argc >= 3) {
        napi_valuetype type;
        napi_typeof(env, args[2], &type);
        if (type == napi_object) {
            napi_value formatVal, passwordVal, levelVal;
            bool hasProp = false;
            
            napi_has_named_property(env, args[2], "format", &hasProp);
            if (hasProp) {
                napi_get_named_property(env, args[2], "format", &formatVal);
                format = GetStringFromNapiValue(env, formatVal);
            }
            
            napi_has_named_property(env, args[2], "password", &hasProp);
            if (hasProp) {
                napi_get_named_property(env, args[2], "password", &passwordVal);
                password = GetStringFromNapiValue(env, passwordVal);
            }
            
            napi_has_named_property(env, args[2], "level", &hasProp);
            if (hasProp) {
                napi_get_named_property(env, args[2], "level", &levelVal);
                level = "-mx=" + GetStringFromNapiValue(env, levelVal);
            }
        }
    }

    // 4. 创建异步工作和Promise
    napi_deferred deferred;
    napi_value promise;
    napi_create_promise(env, &deferred, &promise);

    AsyncWorkContext* ctx = new AsyncWorkContext();
    ctx->env = env;
    ctx->deferred = deferred;
    ctx->operation = "compress";
    ctx->srcPaths = srcPaths;
    ctx->destPath = destPath;
    ctx->format = format;
    ctx->password = password;
    ctx->level = level;

    napi_value resourceName;
    napi_create_string_utf8(env, "CompressOperation", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName,
                          ExecuteP7ZipOperation,
                          OnP7ZipOperationComplete,
                          ctx, &ctx->work);
    napi_queue_async_work(env, ctx->work);

    return promise;
}

/**
 * NAPI函数：extract - 解压压缩包
 */
static napi_value Extract(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 2) {
        napi_throw_error(env, nullptr, "Wrong number of arguments. Expected at least: archivePath, destDir");
        return nullptr;
    }

    // 1. 解析源压缩包路径
    std::string archivePath = GetStringFromNapiValue(env, args[0]);

    // 2. 解析目标目录
    std::string destDir = GetStringFromNapiValue(env, args[1]);

    // 3. 解析密码（第三个参数，可选）
    std::string password;
    if (argc >= 3) {
        password = GetStringFromNapiValue(env, args[2]);
    }

    // 4. 创建异步工作和Promise
    napi_deferred deferred;
    napi_value promise;
    napi_create_promise(env, &deferred, &promise);

    AsyncWorkContext* ctx = new AsyncWorkContext();
    ctx->env = env;
    ctx->deferred = deferred;
    ctx->operation = "extract";
    ctx->srcPaths.push_back(archivePath);
    ctx->destPath = destDir;
    ctx->password = password;

    napi_value resourceName;
    napi_create_string_utf8(env, "ExtractOperation", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName,
                          ExecuteP7ZipOperation,
                          OnP7ZipOperationComplete,
                          ctx, &ctx->work);
    napi_queue_async_work(env, ctx->work);

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

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
    napi_module_register(&demoModule);
}
