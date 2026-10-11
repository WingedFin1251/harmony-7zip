import abilityAccessCtrl, { Permissions, PermissionRequestResult } from '@ohos.abilityAccessCtrl';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import * as native from 'libentry.so';
import { showToast } from '../utils/ToastUtil';
import { FileRow } from '../components/FileRow';
import { FileGridCell } from '../components/FileGridCell';

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
        onConfirm: (destPath: string, password?: string): void => {
          this.startExtract(first.path, destPath, password);
        }
      }),
      cancel: (): void => { this.extractDialogController?.close(); }
    });
    this.extractDialogController.open();
  }

  async startExtract(archivePath: string, destPath: string, password?: string): Promise<void> {
    this.isLoading = true;
    try {
      // 1. 检查压缩文件是否存在
      try {
        fileIo.statSync(archivePath);
      } catch (statErr) {
        showToast('解压失败: 压缩文件不存在');
        console.error('压缩文件不存在: ' + archivePath, JSON.stringify(statErr));
        return;
      }

      // 2. 确保目标目录存在（如果不存在则创建）
      try {
        fileIo.mkdirSync(destPath, true); // recursive = true
      } catch (mkdirErr) {
        // 如果目录已存在，忽略错误
        console.info('创建目录（可能已存在）: ' + destPath);
      }

      // 3. 执行解压
      await native.extract(archivePath, destPath, password);
      showToast('解压成功');
      this.refresh();
    } catch (err) {
      const errMsg = (err as BusinessError).message || JSON.stringify(err);
      showToast('解压失败: ' + errMsg);
      console.error('解压失败详情', errMsg);
    } finally {
      this.isLoading = false;
      this.selectedIndices.clear();
      this.isSelectionMode = false;
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
      // 创建文件选择器
      const documentPicker = new picker.DocumentViewPicker();
      const result = await documentPicker.select({
        maxSelectNumber: 10 // 最多选择10个文件
      });
      if (!result || result.length === 0) {
        return;
      }
      showToast('正在导入 ' + result.length + ' 个文件...');
      // 逐个复制文件到当前目录
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
      // 打开源文件（只读）
      const srcFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      // 获取文件名
      const stat = fileIo.statSync(srcFile.fd);
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
            .fontColor('#666')
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
                    if (item.isDir) {
                      this.openFolder(item);
                    } else {
                      if (!this.isSelectionMode) {
                        this.isSelectionMode = true;
                        this.selectedIndices.add(index);
                      }
                    }
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
                    if (item.isDir) {
                      this.openFolder(item);
                    } else {
                      if (!this.isSelectionMode) {
                        this.isSelectionMode = true;
                        this.selectedIndices.add(index);
                      }
                    }
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
    .backgroundColor('#fff')
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
    .backgroundColor('#f5f5f5')
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
    .backgroundColor('#fafafa')
  }

  // ---------- 底部状态栏 Builder ----------
  @Builder
  StatusBar() {
    Row() {
      Text(`选中 ${this.selectedIndices.size} 项`)
        .fontSize(12)
        .fontColor('#666')
      Blank()
      Text(`${this.files.length} 个项目`)
        .fontSize(12)
        .fontColor('#666')
    }
    .padding({ left: 12, right: 12 })
    .width('100%')
    .height(32)
    .backgroundColor('#f0f0f0')
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
          .onClick((): void => {
            this.controller?.close();
            // 使用可选链调用 onConfirm
            this.onConfirm?.({
              format: this.formats[this.selectedIndex],
              password: this.password || undefined,
              splitSize: this.splitSize || undefined
            });
          })
          .margin(8)
      }
      .margin(16)
    }
    .padding(16)
    .width('90%')
    .backgroundColor('#fff')
    .borderRadius(16)
  }
}
// 解压对话框组件
@CustomDialog
struct ExtractDialog {
  controller?: CustomDialogController;
  @Prop archivePath: string = '';
  @Prop sandboxRoot: string = '';
  onConfirm?: (destPath: string, password?: string) => void;

  @State destPath: string = '';
  @State password: string = '';
  @State showDirPicker: boolean = false;
  @State dirPickerPath: string = '';
  @State dirPickerItems: FileItem[] = [];

  aboutToAppear(): void {
    // 根据 archivePath 自动生成默认解压路径
    const baseName = this.archivePath.substring(this.archivePath.lastIndexOf('/') + 1);
    const dirName = baseName.replace(/\.[^/.]+$/, '');
    this.destPath = this.archivePath.substring(0, this.archivePath.lastIndexOf('/') + 1) + dirName;
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
            .fontColor('#666')
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
                    .fontColor('#999')
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
              .fontColor(Color.White)
              .backgroundColor('#007aff')
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
            .onClick((): void => {
              this.controller?.close();
              this.onConfirm?.(this.destPath, this.password || undefined);
            })
            .margin(8)
        }
        .margin(16)
      }
    }
    .padding(16)
    .width('90%')
    .height(this.showDirPicker ? '80%' : 'auto')
    .backgroundColor('#fff')
    .borderRadius(16)
  }
}