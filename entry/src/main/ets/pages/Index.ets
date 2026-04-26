import { BusinessError } from '@kit.BasicServicesKit';
import { ToastUtil } from '../utils/ToastUtil';
import { FileRow } from '../components/FileRow';
import { FileGridCell } from '../components/FileGridCell';
import { isArchiveFile } from '../utils/FileTypeUtil';
import { common } from '@kit.AbilityKit';

// 导入拆分后的模块
import { FileItem, ColorResource, CompressOptions, ExtractOptions } from '../types/types';
import { FileManager } from '../managers/FileManager';
import { ArchiveManager } from '../managers/ArchiveManager';
import { CompressDialog, ExtractDialog, DeleteConfirmDialog } from '../components/UiComponents';





@Entry
@Component
struct FileBrowser {
  // 状态变量
  @State files: FileItem[] = [];
  @State currentPath: string = '';
  @State selectedIndices: Set<number> = new Set();
  @State isSelectionMode: boolean = false;
  @State viewMode: 'list' | 'grid' = 'list';
  @State isLoading: boolean = false;
  @State searchKeyword: string = '';

  // 管理器实例
  private fileManager: FileManager | null = null;
  private archiveManager: ArchiveManager | null = null;

  // 对话框控制器
  compressDialogController: CustomDialogController | null = null;
  extractDialogController: CustomDialogController | null = null;
  deleteDialogController: CustomDialogController | null = null;

  aboutToAppear(): void {
    try {
      // 获取 UIAbilityContext
      const context = getContext(this) as common.UIAbilityContext;
      if (context && context.filesDir) {
        this.currentPath = context.filesDir;
        console.log('当前路径设置为:', this.currentPath);

        this.fileManager = new FileManager(this.currentPath, context);
        this.archiveManager = new ArchiveManager();

        const uiContext = this.getUIContext();
        ToastUtil.setUIContext(uiContext);

        this.loadFiles();
      } else {
        console.error('获取上下文失败，无法初始化管理器');
        ToastUtil.showToast('初始化失败: 无法获取应用上下文');
        // 后备方案：仅使用沙箱路径，不传 context（导入导出功能会受限）
        this.currentPath = '/data/storage/el2/base/files';
        this.fileManager = new FileManager(this.currentPath);
        this.archiveManager = new ArchiveManager();
        this.loadFiles();
      }
    } catch (err) {
      console.error('aboutToAppear初始化失败:', err);
      ToastUtil.showToast('应用初始化失败: ' + (err as Error).message);
      // 最终回退
      try {
        this.currentPath = '/data/storage/el2/base/files';
        this.fileManager = new FileManager(this.currentPath);
        this.archiveManager = new ArchiveManager();
        this.loadFiles();
      } catch (fallbackErr) {
        console.error('回退初始化也失败:', fallbackErr);
      }
    }
  }

  getSandboxRoot(): string {
    try {
      const uicontext = this.getUIContext();
      if (!uicontext) {
        console.error('getSandboxRoot: 无法获取UIContext');
        return '/data/storage/el2/base/files';
      }

      const context = uicontext.getHostContext();
      if (context && context.filesDir) {
        return context.filesDir;
      } else {
        console.warn('getSandboxRoot: 无法获取filesDir，使用默认路径');
        return '/data/storage/el2/base/files';
      }
    } catch (err) {
      console.error('getSandboxRoot异常:', JSON.stringify(err));
      return '/data/storage/el2/base/files';
    }
  }

  // 辅助方法：安全访问 fileManager
  private getFileManager(): FileManager {
    if (!this.fileManager) {
      throw new Error('FileManager 未初始化');
    }
    return this.fileManager;
  }

  // 辅助方法：安全访问 archiveManager
  private getArchiveManager(): ArchiveManager {
    if (!this.archiveManager) {
      throw new Error('ArchiveManager 未初始化');
    }
    return this.archiveManager;
  }

  async loadFiles(): Promise<void> {
    this.isLoading = true;
    try {
      const fileManager = this.getFileManager();
      await fileManager.loadFiles();
      this.files = fileManager.getFiles();
    } catch (err) {
      ToastUtil.showToast('加载失败: ' + (err as BusinessError).message);
      console.error('加载文件列表失败', JSON.stringify(err));
    } finally {
      this.isLoading = false;
    }
  }

  refresh(): void {
    this.loadFiles();
  }

