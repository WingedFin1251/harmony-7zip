// FileRow.ets
import { FileItem } from '../models/FileItem';

const DEFAULT_FILE_ITEM: FileItem = {
  name: '',
  path: '',
  isDir: false,
  size: 0,
  modified: 0
};

@Component
export struct FileRow {
  @Prop item: FileItem = DEFAULT_FILE_ITEM;
  @Prop selected: boolean = false;
  @Prop isSelectionMode: boolean = false;
  onSelect?: (selected: boolean) => void;
  onOpen?: () => void;


  build() {
    Row() {
      if (this.isSelectionMode) {
        Checkbox()
          .select(this.selected)
          .onChange((value: boolean): void => this.onSelect?.(value))
          .margin({ right: 8 })
      }
      Image(this.item.isDir ? $r('app.media.folder') : $r('app.media.file'))
        .width(24)
        .height(24)
        .margin({ right: 12 })
      Column() {
        Text(this.item.name)
          .fontSize(16)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (!this.item.isDir) {
          Text(this.formatSize(this.item.size))
            .fontSize(12)
            .fontColor('#888')
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text(this.formatDate(this.item.modified))
        .fontSize(12)
        .fontColor('#888')
        .margin({ right: 8 })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.selected ? '#e0f0ff' : 'transparent')
    .onClick((): void => {
      if (this.isSelectionMode) {
        this.onSelect?.(!this.selected);
      } else {
        this.onOpen?.();
      }
    })
    .gesture(
      LongPressGesture()
        .onAction((): void => {
          if (!this.isSelectionMode) {
            this.onSelect?.(true);
          }
        })
    )
  }

  formatSize(size: number): string {
    if (size < 1024) return size + ' B';
    if (size < 1024 * 1024) return (size / 1024).toFixed(1) + ' KB';
    return (size / (1024 * 1024)).toFixed(1) + ' MB';
  }

  formatDate(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getMonth() + 1}/${date.getDate()} ${date.getHours()}:${date.getMinutes()}`;
  }
}