// utils/ToastUtil.ets
import { promptAction } from '@kit.ArkUI';

export function showToast(message: string): void {
  try {
    promptAction.showToast({ message });
  } catch (err) {
    console.error('显示提示失败', JSON.stringify(err));
  }
}