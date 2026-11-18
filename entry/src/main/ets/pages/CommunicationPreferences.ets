import { router } from '@kit.ArkUI';
import { Api } from '../model/Api';
import { Theme, Palette, palette } from '../model/Theme';
import { readableFont } from '../model/UserPreferences';

@Entry
@Component
struct CommunicationPreferences {
  @StorageProp('darkMode') darkMode: boolean = false;
  @StorageProp('textSize') textSize: string = 'normal';
  @State name: string = '';
  @State address: string = '';
  @State confirmed: boolean = false;
  @State hearing: boolean = false;
  @State slower: boolean = false;
  @State shortQuestions: boolean = false;
  @State busy: boolean = false;
  @State ready: boolean = false;
  @State message: string = '';
  private personId: string = '';
  private revision: number = 0;
  private p(): Palette { return palette(this.darkMode); }
  private font(size: number): number { return readableFont(size, this.textSize); }
  aboutToAppear(): void {
    this.personId = ((router.getParams() as Record<string, Object>)?.['personId'] as string) ?? '';
    this.load();
  }
  private async load(): Promise<void> {
    if (this.busy) return;
    this.busy = true; this.ready = false; this.message = '';
    try {
      if (!this.personId) throw new Error('请从居民档案进入。');
      const person = await Api.person(this.personId);
      if (!person || person.id !== this.personId || !Number.isInteger(person.revision) || (person.revision ?? 0) < 1) {
        throw new Error('无法核对档案及版本，请重新读取。');
      }
      this.name = person.name;
      this.revision = person.revision ?? 0;
      this.address = person.preferredAddress ?? '';
      this.confirmed = person.preferredAddressConfirmed === true;
      const needs = person.communicationNeeds ?? [];
      this.hearing = needs.includes('hearing'); this.slower = needs.includes('slower');
      this.shortQuestions = needs.includes('short_questions');
      this.ready = true;
    } catch (e) { this.message = (e as Error).message || '读取失败。'; }
    finally { this.busy = false; }
  }
  private async save(): Promise<void> {
    if (!this.ready || this.busy) return;
    const title = this.address.trim();
    if (title.length > 8 || (this.confirmed && !title)) {
      this.message = '已确认称呼需填写1～8个字；未知可留空并取消勾选。'; return;
    }
    const needs: string[] = [];
    if (this.hearing) needs.push('hearing'); if (this.slower) needs.push('slower');
    if (this.shortQuestions) needs.push('short_questions');
    this.busy = true; this.message = '';
    try {
      await Api.updateCommunicationPreferences(this.personId, this.revision, title, this.confirmed, needs);
      router.back();
    } catch (e) { this.message = (e as Error).message || '保存失败，填写内容已保留。'; }
    finally { this.busy = false; }
  }
  build() {
    Column() {
      Row() {
        Button('返回').backgroundColor(this.p().iconB).fontColor(this.p().accentText).onClick(() => router.back())
        Text('沟通偏好').fontSize(this.font(20)).fontColor(this.p().ink).layoutWeight(1).textAlign(TextAlign.Center)
      }.width('100%').padding(12)
      Scroll() {
        Column({ space: 16 }) {
          Text(this.name).fontSize(this.font(20)).fontColor(this.p().ink)
          Text('只记录已与居民核实的偏好。未确认称呼时，开场使用“您好呀”，不会按姓名、年龄或性别猜称呼。')
            .fontSize(this.font(16)).fontColor(this.p().ink2)
          TextInput({ text: this.address, placeholder: '居民希望如何称呼（最多8字）' }).maxLength(8)
            .fontSize(this.font(16)).fontColor(this.p().ink).backgroundColor(this.p().surface).enabled(this.ready && !this.busy)
            .onChange((value: string) => { this.address = value; this.confirmed = false; })
          Row() {
            Checkbox().select(this.confirmed).selectedColor(Theme.greenDeep).enabled(this.ready && !this.busy)
              .onChange((value: boolean) => this.confirmed = value)
            Text('已与居民确认这个称呼').fontSize(this.font(16)).fontColor(this.p().ink)
          }
          Text('按需勾选已核实的沟通需求，未知保持不选。').fontSize(this.font(16)).fontColor(this.p().ink2)
          Row() {
            Checkbox().select(this.hearing).selectedColor(Theme.greenDeep).enabled(this.ready && !this.busy).onChange((v: boolean) => this.hearing = v)
            Text('需要听得更清楚').fontSize(this.font(16)).fontColor(this.p().ink)
          }
          Row() {
            Checkbox().select(this.slower).selectedColor(Theme.greenDeep).enabled(this.ready && !this.busy).onChange((v: boolean) => this.slower = v)
            Text('希望说得慢一些').fontSize(this.font(16)).fontColor(this.p().ink)
          }
          Row() {
            Checkbox().select(this.shortQuestions).selectedColor(Theme.greenDeep).enabled(this.ready && !this.busy).onChange((v: boolean) => this.shortQuestions = v)
            Text('希望问题更简短').fontSize(this.font(16)).fontColor(this.p().ink)
          }
          if (this.message) {
            Text(this.message).fontSize(this.font(16)).fontColor(this.p().danger)
            Button('重新读取（覆盖本页填写）').backgroundColor(this.p().iconB).fontColor(this.p().accentText)
              .enabled(!this.busy).onClick(() => this.load())
          }
          Button(this.busy ? '处理中…' : '保存沟通偏好').width('100%').constraintSize({ minHeight: 48 })
            .backgroundColor(Theme.greenDeep).fontColor('#FFFFFF').fontSize(this.font(16))
            .enabled(this.ready && !this.busy).onClick(() => this.save())
        }.width('100%').padding(20).alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor(this.p().pageBg)
  }
}
