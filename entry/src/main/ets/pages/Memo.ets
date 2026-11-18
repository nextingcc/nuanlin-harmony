import { router, promptAction } from '@kit.ArkUI';
import { isMemoOverdue, memoDate, memoMinute, MemoItem, readMemoItems, watchMemoMinute } from '../model/MemoReminders';
import { Palette, palette } from '../model/Theme';
import { saveAssistantMemoItems } from '../model/AssistantMemoStore';

@Entry
@Component
struct Memo {
  @State items: MemoItem[] = [];
  @State draft: string = '';
  @State original: string = '';
  @State pickDate: string = '';
  @State pickTime: string = '09:00';
  @State now: string = memoMinute(new Date());
  @State saving: boolean = false;
  @StorageProp('darkMode') darkMode: boolean = false;
  private stopClock: (() => void) | undefined;

  private p(): Palette {
    return palette(this.darkMode);
  }

  private soft(): string {
    return this.darkMode ? '#2A2420' : '#FBF4EA';
  }

  private warnBg(): string {
    return this.darkMode ? '#3A2A28' : '#FBEDE8';
  }

  private warnInk(): string {
    return this.darkMode ? '#E3B0AA' : '#8A4A4A';
  }

  aboutToAppear(): void {
    PersistentStorage.persistProp('memoOriginal', '');
    this.items = readMemoItems().sort((a, b) => (a.dueAt ?? '').localeCompare(b.dueAt ?? ''));
    this.original = AppStorage.get<string>('memoOriginal') ?? '';
    this.pickDate = memoDate(new Date());
  }

  onPageShow(): void {
    this.items = readMemoItems().sort((a, b) => (a.dueAt ?? '').localeCompare(b.dueAt ?? ''));
    this.now = memoMinute(new Date());
    this.stopClock?.();
    this.stopClock = watchMemoMinute(now => {
      const newlyOverdue = this.items.filter(item => isMemoOverdue(item, now) && !isMemoOverdue(item, this.now));
      this.now = now;
      if (newlyOverdue.length > 0) {
        promptAction.showToast({ message: `${newlyOverdue.length} 项备忘录已超时`, duration: 2500 });
      }
    });
  }

  onPageHide(): void {
    this.stopClock?.();
  }

  private pad(n: number): string {
    return n.toString().padStart(2, '0');
  }

  private async persist(items: MemoItem[]): Promise<boolean> {
    if (this.saving) return false;
    this.saving = true;
    try {
      await saveAssistantMemoItems(items);
      this.items = readMemoItems().sort((a, b) => (a.dueAt ?? '').localeCompare(b.dueAt ?? ''));
      return true;
    } catch (e) {
      this.items = readMemoItems().slice();
      promptAction.showToast({ message: '未能保存备忘录，原内容已保留，请重试。', duration: 2500 });
      return false;
    } finally { this.saving = false; }
  }

