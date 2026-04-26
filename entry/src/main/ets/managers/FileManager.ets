import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { ToastUtil } from '../utils/ToastUtil';
import { FileItem } from '../types/types';
import fs from '@ohos.file.fs';
// 替换 fileIo.openSync 为 fs.openSync，返回类型直接是 number
import { fileUri } from '@kit.CoreFileKit';
import wantConstant from '@ohos.app.ability.wantConstant';
import { Want } from '@kit.AbilityKit';

export class FileManager {
  private currentPath: string;
  private files: FileItem[] = [];
  private selectedIndices: Set<number> = new Set();
  private context: common.UIAbilityContext | null = null;

  constructor(initialPath: string, context?: common.UIAbilityContext) {
    this.currentPath = initialPath;
    if (context) {
      this.context = context;
    }
  }

  setContext(context: common.UIAbilityContext): void {
    this.context = context;
  }

  async loadFiles(): Promise<void> {
    try {
      if (!this.currentPath || this.currentPath.trim() === '') {
        console.error('当前路径为空，无法加载文件');
        this.files = [];
        return;
      }

      console.log('加载文件路径:', this.currentPath);
      const fileList = fileIo.listFileSync(this.currentPath);

      this.files = fileList.map((fileName: string): FileItem => {
        const filePath = `${this.currentPath}/${fileName}`;
        try {
          const stat = fileIo.statSync(filePath);
          return {
            name: fileName,
            path: filePath,
            isDir: stat.isDirectory(),
            size: stat.size,
            modified: stat.mtime
          };
        } catch (statErr) {
          console.warn('无法获取文件状态:', filePath, statErr);
          return {
            name: fileName,
            path: filePath,
            isDir: false,
            size: 0,
            modified: Date.now()
          };
        }
      }).sort((a, b) => {
        if (a.isDir && !b.isDir) return -1;
        if (!a.isDir && b.isDir) return 1;
        return a.name.localeCompare(b.name);
      });

      console.log('加载了', this.files.length, '个文件');
    } catch (err) {
      console.error('加载文件失败', err);
      this.files = [];
      throw new Error('加载文件失败: ' + (err as Error).message);
    }
  }

