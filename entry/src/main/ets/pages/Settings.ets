import { readableFont, readableLineHeight } from '../model/UserPreferences';
import { router, promptAction, mediaquery } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Palette, palette, resolveDark } from '../model/Theme';
import { publishReminder } from '../model/Notifier';
import { Api } from '../model/Api';
import { DIALECTS, readPreferences, savePreferences } from '../model/UserPreferences';
import { applySystemBars } from '../model/WindowTheme';
import { saveAssistantMemoItems } from '../model/AssistantMemoStore';
import { loadAvatar, pickAvatarSource, loadAvatarSourceImage, saveCroppedAvatar, discardAvatarSource } from '../model/UserAvatar';
import { avatarCropRegion, clampAvatarScale } from '../model/AvatarCrop';
import { image } from '@kit.ImageKit';

@Entry
@Component
struct Settings {
  private font(base: number): number { return readableFont(base, this.textSize); }
  private line(base: number): number { return readableLineHeight(base, this.textSize); }

  @State dialect: string = '自动识别';
  @State consent: boolean = false;
  @State rate: number = 1;
  @State textSize: string = 'normal';
  @State reduceMotion: boolean = false;
  @State followupDate: string = '';
  @State showDialects: boolean = false;
  @State saving: boolean = false;
  @StorageProp('darkMode') darkMode: boolean = false;
  @StorageProp('accountName') accountName: string = 'nuanlin-dev';
  @StorageProp('orgName') orgName: string = '';
  @StorageProp('runtimeErrorCount') runtimeErrorCount: number = 0;
  @StorageProp('themeMode') themeMode: string = 'auto';
  @State systemDark: boolean = false;
  @State avatarPm: image.PixelMap | undefined = undefined;
  @State cropVisible: boolean = false;
  @State cropScale: number = 1;
  @State cropDx: number = 0;
  @State cropDy: number = 0;
  @State cropImage: image.PixelMap | undefined = undefined;
  @State cropSourceWidth: number = 1;
  @State cropSourceHeight: number = 1;
  private cropStartScale: number = 1;
  private cropStartDx: number = 0;
  private cropStartDy: number = 0;
  private readonly cropView: number = 300;
  private darkListener: mediaquery.MediaQueryListener | null = null;

  private p(): Palette {
    return palette(this.darkMode);
  }

  private clampCropOffset(): void {
    const max = this.cropView * (this.cropScale - 1) / 2;
    this.cropDx = this.cropDx < -max ? -max : (this.cropDx > max ? max : this.cropDx);
    this.cropDy = this.cropDy < -max ? -max : (this.cropDy > max ? max : this.cropDy);
  }

