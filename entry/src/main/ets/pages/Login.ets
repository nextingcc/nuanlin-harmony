import { router } from '@kit.ArkUI';
import { Api } from '../model/Api';
import { Palette, palette } from '../model/Theme';

// 仅本机虚构联调账号，用于评审现场快速进入演示。
const DEMO_ACCOUNT: string = 'nuanlin-dev';
const DEMO_PASSWORD: string = 'GffOJfVXKQXa_csTmWs1Oudx';

@Entry
@Component
struct Login {
  @State account: string = '';
  @State password: string = '';
  @State message: string = '';
  @State busy: boolean = false;
  @StorageProp('darkMode') darkMode: boolean = false;

  private p(): Palette { return palette(this.darkMode); }

  private async doLogin(): Promise<void> {
    if (this.account.trim().length === 0 || this.password.length === 0) {
      this.message = '请输入账号和密码';
      return;
    }
    this.busy = true;
    this.message = '';
    const ok = await Api.login(this.account.trim(), this.password);
    this.busy = false;
    if (ok) {
      AppStorage.setOrCreate('accountName', this.account.trim());
      router.replaceUrl({ url: 'pages/Home' });
    } else {
      this.message = '登录失败，请检查账号或密码';
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
          .onClick(() => router.replaceUrl({ url: 'pages/Welcome' }))
        Blank()
      }
      .width('100%')
      .height(52)
      .padding({ left: 12, right: 20 })

      Column({ space: 0 }) {
        Image($r('app.media.brand_cloud')).width(52).height(52).objectFit(ImageFit.Contain).borderRadius(26)
        Text('暖邻')
          .fontSize(28)
          .fontFamily('serif')
          .fontColor(this.p().ink)
          .letterSpacing(3)
          .margin({ top: 8 })
        Text('社区心理关怀工作台')
          .fontSize(10)
          .fontColor(this.p().muted)
          .letterSpacing(2)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 24, bottom: 30 })

      Column({ space: 12 }) {
        Column({ space: 6 }) {
          Text('账号')
            .fontSize(10)
            .fontColor(this.p().segInk)
            .width('100%')
          TextInput({ placeholder: '请输入社区工作账号', text: this.account })
            .height(48)
            .fontSize(14)
            .fontColor(this.p().ink)
            .placeholderColor(this.darkMode ? this.p().segSub : '#B8A797')
            .backgroundColor(this.p().surface)
            .borderRadius(14)
            .border({ width: 1, color: this.p().border })
            .padding({ left: 14, right: 14 })
            .onChange((v: string) => { this.account = v; })
        }

        Column({ space: 6 }) {
          Text('密码')
            .fontSize(10)
            .fontColor(this.p().segInk)
            .width('100%')
          TextInput({ placeholder: '请输入密码', text: this.password })
            .type(InputType.Password)
            .height(48)
            .fontSize(14)
            .fontColor(this.p().ink)
            .placeholderColor(this.darkMode ? this.p().segSub : '#B8A797')
            .backgroundColor(this.p().surface)
            .borderRadius(14)
            .border({ width: 1, color: this.p().border })
            .padding({ left: 14, right: 14 })
            .onChange((v: string) => { this.password = v; })
        }

        if (this.message.length > 0) {
          Text(this.message)
            .fontSize(10)
            .fontColor(this.p().danger)
            .width('100%')
        }

        Button(this.busy ? '登录中…' : '登录')
          .width('100%')
          .height(48)
          .fontSize(15)
          .fontColor('#FFFFFF')
          .backgroundColor(this.p().accent)
          .borderRadius(24)
          .margin({ top: 6 })
          .enabled(!this.busy)
          .onClick(() => { this.doLogin(); })

        Row({ space: 8 }) {
          Text('演示账号').fontSize(10).fontColor(this.p().segInk)
          Text('一键填入').fontSize(10).fontColor(this.p().accentText)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(11).backgroundColor(this.p().iconB)
            .onClick(() => {
              this.account = DEMO_ACCOUNT;
              this.password = DEMO_PASSWORD;
              this.message = '';
            })
        }.width('100%').justifyContent(FlexAlign.Center).margin({ top: 10 })

        Text('账号由社区管理员分配，登录信息只用于本次会话')
          .fontSize(9)
          .fontColor(this.p().muted)
          .lineHeight(17)
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: 12 })
      }
      .width('100%')
      .padding({ left: 26, right: 26 })

      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.p().pageBg)
  }
}
