import { router } from '@kit.ArkUI';

@Entry
@Component
struct Welcome {
  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Image($r('app.media.welcome'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)

      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [['rgba(18,38,54,0.38)', 0], ['rgba(20,30,30,0.05)', 0.34], ['rgba(30,24,20,0.42)', 0.6], ['rgba(30,24,20,0.88)', 1]]
        })

      Column() {
        Row({ space: 8 }) {
          Image($r('app.media.brand_cloud')).width(40).height(40).objectFit(ImageFit.Contain).borderRadius(20)
          Column({ space: 2 }) {
            Text('暖邻')
              .fontSize(23)
              .fontColor('#FFFFFF')
              .fontFamily('serif')
            Text('NUANLIN · COMMUNITY CARE')
              .fontSize(7)
              .fontColor('rgba(255,255,255,0.75)')
              .letterSpacing(2)
          }
          .alignItems(HorizontalAlign.Start)
          Blank()
          Row({ space: 5 }) {
            Text('◈')
              .fontSize(10)
              .fontColor('rgba(255,255,255,0.9)')
            Text('鸿蒙原生 · 端侧 AI')
              .fontSize(9)
              .fontColor('rgba(255,255,255,0.9)')
          }
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor('rgba(255,255,255,0.18)')
          .border({ width: 1, color: 'rgba(255,255,255,0.34)' })
        }
        .width('100%')
        .padding({ left: 24, right: 24 })

        Blank()

        Column({ space: 0 }) {
          Text('WELCOME · 第九届传智杯 · HARMONYOS')
            .fontSize(8)
            .fontColor('rgba(255,255,255,0.62)')
            .letterSpacing(2.4)
            .margin({ bottom: 14 })
          Text('让每一份心情，\n被温柔看见。')
            .fontSize(33)
            .fontFamily('serif')
            .fontColor('#FFFFFF')
            .lineHeight(47)
            .letterSpacing(1)
          Text('认真地年轻，温柔地老去。\n一次耐心的倾听，连接持续的关怀。')
            .fontSize(12)
            .fontColor('rgba(255,255,255,0.84)')
            .lineHeight(24)
            .margin({ top: 12 })

          Button('开始心灵旅途  →')
            .width('100%')
            .height(50)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#4A3428')
            .backgroundColor('rgba(255,250,244,0.95)')
            .borderRadius(26)
            .margin({ top: 28 })
            .onClick(() => router.replaceUrl({ url: 'pages/Login' }))

          Row({ space: 6 }) {
            Text('◎')
              .fontSize(12)
              .fontColor('rgba(255,255,255,0.85)')
            Text('社区工作账号登录 · 数据仅存本机与社区端')
              .fontSize(10)
              .fontColor('rgba(255,255,255,0.88)')
          }
          .width('100%')
          .height(44)
          .justifyContent(FlexAlign.Center)
          .margin({ top: 10 })
          .borderRadius(22)
          .backgroundColor('rgba(255,255,255,0.12)')
          .border({ width: 1, color: 'rgba(255,255,255,0.34)' })

          Text('继续即表示同意《用户协议》与《隐私政策》\n适老化模式已默认开启')
            .fontSize(8)
            .fontColor('rgba(255,255,255,0.55)')
            .lineHeight(15)
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ top: 18 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 26, right: 26, bottom: 34 })
      }
      .width('100%')
      .height('100%')
      .padding({ top: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#12202B')
  }
}


