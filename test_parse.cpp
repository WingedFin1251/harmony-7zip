#include <iostream>
#include <vector>
#include <string>

using namespace std;

int main() {
    // 模拟命令行参数: 7za x -y -o/path /data/storage/.../archive.7z
    vector<string> argv = {"7za", "x", "-y", "-o/path", "/data/storage/.../archive.7z"};
    
    // 非开关字符串应该包含：程序名、命令、归档文件名
    // 开关字符串：-y, -o/path
    
    cout << "argv[0] = " << argv[0] << endl;
    cout << "argv[1] = " << argv[1] << endl;
    cout << "argv[2] = " << argv[2] << endl;
    cout << "argv[3] = " << argv[3] << endl;
    cout << "argv[4] = " << argv[4] << endl;
    
    // 在7-Zip的解析逻辑中：
    // - 程序名 (argv[0]) 会被忽略或特殊处理
    // - 非开关字符串：程序名、命令、归档文件名
    // - 开关字符串：-y, -o/path
    
    cout << "\n假设解析器处理后的nonSwitchStrings:" << endl;
    cout << "nonSwitchStrings[0] = \"" << argv[0] << "\" (程序名)" << endl;
    cout << "nonSwitchStrings[1] = \"" << argv[1] << "\" (命令)" << endl;
    cout << "nonSwitchStrings[2] = \"" << argv[4] << "\" (归档文件名)" << endl;
    
    cout << "\nParse2函数中的逻辑：" << endl;
    cout << "kCommandIndex = 0" << endl;
    cout << "curCommandIndex = kCommandIndex + 1 = 1" << endl;
    cout << "options.ArchiveName = nonSwitchStrings[curCommandIndex++] = nonSwitchStrings[1] = \"" << argv[1] << "\"" << endl;
    cout << "curCommandIndex 现在 = 2" << endl;
    cout << "AddToCensorFromNonSwitchesStrings 从索引2开始" << endl;
    cout << "nonSwitchStrings[2] = \"" << argv[4] << "\" 被添加到censor中！" << endl;
    
    return 0;
}