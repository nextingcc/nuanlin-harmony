// 系统通知：到期提醒推送到通知栏，点击回到应用。
import { notificationManager } from '@kit.NotificationKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { reminderDay, shouldNotify } from './ReminderRules';

const STORE_NAME: string = 'nuanlin_notify';
const LAST_DAY: string = 'lastNotifyDay';
const BUNDLE: string = 'com.nuanlin.care';
const ABILITY: string = 'EntryAbility';
const DAILY_ID: number = 7301;
const TEST_ID: number = 7302;

function reminderAgent(): wantAgent.WantAgentInfo {
  return {
    wants: [{ bundleName: BUNDLE, abilityName: ABILITY, parameters: { source: 'notification' } }],
    actionType: wantAgent.OperationType.START_ABILITY,
    requestCode: 1,
    wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
  };
}

// daily 为 true 时按自然日去重，避免每次进首页重复提醒。
export async function publishReminder(context: common.UIAbilityContext, text: string,
  daily: boolean): Promise<boolean> {
  let store: preferences.Preferences | undefined;
  let today: string = '';
  try {
    if (daily) {
      store = await preferences.getPreferences(context, { name: STORE_NAME });
      today = reminderDay(new Date());
      const last = await store.get(LAST_DAY, '') as string;
      if (!shouldNotify(last, today)) return false;
    }
    await notificationManager.requestEnableNotification(context);
    const agent = await wantAgent.getWantAgent(reminderAgent());
    const request: notificationManager.NotificationRequest = {
      id: daily ? DAILY_ID : TEST_ID,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: '暖邻 · 今日提醒', text: text }
      },
      wantAgent: agent,
      notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
    };
    await notificationManager.publish(request);
    if (store !== undefined) {
      await store.put(LAST_DAY, today);
      await store.flush();
    }
    return true;
  } catch (e) {
    hilog.warn(0x0000, 'nuanlin', 'notification skipped: %{public}s', JSON.stringify(e));
    return false;
  }
}
