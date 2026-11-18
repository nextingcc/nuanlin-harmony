import { readableFont, readableLineHeight } from '../model/UserPreferences';
import { router } from '@kit.ArkUI';
import { Theme, Palette, palette } from '../model/Theme';
import { Api } from '../model/Api';
import { QueueTask, queueSelection, canRecordContact } from '../model/RescreenWorkflow';

@Entry
@Component
struct FollowupQueue {
  @StorageProp('textSize') preferenceTextSize: string = 'normal';
  @StorageProp('darkMode') darkMode: boolean = false;

  private p(): Palette { return palette(this.darkMode); }

  private font(base: number): number { return readableFont(base, this.preferenceTextSize); }
  private line(base: number): number { return readableLineHeight(base, this.preferenceTextSize); }

  @State tasks: QueueTask[] = [];
  @State loading: boolean = false;
  @State message: string = '';
  @State busyTask: string = '';

  aboutToAppear(): void {
    this.load();
  }

  onPageShow(): void { this.load(); }

  private async load(): Promise<void> {
    if (this.loading || this.busyTask) return;
    this.loading = true;
    try {
      const data = await Api.followups();
      if (data === null) throw new Error('读取失败，请检查网络与登录状态。');
      const page = data as Record<string, Object>;
      const rows = page['items'] as Object[];
      if (!Array.isArray(rows)) throw new Error('任务数据暂不可用，请重试。');
      this.tasks = rows.map((row: Object) => row as QueueTask);
      this.message = '';
    } catch (e) { this.message = (e as Error).message || '读取失败，请重试。'; }
    finally { this.loading = false; }
  }

  private async open(task: QueueTask): Promise<void> {
    if (this.busyTask || this.loading) return;
    this.busyTask = task.id;
    this.message = '';
    try {
      const selected = queueSelection(task);
      if (task.blockedReason) throw new Error(task.blockedReason);
      // 已有会话也由服务端重新核对任务与安全状态，不能盲信旧名单中的activeAssessmentId。
      const started = await Api.startFollowup(task.id, task.revision);
      if (started.personId !== selected.id) throw new Error('复筛与人员不一致，请刷新任务后核对。');
      AppStorage.setOrCreate('sessionId', started.assessmentId);
      AppStorage.setOrCreate('selectedPerson', JSON.stringify(selected));
      router.pushUrl({ url: 'pages/Interview' });
    } catch (e) { this.message = (e as Error).message || '开始复筛失败，请重试。'; }
    finally { this.busyTask = ''; }
  }

  private openProfile(task: QueueTask): void {
    if (this.busyTask || this.loading) return;
    try {
      if (task.state === 'awaiting_confirmation' && !task.activeAssessmentId) {
        throw new Error('本轮复筛编号缺失，请刷新任务后核对。');
      }
      AppStorage.setOrCreate('selectedPerson', JSON.stringify(queueSelection(task)));
      router.pushUrl({ url: 'pages/Profile', params: { assessmentId: task.activeAssessmentId ?? '' } });
    } catch (e) { this.message = (e as Error).message; }
  }

  private record(task: QueueTask): void {
    if (this.busyTask || this.loading) return;
    if (!canRecordContact(task)) { this.openProfile(task); return; }
    router.pushUrl({ url: 'pages/FollowupRecord',
      params: { taskId: task.id, revision: task.revision, name: task.person.name, kind: task.kind ?? 'manual' } });
  }

  private stateText(state: string): string {
    if (state === 'in_progress') return '复筛进行中';
    if (state === 'awaiting_confirmation') return '待确认';
    if (state === 'due') return '已到期';
    return '待回访';
  }

