#include <iostream>
#include <vector>
#include <string>

using namespace std;

int main() {
    cout << "分析7-Zip命令行解析逻辑：" << endl;
    cout << "==========================================" << endl;
    
    cout << "\n命令行: 7za x -y -o/path /data/storage/.../archive.7z" << endl;
    cout << "1. Main.cpp中删除程序名后，commandStrings = [\"x\", \"-y\", \"-o/path\", \"/data/storage/.../archive.7z\"]" << endl;
    cout << "2. Parse1解析后，nonSwitchStrings = [\"x\", \"/data/storage/.../archive.7z\"]" << endl;
    cout << "3. Parse2中:" << endl;
    cout << "   - curCommandIndex = 1" << endl;
    cout << "   - options.ArchiveName = nonSwitchStrings[1] = \"/data/storage/.../archive.7z\"" << endl;
    cout << "   - curCommandIndex++ 后变为 2" << endl;
    cout << "   - AddToCensorFromNonSwitchesStrings(startIndex=2, nonSwitchStrings.size()=2)" << endl;
    cout << "   - 循环不会执行 (2 < 2 为 false)" << endl;
    cout << "   - 但条件 (nonSwitchStrings.Size() == startIndex) && !thereAreSwitchIncludes 为 true" << endl;
    cout << "   - 所以会添加通配符 \"*\" 到 options.Censor" << endl;
    cout << "4. AllAreRelative() 检查 options.Censor，其中只有通配符 \"*\"" << endl;
    cout << "5. 通配符 \"*\" 是相对路径，所以检查通过" << endl;
    
    cout << "\n==========================================" << endl;
    cout << "\n命令行: 7za x /data/storage/.../archive.7z file1 file2" << endl;
    cout << "1. Main.cpp中删除程序名后，commandStrings = [\"x\", \"/data/storage/.../archive.7z\", \"file1\", \"file2\"]" << endl;
    cout << "2. Parse1解析后，nonSwitchStrings = [\"x\", \"/data/storage/.../archive.7z\", \"file1\", \"file2\"]" << endl;
    cout << "3. Parse2中:" << endl;
    cout << "   - curCommandIndex = 1" << endl;
    cout << "   - options.ArchiveName = nonSwitchStrings[1] = \"/data/storage/.../archive.7z\"" << endl;
    cout << "   - curCommandIndex++ 后变为 2" << endl;
    cout << "   - AddToCensorFromNonSwitchesStrings(startIndex=2, nonSwitchStrings.size()=4)" << endl;
    cout << "   - 循环会执行，处理 nonSwitchStrings[2]=\"file1\" 和 nonSwitchStrings[3]=\"file2\"" << endl;
    cout << "   - file1 和 file2 被添加到 options.Censor" << endl;
    cout << "4. 如果 file1 或 file2 是绝对路径，AllAreRelative() 检查会失败" << endl;
    
    cout << "\n==========================================" << endl;
    cout << "\n结论：" << endl;
    cout << "1. 归档文件名不会被添加到 options.Censor（用于提取文件的censor）" << endl;
    cout << "2. 归档文件名会被添加到 arcCensor（用于归档文件的censor）" << endl;
    cout << "3. AllAreRelative() 只检查 options.Censor，不检查 arcCensor" << endl;
    cout << "4. 所以即使归档文件名是绝对路径，AllAreRelative() 检查也不会失败" << endl;
    cout << "5. 问题可能是其他原因导致的" << endl;
    
    return 0;
}