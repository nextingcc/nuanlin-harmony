import { router } from '@kit.ArkUI';
import { Dock } from '../components/Common';
import { Layout } from '../model/Layout';
import { Palette, palette, Theme } from '../model/Theme';

@Entry
@Component
struct Tools {
  @State viewWidth: number = 0;
  @StorageProp('darkMode') darkMode: boolean = false;

  private wide(): boolean {
    return Layout.isWide(this.viewWidth);
  }

  private p(): Palette {
    return palette(this.darkMode);
  }

  @Builder
  toolCard(icon: Resource, title: string, sub: string, target: string, scale: number, dx: number, dy: number) {
    Row({ space: 14 }) {
      Stack() {
        Image(icon).width(48).height(48).objectFit(ImageFit.Contain)
          .scale({ x: scale, y: scale }).translate({ x: dx, y: dy })
      }.width(48).height(48).borderRadius(16).backgroundColor('#FFFFFF').clip(true)
      Column({ space: 3 }) {
        Text(title).fontSize(15).fontColor(this.p().ink).fontWeight(FontWeight.Medium)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(sub).fontSize(9).fontColor(this.p().muted)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›').fontSize(18).fontColor(this.p().chevron)
    }
    .width(this.wide() ? '48.6%' : '100%')
    .padding(14)
    .borderRadius(20)
    .backgroundColor(this.p().surface)
    .border({ width: 1, color: this.p().border })
    .shadow({ radius: 12, color: 'rgba(120,72,60,0.08)', offsetY: 5 })
    .margin({ bottom: 12 })
    .onClick(() => router.pushUrl({ url: target }))
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Image($r('app.media.tools_bg'))
        .width('100%')
        .height('68%')
        .objectFit(ImageFit.Cover)
        .opacity(this.darkMode ? 0.28 : 0.92)
        .align(Alignment.Bottom)

      Column()
        .width('100%')
        .height('100%')
        .linearGradient(this.darkMode ? {
          angle: 180,
          colors: [['rgba(21,19,17,0.97)', 0], ['rgba(21,19,17,0.92)', 0.38], ['rgba(21,19,17,0.72)', 0.7], ['rgba(21,19,17,0.9)', 1]]
        } : {
          angle: 180,
          colors: [['rgba(250,240,231,0.98)', 0], ['rgba(250,240,231,0.92)', 0.38], ['rgba(250,240,231,0.55)', 0.7], ['rgba(250,240,231,0.82)', 1]]
        })

      Column() {
        Scroll() {
          Column() {
            Row() {
              Text($r('app.string.tools_title'))
                .fontSize(24)
                .fontFamily('serif')
                .fontColor(this.p().ink)
                .letterSpacing(2)
              Blank()
              Image($r('app.media.brand_cloud')).width(48).height(48).objectFit(ImageFit.Contain)
            }
            .width('100%')
            .padding({ left: 22, right: 22, top: 20 })

            Text($r('app.string.tools_subtitle'))
              .fontSize(10)
              .fontColor(this.p().muted)
              .width('100%')
              .padding({ left: 22, right: 22, top: 4, bottom: 18 })

            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
              this.toolCard($r('app.media.tool_memo_icon'), '备忘录', '记录待办 · 整理琐事', 'pages/Memo', 1.35, -4, 2)
              this.toolCard($r('app.media.tool_breathe_icon'), '呼吸放松', '舒缓情绪 · 放松身心', 'pages/Breathe', 1.45, 0, 0)
              this.toolCard($r('app.media.tool_journal_icon'), '日志', '日记、心情与一周回顾', 'pages/Journal', 1.17, 0, 2)
            }
            .width('100%')
            .padding({ left: 22, right: 22 })

            Button('已保存的回访计划')
              .backgroundColor(this.darkMode ? '#6F4852' : '#F4D5DE').fontColor(this.darkMode ? '#FFF2F5' : '#754353').fontSize(14)
              .height(32).padding({ left: 14, right: 14 }).borderRadius(16)
              .margin({ left: 22, right: 22, top: 8, bottom: 8 })
              .onClick(() => router.pushUrl({ url: 'pages/VisitPlan' }))

            Text($r('app.string.tools_footer'))
              .fontSize(9)
              .fontColor(this.p().segInk)
              .lineHeight(17)
              .width('100%')
              .padding({ left: 22, right: 22, top: 18, bottom: 20 })
          }
          .width('100%')
          .constraintSize({ minHeight: '100%' })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        Column() {
          Dock({ current: 1 })
        }
        .width('100%')
        .padding({ bottom: 10 })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.p().pageBg)
    .onAreaChange((_old: Area, area: Area) => {
      const width = Layout.parseWidth(String(area.width));
      if (width !== this.viewWidth) this.viewWidth = width;
    })
  }
}
