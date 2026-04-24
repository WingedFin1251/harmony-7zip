#include <iostream>
#include <vector>
#include <string>

using namespace std;

int main() {
    // 测试不同的命令行参数
    
    cout << "测试1: 7za x archive.7z" << endl;
    vector<string> argv1 = {"7za", "x", "archive.7z"};
    cout << "NonSwitchStrings:" << endl;
    cout << "  [0] = \"" << argv1[0] << "\" (程序名)" << endl;
    cout << "  [1] = \"" << argv1[1] << "\" (命令)" << endl;
    cout << "  [2] = \"" << argv1[2] << "\" (归档文件名)" << endl;
    cout << "curCommandIndex = 1" << endl;
    cout << "options.ArchiveName = nonSwitchStrings[1] = \"" << argv1[1] << "\" (这是错误的！应该是archive.7z)" << endl;
    cout << "curCommandIndex++ 后变为 2" << endl;
    cout << "AddToCensorFromNonSwitchesStrings 从索引2开始，处理 nonSwitchStrings[2] = \"" << argv1[2] << "\"" << endl;
    cout << "归档文件名被添加到censor中！" << endl;
    
    cout << "\n测试2: 7za x -y archive.7z" << endl;
    vector<string> argv2 = {"7za", "x", "-y", "archive.7z"};
    cout << "NonSwitchStrings:" << endl;
    cout << "  [0] = \"" << argv2[0] << "\" (程序名)" << endl;
    cout << "  [1] = \"" << argv2[1] << "\" (命令)" << endl;
    cout << "  [2] = \"" << argv2[3] << "\" (归档文件名，因为-y是开关)" << endl;
    cout << "curCommandIndex = 1" << endl;
    cout << "options.ArchiveName = nonSwitchStrings[1] = \"" << argv2[1] << "\" (这是错误的！应该是archive.7z)" << endl;
    cout << "curCommandIndex++ 后变为 2" << endl;
    cout << "AddToCensorFromNonSwitchesStrings 从索引2开始，处理 nonSwitchStrings[2] = \"" << argv2[3] << "\"" << endl;
    cout << "归档文件名被添加到censor中！" << endl;
    
    cout << "\n测试3: 7za x -y -o/path archive.7z" << endl;
    vector<string> argv3 = {"7za", "x", "-y", "-o/path", "archive.7z"};
    cout << "NonSwitchStrings:" << endl;
    cout << "  [0] = \"" << argv3[0] << "\" (程序名)" << endl;
    cout << "  [1] = \"" << argv3[1] << "\" (命令)" << endl;
    cout << "  [2] = \"" << argv3[4] << "\" (归档文件名，因为-y和-o/path是开关)" << endl;
    cout << "curCommandIndex = 1" << endl;
    cout << "options.ArchiveName = nonSwitchStrings[1] = \"" << argv3[1] << "\" (这是错误的！应该是archive.7z)" << endl;
    cout << "curCommandIndex++ 后变为 2" << endl;
    cout << "AddToCensorFromNonSwitchesStrings 从索引2开始，处理 nonSwitchStrings[2] = \"" << argv3[4] << "\"" << endl;
    cout << "归档文件名被添加到censor中！" << endl;
    
    cout << "\n问题分析：" << endl;
    cout << "1. curCommandIndex 初始化为 1 (kCommandIndex + 1)" << endl;
    cout << "2. options.ArchiveName = nonSwitchStrings[curCommandIndex++] 获取 nonSwitchStrings[1]" << endl;
    cout << "3. 但 nonSwitchStrings[1] 是命令，不是归档文件名！" << endl;
    cout << "4. 归档文件名应该是 nonSwitchStrings[2]" << endl;
    cout << "5. 然后 AddToCensorFromNonSwitchesStrings 从 curCommandIndex=2 开始，处理归档文件名" << endl;
    cout << "6. 如果归档文件名是绝对路径，AllAreRelative() 检查会失败！" << endl;
    
    return 0;
}