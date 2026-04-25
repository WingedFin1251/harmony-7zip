import { BusinessError } from '@kit.BasicServicesKit';
import { picker, fileIo, fileUri } from '@kit.CoreFileKit';
import * as native from 'libentry.so';
import { showToast } from '../utils/ToastUtil';
import { FileRow } from '../components/FileRow';
import { FileGridCell } from '../components/FileGridCell';
import { common, Want, wantConstant } from '@kit.AbilityKit';
import { getFileTypeInfo, isArchiveFile, isOpenableFile } from '../utils/FileTypeUtil';

// 临时定义权限类型（如果从 SDK 导入失败）

// 文件项数据类型
interface FileItem {
  name: string;
  path: string;
  isDir: boolean;
  size: number;
  modified: number;
  uri?: string;
}

// 压缩选项接口
interface CompressOptions {
  format: '7z' | 'zip' | 'tar';
  password?: string;
  splitSize?: string;
}

// 颜色资源类型
interface ColorResourceType {
  background_primary: Resource;
  background_secondary: Resource;
  background_tertiary: Resource;
  background_selected: Resource;
  text_primary: Resource;
  text_secondary: Resource;
  text_tertiary: Resource;
  text_disabled: Resource;
  text_inverse: Resource;
  border_primary: Resource;
  border_secondary: Resource;
  accent_primary: Resource;
  accent_secondary: Resource;
  accent_tertiary: Resource;
  status_success: Resource;
  status_warning: Resource;
  status_error: Resource;
  status_info: Resource;
  icon_primary: Resource;
  icon_secondary: Resource;
  icon_disabled: Resource;
  button_primary_background: Resource;
  button_primary_text: Resource;
  button_secondary_background: Resource;
  button_secondary_text: Resource;
  button_danger_background: Resource;
  button_danger_text: Resource;
  card_background: Resource;
  dialog_background: Resource;
  list_item_background: Resource;
  list_item_selected: Resource;
}

// 颜色资源常量
const ColorResource: ColorResourceType = {
  background_primary: $r('app.color.background_primary'),
  background_secondary: $r('app.color.background_secondary'),
  background_tertiary: $r('app.color.background_tertiary'),
  background_selected: $r('app.color.background_selected'),
  text_primary: $r('app.color.text_primary'),
  text_secondary: $r('app.color.text_secondary'),
  text_tertiary: $r('app.color.text_tertiary'),
  text_disabled: $r('app.color.text_disabled'),
  text_inverse: $r('app.color.text_inverse'),
  border_primary: $r('app.color.border_primary'),
  border_secondary: $r('app.color.border_secondary'),
  accent_primary: $r('app.color.accent_primary'),
  accent_secondary: $r('app.color.accent_secondary'),
  accent_tertiary: $r('app.color.accent_tertiary'),
  status_success: $r('app.color.status_success'),
  status_warning: $r('app.color.status_warning'),
  status_error: $r('app.color.status_error'),
  status_info: $r('app.color.status_info'),
  icon_primary: $r('app.color.icon_primary'),
  icon_secondary: $r('app.color.icon_secondary'),
  icon_disabled: $r('app.color.icon_disabled'),
  button_primary_background: $r('app.color.button_primary_background'),
  button_primary_text: $r('app.color.button_primary_text'),
  button_secondary_background: $r('app.color.button_secondary_background'),
  button_secondary_text: $r('app.color.button_secondary_text'),
  button_danger_background: $r('app.color.button_danger_background'),
  button_danger_text: $r('app.color.button_danger_text'),
  card_background: $r('app.color.card_background'),
  dialog_background: $r('app.color.dialog_background'),
  list_item_background: $r('app.color.list_item_background'),
  list_item_selected: $r('app.color.list_item_selected')
};

@Entry
@Component
struct FileBrowser {
  // ---------- 状态变量 ----------
  @State currentPath: string = '';
  @State files: FileItem[] = [];
  @State selectedIndices: Set<number> = new Set();
  @State isSelectionMode: boolean = false;
  @State viewMode: 'list' | 'grid' = 'list';
  @State isLoading: boolean = false;
  @State searchKeyword: string = '';

  compressDialogController: CustomDialogController | null = null;
  extractDialogController: CustomDialogController | null = null;
  deleteDialogController: CustomDialogController | null = null;

  aboutToAppear(): void {
    // 获取应用沙箱根目录
    this.currentPath = getContext(this).filesDir;
    this.loadFiles();
  }

  getSandboxRoot(): string {
    return getContext(this).filesDir;
  }

