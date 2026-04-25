// 文件项数据类型
export interface FileItem {
  name: string;
  path: string;
  isDir: boolean;
  size: number;
  modified: number;
  uri?: string;
}

// 压缩选项接口
export interface CompressOptions {
  format: '7z' | 'zip' | 'tar';
  password?: string;
  splitSize?: string;
}

// 解压选项接口
export interface ExtractOptions {
  destPath: string;
  password?: string;
}

// 颜色资源类型
export interface ColorResourceType {
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
export const ColorResource: ColorResourceType = {
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