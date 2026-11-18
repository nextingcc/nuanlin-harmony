import { readableFont, readableLineHeight } from '../model/UserPreferences';
import { router, promptAction } from '@kit.ArkUI';
import { Theme, Palette, palette } from '../model/Theme';
import { Api } from '../model/Api';
import { reminderDay } from '../model/ReminderRules';
import { contactRecordAllowed } from '../model/RescreenWorkflow';

@Entry
@Component
struct FollowupRecord {
  @StorageProp('darkMode') darkMode: boolean = false;
  @StorageProp('textSize') preferenceTextSize: string = 'normal';

  private p(): Palette { return palette(this.darkMode); }

  private font(base: number): number { return readableFont(base, this.preferenceTextSize); }
  private line(base: number): number { return readableLineHeight(base, this.preferenceTextSize); }

  @State taskId: string = '';
  @State revision: number = 1;
  @State personName: string = '';
  @State method: string = '电话';
  @State outcome: string = 'completed';
  @State notes: string = '';
  @State saving: boolean = false;
  @State message: string = '正在核对任务…';
  @State verified: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    if (params !== null && params !== undefined) {
      this.taskId = (params['taskId'] as string) ?? '';
      this.revision = (params['revision'] as number) ?? 1;
      this.personName = (params['name'] as string) ?? '';
    }
    this.verifyTask();
  }

  private async verifyTask(): Promise<void> {
    this.verified = false;
    try {
      if (!this.taskId) throw new Error('未选择任务，请返回回访名单重新进入。');
      const context = await Api.followupContext(this.taskId);
      this.personName = context.person.name;
      if (!contactRecordAllowed(context.task.kind, context.task.activeAssessmentId)) {
        throw new Error('此任务须完成复筛并人工确认、归档，不能用联系记录完成。请返回回访名单。');
      }
      if (context.task.state === 'completed' || context.task.status === 'completed') {
        throw new Error('此任务已完成，请返回历史记录查看。');
      }
      this.revision = context.task.revision;
      this.verified = true;
      this.message = '';
    } catch (e) { this.message = (e as Error).message || '任务核对失败，请返回名单刷新。'; }
  }

  private async save(): Promise<void> {
    if (this.saving || !this.verified) return;
    if (this.notes.trim().length === 0) {
      this.message = '请填写回访记录';
      return;
    }
    this.saving = true;
    const today = reminderDay(new Date());
    const ok = await Api.addFollowupRecord(this.taskId, this.revision, this.method, this.outcome, this.notes.trim(), today);
    this.saving = false;
    if (ok) {
      promptAction.showToast({ message: '回访记录已保存', duration: 1500 });
      router.replaceUrl({ url: 'pages/FollowupQueue' });
    } else {
      this.message = '保存失败，请重试';
    }
  }

  @Builder
  chip(label: string, value: string, group: string) {
    Button(label)
      .height(32)
      .fontSize(this.font(11))
      .fontColor((group === 'method' ? this.method === value : this.outcome === value) ? '#FFFFFF' : this.p().ink2)
      .backgroundColor((group === 'method' ? this.method === value : this.outcome === value) ? (this.darkMode ? this.p().accent : Theme.greenDeep) : (this.darkMode ? this.p().surface : '#FFFCF7'))
      .border({ width: 1, color: (group === 'method' ? this.method === value : this.outcome === value) ? (this.darkMode ? this.p().accent : Theme.greenDeep) : (this.darkMode ? this.p().border : '#E2CDBD') })
      .borderRadius(15)
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .enabled(!this.saving)
      .onClick(() => {
        if (group === 'method') this.method = value;
        else this.outcome = value;
      })
  }

  build() {
    Column() {
      Row() {
        Text('‹').accessibilityText('返回')
          .fontSize(26)
          .fontColor(this.p().ink)
          .width(32)
          .textAlign(TextAlign.Center)
          .onClick(() => router.replaceUrl({ url: 'pages/FollowupQueue' }))
        Text('回访记录')
          .fontSize(this.font(18))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.p().ink)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('关闭')
          .fontSize(this.font(12))
          .fontColor((this.darkMode ? this.p().segInk : '#8A6B54'))
          .width(44)
          .textAlign(TextAlign.End)
          .onClick(() => router.replaceUrl({ url: 'pages/FollowupQueue' }))
      }
      .width('100%')
      .height(52)
      .padding({ left: 10, right: 18 })

      Scroll() {
        Column({ space: 12 }) {
          if (this.personName.length > 0) {
            Text(this.personName)
              .fontSize(this.font(20))
              .fontFamily('serif')
              .fontColor(this.p().ink)
              .width('100%')
          }

          Column({ space: 8 }) {
            Text('回访方式').fontSize(this.font(10)).fontColor((this.darkMode ? this.p().section : '#9C7E66'))
            Row({ space: 8 }) {
              ForEach(['电话', '上门', '微信'], (item: string) => {
                this.chip(item, item, 'method')
              }, (item: string) => item)
            }
            .width('100%')
          }
          .width('100%')
          .padding(14)
          .borderRadius(16)
          .backgroundColor((this.darkMode ? this.p().surface : '#FFFCF7'))
          .border({ width: 1, color: (this.darkMode ? this.p().border : '#EFD9CF') })

          Column({ space: 8 }) {
            Text('回访结果').fontSize(this.font(10)).fontColor((this.darkMode ? this.p().section : '#9C7E66'))
            Row({ space: 8 }) {
              this.chip('已完成', 'completed', 'outcome')
              this.chip('未接', 'unanswered', 'outcome')
              this.chip('拒访', 'declined', 'outcome')
              this.chip('跟进中', 'ongoing', 'outcome')
            }
            .width('100%')
          }
          .width('100%')
          .padding(14)
          .borderRadius(16)
          .backgroundColor((this.darkMode ? this.p().surface : '#FFFCF7'))
          .border({ width: 1, color: (this.darkMode ? this.p().border : '#EFD9CF') })

          Column({ space: 8 }) {
            Text('记录内容').fontSize(this.font(10)).fontColor((this.darkMode ? this.p().section : '#9C7E66'))
            TextArea({ placeholder: '例如：电话联系本人，情绪较上次稳定，已提醒按时服药，约定两周后再次回访。', text: this.notes })
              .height(130)
              .fontSize(this.font(12))
              .backgroundColor((this.darkMode ? this.p().surface : '#FFFDF8'))
              .border({ width: 1, color: (this.darkMode ? this.p().border : '#EBDCCF') })
              .borderRadius(10)
              .onChange((v: string) => { this.notes = v; })
          }
          .width('100%')
          .padding(14)
          .borderRadius(16)
          .backgroundColor((this.darkMode ? this.p().surface : '#FFFCF7'))
          .border({ width: 1, color: (this.darkMode ? this.p().border : '#EFD9CF') })

          if (this.message.length > 0) {
            Text(this.message).fontSize(this.font(9)).fontColor((this.darkMode ? this.p().danger : '#9C4A45')).width('100%')
          }

          Button(this.saving ? '保存中…' : '保存回访记录')
            .width('100%')
            .height(50)
            .fontSize(this.font(15))
            .fontColor('#FFFFFF')
            .backgroundColor((this.darkMode ? this.p().accent : Theme.greenDeep))
            .borderRadius(25)
            .enabled(!this.saving && this.verified)
            .onClick(() => this.save())
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .padding({ left: 20, right: 20, top: 8, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor((this.darkMode ? this.p().pageBg : '#F8E8E2'))
  }
}
