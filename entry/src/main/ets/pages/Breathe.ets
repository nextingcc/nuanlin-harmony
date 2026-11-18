import { router } from '@kit.ArkUI';
import { Palette, palette } from '../model/Theme';

@Entry
@Component
struct Breathe {
  @State duration: number = 180;
  @State remaining: number = 180;
  @State running: boolean = false;
  @State paused: boolean = false;
  @State phase: string = '准备';
  @State count: number = 0;
  @StorageProp('darkMode') darkMode: boolean = false;
  private timer: number = -1;

  private p(): Palette {
    return palette(this.darkMode);
  }

  private tick(): void {
    if (this.remaining <= 0) {
      this.stop();
      this.phase = '完成';
      return;
    }
    this.remaining--;
    this.count++;
    const p = this.count % 14;
    this.phase = p < 4 ? '吸气' : (p < 8 ? '屏息' : '呼气');
  }

  private start(): void {
    if (this.running) return;
    if (this.remaining <= 0) this.remaining = this.duration;
    this.running = true;
    this.paused = false;
    this.phase = '吸气';
    this.timer = setInterval(() => this.tick(), 1000);
  }

  private pause(): void {
    if (!this.running) return;
    this.paused = true;
    this.running = false;
    if (this.timer >= 0) clearInterval(this.timer);
    this.timer = -1;
    this.phase = '已暂停';
  }

  private stop(): void {
    this.running = false;
    this.paused = false;
    if (this.timer >= 0) clearInterval(this.timer);
    this.timer = -1;
    this.remaining = this.duration;
    this.phase = '准备';
    this.count = 0;
  }

  onPageHide(): void {
    if (this.timer >= 0) clearInterval(this.timer);
    this.timer = -1;
    this.running = false;
  }

  private mmss(): string {
    const m = Math.floor(this.remaining / 60).toString().padStart(2, '0');
    const s = (this.remaining % 60).toString().padStart(2, '0');
    return `${m}:${s}`;
  }

  build() {
    Column() {
      Row() {
        Text('‹').accessibilityText('返回').fontSize(26).fontColor(this.p().ink).width(32).textAlign(TextAlign.Center)
          .onClick(() => {
            this.stop();
            router.back();
          })
        Text('呼吸放松').fontSize(18).fontColor(this.p().ink).layoutWeight(1).textAlign(TextAlign.Center)
        Text('').width(40)
      }
      .width('100%')
      .height(50)

      Column({ space: 8 }) {
        Text(this.phase)
          .fontSize(13)
          .fontColor(this.p().accent)
          .letterSpacing(2)
        Text(this.mmss())
          .fontSize(48)
          .fontFamily('serif')
          .fontColor(this.p().ink)
        Text('跟着节奏，慢慢来就好')
          .fontSize(10)
          .fontColor(this.p().muted)
      }
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 36, bottom: 28 })

      Row({ space: 10 }) {
        ForEach([60, 180, 300], (sec: number) => {
          Text(sec === 60 ? '1 分钟' : (sec === 180 ? '3 分钟' : '5 分钟'))
            .fontSize(10)
            .fontColor(this.duration === sec ? '#FFFFFF' : this.p().segInk)
            .backgroundColor(this.duration === sec ? this.p().accent : this.p().segActive)
            .borderRadius(16)
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .onClick(() => {
              if (this.running) return;
              this.duration = sec;
              this.remaining = sec;
            })
        }, (sec: number) => sec.toString())
      }
      .margin({ bottom: 28 })

      Row({ space: 12 }) {
        Button(this.running ? '暂停' : (this.paused ? '继续' : '开始'))
          .layoutWeight(1)
          .height(46)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor(this.p().accent)
          .borderRadius(23)
          .onClick(() => {
            if (this.running) this.pause();
            else this.start();
          })
        Button('结束')
          .width(92)
          .height(46)
          .fontSize(13)
          .fontColor(this.p().segInk)
          .backgroundColor(this.p().segActive)
          .borderRadius(23)
          .onClick(() => this.stop())
      }
      .width('100%')
      .padding({ left: 30, right: 30 })

      Text('呼吸练习只用于放松，不替代医疗建议。')
        .fontSize(9)
        .fontColor(this.p().muted)
        .margin({ top: 20 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.p().pageBg)
  }
}
