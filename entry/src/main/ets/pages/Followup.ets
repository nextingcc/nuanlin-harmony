import { router } from '@kit.ArkUI';
import { Theme, Palette, palette } from '../model/Theme';
import { NavBar } from '../components/Common';
import { Api } from '../model/Api';

@Entry
@Component
struct Followup {
  @State dueCount: number = 0;
  @State overdueCount: number = 0;
  @State nextTime: string = '-';
  @StorageProp('darkMode') darkMode: boolean = false;

  private p(): Palette {
    return palette(this.darkMode);
  }

  aboutToAppear(): void {
    this.loadStats();
  }

  private async loadStats(): Promise<void> {
    const data = await Api.followups();
    if (data === null) return;
    const page = data as Record<string, Object>;
    const rows = page['items'] as Object[];
    if (rows === null || rows === undefined) return;
    const today = new Date().toISOString().slice(0, 10);
    let overdue = 0;
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i] as Record<string, Object>;
      const due = (row['dueAt'] as string) ?? '';
      if (due.length >= 10 && due.slice(0, 10) < today) overdue++;
      if (i === 0 && due.length >= 16) {
        const t = due.slice(11, 16);
        if (t !== '00:00') this.nextTime = t;
      }
    }
    this.dueCount = rows.length;
    this.overdueCount = overdue;
  }

  @Builder
  menu(label: string, en: string, badge: string, warn: boolean, target: string) {
    Stack({ alignContent: Alignment.Center }) {
      if (!this.darkMode) {
        Image($r('app.media.button_frame'))
          .width(300)
          .height(62)
          .objectFit(ImageFit.Fill)
      }
      if (badge.length > 0) {
        Text(badge)
          .fontSize(9)
        .fontColor('#FFFFFF')
        .backgroundColor(warn ? Theme.pink : Theme.green)
        .borderRadius(11)
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .position({ x: 232, y: 20 })
      }
      Column({ space: 2 }) {
        Text(label)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.p().ink)
          .letterSpacing(2)
        Text(en)
          .fontSize(7)
          .fontColor((this.darkMode ? this.p().muted : '#B08A72'))
          .letterSpacing(2)
      }
      .alignItems(HorizontalAlign.Center)
    }
    .width(this.darkMode ? '88%' : 302)
    .height(62)
    .borderRadius(this.darkMode ? 18 : 0)
    .backgroundColor(this.darkMode ? this.p().segActive : Color.Transparent)
    .border({ width: this.darkMode ? 1 : 0, color: this.p().border })
    .onClick(() => router.pushUrl({ url: target }))
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Image($r('app.media.stationery'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .opacity(this.darkMode ? 0.2 : 1)
      if (this.darkMode) {
        Column().width('100%').height('100%').backgroundColor('#151311').opacity(0.86)
      }

      Column() {
        NavBar({ title: '青禾社区', dark: this.darkMode })
        Scroll() {
          Column() {
            Stack({ alignContent: Alignment.BottomStart }) {
              Image($r('app.media.cafe'))
                .width('100%')
                .height(212)
                .borderRadius(22)
                .objectFit(ImageFit.Cover)
              Text('一起去看看他们吧 · 青禾社区')
                .fontSize(9)
                .fontColor((this.darkMode ? this.p().ink2 : '#8A6338'))
                .backgroundColor((this.darkMode ? this.p().surface : 'rgba(255,252,246,0.86)'))
                .borderRadius(14)
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .margin({ left: 12, bottom: 12 })
            }
            .width('100%')
            .borderRadius(22)
            .border({ width: 5, color: (this.darkMode ? '#3A332C' : '#FFFDF8') })
            .shadow({ radius: 18, color: 'rgba(120,72,60,0.18)', offsetY: 8 })
            .margin({ left: 28, right: 28, top: 4 })

            Text('回访与关怀')
              .fontSize(26)
              .fontFamily('serif')
              .fontColor(this.p().ink)
              .letterSpacing(3)
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 12 })
            Text('今天，先问候一声')
              .fontSize(10)
              .fontColor(this.p().muted)
              .letterSpacing(3)
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 3 })

            Row() {
              Column({ space: 2 }) {
                Text(this.dueCount.toString()).fontSize(17).fontFamily('serif').fontColor(this.p().ink)
                Text('人待回访').fontSize(8).fontColor(this.p().muted)
              }
              .layoutWeight(1)
              Divider().vertical(true).height(24).color((this.darkMode ? this.p().divider : '#EAD9C9'))
              Column({ space: 2 }) {
                Text(this.overdueCount.toString()).fontSize(17).fontFamily('serif').fontColor((this.darkMode ? this.p().danger : '#9C4A45'))
                Text('人已逾期').fontSize(8).fontColor(this.p().muted)
              }
              .layoutWeight(1)
              Divider().vertical(true).height(24).color((this.darkMode ? this.p().divider : '#EAD9C9'))
              Column({ space: 2 }) {
                Text(this.nextTime).fontSize(17).fontFamily('serif').fontColor(this.p().ink)
                Text('下次上门').fontSize(8).fontColor(this.p().muted)
              }
              .layoutWeight(1)
            }
            .width('100%')
            .height(56)
            .margin({ left: 24, right: 24, top: 12 })
            .padding({ left: 8, right: 8 })
            .borderRadius(16)
            .backgroundColor((this.darkMode ? this.p().surface : 'rgba(255,253,248,0.72)'))
            .border({ width: 1, color: (this.darkMode ? this.p().border : 'rgba(255,255,255,0.9)') })

            Column({ space: 10 }) {
              this.menu('回访名单', 'FOLLOW-UP LIST', '后端到期任务', false, 'pages/FollowupQueue')
              this.menu('回访记录', 'HISTORY', '', false, 'pages/FollowupList')
              this.menu('重点关怀对象', 'PRIORITY CARE', '后端实时案件', true, 'pages/CareList')
            }
            .margin({ top: 12 })

            Row({ space: 8 }) {
              Text('♡').fontSize(13).fontColor((this.darkMode ? this.p().danger : '#9C4A45'))
              Text('关怀规则 · 连续 72 小时未记录提醒；168 小时复核')
                .fontSize(9)
                .fontColor((this.darkMode ? this.p().segInk : '#8A6B54'))
            }
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .margin({ top: 30, bottom: 16 })
            .borderRadius(14)
            .backgroundColor((this.darkMode ? this.p().surface : 'rgba(255,253,248,0.82)'))
            .border({ width: 1, color: (this.darkMode ? this.p().border : 'rgba(255,255,255,0.95)') })
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor((this.darkMode ? this.p().pageBg : '#FFFDF9'))
  }
}



