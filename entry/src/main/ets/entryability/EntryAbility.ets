import { AbilityConstant, UIAbility, Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { Api } from '../model/Api';
import { initializePreferences, applyPreferenceTheme } from '../model/UserPreferences';
import { applySystemBars } from '../model/WindowTheme';
import { installErrorGuard } from '../model/ErrorGuard';
import { initializeAssistantMemoStore } from '../model/AssistantMemoStore';

// 启动耗时埋点：onCreate → loadContent 回调，分阶段打点，便于用 hilog 取值。
class StartupClock {
  private started: number = Date.now();
  private mark: number = this.started;

  reset(): void {
    this.started = Date.now();
    this.mark = this.started;
  }

  lap(): number {
    const now = Date.now();
    const cost = now - this.mark;
    this.mark = now;
    return cost;
  }

  total(): number {
    return Date.now() - this.started;
  }
}

const startup = new StartupClock();

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    startup.reset();
    installErrorGuard();
    hilog.info(0x0000, 'nuanlin', '%{public}s', 'Ability onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.loadInitialPage(windowStage);
  }

  private async loadInitialPage(windowStage: window.WindowStage): Promise<void> {
    await initializePreferences(this.context, this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    try { await initializeAssistantMemoStore(this.context); }
    catch (e) { hilog.error(0x0000, 'nuanlin', 'Local memo storage is not ready; writes will require retry.'); }
    const prefsMs = startup.lap();
    await applySystemBars(this.context, AppStorage.get<boolean>('darkMode') === true);
    const barsMs = startup.lap();
    const restored = await Api.restoreSession(this.context);
    const sessionMs = startup.lap();
    windowStage.loadContent(restored ? 'pages/Home' : 'pages/Welcome', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'nuanlin', 'Failed to load content: %{public}s', JSON.stringify(err) ?? '');
        return;
      }
      hilog.info(0x0000, 'nuanlin',
        'startup_ms total=%{public}d prefs=%{public}d bars=%{public}d session=%{public}d restored=%{public}s',
        startup.total(), prefsMs, barsMs, sessionMs, restored ? 'true' : 'false');
      hilog.info(0x0000, 'nuanlin', '%{public}s', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {}

  onForeground(): void {}

  onBackground(): void {}

  onConfigurationUpdate(config: Configuration): void {
    applyPreferenceTheme(config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    applySystemBars(this.context, AppStorage.get<boolean>('darkMode') === true)
      .catch(() => {});
  }
}