  async loadFiles(): Promise<void> {
    this.isLoading = true;
    try {
      // 检查fileIo API是否可用
      if (!canIUse('SystemCapability.FileManagement.File.FileIO')) {
        showToast('当前设备不支持文件管理功能');
        this.isLoading = false;
        return;
      }
      
      // 使用 fileIo 读取沙箱目录下的真实文件列表
      const fileNames: string[] = fileIo.listFileSync(this.currentPath);
      const fileItems: FileItem[] = [];
      for (const name of fileNames) {
        const fullPath = this.currentPath + '/' + name;
        try {
          const stat = fileIo.statSync(fullPath);
          fileItems.push({
            name: name,
            path: fullPath,
            isDir: stat.isDirectory(),
            size: stat.size,
            modified: stat.mtime
          });
        } catch (statErr) {
          // 如果某个文件无法 stat，跳过
          console.error('stat 失败: ' + fullPath, JSON.stringify(statErr));
        }
      }
      // 按文件夹优先、名称排序
      fileItems.sort((a, b) => {
        if (a.isDir !== b.isDir) return a.isDir ? -1 : 1;
        return a.name.localeCompare(b.name);
      });
      this.files = fileItems;
    } catch (err) {
      showToast('加载失败: ' + (err as BusinessError).message);
      console.error('加载文件列表失败', JSON.stringify(err));
    } finally {
      this.isLoading = false;
    }
  }

  refresh(): void {
    this.loadFiles();
  }

  goBack(): void {
    const sandboxRoot = this.getSandboxRoot();
    if (this.currentPath === sandboxRoot) {
      showToast('已在沙箱根目录');
      return;
    }
    const parts = this.currentPath.split('/');
    parts.pop();
    this.currentPath = parts.join('/') || sandboxRoot;
    this.refresh();
  }

  toggleSelect(index: number, selected: boolean): void {
    if (selected) {
      this.selectedIndices.add(index);
    } else {
      this.selectedIndices.delete(index);
    }
    this.isSelectionMode = this.selectedIndices.size > 0;
  }

  toggleSelectAll(): void {
    if (this.selectedIndices.size === this.files.length) {
      this.selectedIndices.clear();
    } else {
      this.selectedIndices = new Set(this.files.keys());
    }
    this.isSelectionMode = this.selectedIndices.size > 0;
  }

  getSelectedPaths(): string[] {
    return Array.from(this.selectedIndices).map(i => this.files[i].path);
  }

  openFolder(item: FileItem): void {
    if (item.isDir) {
      this.currentPath = item.path;
      this.selectedIndices.clear();
      this.isSelectionMode = false;
      this.refresh();
    } else {
      // 如果是文件，尝试打开它
      this.openFile(item);
    }
  }

  async openFile(item: FileItem): Promise<void> {
    try {
      // 检查是否是压缩包
      if (isArchiveFile(item.name)) {
        // 对于压缩包，进入选择模式
        this.isSelectionMode = true;
        this.selectedIndices.clear();
        const index = this.files.findIndex(file => file.path === item.path);
        if (index !== -1) {
          this.selectedIndices.add(index);
        }
        showToast('已选择压缩包，请长按进行解压操作');
        return;
      }

      // 检查是否是可打开的文件类型
      if (!isOpenableFile(item.name)) {
        showToast('不支持打开此文件类型');
        return;
      }

      // 获取文件类型信息
      const fileTypeInfo = getFileTypeInfo(item.name, false);
      
      // 使用系统应用打开文件
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        showToast('无法获取应用上下文');
        return;
      }

      // 将文件路径转换为URI
      let uri: string;
      try {
        // 使用fileUri模块获取正确的URI
        uri = fileUri.getUriFromPath(item.path);
      } catch (uriErr) {
        console.error('获取URI失败:', JSON.stringify(uriErr));
        // 如果获取失败，尝试使用简单路径
        uri = `file://${item.path}`;
      }
      
      // 使用系统应用打开文件
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: uri,
        type: fileTypeInfo.mimeType,
        parameters: {
          'ability.params.showDefaultPicker': true // 强制显示选择弹窗
        },
        // 配置被分享文件的读写权限
        flags: wantConstant.Flags.FLAG_AUTH_WRITE_URI_PERMISSION | wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
      };

