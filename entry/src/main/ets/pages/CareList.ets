import { readableFont, readableLineHeight } from '../model/UserPreferences';
﻿import { router, promptAction } from '@kit.ArkUI';
import { Theme, Palette, palette } from '../model/Theme';
import { Api } from '../model/Api';

interface CarePerson {
  name: string;
  age: number;
  gender: string;
  community: string;
}

interface CareItem {
  id: string;
  revision: number;
  state: string;
  openedAt: string;
  attendance: string;
  person: CarePerson;
}

@Entry
@Component
struct CareList {
  @StorageProp('textSize') preferenceTextSize: string = 'normal';
  @StorageProp('darkMode') darkMode: boolean = false;

  private p(): Palette { return palette(this.darkMode); }

  private font(base: number): number { return readableFont(base, this.preferenceTextSize); }
  private line(base: number): number { return readableLineHeight(base, this.preferenceTextSize); }

  @State items: CareItem[] = [];
  @State loading: boolean = true;
  @State message: string = '';

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.message = '';
    const data = await Api.careCases();
    const list: CareItem[] = [];
    if (data !== null) {
      const page = data as Record<string, Object>;
      const rows = page['items'] as Object[];
      if (rows !== null && rows !== undefined) {
        for (let i = 0; i < rows.length; i++) {
          list.push(rows[i] as CareItem);
        }
      }
    } else {
      this.message = '读取失败，请确认后端与登录状态';
    }
    this.items = list;
    this.loading = false;
  }

  private closeCase(item: CareItem): void {
    AlertDialog.show({
      title: '结案确认',
      message: `确认关闭 ${item.person.name} 的重点关怀案件？`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '确认结案',
        action: async () => {
          const ok = await Api.closeCare(item.id, item.revision, '工作人员核实后结案');
          if (ok) {
            promptAction.showToast({ message: '已结案', duration: 1500 });
            await this.load();
          } else {
            this.message = '结案失败，请重试';
          }
        }
      }
    });
  }

  private dateText(iso: string): string {
    return iso !== undefined && iso.length >= 10 ? iso.slice(0, 10) : '—';
  }

  @Builder
  careCard(item: CareItem) {
    Column({ space: 9 }) {
      Row() {
        Column({ space: 2 }) {
          Text(item.person.name)
            .fontSize(this.font(15))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.p().ink)
          Text(`${item.person.age} 岁 · ${item.person.gender} · ${item.person.community}`)
            .fontSize(this.font(9))
            .fontColor(this.p().muted)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('重点关怀')
          .fontSize(this.font(9))
          .fontColor((this.darkMode ? this.p().danger : '#9C4A45'))
          .backgroundColor((this.darkMode ? this.p().dangerBg : '#F7E4E1'))
          .borderRadius(9)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      }
      .width('100%')

      Row({ space: 6 }) {
        Text(`开案 ${this.dateText(item.openedAt)}`)
          .fontSize(this.font(9))
          .fontColor((this.darkMode ? this.p().segInk : '#8A6B54'))
        Blank()
        Text(`出勤：${item.attendance === 'yes' ? '在访' : (item.attendance === 'no' ? '未访' : '待核实')}`)
          .fontSize(this.font(9))
          .fontColor(item.attendance === 'no' ? (this.darkMode ? this.p().danger : '#9C4A45') : this.p().muted)
      }
      .width('100%')

      Row() {
        Text('出勤状态由现场核实，当前接口仅支持读取')
          .fontSize(this.font(8))
          .fontColor(this.p().muted)
          .layoutWeight(1)
        Text('结案')
          .fontSize(this.font(10))
          .fontColor((this.darkMode ? this.p().danger : '#9C4A45'))
          .border({ width: 1, color: (this.darkMode ? this.p().border : '#E2B8B2') })
          .borderRadius(14)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .onClick(() => this.closeCase(item))
      }
      .width('100%')
    }
    .padding(14)
    .borderRadius(16)
    .backgroundColor((this.darkMode ? this.p().surface : '#FFFCF7'))
    .border({ width: 1, color: (this.darkMode ? this.p().border : '#EFD9CF') })
  }

  build() {
    Stack() {
      Image($r('app.media.followup_paper_bg'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .opacity(this.darkMode ? 0.16 : 1)
      if (this.darkMode) {
        Column().width('100%').height('100%').backgroundColor('#151311').opacity(0.86)
      }
      Column() {
      Row() {
        Text('‹').accessibilityText('返回')
          .fontSize(26)
          .fontColor(this.p().ink)
          .width(32)
          .textAlign(TextAlign.Center)
          .onClick(() => router.replaceUrl({ url: 'pages/Followup' }))
        Text('重点关怀')
          .fontSize(this.font(18))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.p().ink)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('刷新')
          .fontSize(this.font(12))
          .fontColor((this.darkMode ? this.p().segInk : '#8A6B54'))
          .width(44)
          .textAlign(TextAlign.End)
          .onClick(() => this.load())
      }
      .width('100%')
      .height(52)
      .padding({ left: 10, right: 18 })

      Text(`开案 ${this.items.length} 件`)
        .fontSize(this.font(10))
        .fontColor(this.p().muted)
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 8 })

      if (this.message.length > 0) {
        Text(this.message).fontSize(this.font(9)).fontColor((this.darkMode ? this.p().danger : '#9C4A45')).padding({ left: 20, right: 20, bottom: 6 })
      }

      Scroll() {
        Column({ space: 10 }) {
          if (this.loading) {
            Text('正在读取…').fontSize(this.font(11)).fontColor(this.p().muted).padding(20)
          } else if (this.items.length === 0) {
            Column({ space: 6 }) {
              Text('暂无开放的重点关怀案件')
                .fontSize(this.font(13))
                .fontColor(this.p().ink)
              Text('高风险评估归档后会自动开案。')
                .fontSize(this.font(9))
                .fontColor(this.p().muted)
            }
            .padding(24)
            .width('100%')
            .borderRadius(16)
            .backgroundColor((this.darkMode ? this.p().surface : '#FFFCF7'))
            .border({ width: 1, color: (this.darkMode ? this.p().border : '#EFD9CF') })
          } else {
            ForEach(this.items, (item: CareItem) => {
              this.careCard(item)
            }, (item: CareItem) => item.id)
          }
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .padding({ left: 20, right: 20, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.darkMode ? this.p().pageBg : '#F8E8E2')
  }
}