  build() {
    Stack() {
      Image($r('app.media.followup_paper_bg'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .opacity(this.darkMode ? 0.16 : 1)
      if (this.darkMode) {
        Column().width('100%').height('100%').backgroundColor('#151311').opacity(0.86)
      }
      Column() {
      Row() {
        Text('‹').accessibilityText('返回')
          .fontSize(26)
          .fontColor(this.p().ink)
          .width(32)
          .textAlign(TextAlign.Center)
          .onClick(() => router.replaceUrl({ url: 'pages/Followup' }))
        Text('回访名单')
          .fontSize(this.font(18))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.p().ink)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('刷新')
          .fontSize(this.font(12))
          .fontColor((this.darkMode ? this.p().segInk : '#8A6B54'))
          .width(44)
          .textAlign(TextAlign.End)
          .onClick(() => this.load())
      }
      .width('100%')
      .height(52)
      .padding({ left: 10, right: 18 })

      Text(this.message.length > 0 ? '名单暂未更新，已有任务可刷新后核对' : `本页到期 ${this.tasks.length} 件`)
        .fontSize(this.font(10))
        .fontColor(this.p().muted)
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 8 })

      if (this.message.length > 0) {
        Text(this.message).fontSize(this.font(9)).fontColor((this.darkMode ? this.p().segInk : '#8A6B54')).padding({ left: 20, right: 20, bottom: 4 })
      }

      Scroll() {
        Column({ space: 10 }) {
          if (this.loading) {
            Text('正在读取…').fontSize(this.font(11)).fontColor(this.p().muted).padding(20)
          } else if (this.tasks.length === 0 && this.message.length === 0) {
            Column({ space: 6 }) {
              Text('暂无到期回访').fontSize(this.font(13)).fontColor(this.p().ink)
              Text('这里只显示到期任务。下一次复筛时间可在人员档案查看。').fontSize(this.font(12)).fontColor(this.p().muted)
            }
            .width('100%')
            .padding(24)
            .borderRadius(16)
            .backgroundColor((this.darkMode ? this.p().surface : '#FFFCF7'))
            .border({ width: 1, color: (this.darkMode ? this.p().border : '#EFD9CF') })
          } else {
            ForEach(this.tasks, (task: QueueTask) => {
              Column({ space: 10 }) {
                Column({ space: 4 }) {
                  Row({ space: 6 }) {
                    Text(task.person.name)
                      .fontSize(this.font(14))
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.p().ink)
                    Text(this.stateText(task.state))
                      .fontSize(this.font(8))
                      .fontColor(task.state === 'in_progress' ? (this.darkMode ? this.p().accentText : '#5C6B45') : (this.darkMode ? this.p().danger : '#9C4A45'))
                      .backgroundColor(task.state === 'in_progress' ? (this.darkMode ? this.p().iconB : '#EAF0DE') : (this.darkMode ? this.p().dangerBg : '#F7E4E1'))
                      .borderRadius(8)
                      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                  }
                  Text(`${task.person.age} 岁 · ${task.person.gender || '性别未填写'} · ${task.person.community || '社区未填写'}`)
                    .fontSize(this.font(9))
                    .fontColor(this.p().muted)
                  Text(`到期 ${task.dueAt !== undefined && task.dueAt.length >= 10 ? task.dueAt.slice(0, 10) : task.plannedDate}`)
                    .fontSize(this.font(9))
                    .fontColor((this.darkMode ? this.p().segInk : '#8A6B54'))
                  if (!canRecordContact(task)) {
                    Text('须完成复筛并人工确认、归档；联系记录不代表复筛完成。')
                      .fontSize(this.font(12)).fontColor(this.p().ink2)
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                Row({ space: 10 }) {
                Text(canRecordContact(task) ? '联系记录' : '档案与报告')
                  .fontSize(this.font(14))
                  .layoutWeight(1).constraintSize({ minHeight: 44 }).textAlign(TextAlign.Center)
                  .fontColor((this.darkMode ? this.p().accentText : '#5C6B45'))
                  .border({ width: 1, color: (this.darkMode ? this.p().border : '#CBD8B4') })
                  .borderRadius(15)
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .onClick(() => this.record(task))
                Text(this.busyTask === task.id ? '正在核对…' : (task.state === 'awaiting_confirmation' ? '复核归档' :
                  (task.activeAssessmentId ? '继续复筛' : '开始复筛')))
                  .fontSize(this.font(14))
                  .layoutWeight(1).constraintSize({ minHeight: 44 }).textAlign(TextAlign.Center)
                  .fontColor('#FFFFFF')
                  .backgroundColor((this.darkMode ? this.p().accent : Theme.greenDeep))
                  .borderRadius(15)
                  .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                  .onClick(() => { if (task.state === 'awaiting_confirmation') this.openProfile(task); else this.open(task); })
                }.width('100%')
              }
              .width('100%')
              .padding(14)
              .borderRadius(16)
              .backgroundColor((this.darkMode ? this.p().surface : '#FFFCF7'))
              .border({ width: 1, color: (this.darkMode ? this.p().border : '#EFD9CF') })
            }, (task: QueueTask) => task.id + ':' + task.revision.toString() + ':' + task.state)
          }
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .padding({ left: 20, right: 20, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.darkMode ? this.p().pageBg : '#F8E8E2')
  }
}