  private pickupDate(): void {
    const parts = this.pickDate.split('-');
    const selected = parts.length === 3 ? new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])) : new Date();
    DatePickerDialog.show({
      start: new Date(2020, 0, 1),
      end: new Date(2035, 11, 31),
      selected: selected,
      onDateAccept: (value: Date) => { this.pickDate = memoDate(value); }
    });
  }

  private pickupTime(): void {
    TimePickerDialog.show({
      selected: new Date(),
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        this.pickTime = this.pad(value.hour) + ':' + this.pad(value.minute);
      }
    });
  }

  private async add(): Promise<boolean> {
    if (this.saving) return false;
    const text = this.draft.trim();
    if (text.length === 0) {
      promptAction.showToast({ message: '先写一条事项', duration: 1500 });
      return false;
    }
    const due = this.pickDate.length > 0 ? this.pickDate + ' ' + this.pickTime : memoMinute(new Date());
    const item: MemoItem = {
      id: 'm-' + Date.now().toString() + '-' + Math.floor(Math.random() * 1000).toString(),
      text: text,
      done: false,
      dueAt: due
    };
    if (!await this.persist([...readMemoItems(), item])) return false;
    if (this.original.length === 0) this.original = text;
    this.draft = '';
    AppStorage.setOrCreate('memoOriginal', this.original);
    return true;
  }

  private async setDone(id: string, done: boolean): Promise<void> {
    const current = readMemoItems();
    const item = current.find(value => value.id === id);
    if (item === undefined || item.done === done) return;
    const items = current.map((value): MemoItem => value.id === id ? {
      id: value.id, text: value.text, dueAt: value.dueAt, done: done
    } : value);
    await this.persist(items);
  }

  private async remove(id: string): Promise<void> {
    await this.persist(readMemoItems().filter((x: MemoItem) => x.id !== id));
  }

  private incompleteCount(): number {
    let n = 0;
    for (let i = 0; i < this.items.length; i++) {
      if (!this.items[i].done) n++;
    }
    return n;
  }

  private overdueCount(): number {
    return this.items.filter(item => isMemoOverdue(item, this.now)).length;
  }

  private async save(): Promise<void> {
    if (this.saving) return;
    const saved = this.draft.trim().length > 0 ? await this.add() : await this.persist(readMemoItems());
    if (saved) promptAction.showToast({ message: '已保存', duration: 1200 });
  }

  build() {
    Column() {
      Row() {
        Text('‹').accessibilityText('返回').fontSize(26).fontColor(this.p().ink).width(32).textAlign(TextAlign.Center)
          .onClick(() => router.back())
        Text('备忘录').fontSize(18).fontColor(this.p().ink).layoutWeight(1).textAlign(TextAlign.Center)
        Text('').width(40)
      }
      .width('100%')
      .height(50)

      Scroll() {
        Column({ space: 12 }) {
          if (this.incompleteCount() > 0) {
            Row({ space: 8 }) {
              Text('!')
                .fontSize(11)
                .fontColor('#FFFFFF')
                .width(20)
                .height(20)
                .textAlign(TextAlign.Center)
                .borderRadius(10)
                .backgroundColor(this.overdueCount() > 0 ? '#B45A5A' : '#C2778A')
              Text(this.overdueCount() > 0
                ? `还有 ${this.incompleteCount()} 项未完成，其中 ${this.overdueCount()} 项已超时`
                : `还有 ${this.incompleteCount()} 项未完成，记得处理`)
                .fontSize(9)
                .fontColor(this.warnInk())
                .layoutWeight(1)
              Text('按时间排序').fontSize(7).fontColor(this.p().muted)
            }
            .width('100%')
            .padding({ left: 11, right: 11, top: 9, bottom: 9 })
            .borderRadius(12)
            .backgroundColor(this.warnBg())
            .border({ width: 1, color: this.darkMode ? '#5A3A36' : '#EFD2CB' })
          }

          Column() {
            Row() {
              Text('事项').fontSize(9).fontColor(this.p().segInk).layoutWeight(1)
              Text('时间').fontSize(9).fontColor(this.p().segInk).width(88)
              Text('完成').fontSize(9).fontColor(this.p().segInk).width(34).textAlign(TextAlign.Center)
              Text('').width(22)
            }
            .width('100%')
            .padding({ left: 10, right: 4, top: 8, bottom: 8 })
            Divider().color(this.p().divider)
            ForEach(this.items, (item: MemoItem) => {
              Row({ space: 7 }) {
                Text('♥').fontSize(8).fontColor(item.done ? this.p().muted : '#C2778A')
                Column({ space: 2 }) {
                  Text(item.text)
                    .fontSize(11)
                    .fontColor(item.done ? this.p().muted : this.p().ink)
                    .decoration({ type: item.done ? TextDecorationType.LineThrough : TextDecorationType.None })
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.dueAt ?? '')
                    .fontSize(7)
                    .fontColor(isMemoOverdue(item, this.now) ? this.p().danger : this.p().muted)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                if (isMemoOverdue(item, this.now)) {
                  Text('超时').fontSize(7).fontColor(this.p().danger).backgroundColor(this.warnBg()).borderRadius(7)
                    .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                }
                Checkbox({ name: item.id, group: 'memo' })
                  .select(item.done)
                  .enabled(!this.saving)
                  .selectedColor(this.p().accent)
                  .width(24)
                  .height(24)
                  .onChange((v: boolean) => this.setDone(item.id, v))
                Text('×').accessibilityText('删除')
                  .fontSize(12)
                  .fontColor(this.p().chevron)
                  .width(20)
                  .textAlign(TextAlign.Center)
                  .onClick(() => this.remove(item.id))
              }
              .width('100%')
              .padding({ left: 10, right: 2, top: 11, bottom: 11 })
              Divider().color(this.p().divider)
            }, (item: MemoItem) => `${item.id}:${item.done}`)
            if (this.items.length === 0) {
              Text('还没有记录，写下今天要做的事。')
                .fontSize(10)
                .fontColor(this.p().muted)
                .width('100%')
                .padding({ top: 24, bottom: 24 })
                .textAlign(TextAlign.Center)
            }
          }
          .width('100%')
          .padding(10)
          .borderRadius(18)
          .backgroundColor(this.p().surface)
          .border({ width: 1, color: this.p().border, style: BorderStyle.Solid })
          .shadow({ radius: 10, color: 'rgba(120,72,60,0.07)', offsetY: 4 })

          if (this.original.length > 0) {
            Column({ space: 4 }) {
              Text('原始记录').fontSize(9).fontColor(this.p().segInk)
              Text(this.original).fontSize(10).fontColor(this.p().segInk).lineHeight(18)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .borderRadius(14)
            .backgroundColor(this.soft())
          }

          Row({ space: 8 }) {
            Row({ space: 5 }) {
              Text('▦').fontSize(11).fontColor(this.p().segInk)
              Text(this.pickDate).fontSize(9).fontColor(this.p().segInk)
            }
            .padding({ left: 10, right: 10, top: 7, bottom: 7 })
            .borderRadius(10)
            .backgroundColor(this.soft())
            .onClick(() => this.pickupDate())
            Row({ space: 5 }) {
              Text('◷').fontSize(11).fontColor(this.p().segInk)
              Text(this.pickTime).fontSize(9).fontColor(this.p().segInk)
            }
            .padding({ left: 10, right: 10, top: 7, bottom: 7 })
            .borderRadius(10)
            .backgroundColor(this.soft())
            .onClick(() => this.pickupTime())
            Blank()
            Text('选择日期时间').fontSize(7).fontColor(this.p().muted)
          }
          .width('100%')

          Row({ space: 10 }) {
            Button('加入清单')
              .layoutWeight(1)
              .height(42)
              .fontSize(12)
              .fontColor(this.p().accentText)
              .backgroundColor(this.darkMode ? '#2A2E24' : '#EDF2E2')
              .borderRadius(21)
              .onClick(() => this.add())
            Button('保存')
              .layoutWeight(1)
              .height(42)
              .fontSize(12)
              .fontColor('#FFFFFF')
              .backgroundColor(this.p().accent)
              .borderRadius(21)
              .onClick(() => this.save())
          }
          .width('100%')

          TextArea({ placeholder: '记录备注或补充…', text: this.draft })
            .width('100%')
            .height(72)
            .fontSize(12)
            .fontColor(this.p().ink)
            .placeholderColor(this.darkMode ? this.p().segSub : '#B8A797')
            .backgroundColor(this.p().surface)
            .borderRadius(12)
            .border({ width: 1, color: this.p().border })
            .padding(10)
            .onChange((v: string) => { this.draft = v; })

          Text('点击圆圈标记完成。到期未完成的事项会出现在首页通知中。')
            .fontSize(8)
            .fontColor(this.p().muted)
            .lineHeight(15)
            .width('100%')
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
    .backgroundColor(this.p().pageBg)
  }
}