      await context.startAbility(want);
      showToast('正在打开文件...');
      
    } catch (err) {
      console.error('打开文件失败:', JSON.stringify(err));
      showToast('打开文件失败: ' + (err as BusinessError).message);
    }
  }

  showCompressDialog(): void {
    if (this.selectedIndices.size === 0) {
      try {
        showToast('请先选择文件或文件夹');
      } catch (err) {
        console.error('显示提示失败', JSON.stringify(err));
      }
      return;
    }
    this.compressDialogController = new CustomDialogController({
      builder: CompressDialog({
        selectedPaths: this.getSelectedPaths(),
        onConfirm: (options: CompressOptions): Promise<void> => this.startCompress(options)
      }),
      cancel: (): void => { this.compressDialogController?.close(); }
    });
    this.compressDialogController.open();
  }

  async startCompress(options: CompressOptions): Promise<void> {
    this.isLoading = true;
    try {
      await native.compress(
        this.getSelectedPaths(),
        this.currentPath + '/archive.' + options.format,
        options
      );
      showToast('压缩成功');
      this.refresh();
    } catch (err) {
      showToast('压缩失败: ' + (err as BusinessError).message);
    } finally {
      this.isLoading = false;
      this.selectedIndices.clear();
      this.isSelectionMode = false;
    }
  }

  showExtractDialog(): void {
    if (this.selectedIndices.size === 0) {
      try {
        showToast('请先选择一个压缩文件');
      } catch (err) {
        console.error('显示提示失败', JSON.stringify(err));
      }
      return;
    }
    const first = this.files[Array.from(this.selectedIndices)[0]];
    if (first.isDir) {
      try {
        showToast('请选择一个压缩文件，而不是文件夹');
      } catch (err) {
        console.error('显示提示失败', JSON.stringify(err));
      }
      return;
    }
    this.extractDialogController = new CustomDialogController({
      builder: ExtractDialog({
        archivePath: first.path,
        sandboxRoot: this.getSandboxRoot(),
        onConfirm: async (destPath: string, password?: string): Promise<void> => {
          await this.startExtract(first.path, destPath, password);
        }
      }),
      cancel: (): void => { this.extractDialogController?.close(); }
    });
    this.extractDialogController.open();
  }

  async startExtract(archivePath: string, destPath: string, password?: string): Promise<void> {
    this.isLoading = true;
    try {
      console.info('开始解压操作:', { archivePath, destPath, password });
      
      // 检查fileIo API是否可用
      if (!canIUse('SystemCapability.FileManagement.File.FileIO')) {
        showToast('当前设备不支持文件管理功能');
        this.isLoading = false;
        return;
      }
      
      // 0. 验证路径
      if (!archivePath || !destPath) {
        showToast('解压失败: 路径不能为空');
        return;
      }
      
      // 确保目标路径在沙箱内
      const sandboxRoot = this.getSandboxRoot();
      if (!destPath.startsWith(sandboxRoot)) {
        console.error('目标路径不在沙箱内:', { destPath, sandboxRoot });
        showToast('解压失败: 目标路径必须在应用沙箱内');
        return;
      }

      // 1. 检查压缩文件是否存在
      try {
        const stat = fileIo.statSync(archivePath);
        console.info('压缩文件状态:', { path: archivePath, isFile: stat.isFile(), isDirectory: stat.isDirectory() });
        
        if (!stat.isFile()) {
          showToast('解压失败: 选择的不是文件');
          return;
        }
      } catch (statErr) {
        console.error('压缩文件不存在: ' + archivePath, JSON.stringify(statErr));
        showToast('解压失败: 压缩文件不存在');
        return;
      }

      // 2. 确保目标目录存在（如果不存在则创建）
      console.info('创建目标目录:', destPath);
      try {
        // 先检查目标路径是否已经是文件
        try {
          const destStat = fileIo.statSync(destPath);
          if (destStat.isFile()) {
            showToast('解压失败: 目标路径是文件，不是目录');
            return;
          }
        } catch (e) {
          // 路径不存在，继续创建
        }
        
        fileIo.mkdirSync(destPath, true); // recursive = true
        console.info('目录创建成功或已存在:', destPath);
      } catch (mkdirErr) {
        console.error('创建目录失败:', destPath, JSON.stringify(mkdirErr));
        showToast('解压失败: 无法创建目标目录');
        return;
      }

      // 3. 执行解压
      console.info('调用原生解压接口...');
      await native.extract(archivePath, destPath, password);
      console.info('解压操作完成');
      showToast('解压成功');
      
      // 4. 刷新文件列表
      this.refresh();
    } catch (err) {
      const errMsg = (err as BusinessError).message || JSON.stringify(err);
      console.error('解压失败详情:', errMsg, err);
      showToast('解压失败: ' + errMsg);
    } finally {
      this.isLoading = false;
      this.selectedIndices.clear();
      this.isSelectionMode = false;
      console.info('解压操作结束，清理状态');
    }
  }

  showDeleteConfirmDialog(): void {
    const paths = this.getSelectedPaths();
    if (paths.length === 0) {
      showToast('请先选择要删除的文件或文件夹');
      return;
    }
    
    // 构建确认消息
    let message = `确定要删除 ${paths.length} 个文件/文件夹吗？\n\n`;
    const maxShow = 5; // 最多显示5个文件名
    for (let i = 0; i < Math.min(paths.length, maxShow); i++) {
      const fileName = paths[i].split('/').pop() || paths[i];
      message += `• ${fileName}\n`;
    }
    if (paths.length > maxShow) {
      message += `• ... 等 ${paths.length - maxShow} 个文件\n`;
    }
    message += '\n此操作不可撤销！';
    
    this.deleteDialogController = new CustomDialogController({
      builder: DeleteConfirmDialog({
        message: message,
        onConfirm: (): Promise<void> => this.deleteSelected()
      }),
      cancel: () => {
        console.log('用户取消了删除操作');
      },
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });
    
    this.deleteDialogController.open();
  }

  async deleteSelected(): Promise<void> {
    const paths = this.getSelectedPaths();
    if (paths.length === 0) {
      showToast('请先选择要删除的文件或文件夹');
      return;
    }

    // 检查fileIo API是否可用
    if (!canIUse('SystemCapability.FileManagement.File.FileIO')) {
      showToast('当前设备不支持文件管理功能');
      return;
    }

    let successCount = 0;
    let failCount = 0;
    
    for (const path of paths) {
      try {
        // 获取文件信息以判断是文件还是目录
        const stat = fileIo.statSync(path);
        if (stat.isDirectory()) {
          // 删除目录
          fileIo.rmdirSync(path);
        } else {
          // 删除文件
          fileIo.unlinkSync(path);
        }
        successCount++;
      } catch (err) {
        console.error('删除失败: ' + path, JSON.stringify(err));
        failCount++;
      }
    }
    
    if (successCount > 0) {
      if (failCount === 0) {
        showToast(`成功删除 ${successCount} 个文件/文件夹`);
      } else {
        showToast(`成功删除 ${successCount} 个，失败 ${failCount} 个`);
      }
    } else {
      showToast('删除失败，请检查文件权限');
    }
    
    this.selectedIndices.clear();
    this.isSelectionMode = false;
    this.refresh();
  }

  // ---------- 导入功能 ----------

  /**
   * 打开文件选择器，选择文件导入到当前目录
   */
  async importFiles(): Promise<void> {
    try {
      // 1. 检查系统能力（保持原样）
      if (!canIUse('SystemCapability.FileManagement.UserFileService')) {
        showToast('当前设备不支持文件选择功能');
        return;
      }

      // 2. 获取UIAbilityContext（保持原样）
      let context: common.UIAbilityContext;
      try {
        context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      } catch (e) {
        console.error('获取UIAbilityContext失败', e);
        showToast('无法获取应用上下文');
        return;
      }

      // 3. 创建文件选择器
      const documentPicker = new picker.DocumentViewPicker(context);

      // 4. 配置选择选项
      const documentSelectOptions = new picker.DocumentSelectOptions();
      documentSelectOptions.maxSelectNumber = 10;

      // 5. 【关键修改】使用Promise形式的select，并直接传入options对象
      const result: string[] = await documentPicker.select(documentSelectOptions);

      // ... 剩余处理逻辑保持不变 ...
      if (!result || result.length === 0) {
        return;
      }

      showToast('正在导入 ' + result.length + ' 个文件...');

      let successCount = 0;
      for (const uri of result) {
        try {
          await this.copyFileToCurrentDir(uri);
          successCount++;
        } catch (err) {
          console.error('导入文件失败: ' + uri, JSON.stringify(err));
        }
      }

      showToast('成功导入 ' + successCount + ' 个文件');
      this.refresh();

    } catch (err) {
      const bizErr = err as BusinessError;
      if (bizErr.code === 0) {
        // 用户取消选择，不提示
        return;
      }
      showToast('导入失败: ' + bizErr.message);
      console.error('导入文件失败', JSON.stringify(err));
    }
  }



  /**
   * 将 URI 指向的文件复制到当前目录
   */
  async copyFileToCurrentDir(uri: string): Promise<void> {
    try {
      // 检查fileIo API是否可用
      if (!canIUse('SystemCapability.FileManagement.File.FileIO')) {
        throw new Error('当前设备不支持文件操作功能');
      }
      
      // 打开源文件（只读）
      const srcFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      // 从 URI 中提取文件名
      const uriParts = uri.split('/');
      const fileName = uriParts[uriParts.length - 1];
      const destPath = this.currentPath + '/' + fileName;
      // 创建目标文件（读写，若存在则覆盖）
      const destFile = fileIo.openSync(destPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      // 复制文件内容
      const bufSize = 1024 * 1024; // 1MB 缓冲区
      const buf = new ArrayBuffer(bufSize);
      let bytesRead = fileIo.readSync(srcFile.fd, buf);
      while (bytesRead > 0) {
        const writeBuf = buf.slice(0, bytesRead);
        fileIo.writeSync(destFile.fd, writeBuf);
        bytesRead = fileIo.readSync(srcFile.fd, buf);
      }
      // 关闭文件
      fileIo.closeSync(srcFile.fd);
      fileIo.closeSync(destFile.fd);
    } catch (err) {
      console.error('复制文件失败', JSON.stringify(err));
      throw new Error('复制文件失败: ' + JSON.stringify(err));
    }
  }

  // ---------- 导出功能 ----------

  /**
   * 打开文件保存对话框，将选中的文件导出到用户选择的位置
   */
  async exportFiles(): Promise<void> {
    try {
      // 检查是否有选中的文件
      const selectedPaths = this.getSelectedPaths();
      if (selectedPaths.length === 0) {
        showToast('请先选择要导出的文件或文件夹');
        return;
      }

      // 检查picker API是否可用
      if (!canIUse('SystemCapability.FileManagement.UserFileService')) {
        showToast('当前设备不支持文件保存功能');
        return;
      }

      // 创建文件保存对话框
      const documentPicker = new picker.DocumentViewPicker();

      // 逐个处理选中的文件
      let successCount = 0;
      for (const sourcePath of selectedPaths) {
        try {
          // 获取文件名
          const fileName = sourcePath.split('/').pop() || 'file';

          // 创建保存选项
          const documentSaveOptions = new picker.DocumentSaveOptions();
          documentSaveOptions.newFileNames = [fileName];

          // 打开保存对话框，让用户选择保存位置
          const result = await documentPicker.save(documentSaveOptions);

          if (!result || result.length === 0) {
            // 用户取消保存当前文件，继续处理下一个
            continue;
          }

          // 获取保存的URI
          const destUri = result[0];

          // 复制文件到用户选择的位置
          await this.copyFileToPublicDir(sourcePath, destUri);
          successCount++;
        } catch (err) {
          console.error('导出文件失败: ' + sourcePath, JSON.stringify(err));
        }
      }

      if (successCount > 0) {
        showToast('成功导出 ' + successCount + ' 个文件');
      } else {
        showToast('未导出任何文件');
      }

      // 刷新文件列表
      this.refresh();
    } catch (err) {
      const bizErr = err as BusinessError;
      if (bizErr.code === 0) {
        // 用户取消选择，不提示
        return;
      }
      showToast('导出失败: ' + bizErr.message);
      console.error('导出文件失败', JSON.stringify(err));
    }
  }

  /**
   * 将文件从沙箱复制到用户选择的公共目录
   */
  async copyFileToPublicDir(sourcePath: string, destUri: string): Promise<void> {
    try {
      // 检查fileIo API是否可用
      if (!canIUse('SystemCapability.FileManagement.File.FileIO')) {
        throw new Error('当前设备不支持文件操作功能');
      }
      
      // 打开源文件（只读）
      const srcFile = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);

      // 打开目标文件（读写，若存在则覆盖）
      const destFile = fileIo.openSync(destUri, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);

      // 复制文件内容
      const bufSize = 1024 * 1024; // 1MB 缓冲区
      const buf = new ArrayBuffer(bufSize);
      let bytesRead = fileIo.readSync(srcFile.fd, buf);
      while (bytesRead > 0) {
        const writeBuf = buf.slice(0, bytesRead);
        fileIo.writeSync(destFile.fd, writeBuf);
        bytesRead = fileIo.readSync(srcFile.fd, buf);
      }

      // 关闭文件
      fileIo.closeSync(srcFile.fd);
      fileIo.closeSync(destFile.fd);
    } catch (err) {
      console.error('复制文件失败', JSON.stringify(err));
      throw new Error('复制文件失败: ' + JSON.stringify(err));
    }
  }

  // ---------- UI 构建 ----------
  build() {
    Column() {
      this.TitleBar();
      this.ActionBar();

      Row() {
        Button(this.viewMode === 'list' ? '网格视图' : '列表视图')
          .onClick((): void => {
            this.viewMode = this.viewMode === 'list' ? 'grid' : 'list';
          })
          .fontSize(14)
          .height(32)
        Blank()
        if (this.isSelectionMode) {
          Button(this.selectedIndices.size === this.files.length ? '取消全选' : '全选')
            .onClick((): void => this.toggleSelectAll())
            .fontSize(14)
            .height(32)
        }
      }
      .padding({ left: 12, right: 12, bottom: 8 })
      .width('100%')

      if (this.isLoading) {
        LoadingProgress().width(100).height(100).margin({ top: 100 })
      } else if (this.files.length === 0) {
        Column() {
          Image($r('app.media.empty_folder'))
            .width(100)
            .height(100)
            .margin(20)
          Text('此文件夹为空')
            .fontSize(16)
            .fontColor(ColorResource.text_secondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        if (this.viewMode === 'list') {
          List({ space: 2 }) {
            ForEach(this.files, (item: FileItem, index: number) => {
              ListItem() {
                FileRow({
                  item: item,
                  selected: this.selectedIndices.has(index),
                  isSelectionMode: this.isSelectionMode,
                  onSelect: (selected: boolean): void => this.toggleSelect(index, selected),
                  onOpen: (): void => {
                    this.openFolder(item);
                  }
                })
              }
            }, (item: FileItem) => item.path)
          }
          .width('100%')
          .height('100%') // 添加高度设置
          .layoutWeight(1) // 可选，如果希望填充剩余空间
        } else {
          Grid() {
            ForEach(this.files, (item: FileItem, index: number) => {
              GridItem() {
                FileGridCell({
                  item: item,
                  selected: this.selectedIndices.has(index),
                  isSelectionMode: this.isSelectionMode,
                  onSelect: (selected: boolean): void => this.toggleSelect(index, selected),
                  onOpen: (): void => {
                    this.openFolder(item);
                  }
                })
              }
            }, (item: FileItem) => item.path)
          }
          .columnsTemplate('1fr 1fr 1fr 1fr')
          .columnsGap(4)
          .rowsGap(4)
          .padding(4)
          .width('100%')
          .layoutWeight(1)
        }
      }

      this.StatusBar();
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ColorResource.dialog_background)
  }

  // ---------- 标题栏 Builder ----------
  @Builder
  TitleBar() {
    Row() {
      if (this.currentPath !== this.getSandboxRoot()) {
        Button({ type: ButtonType.Circle }) {
          Image($r('sys.media.ohos_ic_back'))
            .width(20)
            .height(20)
        }
        .onClick((): void => this.goBack())
        .margin({ right: 8 })
      }
      // 显示友好路径名：将沙箱根目录显示为 "应用沙箱"
      Text(this.currentPath === this.getSandboxRoot() ? '应用沙箱' : this.currentPath.substring(this.getSandboxRoot().length + 1))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Button({ type: ButtonType.Circle }) {
        // 使用系统搜索图标，如果不存在请替换为其他图标
        Image($r('app.media.search'))
          .width(20)
          .height(20)
      }
      .onClick((): void => {
        showToast('搜索功能待实现');   // 使用封装后的函数
      })
      .margin({ right: 4 })
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.refresh'))
          .width(20)
          .height(20)
      }
      .onClick((): void => this.refresh())
    }
    .padding({ left: 12, right: 12 })
    .width('100%')
    .height(56)
    .backgroundColor(ColorResource.background_secondary)
  }

  // ---------- 操作栏 Builder ----------
  @Builder
  ActionBar() {
    Row() {
      if (this.isSelectionMode) {
        Button('压缩')
          .onClick((): void => this.showCompressDialog())
          .fontSize(14)
          .height(36)
        Blank()
        Button('解压')
          .onClick((): void => this.showExtractDialog())
          .fontSize(14)
          .height(36)
        Blank()
        Button('导出')
          .onClick((): void => {
            try {
              this.exportFiles();
            } catch (err) {
              console.error('导出失败', JSON.stringify(err));
              showToast('导出失败');
            }
          })
          .fontSize(14)
          .height(36)
        Blank()
        Button('删除')
          .onClick((): void => {
            try {
              this.showDeleteConfirmDialog();
            } catch (err) {
              console.error('删除失败', JSON.stringify(err));
              showToast('删除失败');
            }
          })
          .fontSize(14)
          .fontColor(Color.Red)
          .height(36)
      } else {
        Button('新建文件夹')
          .onClick((): void => {
            showToast('新建文件夹待实现');
          })
          .fontSize(14)
          .height(36)
        Blank()
        Button('导入')
          .onClick((): void => {
            try {
              this.importFiles();
            } catch (err) {
              console.error('导入失败', JSON.stringify(err));
              showToast('导入失败');
            }
          })
          .fontSize(14)
          .height(36)
        Blank()
        Button('导出')
          .onClick((): void => {
            try {
              this.exportFiles();
            } catch (err) {
              console.error('导出失败', JSON.stringify(err));
              showToast('导出失败');
            }
          })
          .fontSize(14)
          .height(36)
        Blank()
        Button('压缩')
          .onClick((): void => this.showCompressDialog())
          .fontSize(14)
          .height(36)
        Blank()
        Button('解压')
          .onClick((): void => this.showExtractDialog())
          .fontSize(14)
          .height(36)
      }
    }
    .padding({ left: 12, right: 12 })
    .width('100%')
    .height(48)
    .backgroundColor(ColorResource.background_tertiary)
  }

  // ---------- 底部状态栏 Builder ----------
  @Builder
  StatusBar() {
    Row() {
      Text(`选中 ${this.selectedIndices.size} 项`)
        .fontSize(12)
        .fontColor(ColorResource.text_secondary)
      Blank()
      Text(`${this.files.length} 个项目`)
        .fontSize(12)
        .fontColor(ColorResource.text_secondary)
    }
    .padding({ left: 12, right: 12 })
    .width('100%')
    .height(32)
    .backgroundColor(ColorResource.button_secondary_background)
  }
}

