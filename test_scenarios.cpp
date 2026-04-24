#include <iostream>
#include <vector>
#include <string>

using namespace std;

void testScenario(const string& description, const vector<string>& argv) {
    cout << "\n=== " << description << " ===" << endl;
    cout << "命令行: ";
    for (const auto& arg : argv) {
        cout << arg << " ";
    }
    cout << endl;
    
    // 模拟Parse1后的nonSwitchStrings
    vector<string> nonSwitchStrings;
    
    cout << "\n解析过程:" << endl;
    cout << "1. 原始命令行参数:" << endl;
    for (size_t i = 0; i < argv.size(); i++) {
        cout << "   argv[" << i << "] = \"" << argv[i] << "\"" << endl;
    }
    
    cout << "\n2. Main.cpp删除程序名后，commandStrings:" << endl;
    vector<string> commandStrings;
    for (size_t i = 1; i < argv.size(); i++) {
        commandStrings.push_back(argv[i]);
        cout << "   commandStrings[" << i-1 << "] = \"" << argv[i] << "\"" << endl;
    }
    
    cout << "\n3. Parse1解析开关参数后，nonSwitchStrings:" << endl;
    // 模拟开关参数解析：以'-'开头的参数是开关
    for (const auto& arg : commandStrings) {
        if (!arg.empty() && arg[0] == '-') {
            cout << "   \"" << arg << "\" 是开关参数，跳过" << endl;
        } else {
            nonSwitchStrings.push_back(arg);
            cout << "   nonSwitchStrings[" << nonSwitchStrings.size()-1 << "] = \"" << arg << "\"" << endl;
        }
    }
    
    cout << "\n4. Parse2处理:" << endl;
    cout << "   - kCommandIndex = 0" << endl;
    cout << "   - curCommandIndex = 1" << endl;
    cout << "   - options.ArchiveName = nonSwitchStrings[1] = \"" << (nonSwitchStrings.size() > 1 ? nonSwitchStrings[1] : "N/A") << "\"" << endl;
    cout << "   - curCommandIndex++ 后变为 2" << endl;
    cout << "   - AddToCensorFromNonSwitchesStrings(startIndex=2, nonSwitchStrings.size()=" << nonSwitchStrings.size() << ")" << endl;
    
    if (nonSwitchStrings.size() == 2) {
        cout << "   - nonSwitchStrings.Size() == startIndex (2 == 2)" << endl;
        cout << "   - 如果没有-i开关，会添加通配符\"*\"到options.Censor" << endl;
    } else if (nonSwitchStrings.size() > 2) {
        cout << "   - 处理 nonSwitchStrings[2] 到 nonSwitchStrings[" << nonSwitchStrings.size()-1 << "]:" << endl;
        for (size_t i = 2; i < nonSwitchStrings.size(); i++) {
            cout << "     - nonSwitchStrings[" << i << "] = \"" << nonSwitchStrings[i] << "\" 被添加到options.Censor" << endl;
        }
    }
    
    cout << "\n5. AllAreRelative()检查:" << endl;
    cout << "   - 检查options.Censor中的路径是否都是相对路径" << endl;
    if (nonSwitchStrings.size() > 2) {
        for (size_t i = 2; i < nonSwitchStrings.size(); i++) {
            const string& path = nonSwitchStrings[i];
            if (path.find('/') == 0 || path.find('\\') == 0 || 
                (path.size() > 1 && path[1] == ':')) {
                cout << "   - \"" << path << "\" 是绝对路径！AllAreRelative()会失败" << endl;
            }
        }
    }
}

int main() {
    cout << "7-Zip命令行解析分析" << endl;
    cout << "=====================" << endl;
    
    testScenario("解压归档文件，无文件列表", 
        {"7za", "x", "-y", "-o/path", "/data/storage/.../archive.7z"});
    
    testScenario("解压归档文件，带相对路径文件列表", 
        {"7za", "x", "/data/storage/.../archive.7z", "file1.txt", "dir/file2.txt"});
    
    testScenario("解压归档文件，带绝对路径文件列表", 
        {"7za", "x", "/data/storage/.../archive.7z", "/absolute/path/file1.txt", "relative/file2.txt"});
    
    testScenario("解压归档文件，带-i开关", 
        {"7za", "x", "-i*.txt", "/data/storage/.../archive.7z"});
    
    testScenario("列表命令", 
        {"7za", "l", "/data/storage/.../archive.7z"});
    
    cout << "\n\n结论：" << endl;
    cout << "1. 归档文件名不会被添加到options.Censor（用于提取文件的censor）" << endl;
    cout << "2. 归档文件名会被添加到arcCensor（用于归档文件的censor）" << endl;
    cout << "3. AllAreRelative()只检查options.Censor" << endl;
    cout << "4. 只有当用户在解压命令中指定了文件列表，并且文件列表中有绝对路径时，AllAreRelative()才会失败" << endl;
    cout << "5. 归档文件名本身不会导致AllAreRelative()失败" << endl;
    
    return 0;
}