  goBack(): void {
    try {
      const sandboxRoot = this.getSandboxRoot();
      if (!sandboxRoot || sandboxRoot === '') {
        ToastUtil.showToast('无法获取沙箱根目录');
        return;
      }

      if (this.currentPath === sandboxRoot) {
        ToastUtil.showToast('已在沙箱根目录');
        return;
      }

      if (!this.currentPath || this.currentPath === '') {
        this.currentPath = sandboxRoot;
        this.refresh();
        return;
      }

      const parts = this.currentPath.split('/').filter(part => part.trim() !== '');
      if (parts.length <= 1) {
        this.currentPath = sandboxRoot;
      } else {
        parts.pop();
        this.currentPath = parts.join('/');
        // 确保路径不以斜杠开头
        if (this.currentPath.startsWith('/')) {
          this.currentPath = this.currentPath.substring(1);
        }
      }

      // 更新FileManager的当前路径
      if (this.fileManager) {
        this.fileManager.setCurrentPath(this.currentPath);
      }

      this.refresh();
    } catch (err) {
      console.error('返回操作失败:', JSON.stringify(err));
      ToastUtil.showToast('返回失败: ' + (err as Error).message);
    }
  }

  toggleSelect(index: number, selected: boolean): void {
    const fileManager = this.getFileManager();
    fileManager.toggleSelect(index, selected);
    this.selectedIndices = fileManager.getSelectedIndices();
    this.isSelectionMode = this.selectedIndices.size > 0;
  }

  toggleSelectAll(): void {
    const fileManager = this.getFileManager();
    fileManager.toggleSelectAll();
    this.selectedIndices = fileManager.getSelectedIndices();
    this.isSelectionMode = this.selectedIndices.size > 0;
  }

  getSelectedPaths(): string[] {
    const fileManager = this.getFileManager();
    return fileManager.getSelectedPaths();
  }

  openFolder(item: FileItem): void {
    const fileManager = this.getFileManager();
    fileManager.openFolder(item);
    this.currentPath = fileManager.getCurrentPath();
    this.selectedIndices.clear();
    this.isSelectionMode = false;
    this.refresh();
  }

  async openFile(item: FileItem): Promise<void> {
    const fileManager = this.getFileManager();
    await fileManager.openFile(item);
    this.selectedIndices = fileManager.getSelectedIndices();
    this.isSelectionMode = this.selectedIndices.size > 0;
  }

