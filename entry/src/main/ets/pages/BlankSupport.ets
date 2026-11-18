import { router } from '@kit.ArkUI';

@Entry
@Component
struct BlankSupport {
  build() {
    Column() {
      Button('‹').backgroundColor(Color.Transparent).fontColor('#503326').fontSize(24)
        .accessibilityText('返回').onClick(() => router.back())
    }.width('100%').height('100%').alignItems(HorizontalAlign.Start).backgroundColor('#FFF9F3')
  }
}
