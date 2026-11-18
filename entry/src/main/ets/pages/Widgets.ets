import { router } from '@kit.ArkUI';
import { Theme } from '../model/Theme';
import { Api } from '../model/Api';
import { loadServerReminders } from '../model/StaffReminders';
import { TopicSession, topicView } from '../model/TopicInterviewState';

interface WidgetResident {
  name: string;
}

@Entry
@Component
struct Widgets {
  @State followupText: string = '正在读取…';
  @State careText: string = '正在读取…';
  @State interviewName: string = '';
  @State interviewProgress: string = '';
  private loadId: number = 0;

  aboutToAppear(): void {
    this.refreshCards();
  }

  onPageShow(): void {
    this.refreshCards();
  }

  private refreshCards(): void {
    this.load().catch(() => {
      this.followupText = '无法读取回访，请返回后重试';
      this.careText = '无法读取关怀提醒，请返回后重试';
    });
  }

  private async load(): Promise<void> {
    const request = ++this.loadId;
    this.interviewName = '';
    this.interviewProgress = '';
    this.followupText = '正在读取…';
    this.careText = '正在读取…';
    const result = await loadServerReminders();
    if (request !== this.loadId) return;
    const due = result.items.filter(item => item.route === 'pages/FollowupQueue');
    const care = result.items.filter(item => item.route === 'pages/CareList');
    const fallback = result.unavailable ? '部分数据暂不可用' : '';
    this.followupText = due.slice(0, 3).map(item => item.title + ' · ' + item.detail).join('\n') ||
      fallback || '暂无到期回访';
    this.careText = care.slice(0, 3).map(item => item.title + ' · ' + item.detail).join('\n') ||
      fallback || '暂无重点关怀提醒';
    const sessionId = AppStorage.get<string>('widgetInterviewId') ?? '';
    const resident = AppStorage.get<string>('widgetInterviewResident') ?? '';
    if (!sessionId || !resident) return;
    try {
      const session = await Api.getInterview(sessionId) as TopicSession | null;
      if (request !== this.loadId || !session || session.completed || session.archived) return;
      const person = JSON.parse(resident) as WidgetResident;
      const progress = topicView(session);
      this.interviewName = person.name;
      this.interviewProgress = `已结束 ${progress.done} / ${progress.total} 个话题`;
    } catch (e) {
      this.interviewName = '';
    }
  }

  private continueInterview(): void {
    if (!this.interviewName) {
      router.pushUrl({ url: 'pages/ResidentList' });
      return;
    }
    AppStorage.setOrCreate('sessionId', AppStorage.get<string>('widgetInterviewId') ?? '');
    AppStorage.setOrCreate('selectedPerson', AppStorage.get<string>('widgetInterviewResident') ?? '');
    router.pushUrl({ url: 'pages/Interview' });
  }

  @Builder
  shortcut(icon: Resource, label: string, route: string) {
    Column({ space: 4 }) {
      Image(icon).width(46).height(46).objectFit(ImageFit.Contain).borderRadius(13)
      Text(label).fontSize(10).fontColor('#FFFFFF')
    }.layoutWeight(1).onClick(() => router.pushUrl({ url: route }))
  }

  @Builder
  widget(title: string, action: string, tint: string, route: string) {
    Column({ space: 6 }) {
      Row({ space: 5 }) {
        Image($r('app.media.brand_cloud')).width(20).height(20).objectFit(ImageFit.Contain).borderRadius(10)
        Text(title)
          .fontSize(10)
          .fontColor(Theme.ink)
        Blank()
      }
      .width('100%')
      Text(route === 'pages/FollowupQueue' ? this.followupText : this.careText)
        .fontSize(9)
        .fontColor(Theme.ink2)
        .lineHeight(15)
        .width('100%')
        .layoutWeight(1)
      Text(action)
        .fontSize(8)
        .fontColor('#FFFFFF')
        .backgroundColor(Theme.green)
        .borderRadius(9)
        .padding({ left: 9, right: 9, top: 4, bottom: 4 })
        .onClick(() => router.pushUrl({ url: route }))
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .height(150)
    .padding(11)
    .borderRadius(18)
    .backgroundColor(tint)
    .border({ width: 1, color: 'rgba(255,255,255,0.7)' })
    .shadow({ radius: 12, color: 'rgba(0,0,0,0.14)', offsetY: 6 })
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Image($r('app.media.hero_balloons'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({ angle: 180, colors: [['rgba(30,45,55,0.32)', 0], ['rgba(40,30,28,0.1)', 0.5], ['rgba(30,24,20,0.5)', 1]] })

      Column({ space: 10 }) {
        Row() {
          Text('‹').accessibilityText('返回')
            .fontSize(24)
            .fontColor('#FFFFFF')
            .width(30)
            .onClick(() => router.replaceUrl({ url: 'pages/Home' }))
          Text('万能卡片与实况窗')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Blank().width(30)
        }
        .width('100%')
        .height(44)

        Row({ space: 9 }) {
          Text('◉').accessibilityText('语音输入')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .width(28)
            .height(28)
            .textAlign(TextAlign.Center)
            .borderRadius(14)
            .backgroundColor(Theme.pink)
          Column({ space: 2 }) {
            Text(this.interviewName ? '最近访谈 · ' + this.interviewName : '暂无可继续的访谈')
              .fontSize(11)
              .fontColor('#FFFFFF')
            Text(this.interviewProgress || '从筛查名单选择居民')
              .fontSize(8)
              .fontColor('rgba(255,255,255,0.75)')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text(this.interviewName ? '继续' : '筛查名单')
            .fontSize(9)
            .fontColor(Theme.ink)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .onClick(() => this.continueInterview())
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(18)
        .backgroundColor('rgba(32,44,52,0.55)')
        .border({ width: 1, color: 'rgba(255,255,255,0.3)' })

        Text('万能卡片 · 2×2')
          .fontSize(8)
          .fontColor('rgba(255,255,255,0.9)')
          .letterSpacing(1)
          .width('100%')

        Row({ space: 10 }) {
          this.widget('到期回访', '查看名单', 'rgba(255,252,246,0.9)', 'pages/FollowupQueue')
          this.widget('关怀提醒', '查看关怀', 'rgba(255,244,240,0.9)', 'pages/CareList')
        }
        .width('100%')

        Column({ space: 6 }) {
          Text('✦ 回访工作台').fontSize(12).fontColor('#6A4B7D').width('100%')
          Text('查看待办提醒，或进入回访与关怀工作台。')
            .fontSize(11).fontColor(Theme.ink).width('100%')
          Row({ space: 8 }) {
            Button('回访与关怀').fontSize(10).backgroundColor(Theme.green)
              .onClick(() => router.pushUrl({ url: 'pages/Followup' }))
            Button('查看提醒').fontSize(10).backgroundColor(Theme.green)
              .onClick(() => router.pushUrl({ url: 'pages/Notifications' }))
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(11)
        .borderRadius(16)
        .backgroundColor('rgba(246,240,250,0.9)')
        .border({ width: 1, color: 'rgba(255,255,255,0.7)' })

        Blank()

        Row({ space: 8 }) {
          this.shortcut($r('app.media.nav_home_clear'), '首页', 'pages/Home')
          this.shortcut($r('app.media.care_screening'), '筛查', 'pages/ResidentList')
          this.shortcut($r('app.media.care_followup'), '回访', 'pages/Followup')
          this.shortcut($r('app.media.nav_settings'), '设置', 'pages/Settings')
        }.width('100%').padding({ bottom: 14 })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 10 })
    }
    .width('100%')
    .height('100%')
  }
}
