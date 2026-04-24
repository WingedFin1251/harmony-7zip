// FileGridCell.ets
import { FileItem } from '../models/FileItem';

const DEFAULT_FILE_ITEM: FileItem = {
  name: '',
  path: '',
  isDir: false,
  size: 0,
  modified: 0
};

@Component
export struct FileGridCell {   // 关键：将 FileRow 改为 FileGridCell
  @Prop item: FileItem = DEFAULT_FILE_ITEM;
  @Prop selected: boolean = false;
  @Prop isSelectionMode: boolean = false;
  onSelect?: (selected: boolean) => void;
  onOpen?: () => void;

  build() {
    Column() {
      Image(this.item.isDir ? $r('app.media.folder') : $r('app.media.file'))
        .width(48)
        .height(48)
        .margin(8)
      Text(this.item.name)
        .fontSize(14)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)
      if (!this.item.isDir) {
        Text(this.formatSize(this.item.size))
          .fontSize(10)
          .fontColor('#888')
      }
    }
    .width('100%')
    .aspectRatio(1.0)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.selected ? '#e0f0ff' : '#f8f8f8')
    .borderRadius(8)
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
}