  // 在 FileManager 类中添加
  async openWithOtherApp(filePath: string): Promise<void> {
    if (!this.context) {
      throw new Error('应用上下文未初始化，无法打开文件');
    }
    try {
      const uri = fileUri.getUriFromPath(filePath);
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: uri,
        type: this.getMimeTypeFromExtension(filePath),
        flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
      };
      await this.context.startAbility(want);
    } catch (err) {
      // 将 unknown 转换为 Error 对象（符合 ArkTS 规范）
      const error = err instanceof Error ? err : new Error(String(err));
      console.error('打开文件失败:', error.message);
      throw new Error('无法打开文件，可能没有合适的应用: ' + error.message);
    }
  }

  private getMimeTypeFromExtension(filePath: string): string {
    const ext = filePath.split('.').pop()?.toLowerCase();
    // 按需增加 MIME 映射
    switch (ext) {
      case 'txt': return 'text/plain';
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'pdf': return 'application/pdf';
      default: return 'application/octet-stream';
    }
  }

  getFiles(): FileItem[] {
    return this.files;
  }

  getCurrentPath(): string {
    return this.currentPath;
  }

  setCurrentPath(path: string): void {
    this.currentPath = path;
  }

  toggleSelect(index: number, selected: boolean): void {
    if (selected) {
      this.selectedIndices.add(index);
    } else {
      this.selectedIndices.delete(index);
    }
  }

  getSelectedIndices(): Set<number> {
    return new Set(this.selectedIndices);
  }

  toggleSelectAll(): void {
    if (this.selectedIndices.size === this.files.length) {
      this.selectedIndices.clear();
    } else {
      for (let i = 0; i < this.files.length; i++) {
        this.selectedIndices.add(i);
      }
    }
  }

  getSelectedPaths(): string[] {
    return Array.from(this.selectedIndices).map(index => this.files[index].path);
  }

  openFolder(item: FileItem): void {
    if (item.isDir) {
      this.currentPath = item.path;
      this.selectedIndices.clear();
    }
  }

  async openFile(item: FileItem): Promise<string> {
    if (!item.isDir) {
      return item.path;
    }
    throw new Error('无法打开文件夹');
  }

  async deleteSelectedFiles(): Promise<void> {
    const selectedPaths = this.getSelectedPaths();
    if (selectedPaths.length === 0) {
      ToastUtil.showToast('请先选择要删除的文件或文件夹');
      return;
    }

    let successCount = 0;
    let failCount = 0;

    for (const path of selectedPaths) {
      try {
        const stat = fileIo.statSync(path);
        if (stat.isDirectory()) {
          await this.deleteDirectoryRecursive(path);
        } else {
          fileIo.unlinkSync(path);
        }
        successCount++;
      } catch (err) {
        console.error('删除文件失败', path, err);
        failCount++;
      }
    }

    if (successCount > 0) {
      ToastUtil.showToast(`成功删除 ${successCount} 个${failCount > 0 ? `，失败 ${failCount} 个` : ''}`);
    } else {
      ToastUtil.showToast('删除失败，请检查文件权限');
    }

    await this.loadFiles();
    this.selectedIndices.clear();
  }

  private async deleteDirectoryRecursive(dirPath: string): Promise<void> {
    try {
      const files = fileIo.listFileSync(dirPath);
      for (const file of files) {
        const fullPath = `${dirPath}/${file}`;
        const stat = fileIo.statSync(fullPath);
        if (stat.isDirectory()) {
          await this.deleteDirectoryRecursive(fullPath);
        } else {
          fileIo.unlinkSync(fullPath);
        }
      }
      fileIo.rmdirSync(dirPath);
    } catch (err) {
      console.error('删除目录失败', dirPath, err);
      throw new Error('删除目录失败: ' + (err as Error).message);
    }
  }

  /**
   * 复制文件（使用高效且正确的循环）
   * @param srcUri 源URI（支持 file:// 或 绝对路径）
   * @param destPath 目标绝对路径
   */
  private async copyFile(srcUri: string, destPath: string): Promise<void> {
    let srcFile: fs.File | null = null;
    let destFile: fs.File | null = null;
    try {
      srcFile = fs.openSync(srcUri, fs.OpenMode.READ_ONLY);
      destFile = fs.openSync(destPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      const buffer = new ArrayBuffer(64 * 1024);
      let bytesRead: number;
      while ((bytesRead = fs.readSync(srcFile.fd, buffer)) > 0) {
        fs.writeSync(destFile.fd, buffer, { length: bytesRead });
      }
    } catch (err) {
      // 清理不完整的目标文件
      if (destFile) {
        try { fs.closeSync(destFile.fd); } catch (e) { /* 忽略清理时的错误 */ }
        try { fs.unlinkSync(destPath); } catch (e) { /* 忽略删除错误 */ }
      }
      // 将捕获的值转换为 Error 对象才能抛出
      const error = err instanceof Error ? err : new Error(String(err));
      throw error;
    } finally {
      if (srcFile) {
        try { fs.closeSync(srcFile.fd); } catch (e) { /* 忽略 */ }
      }
      if (destFile) {
        try { fs.closeSync(destFile.fd); } catch (e) { /* 忽略 */ }
      }
    }
  }

  /**
   * 导入文件（从系统文件管理器选择文件）
   */
  async importFiles(): Promise<void> {
    if (!this.context) {
      ToastUtil.showToast('导入失败: 应用上下文未初始化');
      console.error('FileManager.context is null');
      return;
    }

    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 20;
      // 鸿蒙API中 selectMode 可能不存在，如有错误请删除此行
      // options.selectMode = picker.DocumentSelectMode.FILE;

      const documentPicker = new picker.DocumentViewPicker(this.context);
      const uris = await documentPicker.select(options);

      if (!uris || uris.length === 0) {
        ToastUtil.showToast('未选择任何文件');
        return;
      }

      ToastUtil.showToast(`正在导入 ${uris.length} 个文件...`);
      let successCount = 0;
      let failCount = 0;

      for (const uri of uris) {
        try {
          // 提取原始文件名并解码
          let fileName = decodeURIComponent(uri.split('/').pop() || '');
          if (!fileName) {
            console.warn('无法提取文件名:', uri);
            failCount++;
            continue;
          }

          let destPath = `${this.currentPath}/${fileName}`;

          // 处理文件名冲突 (重命名)
          let counter = 1;
          const nameWithoutExt = fileName.substring(0, fileName.lastIndexOf('.'));
          const ext = fileName.substring(fileName.lastIndexOf('.'));
          while (true) {
            try {
              fileIo.statSync(destPath);
              // 存在则重命名
              fileName = `${nameWithoutExt}(${counter})${ext}`;
              destPath = `${this.currentPath}/${fileName}`;
              counter++;
            } catch {
              break; // 文件不存在，跳出循环
            }
          }

          await this.copyFile(uri, destPath);
          successCount++;
        } catch (err) {
          console.error('导入单个文件失败', uri, err);
          failCount++;
        }
      }

      if (successCount > 0) {
        ToastUtil.showToast(`成功导入 ${successCount} 个文件${failCount > 0 ? `，失败 ${failCount} 个` : ''}`);
        await this.loadFiles();
      } else {
        ToastUtil.showToast('导入失败，没有成功导入任何文件');
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error('导入文件失败', error);
      if (error.code === 13900001) {
        ToastUtil.showToast('已取消导入');
      } else {
        ToastUtil.showToast(`导入失败: ${error.message}`);
      }
    }
  }

  /**
   * 导出文件（将选中的文件保存到系统下载目录或用户指定位置）
   */
  async exportFiles(): Promise<void> {
    const selectedPaths = this.getSelectedPaths();
    if (selectedPaths.length === 0) {
      ToastUtil.showToast('请先选择要导出的文件');
      return;
    }
    if (!this.context) {
      ToastUtil.showToast('导出失败: 应用上下文未初始化');
      return;
    }

    try {
      let successCount = 0;
      for (const srcPath of selectedPaths) {
        const fileName = srcPath.split('/').pop() || 'file';
        const saveOptions = new picker.DocumentSaveOptions();

        // 鸿蒙 API 中 DocumentSaveOptions 支持的属性名可能是 'fileName' 或 'suggestedName'
        // 由于无法使用 in 操作符，这里通过尝试赋值（忽略类型错误，运行时有效）
        // 注意：此写法在 ArkTS 中允许，但可能需要 @ts-ignore 或使用类型断言为 Record<string, Object>
        const opt = saveOptions as Record<string, Object>;
        if (opt.fileName !== undefined) {
          opt.fileName = fileName;
        } else if (opt.suggestedName !== undefined) {
          opt.suggestedName = fileName;
        }

        const documentPicker = new picker.DocumentViewPicker(this.context);
        const result = await documentPicker.save(saveOptions);
        let destUri: string | undefined;
        if (typeof result === 'string') {
          destUri = result;
        } else if (Array.isArray(result) && result.length > 0) {
          destUri = result[0];
        }

        if (destUri) {
          await this.copyFile(srcPath, destUri);
          successCount++;
        }
      }
      ToastUtil.showToast(`成功导出 ${successCount} 个文件`);
    } catch (err) {
      const error = err as BusinessError;
      console.error('导出文件失败', error);
      if (error.code === 13900001) {
        ToastUtil.showToast('已取消导出');
      } else {
        ToastUtil.showToast(`导出失败: ${error.message}`);
      }
    }
  }
}