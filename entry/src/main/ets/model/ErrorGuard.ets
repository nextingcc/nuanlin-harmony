import { errorManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

// 全局异常兜底：只做记录与提示，不吞错、不隐藏崩溃。
let installed: boolean = false;

function bump(): void {
  const count: number = (AppStorage.get<number>('runtimeErrorCount') ?? 0) + 1;
  AppStorage.setOrCreate('runtimeErrorCount', count);
}

export function installErrorGuard(): void {
  if (installed) return;
  installed = true;
  try {
    errorManager.on('globalErrorOccurred', (reason: errorManager.GlobalError) => {
      bump();
      hilog.error(0x0000, 'nuanlin', 'global_error message=%{public}s stack=%{public}s',
        reason.message ?? '', reason.stack ?? '');
    });
    errorManager.on('unhandledRejection', (reason: Error, promise: Promise<Object>) => {
      bump();
      hilog.error(0x0000, 'nuanlin', 'unhandled_rejection %{public}s', JSON.stringify(reason));
    });
  } catch (e) {
    hilog.warn(0x0000, 'nuanlin', 'error guard unavailable: %{public}s', JSON.stringify(e));
  }
}
