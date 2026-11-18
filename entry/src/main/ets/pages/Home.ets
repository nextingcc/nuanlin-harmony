import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Theme, Palette, palette } from '../model/Theme';
import { Dock } from '../components/Common';
import { watchMemoMinute } from '../model/MemoReminders';
import { loadServerReminders, memoReminders, StaffReminder } from '../model/StaffReminders';
import { Layout } from '../model/Layout';
import { publishReminder } from '../model/Notifier';
import { reminderSummary } from '../model/ReminderRules';
import { loadAvatar } from '../model/UserAvatar';
import { image } from '@kit.ImageKit';

@Entry
@Component
struct Home {
  @State current: number = 0;
  @StorageProp('reduceMotion') reduceMotion: boolean = false;
  @StorageProp('darkMode') darkMode: boolean = false;
  @State memoItems: StaffReminder[] = [];
  @State serverItems: StaffReminder[] = [];
  @State avatarPm: image.PixelMap | undefined = undefined;
  @State viewWidth: number = 0;
  private stopClock: (() => void) | undefined;
  private requestId: number = 0;

  private p(): Palette {
    return palette(this.darkMode);
  }


  private wide(): boolean {
    return Layout.isWide(this.viewWidth);
  }

  onPageShow(): void {
    loadAvatar(getContext(this) as common.UIAbilityContext).then((pm: image.PixelMap | undefined) => { this.avatarPm = pm; });
    this.stopClock?.();
    this.stopClock = watchMemoMinute(now => { this.memoItems = memoReminders(now); });
    this.loadToday();
  }

  onPageHide(): void {
    this.stopClock?.();
    this.requestId++;
  }

  private async loadToday(): Promise<void> {
    const requestId = ++this.requestId;
    const result = await loadServerReminders();
    if (this.requestId !== requestId) return;
    this.serverItems = result.items.filter(item => !item.read);
    const due = this.serverItems.filter(item => item.route === 'pages/FollowupQueue').length;
    const care = this.serverItems.filter(item => item.route === 'pages/CareList').length;
    if (due + care > 0) {
      const context = getContext(this) as common.UIAbilityContext;
      await publishReminder(context, reminderSummary(due, care), true);
    }
  }
  private slides: Resource[] = [
    $r('app.media.slide1'),
    $r('app.media.slide2'),
    $r('app.media.slide3'),
    $r('app.media.slide4'),
    $r('app.media.slide5')
  ];
  private titles: string[] = ['依然可以很酷', '一起看夕阳', '被看见的心情', '一个人的午后', '一起散步的傍晚'];
  private subs: string[] = ['STILL COOL · STILL ME', 'TOGETHER AT DUSK', 'BEING SEEN · TOGETHER', 'ALONE, BUT NOT LONELY', 'A WALK BY THE SEA'];

