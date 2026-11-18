@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('title') title: string = '今日提醒';
  @LocalStorageProp('count') count: string = '—';
  @LocalStorageProp('detail') detail: string = '打开暖邻查看';

  build() {
    Column({ space: 3 }) {
      Row() {
        Text('暖邻').fontSize(11).fontWeight(FontWeight.Medium).fontColor('#7E8F63')
        Blank()
        Text(this.title).fontSize(9).fontColor('#A0806E')
      }
      .width('100%')

      Blank()

      Text(this.count)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#414C32')

      Text(this.detail)
        .fontSize(10)
        .fontColor('#7D7169')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Blank()

      Text('点开查看 ›').fontSize(9).fontColor('#84965E')
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#FFF9F3')
    .borderRadius(16)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        bundleName: 'com.nuanlin.care',
        abilityName: 'EntryAbility',
        params: { route: 'pages/Home' }
      });
    })
  }
}