  showCompressDialog(): void {
    if (this.selectedIndices.size === 0) {
      try {
        ToastUtil.showToast('请先选择文件或文件夹');
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
      const archiveManager = this.getArchiveManager();
      await archiveManager.startCompress(this.getSelectedPaths(), this.currentPath, options);
      this.selectedIndices.clear();
      this.isSelectionMode = false;
      this.refresh();
    } catch (err) {
      console.error('压缩失败', JSON.stringify(err));
    } finally {
      this.isLoading = false;
    }
  }

  showExtractDialog(): void {
    const selectedPaths = this.getSelectedPaths();
    if (selectedPaths.length !== 1) {
      ToastUtil.showToast('请选择一个压缩包');
      return;
    }
    this.extractDialogController = new CustomDialogController({
      builder: ExtractDialog({
        archivePath: selectedPaths[0],
        sandboxRoot: this.getSandboxRoot(),
        onConfirm: (destPath: string, password?: string): Promise<void> => this.startExtract(destPath, password)
      }),
      cancel: (): void => { this.extractDialogController?.close(); }
    });
    this.extractDialogController.open();
  }

  async startExtract(destPath: string, password?: string): Promise<void> {
    this.isLoading = true;
    try {
      const archiveManager = this.getArchiveManager();
      const options: ExtractOptions = {
        password: password,
        extractPath: destPath
      };
      await archiveManager.startExtract(this.getSelectedPaths(), this.currentPath, options);
      this.selectedIndices.clear();
      this.isSelectionMode = false;
      this.refresh();
    } catch (err) {
      console.error('解压失败', JSON.stringify(err));
    } finally {
      this.isLoading = false;
    }
  }

  showDeleteConfirmDialog(): void {
    const selectedPaths = this.getSelectedPaths();
    if (selectedPaths.length === 0) {
      ToastUtil.showToast('请先选择要删除的文件或文件夹');
      return;
    }
    this.deleteDialogController = new CustomDialogController({
      builder: DeleteConfirmDialog({
        message: `确定要删除选中的 ${selectedPaths.length} 个文件/文件夹吗？`,
        onConfirm: (): Promise<void> => this.deleteSelectedFiles()
      }),
      cancel: (): void => { this.deleteDialogController?.close(); }
    });
    this.deleteDialogController.open();
  }

  async deleteSelectedFiles(): Promise<void> {
    const fileManager = this.getFileManager();
    await fileManager.deleteSelectedFiles();
    this.selectedIndices = fileManager.getSelectedIndices();
    this.files = fileManager.getFiles();
    this.isSelectionMode = false;
  }

  async importFiles(): Promise<void> {
    const fileManager = this.getFileManager();
    await fileManager.importFiles();
    this.files = fileManager.getFiles();
  }

  async exportFiles(): Promise<void> {
    const fileManager = this.getFileManager();
    await fileManager.exportFiles();
  }

  async openFileWithOtherApp(item: FileItem): Promise<void> {
    try {
      await this.getFileManager().openWithOtherApp(item.path);
    } catch (err) {
      ToastUtil.showToast((err as Error).message);
    }
  }

  openArchiveItem(item: FileItem): void {
    const fileManager = this.getFileManager();
    // 1. 清除所有选中
    const currentSelected = Array.from(fileManager.getSelectedIndices());
    for (const idx of currentSelected) {
      fileManager.toggleSelect(idx, false);
    }
    // 2. 选中当前文件
    const index = this.files.findIndex(f => f.path === item.path);
    if (index !== -1) {
      fileManager.toggleSelect(index, true);
    }
    // 3. 同步页面状态
    this.selectedIndices = fileManager.getSelectedIndices();
    this.isSelectionMode = false; // 可选，退出多选模式
    // 4. 弹出解压对话框
    this.showExtractDialog();
  }


  // ---------- UI构建 ----------

  @Builder
  TitleBar() {
    Column() {
      Row() {
        Text('文件管理器')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(ColorResource.text_primary)
          .layoutWeight(1)

        if (this.isSelectionMode) {
          Text(`已选择 ${this.selectedIndices.size} 个`)
            .fontSize(14)
            .fontColor(ColorResource.text_secondary)
            .margin({ right: 12 })
        }

        Button(this.isSelectionMode ? '取消' : '选择')
          .onClick(() => {
            if (this.isSelectionMode) {
              this.selectedIndices.clear();
              this.isSelectionMode = false;
            } else {
              this.isSelectionMode = true;
            }
          })
          .backgroundColor(ColorResource.button_secondary_background)
          .fontColor(ColorResource.button_secondary_text)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(4)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .backgroundColor(ColorResource.background_secondary)
    }
  }

  @Builder
  ActionBar() {
    Row() {
      // 返回按钮
      Button('返回')
        .enabled(this.currentPath !== this.getSandboxRoot())
        .onClick(() => this.goBack())
        .backgroundColor(ColorResource.button_secondary_background)
        .fontColor(ColorResource.button_secondary_text)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(4)

      // 刷新按钮
      Button('刷新')
        .onClick(() => this.refresh())
        .backgroundColor(ColorResource.button_secondary_background)
        .fontColor(ColorResource.button_secondary_text)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(4)
        .margin({ left: 8 })

      // 视图切换
      Button(this.viewMode === 'list' ? '网格' : '列表')
        .onClick(() => {
          this.viewMode = this.viewMode === 'list' ? 'grid' : 'list';
        })
        .backgroundColor(ColorResource.button_secondary_background)
        .fontColor(ColorResource.button_secondary_text)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(4)
        .margin({ left: 8 })

      // 搜索框
      TextInput({ placeholder: '搜索文件...', text: this.searchKeyword })
        .onChange((value: string) => this.searchKeyword = value)
        .layoutWeight(1)
        .margin({ left: 8 })
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(ColorResource.background_tertiary)
        .borderRadius(4)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor(ColorResource.background_primary)
  }

  @Builder
  StatusBar() {
    Row() {
      // 全选按钮
      if (this.isSelectionMode) {
        Button('全选')
          .onClick(() => this.toggleSelectAll())
          .backgroundColor(ColorResource.button_secondary_background)
          .fontColor(ColorResource.button_secondary_text)
          .padding({ left: 4, right: 4, top: 8, bottom: 8 })
          .borderRadius(4)
          .margin({ right: 8 })
      }

      // 压缩按钮
      Button('压缩')
        .enabled(this.selectedIndices.size > 0)
        .onClick(() => this.showCompressDialog())
        .backgroundColor(ColorResource.button_primary_background)
        .fontColor(ColorResource.button_primary_text)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(4)
        .margin({ right: 8 })

      // 解压按钮
      Button('解压')
        .enabled(this.selectedIndices.size === 1 && isArchiveFile(this.files[Array.from(this.selectedIndices)[0]]?.name || ''))
        .onClick(() => this.showExtractDialog())
        .backgroundColor(ColorResource.button_primary_background)
        .fontColor(ColorResource.button_primary_text)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(4)
        .margin({ right: 8 })

      // 删除按钮
      Button('删除')
        .enabled(this.selectedIndices.size > 0)
        .onClick(() => this.showDeleteConfirmDialog())
        .backgroundColor(ColorResource.button_danger_background)
        .fontColor(ColorResource.button_danger_text)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(4)
        .margin({ right: 8 })

      // 导入按钮
      Button('导入')
        .onClick(() => this.importFiles())
        .backgroundColor(ColorResource.button_secondary_background)
        .fontColor(ColorResource.button_secondary_text)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(4)
        .margin({ right: 8 })

      // 导出按钮
      Button('导出')
        .enabled(this.selectedIndices.size > 0)
        .onClick(() => this.exportFiles())
        .backgroundColor(ColorResource.button_secondary_background)
        .fontColor(ColorResource.button_secondary_text)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(4)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor(ColorResource.background_secondary)
  }

  build() {
    Column() {
      // 顶部固定区域（不滚动）
      this.TitleBar()
      this.ActionBar()

      // 路径显示栏
      Row() {
        Text(this.currentPath)
          .fontSize(12)
          .fontColor(ColorResource.text_secondary)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .maxLines(1)
          .layoutWeight(1)
          .margin({ left: 16, right: 16, top: 8, bottom: 8 })
      }
      .backgroundColor(ColorResource.background_tertiary)

      // 可滚动的文件列表区域（自动占满剩余高度）
      Scroll() {
        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .color(ColorResource.accent_primary)
              .width(40)
              .height(40)
            Text('加载中...')
              .fontSize(14)
              .fontColor(ColorResource.text_secondary)
              .margin({ top: 12 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.files.length === 0) {
          Column() {
            Image($r('app.media.folder'))
              .width(80)
              .height(80)
              .margin({ bottom: 16 })
            Text('文件夹为空')
              .fontSize(16)
              .fontColor(ColorResource.text_secondary)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          if (this.viewMode === 'list') {
            List() {
              ForEach(this.files, (item: FileItem, index: number) => {
                ListItem() {
                  FileRow({
                    item: item,
                    selected: this.selectedIndices.has(index),
                    isSelectionMode: this.isSelectionMode,
                    onSelect: (selected: boolean) => this.toggleSelect(index, selected),
                    onOpen: () => {
                      if (item.isDir) {
                        this.openFolder(item);
                      } else if (isArchiveFile(item.name)) {
                        this.openArchiveItem(item);
                      } else {
                        this.openFileWithOtherApp(item);
                      }
                    }
                  })
                }
              }, (item: FileItem) => item.path)
            }
            .width('100%')
            .height('100%')   // 添加这行
          } else {
            Grid() {
              ForEach(this.files, (item: FileItem, index: number) => {
                GridItem() {
                  FileGridCell({
                    item: item,
                    selected: this.selectedIndices.has(index),
                    isSelectionMode: this.isSelectionMode,
                    onSelect: (selected: boolean) => this.toggleSelect(index, selected),
                    onOpen: () => {
                      if (item.isDir) {
                        this.openFolder(item);
                      } else if (isArchiveFile(item.name)) {
                        this.openArchiveItem(item);
                      } else {
                        this.openFileWithOtherApp(item);
                      }
                    }
                  })
                }
              }, (item: FileItem) => item.path)
            }
            .columnsTemplate('1fr 1fr 1fr')
            .rowsTemplate('auto')
            .columnsGap(8)
            .rowsGap(8)
            .width('100%')
            .padding(8)
          }
        }
      }
      .width('100%')
      .layoutWeight(1)              // 关键：占据剩余所有垂直空间
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)

      // 底部功能区（始终在底部）
      this.StatusBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ColorResource.background_primary)
  }
}