import { router, promptAction } from '@kit.ArkUI';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { VoiceRecorder } from '../model/Voice';
import { Api, JournalAnalysis, JournalEntry, JournalSuggestion } from '../model/Api';
import { MemoItem, readMemoItems } from '../model/MemoReminders';
import { suggestionMemoId, suggestionMemoText } from '../model/JournalMemo';
import { Palette, palette } from '../model/Theme';
import { saveAssistantMemoItems } from '../model/AssistantMemoStore';

const MOODS: string[] = ['激动', '尴尬', '热情', '幸福', '开心', '有趣', '伤心', '累', '害羞', '生气'];
const FACES: Resource[] = [$r('app.media.journal_mood_0'), $r('app.media.journal_mood_1'),
  $r('app.media.journal_mood_2'), $r('app.media.journal_mood_3'), $r('app.media.journal_mood_4'),
  $r('app.media.journal_mood_5'), $r('app.media.journal_mood_6'), $r('app.media.journal_mood_7'),
  $r('app.media.journal_mood_8'), $r('app.media.journal_mood_angry')];
const BACKGROUNDS: Resource[] = [$r('app.media.journal_bg_0'), $r('app.media.journal_bg_1'),
  $r('app.media.journal_bg_2'), $r('app.media.journal_bg_3')];
const NOTE_IMAGES: Resource[] = [$r('app.media.journal_suggest_1'), $r('app.media.journal_suggest_2'),
  $r('app.media.journal_suggest_3'), $r('app.media.journal_suggest_4'), $r('app.media.journal_suggest_5')];
const TABS: string[] = ['日记簿', '心情日历', '一周回顾'];
const DAYS: string[] = ['一', '二', '三', '四', '五', '六', '日'];
const POSITIONS: number[] = [0, 1, 2, 3, 4, 5, 6];
const WEEKS: number[] = [0, 1, 2, 3, 4, 5];
const BROWN: string = '#684938';
const GREEN: string = '#53663D';
const PAPER: string = '#FFFAEF';
const EDGE: string = '#B99A7E';


function shift(day: Date, offset: number): Date {
  return new Date(day.getFullYear(), day.getMonth(), day.getDate() + offset);
}
function dateKey(day: Date): string {
  return day.getFullYear().toString() + '-' + (day.getMonth() + 1).toString().padStart(2, '0') +
    '-' + day.getDate().toString().padStart(2, '0');
}
function weekStart(day: Date): Date {
  return shift(day, -((day.getDay() + 6) % 7));
}

@Entry
@Component
struct Journal {
  @StorageProp('darkMode') darkMode: boolean = false;