  private async changeAvatar(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const picked: boolean = await pickAvatarSource(ctx);
      if (!picked) return;
      const source = await loadAvatarSourceImage(ctx);
      if (source.pixelMap === undefined) {
        promptAction.showToast({ message: '未能读取所选照片，请重试' });
        return;
      }
      this.cropImage = source.pixelMap;
      this.cropSourceWidth = source.width;
      this.cropSourceHeight = source.height;
      this.cropScale = 1;
      this.cropDx = 0;
      this.cropDy = 0;
      this.cropVisible = true;
    } catch (e) {
      promptAction.showToast({ message: '未能读取所选照片，请重试' });
    }
  }

  private cancelCrop(): void {
    this.cropVisible = false;
    this.cropImage = undefined;
    discardAvatarSource(getContext(this) as common.UIAbilityContext);
  }

  private async applyCrop(): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext;
    const region = avatarCropRegion(this.cropSourceWidth, this.cropSourceHeight, this.cropView,
      this.cropScale, this.cropDx, this.cropDy);
    const saved: boolean = await saveCroppedAvatar(ctx, region.x, region.y, region.size);
    if (saved) {
      this.avatarPm = await loadAvatar(ctx);
      promptAction.showToast({ message: '头像已更新' });
    } else {
      promptAction.showToast({ message: '头像保存失败，请重试' });
    }
    this.cropVisible = false;
    this.cropImage = undefined;
    discardAvatarSource(ctx);
  }

  private runtimeLabel(): string {
    return this.runtimeErrorCount > 0
      ? '已记录 ' + this.runtimeErrorCount.toString() + ' 次异常（写入系统日志）'
      : '本次运行未记录未捕获异常';
  }

  private orgLabel(): string {
    if (this.orgName === 'nuanlin-integration') return '青禾社区';
    if (this.orgName.length === 0) return '青禾社区';
    return '社区账号';
  }

  private applyTheme(): void {
    const dark: boolean = resolveDark(this.themeMode, this.systemDark);
    AppStorage.setOrCreate('darkMode', dark);
    this.darkMode = dark;
    applySystemBars(getContext(this) as common.UIAbilityContext, dark).catch(() => {});
  }

  private setTheme(mode: string): void {
    this.themeMode = mode;
    AppStorage.setOrCreate('themeMode', mode);
    this.applyTheme();
    // 主题切换即时生效并直接持久化，不依赖「保存设置」。
    const prefs = readPreferences();
    prefs.themeMode = mode;
    savePreferences(getContext(this) as common.Context, prefs).catch(() => {
      promptAction.showToast({ message: '主题已切换，保存失败，重启后可能恢复。', duration: 2000 });
    });
  }

  aboutToAppear(): void {
    loadAvatar(getContext(this) as common.UIAbilityContext).then((pm: image.PixelMap | undefined) => { this.avatarPm = pm; });
    const legacyDark: boolean = AppStorage.get<boolean>('darkMode') ?? false;
    const stored: string = AppStorage.get<string>('themeMode') ?? (legacyDark ? 'dark' : 'auto');
    this.themeMode = stored;
    this.darkListener = mediaquery.matchMediaSync('(prefers-color-scheme: dark)');
    this.systemDark = this.darkListener.matches;
    this.darkListener.on('change', (result: mediaquery.MediaQueryResult) => {
      this.systemDark = result.matches;
      this.applyTheme();
    });
    this.applyTheme();
    const prefs = readPreferences();
    this.dialect = prefs.voiceDialect;
    this.consent = AppStorage.get<boolean>('voiceConsent') ?? false;
    this.rate = prefs.ttsRate;
    this.textSize = prefs.textSize;
    this.reduceMotion = prefs.reduceMotion;
    this.followupDate = prefs.followupDate || this.defaultDate();
  }

  aboutToDisappear(): void {
    if (this.darkListener !== null) {
      this.darkListener.off('change');
      this.darkListener = null;
    }
  }

  private defaultDate(): string {
    return this.fmt(new Date());
  }

  private weekday(): string {
    const names = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
    return names[new Date(this.followupDate + 'T12:00:00').getDay()] ?? '';
  }

  private fmt(d: Date): string {
    const m = (d.getMonth() + 1).toString().padStart(2, '0');
    const day = d.getDate().toString().padStart(2, '0');
    return `${d.getFullYear()}-${m}-${day}`;
  }

  private pickDate(): void {
    const parts = this.followupDate.split('-');
    const selected = parts.length === 3 ? new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])) : new Date();
    DatePickerDialog.show({
      start: new Date(2020, 0, 1),
      end: new Date(2035, 11, 31),
      selected: selected,
      onDateAccept: (value: Date) => { this.followupDate = this.fmt(value); }
    });
  }

  private async save(): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    try {
      await savePreferences(getContext(this) as common.UIAbilityContext, {
        voiceDialect: this.dialect, ttsRate: this.rate, textSize: this.textSize,
        reduceMotion: this.reduceMotion, themeMode: this.themeMode, followupDate: this.followupDate });
      AppStorage.setOrCreate('voiceConsent', this.consent);
      this.applyTheme();
      promptAction.showToast({ message: '设置已保存', duration: 1500 });
    } catch (e) {
      promptAction.showToast({ message: '保存失败，修改仍保留，请重试。', duration: 2500 });
    } finally { this.saving = false; }
  }

  private async testNotification(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const ok = await publishReminder(context, '测试提醒：回访与关怀提醒通道正常', false);
    promptAction.showToast({ message: ok ? '已发送系统通知' : '通知未开启或被拒绝', duration: 1500 });
  }

  private confirmLogout(): void {
    AlertDialog.show({
      title: '退出登录',
      message: '将清除本机保存的登录会话，本地备忘录与设置不受影响。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '退出',
        action: async () => {
          await Api.logout();
          router.replaceUrl({ url: 'pages/Login' });
        }
      }
    });
  }

  private confirmClearMemos(): void {
    AlertDialog.show({
      title: '清除本地备忘录',
      message: '只删除本机备忘录，不影响服务端档案与访谈记录。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '清除',
        action: async () => {
          try {
            await saveAssistantMemoItems([]);
            promptAction.showToast({ message: '本地备忘录已清除', duration: 1500 });
          } catch (e) { promptAction.showToast({ message: '暂未清除，原备忘录已保留，请重试。', duration: 2000 }); }
        }
      }
    });
  }

  @Builder
  section(text: string) {
    Text(text).fontSize(this.font(10)).fontColor(this.p().section).letterSpacing(2).width('100%').margin({ top: 8, bottom: 8 })
  }

  @Builder
  seg(options: string[], labels: string[], current: string, pick: (v: string) => void) {
    Row() {
      ForEach(options, (opt: string, i: number) => {
        Column({ space: 1 }) {
          Text(labels[i]).fontSize(this.font(10)).fontColor(current === opt ? this.p().ink : this.p().segInk)
        }
        .layoutWeight(1).constraintSize({ minHeight: 44 }).padding(8).justifyContent(FlexAlign.Center).borderRadius(10)
        .backgroundColor(current === opt ? this.p().segActive : Color.Transparent)
        .onClick(() => pick(opt))
      }, (opt: string) => opt)
    }
    .padding(3).borderRadius(13).backgroundColor(this.p().segBg).width('100%')
  }

  private themeLabel(mode: string): string {
    if (mode === 'light') return '浅色';
    if (mode === 'dark') return '深色';
    return '跟随系统';
  }

  // 主题分段直接读 this.themeMode，避免 @Builder 参数缓存导致高亮停留在旧选项。
  @Builder
  themeSeg() {
    Row() {
      ForEach(['auto', 'light', 'dark'], (option: string) => {
        Column({ space: 1 }) {
          Text(this.themeLabel(option)).fontSize(this.font(10))
            .fontColor(this.themeMode === option ? this.p().ink : this.p().segInk)
        }
        .layoutWeight(1).constraintSize({ minHeight: 44 }).padding(8).justifyContent(FlexAlign.Center).borderRadius(10)
        .backgroundColor(this.themeMode === option ? this.p().segActive : Color.Transparent)
        .onClick(() => this.setTheme(option))
      }, (option: string) => option)
    }
    .padding(3).borderRadius(13).backgroundColor(this.p().segBg).width('100%')
  }

  @Builder
  rateSeg() {
    Row() {
      ForEach(['0.75', '1', '1.25', '1.5'], (opt: string, i: number) => {
        Column({ space: 1 }) {
          Text(['慢一点', '标准', '稍快', '更快'][i])
            .fontSize(this.font(10))
            .fontWeight(this.rate === Number(opt) ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.rate === Number(opt) ? this.p().ink : this.p().segInk)
          Text(opt).fontSize(this.font(7))
            .fontColor(this.rate === Number(opt) ? this.p().accent : this.p().segSub)
        }
        .layoutWeight(1).constraintSize({ minHeight: this.textSize === 'normal' ? 44 : 60 }).padding(6)
        .justifyContent(FlexAlign.Center).borderRadius(10)
        .backgroundColor(this.rate === Number(opt) ? this.p().segActive : Color.Transparent)
        .shadow(this.rate === Number(opt) ? { radius: 3, color: 'rgba(74,52,40,0.10)', offsetY: 1 } : { radius: 0, color: Color.Transparent })
        .onClick(() => { this.rate = Number(opt); })
      }, (opt: string) => opt)
    }
    .padding(3).borderRadius(13).backgroundColor(this.p().segBg).width('100%')
  }

  @Builder
  sizeSeg() {
    Row() {
      ForEach(['normal', 'large', 'extra'], (opt: string, i: number) => {
        Column({ space: 1 }) {
          Text(['标准', '大字', '特大'][i])
            .fontSize(this.font(10))
            .fontWeight(this.textSize === opt ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.textSize === opt ? this.p().ink : this.p().segInk)
        }
        .layoutWeight(1).constraintSize({ minHeight: 44 }).padding(8).justifyContent(FlexAlign.Center).borderRadius(10)
        .backgroundColor(this.textSize === opt ? this.p().segActive : Color.Transparent)
        .shadow(this.textSize === opt ? { radius: 3, color: 'rgba(74,52,40,0.10)', offsetY: 1 } : { radius: 0, color: Color.Transparent })
        .onClick(() => { this.textSize = opt; })
      }, (opt: string) => opt)
    }
    .padding(3).borderRadius(13).backgroundColor(this.p().segBg).width('100%')
  }

  private iconBackground(kind: string): string {
    if (kind === 'b') return this.p().iconB;
    if (kind === 'c') return this.p().iconC;
    return this.p().iconA;
  }

  @Builder
  row(icon: string, kind: string, title: string, sub: string, action: string, tap: () => void) {
    Row({ space: 10 }) {
      if (icon === 'brand') {
        Image($r('app.media.brand_cloud')).width(34).height(34).objectFit(ImageFit.Contain).borderRadius(12)
      } else {
        Text(icon).fontSize(this.font(16)).fontColor(this.p().ink2).width(34).height(34).textAlign(TextAlign.Center).borderRadius(12)
          .backgroundColor(this.iconBackground(kind))
      }
      Column({ space: 2 }) {
        Text(title).fontSize(this.font(12)).fontColor(this.p().ink)
        Text(sub).fontSize(this.font(9)).fontColor(this.p().muted)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text(action).fontSize(this.font(11)).fontColor(this.p().accentText)
    }.width('100%').padding({ top: 10, bottom: 10 }).onClick(tap)
  }

  build() {
    Stack() {
      Image($r('app.media.settings_bg')).width('100%').height('100%').objectFit(ImageFit.Cover)
      if (this.darkMode) {
        Column().width('100%').height('100%').backgroundColor('#151311').opacity(0.88)
      }
      Column() {
      Row() {
        Text('‹').accessibilityText('返回').fontSize(26).fontColor(this.p().ink).width(32).textAlign(TextAlign.Center)
          .onClick(() => { if (Number(router.getLength()) > 1) router.back(); else router.replaceUrl({ url: 'pages/Home' }); })
        Text('设置').fontSize(this.font(18)).fontWeight(FontWeight.Medium).fontColor(this.p().ink).layoutWeight(1).textAlign(TextAlign.Center)
        Text('').width(44)
      }
      .width('100%').height(52).padding({ left: 10, right: 18 })

      Scroll() {
        Column({ space: 2 }) {
          this.section('个人资料')
          Column() {
            Row({ space: 12 }) {
              if (this.avatarPm !== undefined) {
                Image(this.avatarPm)
                  .width(52).height(52).borderRadius(26).objectFit(ImageFit.Cover)
                  .border({ width: 1, color: this.p().border })
                  .accessibilityText('当前头像')
              } else {
                Text('✿').fontSize(22).fontColor(this.p().ink2).width(52).height(52)
                  .textAlign(TextAlign.Center).borderRadius(26).backgroundColor(this.p().iconC)
              }
              Column({ space: 2 }) {
                Text('头像').fontSize(this.font(12)).fontColor(this.p().ink)
                Text('从手机图库选择一张照片').fontSize(this.font(9)).fontColor(this.p().muted)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Text('更换').fontSize(this.font(11)).fontColor(this.p().accentText)
            }
            .width('100%').padding({ top: 10, bottom: 10 })
            .onClick(() => { this.changeAvatar(); })
          }
          .padding({ left: 12, right: 12 }).borderRadius(18)
          .backgroundColor(this.p().surface).border({ width: 1, color: this.p().border })

          this.section('运行配置')
          Column() {
            this.row('☁', 'a', '后端服务', 'http://127.0.0.1:8010/api/v1', '已连接', () => {})
            Divider().color(this.p().divider)
            this.row('◍', 'b', '当前账号', this.accountName + ' · ' + this.orgLabel(), '', () => {})
          }.padding({ left: 12, right: 12 }).borderRadius(18)
          .backgroundColor(this.p().surface).border({ width: 1, color: this.p().border })

          this.section('外观')
          Column() {
            Column({ space: 8 }) {
              Row({ space: 10 }) {
                Text('◐').fontSize(this.font(16)).fontColor(this.p().ink2).width(34).height(34).textAlign(TextAlign.Center).borderRadius(12).backgroundColor(this.p().iconC)
                Column({ space: 2 }) {
                  Text('深色模式').fontSize(this.font(12)).fontColor(this.p().ink)
                  Text(this.themeMode === 'auto'
                    ? (this.darkMode ? '跟随系统 · 当前系统为深色' : '跟随系统 · 当前系统为浅色')
                    : (this.themeMode === 'dark' ? '始终深色 · 操作类页面使用深色背景' : '始终浅色 · 保持暖色纸张风格'))
                    .fontSize(this.font(9)).fontColor(this.p().muted)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              }.width('100%').padding({ top: 10, bottom: 4 })
              this.themeSeg()
            }.width('100%').padding({ bottom: 10 })
            Divider().color(this.p().divider)
            Column({ space: 7 }) {
              Row() {
              Text('主要工作页面字号').fontSize(this.font(12)).fontColor(this.p().ink)
                Blank()
                Text(this.textSize === 'large' ? '大字' : (this.textSize === 'extra' ? '特大' : '标准')).fontSize(this.font(10)).fontColor(this.p().accentText)
              }.width('100%')
              this.sizeSeg()
            }.width('100%').padding({ top: 10, bottom: 10 })
            Divider().color(this.p().divider)
            Row() {
              Column({ space: 2 }) {
                Text('减少动态效果').fontSize(this.font(12)).fontColor(this.p().ink)
                Text('关闭首页轮播自动播放').fontSize(this.font(9)).fontColor(this.p().muted)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.reduceMotion }).selectedColor(this.p().accent)
                .onChange((on: boolean) => { this.reduceMotion = on; })
            }.width('100%').padding({ top: 10, bottom: 10 })
          }.padding({ left: 12, right: 12 }).borderRadius(18)
          .backgroundColor(this.p().surface).border({ width: 1, color: this.p().border })

          this.section('提醒')
          Column() {
            this.row('✦', 'c', '发送测试通知', '验证系统通知通道是否可用', '发送', () => this.testNotification())
            Divider().color(this.p().divider)
            Column({ space: 2 }) {
              Text('到期提醒').fontSize(this.font(12)).fontColor(this.p().ink)
              Text('首页检测到到期回访或重点关怀时，按自然日推送一次系统通知。').fontSize(this.font(9)).fontColor(this.p().muted).lineHeight(this.line(16))
            }.alignItems(HorizontalAlign.Start).width('100%').padding({ top: 10, bottom: 10 })
          }.padding({ left: 12, right: 12 }).borderRadius(18)
          .backgroundColor(this.p().surface).border({ width: 1, color: this.p().border })

          this.section('使用设置')
          Column() {
            this.row('▦', 'a', '本机参考日期', this.followupDate + ' ' + this.weekday() + ' · 正式回访日期在人员档案安排', '›', () => this.pickDate())
            Divider().color(this.p().divider)
            Row({ space: 10 }) {
              Text('◌').fontSize(this.font(16)).fontColor(this.p().ink2).width(34).height(34).textAlign(TextAlign.Center).borderRadius(12).backgroundColor(this.p().iconA)
              Column({ space: 2 }) {
                Text('语音输入').fontSize(this.font(12)).fontColor(this.p().ink)
                Text('常见方言 · 云端识别授权').fontSize(this.font(9)).fontColor(this.p().muted)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Text(this.showDialects ? '⌃' : '›').fontSize(this.font(16)).fontColor(this.p().chevron)
            }.width('100%').padding({ top: 10, bottom: 10 }).onClick(() => { this.showDialects = !this.showDialects; })
            if (this.showDialects) {
              Column({ space: 8 }) {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(DIALECTS, (d: string) => {
                    Text(d).fontSize(this.font(9)).fontColor(this.dialect === d ? '#FFFFFF' : this.p().chipInk)
                      .backgroundColor(this.dialect === d ? this.p().accent : this.p().chipBg).borderRadius(10)
                      .padding({ left: 9, right: 9, top: 5, bottom: 5 }).margin({ right: 6, bottom: 6 })
                      .onClick(() => { this.dialect = d; })
                  }, (d: string) => d)
                }.width('100%')
                Row() {
                  Column({ space: 2 }) {
                    Text('允许本次登录使用云端语音识别').fontSize(this.font(10)).fontColor(this.p().ink)
                    Text('音频发送至讯飞识别，默认不保存原始录音').fontSize(this.font(8)).fontColor(this.p().muted)
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.consent }).selectedColor(this.p().accent)
                    .onChange((on: boolean) => { this.consent = on; })
                }.width('100%')
              }.width('100%').padding({ bottom: 10 })
            }
            Divider().color(this.p().divider)
            Column({ space: 7 }) {
              Row() {
                Text('题目播报倍速').fontSize(this.font(12)).fontColor(this.p().ink)
                Blank()
                Text(`${this.rate}×`).fontSize(this.font(10)).fontColor(this.p().accentText)
              }.width('100%')
              this.rateSeg()
            }.width('100%').padding({ top: 10, bottom: 10 })
          }.padding({ left: 12, right: 12 }).borderRadius(18)
          .backgroundColor(this.p().surface).border({ width: 1, color: this.p().border })

          this.section('安全与数据')
          Column() {
            this.row('⏻', 'a', '退出登录', '清除本机保存的加密会话', '退出', () => this.confirmLogout())
            Divider().color(this.p().divider)
            this.row('⌫', 'a', '清除本地备忘录', '只影响本机，不影响服务端数据', '清除', () => this.confirmClearMemos())
            Divider().color(this.p().divider)
            Column({ space: 2 }) {
              Text('会话存储').fontSize(this.font(12)).fontColor(this.p().ink)
              Text('登录会话以 HUKS 密钥加密后写入本机 Preferences，退出登录即删除。').fontSize(this.font(9)).fontColor(this.p().muted).lineHeight(this.line(16))
            }.alignItems(HorizontalAlign.Start).width('100%').padding({ top: 10, bottom: 10 })
          }.padding({ left: 12, right: 12 }).borderRadius(18)
          .backgroundColor(this.p().surface).border({ width: 1, color: this.p().border })

          this.section('关于')
          Column() {
            this.row('brand', 'c', '暖邻 · 鸿蒙手机端', 'v1.0.0 · API 22 · DevEco 6.0.2', '', () => {})
            Divider().color(this.p().divider)
            this.row('◈', 'c', '运行诊断', this.runtimeLabel(), '', () => {})
            Divider().color(this.p().divider)
            this.row('▤', 'c', '服务卡片', '桌面长按暖邻图标 → 卡片 → 添加「暖邻提醒」', '', () => {})
            Divider().color(this.p().divider)
            Column({ space: 2 }) {
              Text('数据说明').fontSize(this.font(12)).fontColor(this.p().ink)
              Text('当前为本地开发环境（127.0.0.1），仅使用虚构演示数据；正式使用需配置 HTTPS 与签名包。').fontSize(this.font(9)).fontColor(this.p().muted).lineHeight(this.line(16))
            }.alignItems(HorizontalAlign.Start).width('100%').padding({ top: 10, bottom: 10 })
          }.padding({ left: 12, right: 12 }).borderRadius(18)
          .backgroundColor(this.p().surface).border({ width: 1, color: this.p().border })

          Text('设置保存在本机；识别文字先进入回答框，核对后再提交。')
            .fontSize(this.font(9)).fontColor(this.p().muted).lineHeight(this.line(17)).width('100%').padding(12).margin({ top: 10 })
            .borderRadius(14).backgroundColor(this.p().surfaceSoft).border({ width: 1, color: this.p().noteBorder, style: BorderStyle.Dashed })

          Button(this.saving ? '正在保存…' : '✓ 保存设置').enabled(!this.saving)
            .width('100%').height(46).fontSize(this.font(13)).fontColor('#FFFFFF')
            .backgroundColor(this.p().accent).borderRadius(23).margin({ top: 8 }).onClick(() => this.save())
        }
        .width('100%').constraintSize({ minHeight: '100%' }).padding({ left: 20, right: 20, top: 6, bottom: 24 })
      }
      .layoutWeight(1).scrollBar(BarState.Off)
      }
      .width('100%').height('100%')

      if (this.cropVisible) {
        Column() {
          Column({ space: 12 }) {
            Text('调整头像').fontSize(this.font(15)).fontColor(this.p().ink)
            Stack() {
              Image(this.cropImage)
                .width('100%').height('100%')
                .objectFit(ImageFit.Cover)
                .scale({ x: this.cropScale, y: this.cropScale })
                .offset({ x: this.cropDx, y: this.cropDy })
            }
            .width(this.cropView).height(this.cropView)
            .clip(true).borderRadius(18).backgroundColor('#000000')
            .gesture(
              GestureGroup(GestureMode.Parallel,
                PinchGesture()
                  .onActionStart(() => { this.cropStartScale = this.cropScale; })
                  .onActionUpdate((event: GestureEvent) => {
                    this.cropScale = clampAvatarScale(this.cropStartScale * event.scale);
                    this.clampCropOffset();
                  }),
                PanGesture()
                  .onActionStart(() => {
                    this.cropStartDx = this.cropDx;
                    this.cropStartDy = this.cropDy;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    this.cropDx = this.cropStartDx + event.offsetX;
                    this.cropDy = this.cropStartDy + event.offsetY;
                    this.clampCropOffset();
                  })
              )
            )
            Row({ space: 12 }) {
              Button('－').width(46).height(32).fontSize(14).borderRadius(16)
                .backgroundColor(this.p().surfaceSoft).fontColor(this.p().ink)
                .onClick(() => {
                  this.cropScale = clampAvatarScale(this.cropScale - 0.2);
                  this.clampCropOffset();
                })
              Text('双指缩放，拖动调整取景').fontSize(this.font(9)).fontColor(this.p().muted)
              Button('＋').width(46).height(32).fontSize(14).borderRadius(16)
                .backgroundColor(this.p().surfaceSoft).fontColor(this.p().ink)
                .onClick(() => {
                  this.cropScale = clampAvatarScale(this.cropScale + 0.2);
                  this.clampCropOffset();
                })
            }.width('100%').justifyContent(FlexAlign.Center)
            Row({ space: 10 }) {
              Button('取消').layoutWeight(1).height(42).fontSize(this.font(12))
                .backgroundColor(this.p().surfaceSoft).fontColor(this.p().ink)
                .onClick(() => this.cancelCrop())
              Button('使用').layoutWeight(1).height(42).fontSize(this.font(12))
                .backgroundColor(this.p().accent).fontColor('#FFFFFF')
                .onClick(() => { this.applyCrop(); })
            }.width('100%')
          }
          .width(340).padding(18).borderRadius(24)
          .backgroundColor(this.p().surface).border({ width: 1, color: this.p().border })
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(0,0,0,0.55)').zIndex(60)
      }
    }
    .width('100%').height('100%')
    .backgroundColor(this.p().pageBg)
  }
}
