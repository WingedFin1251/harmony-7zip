// utils/ToastUtil.ets
import { UIContext } from '@kit.ArkUI';

class ToastUtil {
  private static uicontext: UIContext | null = null;

  static setUIContext(context: UIContext): void {
    ToastUtil.uicontext = context;
  }

  static showToast(message: string): void {
    if (!ToastUtil.uicontext) {
      console.error('UIContext 未设置，无法显示 Toast');
      return;
    }

    try {
      const promptAction = ToastUtil.uicontext.getPromptAction();
      if (promptAction) {
        promptAction.showToast({ message });
      } else {
        console.error('无法获取 PromptAction 对象');
      }
    } catch (err) {
      console.error('显示提示失败', JSON.stringify(err));
    }
  }
}

export { ToastUtil };