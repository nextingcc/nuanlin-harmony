import { readableFont, readableLineHeight } from '../model/UserPreferences';
import { router } from '@kit.ArkUI';
import { Theme, Palette, palette } from '../model/Theme';
import { Api, FollowupHistoryRecord } from '../model/Api';

@Entry
@Component
struct FollowupList {
  @StorageProp('darkMode') darkMode: boolean = false;
  @StorageProp('textSize') preferenceTextSize: string = 'normal';

  private p(): Palette { return palette(this.darkMode); }

  private font(base: number): number { return readableFont(base, this.preferenceTextSize); }
  private line(base: number): number { return readableLineHeight(base, this.preferenceTextSize); }

  @State records: FollowupHistoryRecord[] = [];
  @State names: Record<string, string> = {};
  @State loading: boolean = false;
  @State message: string = '';
  @State nextCursor: string = '';
  @State loaded: boolean = false;
  @State opening: boolean = false;
  private retryMore: boolean = false;

  onPageShow(): void {
    this.load(false);
  }

  private async load(more: boolean): Promise<void> {
    if (this.loading) return;
    this.retryMore = more;
    this.loading = true;
    this.message = '';
    try {
      const page = await Api.followupHistory(more ? this.nextCursor : '');
      const rows = more ? this.records.slice() : [];
      for (const item of page.items) {
        if (!rows.some((row: FollowupHistoryRecord) => row.id === item.id)) rows.push(item);
      }
      this.records = rows;
      this.nextCursor = page.nextCursor ?? '';
      this.loaded = true;
      // 姓名读取失败不影响已保存记录的查看，不使用示例姓名补位。
      const names: Record<string, string> = more ? this.names : {};
      for (const item of page.items) {
        if (names[item.personId]) continue;
        try {
          const person = await Api.person(item.personId);
          if (person) names[item.personId] = person.name;
        } catch (ignored) {}
      }
      this.names = names;
    } catch (e) {
      this.message = '读取失败，请检查网络与登录状态后重试。';
    } finally {
      this.loading = false;
    }
  }

  private async openPerson(personId: string): Promise<void> {
    if (this.opening) return;
    this.opening = true;
    try {
      const person = await Api.person(personId);
      if (!person) throw new Error('person unavailable');
      AppStorage.setOrCreate('selectedPerson', JSON.stringify(person));
      router.pushUrl({ url: 'pages/Profile' });
    } catch (e) {
      this.message = '暂时无法打开该档案，请重试。';
    } finally {
      this.opening = false;
    }
  }

  private outcomeText(value: string): string {
    if (value === 'completed') return '已完成';
    if (value === 'unanswered') return '未接通';
    if (value === 'declined') return '已婉拒';
    if (value === 'ongoing') return '持续跟进';
    return '状态待核实';
  }

  build() {
    Column() {
      Row() {
        Button('返回').fontSize(this.font(16)).constraintSize({ minHeight: 44 }).onClick(() => router.replaceUrl({ url: 'pages/Followup' }))
        Text('回访记录').fontSize(this.font(20)).fontColor(this.p().ink).layoutWeight(1).textAlign(TextAlign.Center)
        Button('刷新').fontSize(this.font(16)).constraintSize({ minHeight: 44 }).enabled(!this.loading).onClick(() => this.load(false))
      }
      .width('100%').padding(16)

      if (this.message.length > 0) {
        Text(this.message).fontSize(this.font(14)).fontColor((this.darkMode ? this.p().danger : '#9C4A45')).padding(12)
        Button('重试').fontSize(this.font(16)).constraintSize({ minHeight: 44 }).enabled(!this.loading).onClick(() => this.load(this.retryMore))
      }
      List({ space: 12 }) {
        ForEach(this.records, (item: FollowupHistoryRecord) => {
          ListItem() {
            Column({ space: 8 }) {
              Text(this.names[item.personId] ?? ('档案 ' + item.personId))
                .fontSize(this.font(17)).fontWeight(FontWeight.Medium).fontColor(this.p().ink)
              Text(item.date + ' · ' + item.method + ' · ' + this.outcomeText(item.outcome))
                .fontSize(this.font(14)).fontColor(this.p().ink2)
              Text(item.notes || '未填写备注').fontSize(this.font(16)).lineHeight(this.line(24)).fontColor(this.p().ink)
              Button('查看人员档案').fontSize(this.font(16)).constraintSize({ minHeight: 44 }).enabled(!this.opening).onClick(() => this.openPerson(item.personId))
            }
            .alignItems(HorizontalAlign.Start).width('100%').padding(16)
            .borderRadius(16).backgroundColor((this.darkMode ? this.p().surface : '#FFFCF7'))
          }
        }, (item: FollowupHistoryRecord) => item.id)
        ListItem() {
          Column({ space: 10 }) {
            if (this.loading) {
              Text('正在读取…').fontSize(this.font(16)).fontColor(this.p().muted).padding(16)
            } else if (this.loaded && this.records.length === 0 && this.message.length === 0) {
              Text('暂无回访记录').fontSize(this.font(16)).fontColor(this.p().muted).padding(24)
            } else if (this.nextCursor.length > 0) {
              Button('加载更多').fontSize(this.font(16)).constraintSize({ minHeight: 44 }).onClick(() => this.load(true))
            }
          }.width('100%')
        }
      }
      .width('100%').layoutWeight(1).padding({ left: 16, right: 16, bottom: 16 })
    }
    .width('100%').height('100%').backgroundColor((this.darkMode ? this.p().pageBg : '#F8F5EE'))
  }
}
