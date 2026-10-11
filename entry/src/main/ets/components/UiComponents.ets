import { CompressOptions, ColorResource } from '../types/types';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { FileItem } from '../types/types'; // 注意：需要从你的 types 导入 FileItem
// 压缩对话框组件
@CustomDialog
export struct CompressDialog {
  controller: CustomDialogController;
  selectedPaths: string[] = [];
  onConfirm?: (options: CompressOptions) => Promise<void>;

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
          .onClick((): void => { this.controller.close(); })
          .margin(8)
        Button('开始压缩')
          .onClick(async (): Promise<void> => {
            if (this.onConfirm) {
              const options: CompressOptions = {
                format: this.formats[this.selectedIndex],
                password: this.password || undefined,
                splitSize: this.splitSize || undefined
              };
              await this.onConfirm(options);
              this.controller.close();
            }
          })
          .margin(8)
      }
      .justifyContent(FlexAlign.End)
      .width('100%')
      .padding(8)
    }
    .backgroundColor(ColorResource.dialog_background)
    .padding(16)
    .borderRadius(8)
  }
}

// 解压对话框组件
@CustomDialog
export struct ExtractDialog {
  controller: CustomDialogController;
  archivePath: string = '';
  sandboxRoot: string = '';
  onConfirm?: (destPath: string, password?: string, isExternal?: boolean) => Promise<void>;

  @State password: string = '';
  @State extractPath: string = '';
  @State isExternal: boolean = false;

  private dirPickerController: CustomDialogController | null = null;
  private context: common.UIAbilityContext | null = null;

  /**
   * 获取压缩包的基础名称（不含扩展名，不含路径）
   */
  private getArchiveBaseName(): string {
    const fullFileName = this.archivePath.split('/').pop() || 'archive';
    const lastDotIndex = fullFileName.lastIndexOf('.');
    return lastDotIndex > 0 ? fullFileName.substring(0, lastDotIndex) : fullFileName;
  }

  /**
   * 获取默认解压路径：沙箱根目录 / 压缩包文件名（不含扩展名）
   */
  private getDefaultExtractPath(): string {
    return `${this.sandboxRoot}/${this.getArchiveBaseName()}`;
  }