// 压缩对话框组件（需单独文件或在此定义）
// 定义选项接口，与 Select 组件要求的类型匹配
interface SelectOption {
  value: string;
}

@CustomDialog
struct CompressDialog {
  controller?: CustomDialogController;
  @Prop selectedPaths: string[] = [];  // 数据属性保留 @Prop
  onConfirm?: (options: CompressOptions) => Promise<void>;  // 移除 @Prop，改为可选

  private formats: ('7z' | 'zip' | 'tar')[] = ['7z', 'zip', 'tar'];
  @State selectedIndex: number = 0;
  @State password: string = '';
  @State splitSize: string = '';

  build() {
    Column() {
      Text('压缩选项').fontSize(20).margin(16)

      Row() {
        Text('格式:').width(80)
        // 使用泛型 map<SelectOption> 确保返回类型正确
        Select(this.formats.map<SelectOption>(f => ({ value: f })))
          .selected(this.selectedIndex)
          .onSelect((index: number, _: string): void => {
            this.selectedIndex = index;
          })
          .layoutWeight(1)
      }
      .width('100%')
      .padding(8)

      Row() {
        Text('密码:').width(80)
        TextInput({ placeholder: '可选', text: this.password })
          .onChange((value: string) => this.password = value)
          .type(InputType.Password)
          .layoutWeight(1)
      }
      .width('100%')
      .padding(8)

      Row() {
        Text('分卷大小:').width(80)
        TextInput({ placeholder: '例如 10M', text: this.splitSize })
          .onChange((value: string) => this.splitSize = value)
          .layoutWeight(1)
      }
      .width('100%')
      .padding(8)

      Row() {
        Button('取消')
          .onClick((): void => { this.controller?.close(); })
          .margin(8)
        Button('开始压缩')
          .onClick(async (): Promise<void> => {
            this.controller?.close();
            // 使用可选链调用 onConfirm
            if (this.onConfirm) {
              await this.onConfirm({
                format: this.formats[this.selectedIndex],
                password: this.password || undefined,
                splitSize: this.splitSize || undefined
              });
            }
          })
          .margin(8)
      }
      .margin(16)
    }
    .padding(16)
    .width('90%')
    .backgroundColor(ColorResource.dialog_background)
    .borderRadius(16)
  }
}
// 解压对话框组件
@CustomDialog
struct ExtractDialog {
  controller?: CustomDialogController;
  @Prop archivePath: string = '';
  @Prop sandboxRoot: string = '';
  onConfirm?: (destPath: string, password?: string) => Promise<void>;