  private p(): Palette { return palette(this.darkMode); }
  private brown(): string { return this.darkMode ? this.p().ink : BROWN; }
  private paper(): string { return this.darkMode ? this.p().surface : PAPER; }
  private edge(): string { return this.darkMode ? this.p().border : EDGE; }
  private green(): string { return this.darkMode ? this.p().accent : GREEN; }
  @State tab: number = 0;
  @State noteOpen: boolean = false;
  @State noteLoading: boolean = false;
  @State noteError: string = '';
  @State noteIndex: number = 0;
  @State notes: JournalSuggestion[] = [];
  @State noteSaved: string[] = [];
  private noteWeek: string = '';
  @State selected: Date = new Date();
  @State month: Date = new Date();
  @State week: Date = weekStart(new Date());
  @State entries: JournalEntry[] = [];
  @State draft: string = '';
  @State savedDraft: string = '';
  @State sheet: boolean = false;
  @State mood: number = -1;
  @State comfort: number = -1;
  @State error: string = '';
  @State busy: boolean = false;
  @State loading: boolean = false;
  @State voice: string = '';
  @State wave: number[] = new Array<number>(24).fill(0);
  private recorder: VoiceRecorder = new VoiceRecorder();
  private voiceRun: number = 0;
  private voiceTimer: number = -1;
  private loadId: number = 0;
  private chart: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));

  aboutToAppear(): void {
    this.load();
  }

  aboutToDisappear(): void {
    this.closeVoice();
  }

  private closeVoice(): void {
    this.voiceRun++;
    clearTimeout(this.voiceTimer);
    this.recorder.cancel();
    this.voice = '';
  }

  private finishVoice(): void {
    clearTimeout(this.voiceTimer);
    this.voice = '正在转写…';
    this.recorder.finish();
  }

  private async startVoice(): Promise<void> {
    if (!(AppStorage.get<boolean>('voiceConsent') ?? false)) {
      AlertDialog.show({
        title: '云端语音识别',
        message: '录音会发送到语音服务转成文字。转写结果由你核对后保存。',
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: { value: '同意并录音', action: () => {
          AppStorage.setOrCreate('voiceConsent', true);
          this.startVoice();
        } }
      });
      return;
    }
    const run = ++this.voiceRun;
    this.error = '';
    this.wave = this.wave.map(() => 0);
    this.voice = '正在连接语音服务…';
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context,
        ['ohos.permission.MICROPHONE']);
      if (run !== this.voiceRun) return;
      if (permission.authResults[0] !== 0) {
        this.closeVoice();
        this.error = '请允许麦克风权限，或直接输入文字。';
        return;
      }
      const started = await this.recorder.startDictation(() => {}, (text: string) => {
        if (run !== this.voiceRun) return;
        this.closeVoice();
        if (text.trim()) {
          this.draft = (this.draft + (this.draft ? '\n' : '') + text.trim()).slice(0, 4000);
        } else {
          this.error = '没识别到文字，请重录或打字。';
        }
      }, (message: string) => {
        if (run !== this.voiceRun) return;
        this.closeVoice();
        this.error = message;
      }, (level: number) => {
        if (run === this.voiceRun) this.wave = [...this.wave.slice(1), level];
      });
      if (started && run === this.voiceRun) {
        this.voice = '停止录音';
        this.voiceTimer = setTimeout(() => this.finishVoice(), 60000);
      }
    } catch (e) {
      if (run !== this.voiceRun) return;
      this.closeVoice();
      this.error = '无法开启麦克风，请检查权限或打字。';
    }
  }

  private async load(): Promise<void> {
    const id = ++this.loadId;
    this.loading = true;
    this.error = '';
    this.entries = [];
    const tab = this.tab;
    const start = tab === 0 ? this.selected : tab === 1 ?
      new Date(this.month.getFullYear(), this.month.getMonth(), 1) : this.week;
    const end = tab === 0 ? start : tab === 1 ?
      new Date(start.getFullYear(), start.getMonth() + 1, 0) : shift(start, 6);
    try {
      const entries = await Api.journal(dateKey(start), dateKey(end));
      if (id !== this.loadId) return;
      this.entries = entries;
      if (tab === 0) {
        this.draft = entries[0]?.diary ?? '';
        this.savedDraft = this.draft;
      }
      if (tab === 2) this.drawChart();
    } catch (e) {
      if (id === this.loadId) this.error = (e as Error).message || '无法加载日志，请重试。';
    } finally {
      if (id === this.loadId) this.loading = false;
    }
  }

  private setTab(tab: number): void {
    if (this.busy || this.loading || this.tab === tab) return;
    if (this.tab === 0 && this.draft !== this.savedDraft) {
      this.continueAfterSaving(() => this.activateTab(tab));
      return;
    }
    this.activateTab(tab);
  }

  private activateTab(tab: number): void {
    this.closeVoice();
    if (tab === 2) this.week = weekStart(this.selected);
    this.tab = tab;
    this.load();
  }

  private continueAfterSaving(action: () => void): void {
    AlertDialog.show({
      title: '日记还没有保存',
      message: '先保存这篇日记，再继续查看，避免分析使用到旧内容。',
      primaryButton: { value: '继续编辑', action: () => {} },
      secondaryButton: { value: '保存并继续', action: async () => {
        await this.save(false);
        if (!this.error) action();
      } }
    });
  }

  private selectDiaryDate(day: Date): void {
    const open = (): void => {
      this.selected = day;
      this.draft = '';
      this.savedDraft = '';
      this.load();
    };
    if (this.draft !== this.savedDraft) this.continueAfterSaving(open);
    else open();
  }

  private moodAt(day: Date): number {
    return MOODS.indexOf(this.entries.find((entry: JournalEntry) => entry.date === dateKey(day))?.mood ?? '');
  }

  private calendarDay(index: number): Date {
    return shift(weekStart(new Date(this.month.getFullYear(), this.month.getMonth(), 1)), index);
  }

  private openMood(day: Date): void {
    if (this.loading || this.busy || this.error || dateKey(day) > dateKey(new Date())) return;
    this.selected = day;
    this.mood = this.moodAt(day);
    this.comfort = this.entries.find((entry: JournalEntry) => entry.date === dateKey(day))?.comfort ?? -1;
    this.sheet = true;
  }

  private encouragement(): string {
    if (this.mood === 9) return '生气也可以。先给自己一点时间，再想想自己想说什么。';
    if (this.mood === 1) return '偶尔有点尴尬也没关系，给自己一点时间。';
    if (this.mood === 6) return '难过的时候，可以先允许自己慢一点。';
    if (this.mood === 7) return '辛苦了，今天也可以给自己留一点休息时间。';
    if (this.mood === 8) return '按自己的节奏来，慢一点也很好。';
    return '把今天的小快乐记下来。';
  }

  private async save(mood: boolean): Promise<void> {
    if (this.busy || this.loading || (mood && this.mood < 0)) return;
    this.busy = true;
    this.error = '';
    try {
      await Api.saveJournal(dateKey(this.selected), mood ? null : this.draft, mood ? MOODS[this.mood] : null,
        mood && this.comfort >= 0 ? this.comfort : null);
      this.sheet = false;
      promptAction.showToast({ message: '已保存' });
      await this.load();
    } catch (e) {
      this.error = (e as Error).message || '保存失败，请重试。';
    } finally {
      this.busy = false;
    }
  }

  private drawChart(): void {
    const ctx = this.chart;
    const width = ctx.width;
    if (width <= 38 || ctx.height < 100) return;
    ctx.clearRect(0, 0, width, ctx.height);
    const step = width / 7;
    for (let level = 0; level <= 10; level += 2) {
      const y = 108 - level * 9;
      ctx.strokeStyle = (this.darkMode ? '#3A332C' : '#E9DCCA');
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(width, y);
      ctx.stroke();
    }
    let previous = -1;
    for (let i = 0; i < 7; i++) {
      const x = (i + 0.5) * step;
      const day = shift(this.week, i);
      const value = this.entries.find((entry: JournalEntry) => entry.date === dateKey(day))?.comfort ?? -1;
      if (value >= 0) {
        const y = 108 - value * 9;
        ctx.strokeStyle = this.green();
        ctx.lineWidth = 2;
        if (previous >= 0) {
          ctx.beginPath();
          ctx.moveTo(x - step, 108 - previous * 9);
          ctx.lineTo(x, y);
          ctx.stroke();
        }
        ctx.fillStyle = this.green();
        ctx.beginPath();
        ctx.arc(x, y, 4, 0, 2 * Math.PI);
        ctx.fill();
      }
      previous = value;
    }
  }

  @Builder
  diaryPage() {
    Column({ space: 12 }) {
      Button() {
        Row({ space: 8 }) {
          Image($r('app.media.diary_envelope')).width(24).height(24).objectFit(ImageFit.Contain)
          Text(dateKey(this.selected) + '  ▾').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#503326')
        }
      }.width('100%').height(42).backgroundColor('#F2DED2')
        .enabled(!this.busy && !this.loading && !this.voice).onClick(() => {
          DatePickerDialog.show({
            selected: this.selected, end: new Date(),
            onDateAccept: (day: Date) => this.selectDiaryDate(day)
          });
        })
      Column({ space: 6 }) {
        TextArea({ text: this.draft, placeholder: this.voice === '正在转写…' ? this.voice : '记下今天发生的事…' })
          .height(205).maxLength(4000).fontSize(17).fontColor(this.brown()).backgroundColor(this.paper())
    .placeholderColor(this.darkMode ? this.p().segSub : '#B39A85')
          .enabled(!this.loading && !this.busy && !this.voice).onChange((value: string) => {
            this.draft = value;
          })
        Row({ space: 8 }) {
          if (!this.voice) {
            Blank()
            Button() {
              Image($r('app.media.journal_microphone')).width(24).height(24)
            }.width(46).height(46).backgroundColor((this.darkMode ? '#F2DED2' : '#EADACB'))
              .accessibilityText('语音输入').enabled(!this.loading && !this.busy).onClick(() => this.startVoice())
          } else {
            Button('■').width(44).height(44).backgroundColor((this.darkMode ? this.p().iconA : '#F2DED2')).fontColor(this.brown())
              .accessibilityText('取消录音或转写').onClick(() => this.closeVoice())
            if (this.voice === '停止录音') {
              Row({ space: 2 }) {
                ForEach(this.wave, (level: number) => {
                  Column().width(3).height(4 + level * 22).borderRadius(2).backgroundColor(this.green())
                }, (_level: number, index: number) => index.toString())
              }.layoutWeight(1).justifyContent(FlexAlign.Center).accessibilityText('正在录音')
            } else {
              Row({ space: 8 }) {
                LoadingProgress().width(18).height(18).color(this.green())
                Text(this.voice).fontSize(14).fontColor(this.brown())
              }.layoutWeight(1)
            }
            Button() {
              Image($r('app.media.journal_send')).width(22).height(22)
            }.width(44).height(44).padding(0).backgroundColor(this.green())
              .accessibilityText('结束录音并转写').enabled(this.voice === '停止录音')
              .onClick(() => this.finishVoice())
          }
        }.width('100%').padding({ left: 8, right: 8, bottom: 8 })
      }.width('100%').backgroundColor(this.paper())
        .border({ width: 1, color: this.edge(), style: BorderStyle.Dashed }).borderRadius(18)
      Button('保存日记').width('100%').height(48).backgroundColor(this.green())
        .enabled(!this.busy && !this.loading && !this.voice).onClick(() => this.save(false))
    }
    .width('100%')
  }

  @Builder
  calendarPage() {
    Column({ space: 8 }) {
      Row() {
        Button('‹').accessibilityText('返回').backgroundColor(this.green()).fontColor(Color.White).onClick(() => {
          this.month = new Date(this.month.getFullYear(), this.month.getMonth() - 1, 1);
          this.load();
        })
        Text(this.month.getFullYear() + '年' + (this.month.getMonth() + 1) + '月')
          .layoutWeight(1).textAlign(TextAlign.Center).fontColor(this.brown())
        Button('›').backgroundColor(this.green()).fontColor(Color.White).onClick(() => {
          this.month = new Date(this.month.getFullYear(), this.month.getMonth() + 1, 1);
          this.load();
        })
      }.width('100%')
      Row() {
        ForEach(DAYS, (day: string) => {
          Text(day).layoutWeight(1).textAlign(TextAlign.Center).fontColor(this.brown())
        })
      }.width('100%')
      ForEach(WEEKS, (row: number) => {
        Row() {
          ForEach(POSITIONS, (col: number) => {
            Column({ space: 2 }) {
              if (this.calendarDay(row * 7 + col).getMonth() === this.month.getMonth()) {
                Text(this.calendarDay(row * 7 + col).getDate().toString()).fontSize(13).fontColor(this.brown())
                if (this.moodAt(this.calendarDay(row * 7 + col)) >= 0) {
                  Image(FACES[this.moodAt(this.calendarDay(row * 7 + col))])
                    .width(43).height(43).objectFit(ImageFit.Contain)
                }
              }
            }.layoutWeight(1).height(62).justifyContent(FlexAlign.Center)
            .onClick(() => {
              const day = this.calendarDay(row * 7 + col);
              if (day.getMonth() === this.month.getMonth()) this.openMood(day);
            })
          })
        }.width('100%')
      })
      Button('+  记录今天').height(44).fontColor('#FFFFFF').backgroundColor(this.darkMode ? this.p().accent : BROWN)
        .enabled(!this.loading && !this.busy && this.error.length === 0)
        .onClick(() => {
          if (dateKey(new Date()).slice(0, 7) === dateKey(this.month).slice(0, 7)) {
            this.openMood(new Date());
          } else {
            this.month = new Date();
            this.load().then(() => this.openMood(new Date()));
          }
        })
    }.width('100%').padding(10).border({ width: 2, color: this.edge() }).borderRadius(18).backgroundColor(this.paper())
  }

  @Builder
  moodPanel() {
    Column({ space: 10 }) {
      Row() {
        Text('心情 · ' + dateKey(this.selected)).layoutWeight(1).fontSize(19).fontColor(this.brown())
        Button('×').backgroundColor(this.green()).fontColor(Color.White)
          .enabled(!this.busy).onClick(() => this.sheet = false)
      }.width('100%')
      Grid() {
        ForEach(MOODS, (label: string, index: number) => {
          GridItem() {
            Column({ space: 2 }) {
              Image(FACES[index]).width(76).height(70).objectFit(ImageFit.Contain)
              Text(label).fontColor(this.brown()).fontSize(15)
            }.width('100%').height(94).justifyContent(FlexAlign.Center).borderRadius(14)
            .backgroundColor(this.mood === index ? (this.darkMode ? this.p().iconB : '#E3EACF') : this.paper())
            .onClick(() => this.mood = index)
          }
        })
      }.columnsTemplate('1fr 1fr 1fr').rowsTemplate('1fr 1fr 1fr 1fr').height(384)
      if (this.mood >= 0) {
        Text(this.encouragement()).fontColor(this.brown()).padding(10).width('100%').backgroundColor((this.darkMode ? this.p().surfaceSoft : '#F4E2D9'))
        Row() {
          Text(this.comfort < 0 ? '舒适度（选填）' : '舒适度 ' + this.comfort + '/10')
            .layoutWeight(1).fontColor(this.brown())
          Button('清空').backgroundColor(this.green()).fontColor(Color.White)
            .onClick(() => this.comfort = -1)
        }.width('100%')
        Slider({ value: this.comfort < 0 ? 0 : this.comfort, min: 0, max: 10, step: 1 })
          .selectedColor(this.green()).onChange((value: number) => this.comfort = value)
      }
      if (this.error) Text(this.error).fontColor((this.darkMode ? this.p().danger : '#963E39'))
      Button('保存心情').width('100%').height(46).backgroundColor(this.green())
        .enabled(this.mood >= 0 && !this.busy).onClick(() => this.save(true))
    }.padding(16).width('100%').backgroundColor(this.paper()).borderRadius(24)
    .border({ width: 1, color: this.edge(), style: BorderStyle.Dashed })
  }

  @Builder
  reviewPage() {
    Column({ space: 14 }) {
      Stack() {
        Image($r('app.media.journal_week_lace')).width('100%').height(58).objectFit(ImageFit.Fill)
        Row() {
          Button('‹').width(38).height(38).backgroundColor(this.green()).fontColor(Color.White)
            .accessibilityText('上一周').enabled(!this.busy).onClick(() => this.changeWeek(-7))
          Text(dateKey(this.week) + ' ~ ' + dateKey(shift(this.week, 6)))
            .layoutWeight(1).textAlign(TextAlign.Center).fontColor((this.darkMode ? this.p().accentText : '#973D5B'))
            .fontSize(14).fontWeight(FontWeight.Bold)
          Button('›').width(38).height(38).backgroundColor(this.green()).fontColor(Color.White)
            .accessibilityText('下一周').enabled(!this.busy).onClick(() => this.changeWeek(7))
        }.width('100%').padding({ left: 14, right: 14 })
      }.width('100%').height(58)
      Column({ space: 6 }) {
        Text('自评舒适度').fontSize(18).fontColor(this.brown()).width('100%')
        Text('纵轴：自评舒适度（0～10 分）').fontSize(13).fontColor(this.brown()).width('100%')
        Row() {
          Column() {
            ForEach([10, 8, 6, 4, 2, 0], (score: number) => {
              Text(score.toString()).fontSize(12).fontColor(this.brown()).height(18)
            })
          }.width(24).padding({ top: 9 })
          Canvas(this.chart).layoutWeight(1).height(120).onReady(() => this.drawChart())
        }.width('100%').alignItems(VerticalAlign.Top)
        Row() {
          Blank().width(24)
          ForEach(POSITIONS, (index: number) => {
            Column({ space: 3 }) {
              Text(dateKey(shift(this.week, index)).slice(5).replace('-', '/')).fontSize(11).fontColor(this.brown())
              if (this.moodAt(shift(this.week, index)) >= 0) {
                Image(FACES[this.moodAt(shift(this.week, index))]).width(31).height(31)
                  .accessibilityText(MOODS[this.moodAt(shift(this.week, index))])
              } else {
                Text('—').height(31).fontSize(12).fontColor(this.brown())
              }
            }.layoutWeight(1)
          })
        }.width('100%')
        Text('横轴：日期和当天心情。只记录心情时，显示表情，分数留空。')
          .fontSize(12).fontColor(this.brown()).width('100%')
      }.padding(12).width('100%').backgroundColor(this.paper()).borderRadius(14).border({ width: 1, color: this.edge() })
      Button('心情调节建议  ›').width('100%').height(48).backgroundColor(this.green())
        .enabled(!this.busy && !this.loading && !this.error)
        .onClick(() => { this.openNotes(); })

    }.width('100%')
  }


  private noteImage(): Resource {
    return NOTE_IMAGES[Math.min(this.noteIndex, NOTE_IMAGES.length - 1)];
  }

  private weekStartKey(): string {
    return dateKey(weekStart(this.week));
  }

  private weekEndKey(): string {
    return dateKey(shift(weekStart(this.week), 6));
  }

  private chosenDates(): string[] {
    const days: string[] = [];
    for (let i = 0; i < this.entries.length; i++) {
      const entry = this.entries[i];
      if (entry.diary !== null && entry.diary !== undefined && entry.diary.length > 0) days.push(entry.date);
    }
    return days;
  }

  private async openNotes(): Promise<void> {
    if (this.noteLoading) return;
    this.noteOpen = true;
    this.noteError = '';
    this.noteIndex = 0;
    this.refreshSaved();
    const start = this.weekStartKey();
    if (this.notes.length === 5 && this.noteWeek === start) return;
    this.noteLoading = true;
    const days = this.chosenDates();
    try {
      const analysis: JournalAnalysis = await Api.journalAnalysis(start, days);
      const result: JournalSuggestion[] = await Api.journalSuggestions(start, days, undefined, analysis.contextId);
      this.notes = result;
      this.noteWeek = start;
      this.noteIndex = 0;
      if (result.length === 0) this.noteError = '暂未生成建议，请稍后重试。';
    } catch (e) {
      this.noteError = (e as Error).message || '暂时无法生成建议，请重试。';
    } finally {
      this.noteLoading = false;
    }
  }

  private refreshSaved(): void {
    this.noteSaved = readMemoItems().map((item: MemoItem) => item.text);
  }

  private noteMemoText(): string {
    const item = this.notes[this.noteIndex];
    if (!item) return '';
    return suggestionMemoText(item.title, item.text, item.steps, item.category, item.created_at,
      item.source, item.page ?? 0, item.section ?? '');
  }

  private isNoteSaved(): boolean {
    const text = this.noteMemoText();
    return text.length > 0 && this.noteSaved.includes(text);
  }

  private noteMemoSaving: boolean = false;

  private async saveNote(): Promise<void> {
    if (this.noteMemoSaving) return;
    const text = this.noteMemoText();
    const item = this.notes[this.noteIndex];
    if (text.length === 0 || !item) return;
    const items = readMemoItems();
    const id = suggestionMemoId(item.suggestion_id);
    this.noteMemoSaving = true;
    try {
      if (!items.some((saved: MemoItem) => saved.id === id || saved.text === text)) {
        const entry: MemoItem = { id: id, text: text, done: false, dueAt: '' };
        await saveAssistantMemoItems([...items, entry]);
      }
      this.refreshSaved();
      promptAction.showToast({ message: '已为你保存，可以随时回来查看', duration: 1500 });
    } catch (e) {
      promptAction.showToast({ message: '暂未保存，请重试，建议内容已保留。', duration: 2000 });
    } finally { this.noteMemoSaving = false; }
  }

  private moveNote(delta: number): void {
    const next = this.noteIndex + delta;
    if (next < 0 || next >= this.notes.length) return;
    this.noteIndex = next;
  }

  private changeWeek(offset: number): void {
    this.week = shift(this.week, offset);
    this.load();
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Image(BACKGROUNDS[this.sheet ? 2 : this.tab === 2 ? 3 : this.tab])
        .width('100%').height('100%').objectFit(ImageFit.Fill)
        .opacity(this.darkMode ? 0.2 : 1)
      if (this.darkMode) {
        Column().width('100%').height('100%').backgroundColor('#151311').opacity(0.88)
      }
      Column() {
        Row() {
          Button('‹').accessibilityText('返回').fontSize(24).fontColor(this.brown()).backgroundColor('#00FFFFFF').onClick(() => {
            if (this.sheet) {
              if (!this.busy) this.sheet = false;
            } else {
              router.back();
            }
          })
          Text(TABS[this.tab]).fontSize(23).fontWeight(FontWeight.Medium).fontColor(this.brown())
            .layoutWeight(1).textAlign(TextAlign.Center)
          Blank().width(48)
        }.width('100%').height(58)
        Scroll() {
          Column({ space: 10 }) {
            if (this.sheet) this.moodPanel()
            else if (this.tab === 0) this.diaryPage()
            else if (this.tab === 1) this.calendarPage()
            else this.reviewPage()
            if (this.loading) Text('正在加载…').fontColor(this.brown())
            if (this.error && !this.sheet) {
              Text(this.error).fontColor((this.darkMode ? this.p().danger : '#963E39'))
              Button('刷新记录').onClick(() => this.load())
            }
          }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 100 })
        }.layoutWeight(1).width('100%')
        if (!this.sheet) {
          Row() {
            ForEach(TABS, (label: string, index: number) => {
              Button(label).layoutWeight(1).height(48).fontColor(this.tab === index ? this.green() : this.brown())
                .backgroundColor(this.tab === index ? (this.darkMode ? this.p().iconB : '#E4ECD7') : this.paper()).onClick(() => this.setTab(index))
            })
          }.width('100%').padding(6).backgroundColor(this.paper())
        }
      }.width('100%').height('100%')
      if (this.noteOpen) {
        Stack({ alignContent: Alignment.Center }) {
          Column().width('100%').height('100%').backgroundColor('rgba(0,0,0,0.42)').zIndex(1)
            .onClick(() => { this.noteOpen = false; })
          Column({ space: 16 }) {
            Column({ space: 0 }) {
              if (this.noteLoading) {
                Column({ space: 12 }) {
                  LoadingProgress().width(46).height(46).color(this.green())
                  Text('正在整理本周建议…').fontSize(14).fontColor('#5C4A3C')
                }.padding({ top: 48, bottom: 48 })
              } else if (this.noteError.length > 0) {
                Column({ space: 14 }) {
                  Text(this.noteError).fontSize(14).fontColor('#9A4D46').textAlign(TextAlign.Center)
                  Button('重新生成').fontSize(14).height(40).backgroundColor(this.green())
                    .onClick(() => { this.notes = []; this.openNotes(); })
                }.padding(36)
              } else if (this.notes.length > 0) {
                Column({ space: 0 }) {
                  Image(this.noteImage())
                    .width('100%').height(250).objectFit(ImageFit.Contain)
                    .backgroundColor('#FFFAF4').borderRadius(20)
                    .margin({ top: 14, left: 14, right: 14 })
                  Column({ space: 8 }) {
                    Text(this.notes[this.noteIndex].title)
                      .fontSize(24).fontWeight(FontWeight.Bold).fontColor('#3C2E24').width('100%')
                    Text(this.notes[this.noteIndex].text)
                      .fontSize(15).lineHeight(22).fontColor('#5C4A3C').width('100%')
                  }.padding({ left: 18, right: 18, top: 14 })
                  Row() {
                    Blank()
                    Row({ space: 6 }) {
                      Text('✦').fontSize(13).fontColor('#7E8F63')
                      Text(this.isNoteSaved() ? '✓ 已添加至备忘录' : '生成备注')
                        .fontSize(15).fontColor('#3C2E24')
                    }
                    .height(44).padding({ left: 20, right: 20 })
                    .backgroundColor('#B3FFFFFF')
                    .border({ width: 1, color: '#F2FFFFFF' })
                    .borderRadius(22)
                    .shadow({ radius: 8, color: 'rgba(255,255,255,0.55)', offsetY: 2 })
                    .onClick(() => this.saveNote())
                  }.width('100%').padding({ left: 18, right: 18, top: 12, bottom: 16 })
                }.width('100%').backgroundColor('#FDE4E5').borderRadius(26)
              }
            }.width('100%')
            if (!this.noteLoading && this.noteError.length === 0 && this.notes.length > 0) {
              Row({ space: 12 }) {
                if (this.noteIndex > 0) {
                  Button('‹  上一个建议').height(42).fontSize(15).fontColor('#F6EEE4')
                    .backgroundColor('rgba(24,18,12,0.62)')
                    .border({ width: 1, color: 'rgba(255,255,255,0.28)' }).borderRadius(21)
                    .onClick(() => this.moveNote(-1))
                }
                if (this.noteIndex < this.notes.length - 1) {
                  Button('下一个建议  ›').height(42).fontSize(15).fontColor('#F6EEE4')
                    .backgroundColor('rgba(24,18,12,0.62)')
                    .border({ width: 1, color: 'rgba(255,255,255,0.28)' }).borderRadius(21)
                    .onClick(() => this.moveNote(1))
                }
              }.width('100%').justifyContent(FlexAlign.Center)
            }
          }.width('86%').zIndex(2)
        }.width('100%').height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .position({ x: 0, y: 0 }).zIndex(90)
      }
    }.width('100%').height('100%').backgroundColor(this.paper())
  }
}