  aboutToAppear(): void {
    try {
      this.context = getContext(this) as common.UIAbilityContext;
    } catch (e) {
      console.error('ExtractDialog 获取上下文失败', e);
    }
    // 默认解压路径：沙箱根目录 / 压缩包文件名（不含扩展名）
    this.extractPath = this.getDefaultExtractPath();

    // 初始化目录选择器控制器
    this.dirPickerController = new CustomDialogController({
      builder: DirectoryPickerDialog({
        sandboxRoot: this.sandboxRoot,   // ✅ 必须传入
        onSelect: (uri: string, isExternal: boolean) => {
          if (isExternal && uri) {
            // 外部存储：直接使用用户选择的目录URI
            this.extractPath = uri;
            this.isExternal = true;
          } else if (!isExternal && uri) {
            // 内部存储：在用户选择的目录下自动创建以压缩包命名的子文件夹
            this.extractPath = `${uri}/${this.getArchiveBaseName()}`;
            this.isExternal = false;
          } else {
            // 兜底：使用默认路径
            this.extractPath = this.getDefaultExtractPath();
            this.isExternal = false;
          }
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
  }

  build() {
    Column() {
      Text('解压选项')
        .fontSize(20)
        .margin(16)

      // 密码输入行
      Row() {
        Text('密码:')
          .width(80)
        TextInput({ placeholder: '可选', text: this.password })
          .onChange((value: string) => this.password = value)
          .type(InputType.Password)
          .layoutWeight(1)
      }
      .width('100%')
      .padding(8)

      // 解压路径选择行
      Row() {
        Text('解压到:')
          .width(80)
        TextInput({ text: this.extractPath })
          .onChange((value: string) => {
            this.extractPath = value;
            this.isExternal = false; // 手动输入视为内部路径
          })
          .layoutWeight(1)
        Button('浏览')
          .onClick(() => {
            this.dirPickerController?.open();
          })
          .margin({ left: 8 })
      }
      .width('100%')
      .padding(8)

      // 外部存储提示
      if (this.isExternal) {
        Column() {
          Text('提示：文件将先解压到临时目录，然后复制到外部存储，完成后自动删除临时文件')
            .fontSize(12)
            .fontColor(ColorResource.status_info)
            .margin({ top: 8, bottom: 4 })
          Text('注意：外部存储将扁平化保存所有文件（不保留文件夹层级）')
            .fontSize(12)
            .fontColor(ColorResource.status_warning)
            .margin({ bottom: 8 })
        }
        .width('100%')
      }

      // 操作按钮
      Row() {
        Button('取消')
          .onClick(() => this.controller.close())
          .margin(8)
        Button('开始解压')
          .onClick(async () => {
            if (this.onConfirm) {
              await this.onConfirm(this.extractPath, this.password || undefined, this.isExternal);
              this.controller.close();
            }
          })
          .margin(8)
      }
      .justifyContent(FlexAlign.End)
      .width('100%')
      .padding(8)
    }
    .backgroundColor(ColorResource.dialog_background)
    .padding(16)
    .borderRadius(8)
  }
}

// 删除确认对话框组件
@CustomDialog
export struct DeleteConfirmDialog {
  controller: CustomDialogController;
  message: string = '';
  onConfirm?: () => Promise<void>;

  build() {
    Column() {
      Text('确认删除')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 16, bottom: 16 })

      Text(this.message)
        .fontSize(16)
        .textAlign(TextAlign.Center)
        .margin({ bottom: 24 })

      Row() {
        Button('取消')
          .onClick((): void => { this.controller.close(); })
          .margin(8)
        Button('删除')
          .backgroundColor(ColorResource.button_danger_background)
          .fontColor(ColorResource.button_danger_text)
          .onClick(async (): Promise<void> => {
            if (this.onConfirm) {
              await this.onConfirm();
              this.controller.close();
            }
          })
          .margin(8)
      }
      .justifyContent(FlexAlign.End)
      .width('100%')
    }
    .backgroundColor(ColorResource.dialog_background)
    .padding(16)
    .borderRadius(8)
  }
}

// 选择选项接口
interface SelectOption {
  value: string;
}

@CustomDialog
export struct DirectoryPickerDialog {
  controller: CustomDialogController;
  sandboxRoot: string = '';
  onSelect?: (uri: string, isExternal: boolean) => void;

  private context: common.UIAbilityContext | null = null;
  private internalPickerController: CustomDialogController | null = null;

  aboutToAppear(): void {
    try {
      this.context = getContext(this) as common.UIAbilityContext;
    } catch (e) {
      console.error('DirectoryPickerDialog 获取上下文失败', e);
    }

    // 内部目录选择器（始终可用）
    this.internalPickerController = new CustomDialogController({
      builder: InternalDirectoryPickerDialog({
        sandboxRoot: this.sandboxRoot,
        onSelect: (selectedPath: string) => {
          this.onSelect?.(selectedPath, false);
          this.controller.close(); // 选择完毕后关闭外层对话框
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
  }

  build() {
    Column() {
      Text('选择解压位置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 16, bottom: 16 })

      // 按钮1：内部存储（沙箱）- 始终可用
      Button('内部存储（沙箱）')
        .width('80%')
        .margin({ bottom: 12 })
        .onClick(() => {
          this.internalPickerController?.open();
        })

      // 按钮2：外部存储（公共目录）- 根据能力决定行为
      Button('外部存储（公共目录）')
        .width('80%')
        .margin({ bottom: 20 })
        .onClick(async () => {
          if (!this.context) {
            promptAction.showToast({ message: '无法获取应用上下文' });
            return;
          }

          // 第一步：检测是否支持文件夹选择器
          const supportsFolderPicker = canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection');

          if (!supportsFolderPicker) {
            // 不支持 -> 友好提示，并引导使用内部存储
            promptAction.showToast({
              message: '当前设备不支持直接选择外部文件夹，您可以使用“内部存储”功能',
              duration: 2000
            });
            // 可选：自动打开内部选择器
            this.internalPickerController?.open();
            return;
          }

          // 第二步：支持 -> 尝试调用系统 DocumentViewPicker
          try {
            const options = new picker.DocumentSelectOptions();
            options.selectMode = picker.DocumentSelectMode.FOLDER;
            const documentPicker = new picker.DocumentViewPicker(this.context);
            const uris = await documentPicker.select(options);
            if (uris && uris.length > 0) {
              // 成功获取到外部目录 URI
              this.onSelect?.(uris[0], true);
              this.controller.close();
            } else {
              // 用户取消选择
              promptAction.showToast({ message: '未选择目录' });
            }
          } catch (err) {
            console.error('选择外部目录失败', err);
            // 选择器可能被系统限制或取消
            promptAction.showToast({
              message: '选择目录失败，请尝试使用“内部存储”选项',
              duration: 2000
            });
            // 降级：打开内部选择器
            this.internalPickerController?.open();
          }
        })
    }
    .width('80%')
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(16)
  }
}

// 内部目录浏览器对话框
@CustomDialog
export struct InternalDirectoryPickerDialog {
  controller: CustomDialogController;
  sandboxRoot!: string;                 // 由父组件传入
  onSelect?: (selectedPath: string) => void;

  @State currentPath: string = '';
  @State directories: string[] = [];
  @State isLoading: boolean = true;

  aboutToAppear(): void {
    this.currentPath = this.sandboxRoot;
    this.loadDirectories();
  }

  async loadDirectories(): Promise<void> {
    this.isLoading = true;
    try {
      const files = fileIo.listFileSync(this.currentPath);
      const dirs: string[] = [];
      for (const file of files) {
        const fullPath = `${this.currentPath}/${file}`;
        try {
          const stat = fileIo.statSync(fullPath);
          if (stat.isDirectory()) {
            dirs.push(file);
          }
        } catch (e) {
          console.warn(`无法获取文件状态: ${fullPath}`, e);
        }
      }
      this.directories = dirs;
    } catch (err) {
      console.error('加载目录失败', err);
      promptAction.showToast({ message: '加载目录失败' });
    } finally {
      this.isLoading = false;
    }
  }

  enterDirectory(dirName: string): void {
    this.currentPath = `${this.currentPath}/${dirName}`;
    this.loadDirectories();
  }

  goBack(): void {
    if (this.currentPath === this.sandboxRoot) {
      promptAction.showToast({ message: '已在根目录' });
      return;
    }
    const parts = this.currentPath.split('/');
    parts.pop();
    this.currentPath = parts.join('/');
    this.loadDirectories();
  }

  confirmSelection(): void {
    this.onSelect?.(this.currentPath);
    this.controller.close();
  }

  build() {
    Column() {
      Row() {
        Text('选择解压目录')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Button('取消')
          .onClick(() => this.controller.close())
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ColorResource.background_secondary)

      Text(this.currentPath)
        .fontSize(12)
        .fontColor(ColorResource.text_secondary)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .maxLines(1)
        .margin({ left: 12, right: 12, top: 8, bottom: 8 })

      if (this.isLoading) {
        LoadingProgress().width(40).height(40).margin({ top: 20 })
      } else {
        List() {
          if (this.currentPath !== this.sandboxRoot) {
            ListItem() {
              Row() {
                Image($r('sys.symbol.arrow_up')).width(20).height(20).margin({ right: 12 })
                Text('...').fontSize(16)
              }
              .padding(12)
              .width('100%')
              .onClick(() => this.goBack())
            }
          }
          ForEach(this.directories, (dir: string) => {
            ListItem() {
              Row() {
                Image($r('sys.symbol.folder')).width(20).height(20).margin({ right: 12 })
                Text(dir).fontSize(16)
              }
              .padding(12)
              .width('100%')
              .onClick(() => this.enterDirectory(dir))
            }
          }, (dir: string) => dir)
        }
        .layoutWeight(1)
      }

      Row() {
        Button('确认选择此目录')
          .width('90%')
          .onClick(() => this.confirmSelection())
      }
      .width('100%')
      .padding(12)
      .justifyContent(FlexAlign.Center)
    }
    .width('90%')
    .height('80%')
    .backgroundColor(Color.White)
    .borderRadius(16)
  }
}