  @State destPath: string = '';
  @State password: string = '';
  @State showDirPicker: boolean = false;
  @State dirPickerPath: string = '';
  @State dirPickerItems: FileItem[] = [];

  aboutToAppear(): void {
    // 根据 archivePath 自动生成默认解压路径
    console.info('ExtractDialog.aboutToAppear: archivePath =', this.archivePath);
    
    if (!this.archivePath) {
      console.warn('archivePath 为空，使用沙箱根目录');
      this.destPath = this.sandboxRoot;
      return;
    }
    
    const lastSlashIndex = this.archivePath.lastIndexOf('/');
    if (lastSlashIndex === -1) {
      console.warn('archivePath 不包含路径分隔符:', this.archivePath);
      this.destPath = this.sandboxRoot + '/' + this.archivePath.replace(/\.[^/.]+$/, '');
      return;
    }
    
    const baseName = this.archivePath.substring(lastSlashIndex + 1);
    const dirName = baseName.replace(/\.[^/.]+$/, '') || 'extracted';
    const parentDir = this.archivePath.substring(0, lastSlashIndex + 1);
    
    this.destPath = parentDir + dirName;
    console.info('生成的解压路径:', this.destPath);
  }

  /**
   * 打开目录浏览器，加载沙箱根目录的子目录列表
   */
  openDirPicker(): void {
    this.dirPickerPath = this.sandboxRoot;
    this.loadDirItems(this.dirPickerPath);
    this.showDirPicker = true;
  }

