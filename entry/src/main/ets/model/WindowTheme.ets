// 系统栏跟随应用主题：深色用深底浅图标，浅色用浅底深图标。
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export async function applySystemBars(context: common.UIAbilityContext, dark: boolean): Promise<void> {
  try {
    const win: window.Window = await window.getLastWindow(context);
    await win.setWindowSystemBarProperties({
      statusBarColor: dark ? '#151311' : '#F8E8E2',
      statusBarContentColor: dark ? '#FFFFFF' : '#000000',
      navigationBarColor: dark ? '#151311' : '#F8E8E2',
      navigationBarContentColor: dark ? '#FFFFFF' : '#000000'
    });
    await win.setWindowBackgroundColor(dark ? '#151311' : '#F8E8E2');
  } catch (e) {
    hilog.warn(0x0000, 'nuanlin', 'system bars update failed: %{public}s', JSON.stringify(e));
  }
}