  @Builder
  ribbon(index: number, title: string, en: string, bg: string, fg: string, target: string, width: string) {
    Row({ space: 10 }) {
      Image([$r('app.media.care_screening'), $r('app.media.care_followup'), $r('app.media.care_professional'), $r('app.media.care_support')][index])
        .width(32).height(32).objectFit(ImageFit.Contain)
      Column({ space: 1 }) {
        Text(title)
          .fontSize(this.wide() ? 13 : 14)
          .fontWeight(FontWeight.Medium)
          .fontColor(fg)
          .letterSpacing(1.2)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(en)
          .fontSize(6)
          .fontColor(fg)
          .opacity(0.72)
          .letterSpacing(this.wide() ? 0.4 : 1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(14)
        .fontColor(fg)
        .opacity(0.6)
    }
    .width(width)
    .height(56)
    .padding({ left: 16, right: 14 })
    .borderRadius(28)
    .backgroundColor(bg)
    .linearGradient({ angle: 180, colors: [['rgba(255,255,255,0.82)', 0], [bg, 0.32], [bg, 1]] })
    .border({ width: 1, color: 'rgba(255,255,255,0.85)' })
    .shadow({ radius: 12, color: 'rgba(112,83,67,0.12)', offsetY: 5 })
    .margin({ bottom: 12 })
    .onClick(() => router.pushUrl({ url: target }))
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll() {
        Column() {
          Row({ space: 9 }) {
            Image($r('app.media.brand_cloud')).width(36).height(36).objectFit(ImageFit.Contain).borderRadius(18)
            Column({ space: 2 }) {
              Text('NUANLIN · COMMUNITY CARE')
                .fontSize(6)
                .fontColor(Theme.muted)
                .letterSpacing(2)
            }
            .alignItems(HorizontalAlign.Start)
            Blank()
            Text('✉')
              .onClick(() => router.pushUrl({ url: 'pages/Notifications' }))
              .accessibilityText('通知')
              .fontSize(17)
              .fontColor(this.p().ink2)
              .width(28)
              .height(28)
              .textAlign(TextAlign.Center)
            Text('◔')
              .onClick(() => router.pushUrl({ url: 'pages/Widgets' }))
              .fontSize(17)
              .fontColor(this.p().ink2)
              .width(28)
              .height(28)
              .textAlign(TextAlign.Center)
            if (this.avatarPm !== undefined) {
              Image(this.avatarPm)
                .width(28)
                .height(28)
                .borderRadius(14)
                .objectFit(ImageFit.Cover)
                .border({ width: 1.5, color: '#FFFFFF' })
                .accessibilityText('我的头像')
            } else {
              Image($r('app.media.avatar_f2'))
                .width(28)
                .height(28)
                .borderRadius(14)
                .border({ width: 1.5, color: '#FFFFFF' })
            }
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 8, bottom: 2 })

          Row() {
            Text('暖邻')
              .fontSize(24)
              .fontFamily('serif')
              .fontColor(this.p().ink)
              .letterSpacing(2)
            Blank()
            Text('今天也一起，慢慢来。')
              .fontSize(9)
              .fontColor(this.darkMode ? this.p().muted : '#B08A72')
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 2 })

          Row() {
            Text('ISSUE 04 — WINTER 2026')
              .fontSize(7)
              .fontColor(Theme.muted)
              .letterSpacing(2)
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 9, bottom: 6 })

          Swiper() {
            ForEach(this.slides, (item: Resource, index: number) => {
              Stack({ alignContent: Alignment.TopStart }) {
                Image(item)
                  .width('100%')
                  .height(210)
                  .objectFit(ImageFit.Cover)
                Column()
                  .width('100%')
                  .height(210)
                  .linearGradient({
                    angle: 180,
                    colors: [['rgba(30,24,20,0.30)', 0], ['rgba(30,24,20,0)', 0.24], ['rgba(30,24,20,0.05)', 0.5], ['rgba(30,24,20,0.65)', 1]]
                  })
                Column() {
                  Row() {
                    Text('本期插画 · 被看见的心情')
                      .fontSize(6)
                      .fontColor('rgba(255,255,255,0.9)')
                      .letterSpacing(1.4)
                    Blank()
                    Text('WINTER 2026')
                      .fontSize(6)
                      .fontColor('rgba(255,255,255,0.9)')
                      .letterSpacing(1.4)
                  }
                  .width('100%')

                  Blank()

                  Column({ space: 3 }) {
                    Text(this.titles[index])
                      .fontSize(23)
                      .fontFamily('serif')
                      .fontColor('#FFFFFF')
                      .letterSpacing(1.5)
                      .shadow({ radius: 10, color: 'rgba(0,0,0,0.4)', offsetY: 2 })
                    Text(this.subs[index])
                      .fontSize(6)
                      .fontColor('rgba(255,255,255,0.8)')
                      .letterSpacing(2.4)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')

                  Row() {
                    Blank()
                    Text(`0${index + 1} / 05`)
                      .fontSize(9)
                      .fontColor('rgba(255,255,255,0.9)')
                  }
                  .width('100%')
                  .padding({ top: 6 })
                }
                .width('100%')
                .height(210)
                .padding({ left: 18, right: 18, top: 13, bottom: 15 })
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .height(210)
            }, (item: Resource, index: number) => index.toString())
          }
          .width('100%')
          .height(210)
          .autoPlay(!this.reduceMotion)
          .interval(4500)
          .loop(true)
          .indicator(false)
          .onChange((index: number) => {
            this.current = index;
          })

          Row() {
            Row({ space: 5 }) {
              ForEach([0, 1, 2, 3, 4], (i: number) => {
                Circle()
                  .width(5)
                  .height(5)
                  .fill(i === this.current ? Theme.ink : '#DCC2C7')
              }, (i: number) => i.toString())
            }
          }
          .width('100%')
          .padding({ top: 10 })
          .justifyContent(FlexAlign.Center)

          Row() {
            Text('Choice')
              .fontSize(38)
              .fontFamily('serif')
              .fontColor('#8FB3C0')
              .letterSpacing(-0.5)
            Blank()
            Column() {
              Text('04 ENTRIES')
                .fontSize(6)
                .fontColor('#B99C82')
                .letterSpacing(1.6)
              Text('P.01')
                .fontSize(6)
                .fontColor('#B99C82')
                .letterSpacing(1.6)
            }
            .alignItems(HorizontalAlign.End)
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 12 })

          Text('今天，想从哪一件事开始？')
            .fontSize(11)
            .fontFamily('serif')
            .fontColor(this.p().ink2)
            .width('100%')
            .padding({ left: 18, right: 18, top: 2 })

          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            this.ribbon(0, '心理筛查', 'PSYCHOLOGICAL SCREENING', '#E2EDD9', '#3D5136', 'pages/ResidentList',
              this.wide() ? '48.8%' : '100%')
            this.ribbon(1, '回访与重点关怀', 'FOLLOW-UP & PRIORITY CARE', '#F5DDE5', '#704553', 'pages/Followup',
              this.wide() ? '48.8%' : '100%')
            this.ribbon(2, '寻求专业帮助', 'PROFESSIONAL HELP', '#F6EBC8', '#69512E', 'pages/BlankSupport',
              this.wide() ? '48.8%' : '100%')
            this.ribbon(3, '心理关怀与支持', 'CARE & SUPPORT', '#E7D7CA', '#5D4435', 'pages/BlankSupport',
              this.wide() ? '48.8%' : '100%')
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 10 })

          Column() {
            Row() {
              Text('今日提醒')
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.p().ink)
              Blank()
              Text(`${this.memoItems.length + this.serverItems.length} 件`)
                .fontSize(6)
                .fontColor('#B99C82')
                .letterSpacing(1.6)
            }
            .width('100%')
            .padding({ top: 10, bottom: 4 })

            ForEach([...this.memoItems, ...this.serverItems], (task: StaffReminder) => {
              Row({ space: 8 }) {
                Text(task.title)
                  .fontSize(11)
                  .fontColor(this.p().ink2)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(task.tag)
                  .fontSize(9)
                  .fontColor('#8A4A4A')
                Text('›').fontSize(11).fontColor(Theme.muted)
              }
              .width('100%')
              .height(38)
              .border({ width: { top: 1 }, color: '#F2DFE1' })
              .onClick(() => router.pushUrl({ url: task.route }))
            }, (task: StaffReminder) => `${task.route}:${task.id}`)
          }
          .width('100%')
          .padding({ left: 18, right: 18 })
          .margin({ top: 8 })
        }
        .width('100%')
        .padding({ bottom: 92 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      Dock({ current: 0 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.darkMode ? this.p().pageBg : '#FFF9F8')
    .onAreaChange((_old: Area, area: Area) => {
      const width = Layout.parseWidth(String(area.width));
      if (width !== this.viewWidth) this.viewWidth = width;
    })
  }
}