  /**
   * 加载指定路径下的所有子目录
   */
  loadDirItems(path: string): void {
    try {
      const names: string[] = fileIo.listFileSync(path);
      const dirs: FileItem[] = [];
      for (const name of names) {
        const fullPath = path + '/' + name;
        try {
          const stat = fileIo.statSync(fullPath);
          if (stat.isDirectory()) {
            dirs.push({
              name: name,
              path: fullPath,
              isDir: true,
              size: 0,
              modified: stat.mtime
            });
          }
        } catch (e) {
          console.error('stat 失败: ' + fullPath, JSON.stringify(e));
        }
      }
      dirs.sort((a, b) => a.name.localeCompare(b.name));
      this.dirPickerItems = dirs;
    } catch (err) {
      console.error('加载目录列表失败', JSON.stringify(err));
      this.dirPickerItems = [];
    }
  }

  /**
   * 进入子目录
   */
  enterDir(dirPath: string): void {
    this.dirPickerPath = dirPath;
    this.loadDirItems(dirPath);
  }

  /**
   * 返回上级目录
   */
  goUpDir(): void {
    if (this.dirPickerPath === this.sandboxRoot) {
      return;
    }
    const parent = this.dirPickerPath.substring(0, this.dirPickerPath.lastIndexOf('/'));
    this.dirPickerPath = parent || this.sandboxRoot;
    this.loadDirItems(this.dirPickerPath);
  }

