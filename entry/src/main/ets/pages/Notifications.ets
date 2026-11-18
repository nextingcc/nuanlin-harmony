import { router } from '@kit.ArkUI';
import { Palette, palette } from '../model/Theme';
import { Api } from '../model/Api';
import { watchMemoMinute } from '../model/MemoReminders';
import { loadServerReminders, memoReminders, StaffReminder } from '../model/StaffReminders';

@Entry
@Component
struct Notifications {
  @State memoItems: StaffReminder[] = [];
  @State serverItems: StaffReminder[] = [];
  @State loading: boolean = true;
  @State unavailable: boolean = false;
  @State message: string = '';
  @StorageProp('darkMode') darkMode: boolean = false;
  private stopClock: (() => void) | undefined;
  private requestId: number = 0;

  private p(): Palette {
    return palette(this.darkMode);
  }

  onPageShow(): void {
    this.stopClock?.();
    this.stopClock = watchMemoMinute(now => { this.memoItems = memoReminders(now); });
    this.load();
  }

  onPageHide(): void {
    this.stopClock?.();
    this.requestId++;
  }

  private async load(): Promise<void> {
    const requestId = ++this.requestId;
    this.loading = true;
    const result = await loadServerReminders();
    if (requestId !== this.requestId) return;
    this.serverItems = result.items;
    this.unavailable = result.unavailable;
    this.loading = false;
  }

  private async read(item: StaffReminder): Promise<void> {
    if (item.activationVersion === undefined || item.read) return;
    const ok = await Api.markNotificationRead(item.id, item.activationVersion);
    if (ok) {
      this.message = '已标记已读';
      await this.load();
    } else {
      this.message = '标记失败，请重试';
    }
  }

  build() {
    Column() {
      Row() {
        Text('‹').accessibilityText('返回')
          .fontSize(26)
          .fontColor(this.p().ink)
          .width(32)
          .textAlign(TextAlign.Center)
          .onClick(() => router.back())
        Text('通知')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.p().ink)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('刷新')
          .fontSize(12)
          .fontColor(this.p().segInk)
          .width(44)
          .textAlign(TextAlign.End)
          .onClick(() => this.load())
      }
      .width('100%')
      .height(52)
      .padding({ left: 10, right: 18 })

      if (this.message.length > 0) {
        Text(this.message).fontSize(9).fontColor(this.p().segInk).padding({ left: 20, right: 20, bottom: 4 })
      }
      if (this.unavailable && !this.loading) {
        Text('部分回访或重点关怀提醒读取失败，请刷新重试。')
          .fontSize(10).fontColor(this.p().danger).padding({ left: 20, right: 20, bottom: 6 })
      }

      Scroll() {
        Column({ space: 10 }) {
          if (this.loading) {
            Text('正在读取回访和重点关怀提醒…').fontSize(11).fontColor(this.p().muted).padding(12)
          }
          if (!this.loading && !this.unavailable && this.memoItems.length + this.serverItems.length === 0) {
            Column({ space: 6 }) {
              Text('暂无通知').fontSize(13).fontColor(this.p().ink)
            }
            .width('100%')
            .padding(24)
            .borderRadius(16)
            .backgroundColor(this.p().surface)
            .border({ width: 1, color: this.p().border })
          }
          ForEach([...this.memoItems, ...this.serverItems], (item: StaffReminder) => {
            Column({ space: 6 }) {
              Row({ space: 8 }) {
                Text(item.title)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.p().ink)
                  .layoutWeight(1)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(item.tag)
                  .fontSize(9)
                  .fontColor(this.p().danger)
                  .backgroundColor(this.p().dangerBg)
                  .borderRadius(9)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              }
              .width('100%')
              Text(item.detail)
                .fontSize(10)
                .fontColor(this.p().muted)
                .width('100%')
              Row({ space: 14 }) {
                Blank()
                if (item.activationVersion !== undefined) {
                  Text(item.read ? '已读' : '标记已读')
                    .fontSize(11)
                    .fontColor(item.read ? this.p().muted : this.p().accentText)
                    .onClick(() => this.read(item))
                }
                Text('查看 ›')
                  .fontSize(11)
                  .fontColor(this.p().accentText)
                  .onClick(() => router.pushUrl({ url: item.route }))
              }.width('100%').height(32)
            }
            .width('100%')
            .padding(14)
            .borderRadius(16)
            .backgroundColor(this.p().surface)
            .border({ width: 1, color: this.p().border })
          }, (item: StaffReminder) => `${item.route}:${item.id}:${item.activationVersion ?? 0}:${item.read ?? false}`)
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
    .backgroundColor(this.p().pageBg)
  }
}
