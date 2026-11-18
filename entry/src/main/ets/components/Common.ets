import { router } from '@kit.ArkUI';
import { Theme } from '../model/Theme';
import { readableFont } from '../model/UserPreferences';

@Component
export struct Avatar {
  @Prop src: Resource = $r('app.media.avatar_f1');
  @Prop diameter: number = 40;

  build() {
    Image(this.src)
      .width(this.diameter)
      .height(this.diameter)
      .borderRadius(this.diameter / 2)
      .border({ width: 1.5, color: '#EBD9C8' })
      .backgroundColor('#FFFFFF')
      .objectFit(ImageFit.Cover)
  }
}

@Component
export struct Tag {
  @StorageProp('textSize') preferenceTextSize: string = 'normal';
  @StorageProp('darkMode') darkMode: boolean = false;
  @Prop text: string = '';
  @Prop kind: string = 'green';

  private bg(): string {
    if (this.darkMode) {
      if (this.kind === 'red') return '#3A2A28';
      if (this.kind === 'amber') return '#3A3020';
      if (this.kind === 'lilac') return '#2E2A3A';
      if (this.kind === 'sky') return '#22323A';
      return '#2A2E24';
    }
    if (this.kind === 'red') return '#FBE3E1';
    if (this.kind === 'amber') return '#FBEDD8';
    if (this.kind === 'lilac') return '#F0E9F6';
    if (this.kind === 'sky') return '#E6F0F4';
    return '#E9F0DE';
  }

  private fg(): string {
    if (this.darkMode) {
      if (this.kind === 'red') return '#E3A5A0';
      if (this.kind === 'amber') return '#D8B98A';
      if (this.kind === 'lilac') return '#C9B8E0';
      if (this.kind === 'sky') return '#A9CBD8';
      return '#B7C79F';
    }
    if (this.kind === 'red') return '#9C4A45';
    if (this.kind === 'amber') return '#8A6338';
    if (this.kind === 'lilac') return '#6A4B7D';
    if (this.kind === 'sky') return '#40697A';
    return '#56693C';
  }

  build() {
    Text(this.text)
      .fontSize(readableFont(10, this.preferenceTextSize))
      .fontColor(this.fg())
      .backgroundColor(this.bg())
      .borderRadius(5)
      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
  }
}

@Component
export struct NavBar {
  @Prop title: string = '';
  @Prop showBack: boolean = true;
  @Prop action: string = '';
  @Prop dark: boolean = false;

  build() {
    Row() {
      if (this.showBack) {
        Text('‹').accessibilityText('返回')
          .fontSize(26)
          .fontColor(this.dark ? '#FFFFFF' : Theme.ink)
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .borderRadius(18)
          .backgroundColor(this.dark ? 'rgba(255,255,255,0.18)' : 'rgba(255,255,255,0.6)')
          .onClick(() => router.replaceUrl({ url: 'pages/Home' }))
      } else {
        Blank().width(36)
      }
      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.dark ? '#FFFFFF' : Theme.ink)
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
      if (this.action.length > 0) {
        Text(this.action)
          .fontSize(12)
          .fontColor(this.dark ? '#FFFFFF' : Theme.ink2)
          .width(52)
          .textAlign(TextAlign.End)
      } else {
        Blank().width(36)
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
  }
}

@Component
export struct Dock {
  @Prop current: number = 0;
  @StorageProp('darkMode') darkMode: boolean = false;

  private go(index: number, url: string): void {
    if (index === this.current) return;
    router.replaceUrl({ url: url });
  }

  private surface(): string {
    return this.darkMode ? 'rgba(36,31,27,0.96)' : 'rgba(255,252,247,0.94)';
  }

  private edge(): string {
    return this.darkMode ? 'rgba(70,60,50,0.9)' : 'rgba(255,255,255,0.9)';
  }

  private ink(): string {
    return this.darkMode ? '#D9C8B6' : Theme.muted;
  }

  @Builder
  item(index: number, icon: Resource, label: ResourceStr, url: string) {
    Column({ space: 3 }) {
      Stack() {
        if (index === this.current) {
          Circle()
            .width(40)
            .height(40)
            .fill(this.darkMode ? 'rgba(143,165,116,0.30)' : 'rgba(157,190,151,0.22)')
        }
        Image(icon)
          .width(36)
          .height(36)
          .objectFit(ImageFit.Contain)
          .opacity(index === this.current ? 1 : 0.9)
      }
      .width(40)
      .height(40)
      Text(label)
        .fontSize(9)
        .fontColor(index === this.current ? (this.darkMode ? '#B7C79F' : Theme.greenDeep) : this.ink())
        .fontWeight(index === this.current ? FontWeight.Bold : FontWeight.Normal)
      Circle()
        .width(4)
        .height(4)
        .fill(index === this.current ? (this.darkMode ? '#8FA574' : Theme.green) : Color.Transparent)
    }
    .layoutWeight(1)
    .onClick(() => this.go(index, url))
  }

  build() {
    Row() {
      this.item(0, $r('app.media.nav_home_clear'), $r('app.string.tab_home'), 'pages/Home')
      this.item(1, $r('app.media.nav_tools'), $r('app.string.tab_tools'), 'pages/Tools')
      this.item(2, $r('app.media.nav_assistant'), $r('app.string.tab_assistant'), 'pages/Assistant')
      this.item(3, $r('app.media.nav_settings'), $r('app.string.tab_settings'), 'pages/Settings')
    }
    .width('92%')
    .height(58)
    .margin({ bottom: 14 })
    .backgroundColor(this.surface())
    .borderRadius(22)
    .border({ width: 1, color: this.edge() })
    .shadow({ radius: 18, color: 'rgba(90,60,40,0.16)', offsetY: 8 })
  }
}