  /**
   * 确认选择当前目录
   */
  confirmDir(): void {
    this.destPath = this.dirPickerPath;
    this.showDirPicker = false;
  }

  build() {
    Column() {
      if (this.showDirPicker) {
        // ---------- 目录浏览器模式 ----------
        Column() {
          // 标题栏
          Row() {
            if (this.dirPickerPath !== this.sandboxRoot) {
              Button({ type: ButtonType.Circle }) {
                Image($r('sys.media.ohos_ic_back'))
                  .width(18)
                  .height(18)
              }
              .onClick((): void => this.goUpDir())
              .width(32)
              .height(32)
            }
            Text('选择目标目录')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .layoutWeight(1)
              .margin({ left: 8 })
          }
          .width('100%')
          .padding(8)

          // 当前路径
          Text(this.dirPickerPath === this.sandboxRoot ?
            '应用沙箱' : this.dirPickerPath.substring(this.sandboxRoot.length + 1))
            .fontSize(12)
            .fontColor(ColorResource.text_secondary)
            .width('100%')
            .padding({ left: 8, bottom: 4 })

          // 目录列表
          List({ space: 4 }) {
            ForEach(this.dirPickerItems, (item: FileItem) => {
              ListItem() {
                Row() {
                  Image($r('app.media.folder'))
                    .width(24)
                    .height(24)
                    .margin({ right: 8 })
                  Text(item.name)
                    .fontSize(14)
                    .layoutWeight(1)
                  Text('>')
                    .fontSize(16)
                    .fontColor(ColorResource.text_tertiary)
                }
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .width('100%')
                .onClick((): void => {
                  this.enterDir(item.path);
                })
              }
            }, (item: FileItem) => item.path)
          }
          .layoutWeight(1)
          .width('100%')
          .height('100%')

          // 按钮行
          Row() {
            Button('取消')
              .onClick((): void => {
                this.showDirPicker = false;
              })
              .margin(8)
            Button('选择此目录')
              .onClick((): void => {
                this.confirmDir();
              })
              .margin(8)
              .fontColor(ColorResource.text_inverse)
              .backgroundColor(ColorResource.accent_primary)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding(8)
        }
        .width('100%')
        .height('100%')
      } else {
        // ---------- 正常解压表单模式 ----------
        Text('解压到')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin(16)

        // 目标路径行
        Row() {
          Text('目标路径:')
            .width(80)
          TextInput({ placeholder: '选择路径', text: this.destPath })
            .onChange((value: string) => this.destPath = value)
            .layoutWeight(1)
          Button('...')
            .onClick((): void => {
              this.openDirPicker();
            })
            .height(40)
        }
        .width('100%')
        .padding(8)

        // 密码输入行
        Row() {
          Text('密码:')
            .width(80)
          TextInput({ placeholder: '如果需要', text: this.password })
            .onChange((value: string) => this.password = value)
            .type(InputType.Password)
            .layoutWeight(1)
        }
        .width('100%')
        .padding(8)

        // 按钮行
        Row() {
          Button('取消')
            .onClick((): void => {
              this.controller?.close();
            })
            .margin(8)
          Button('开始解压')
            .onClick(async (): Promise<void> => {
              // 验证目标路径
              if (!this.destPath || this.destPath.trim() === '') {
                showToast('请选择或输入有效的目标路径');
                return;
              }
              
              // 清理路径：移除开头和结尾的空格，确保以沙箱根目录开头
              let cleanPath = this.destPath.trim();
              if (!cleanPath.startsWith(this.sandboxRoot)) {
                // 如果不是绝对路径，则相对于沙箱根目录
                if (cleanPath.startsWith('/')) {
                  // 已经是绝对路径，但不在沙箱内
                  showToast('目标路径必须在应用沙箱内');
                  return;
                } else {
                  // 相对路径，转换为绝对路径
                  cleanPath = this.sandboxRoot + '/' + cleanPath;
                }
              }
              
              this.controller?.close();
              if (this.onConfirm) {
                await this.onConfirm(cleanPath, this.password || undefined);
              }
            })
            .margin(8)
        }
        .margin(16)
      }
    }
    .padding(16)
    .width('90%')
    .height(this.showDirPicker ? '80%' : 'auto')
    .backgroundColor(ColorResource.dialog_background)
    .borderRadius(16)
  }
}

// 删除确认对话框组件
@CustomDialog
struct DeleteConfirmDialog {
  controller?: CustomDialogController;
  @Prop message: string = '';
  onConfirm?: () => Promise<void>;

  build() {
    Column() {
      Text('确认删除')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 16, bottom: 16 })

      Text(this.message)
        .fontSize(14)
        .textAlign(TextAlign.Start)
        .padding({ left: 16, right: 16, bottom: 24 })
        .width('100%')

      Row() {
        Button('取消')
          .onClick((): void => {
            this.controller?.close();
          })
          .backgroundColor(ColorResource.button_secondary_background)
          .fontColor(ColorResource.text_primary)
          .margin(8)
          .width(100)
          .height(40)

        Button('确认删除')
          .onClick(async (): Promise<void> => {
            this.controller?.close();
            if (this.onConfirm) {
              await this.onConfirm();
            }
          })
          .backgroundColor(ColorResource.button_danger_background)
          .fontColor(ColorResource.text_inverse)
          .margin(8)
          .width(100)
          .height(40)
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .margin({ bottom: 16 })
    }
    .padding(16)
    .width('80%')
    .backgroundColor(ColorResource.dialog_background)
    .borderRadius(16)
  }
}