import { describe, it, expect } from '@ohos/hypium';
import { Layout } from '../../../main/ets/model/Layout';
import { reminderDay, reminderSummary, shouldNotify } from '../../../main/ets/model/ReminderRules';

export default function abilityTest() {
  describe('NuanlinPureLogic', () => {
    it('breakpoint_columns', 0, () => {
      expect(Layout.columns(390)).assertEqual(1);
      expect(Layout.columns(600)).assertEqual(2);
      expect(Layout.columns(900)).assertEqual(3);
      expect(Layout.isWide(599)).assertFalse();
      expect(Layout.isWide(600)).assertTrue();
    });

    it('reminder_daily_dedup', 0, () => {
      expect(reminderDay(new Date(2026, 10, 16))).assertEqual('2026-11-16');
      expect(shouldNotify('', '2026-11-16')).assertTrue();
      expect(shouldNotify('2026-11-16', '2026-11-16')).assertFalse();
      expect(shouldNotify('2026-11-15', '2026-11-16')).assertTrue();
    });

    it('reminder_summary_copy', 0, () => {
      expect(reminderSummary(0, 0)).assertEqual('今天没有到期提醒');
      expect(reminderSummary(2, 3)).assertEqual('回访 2 条 · 重点关怀 3 条 今天到期');
    });
  });
}
