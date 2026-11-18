import { router } from '@kit.ArkUI';
import { Api, ResidenceInput } from '../model/Api';
import { residenceInput, validateResidence } from '../model/ResidenceState';
import { Theme, Palette, palette } from '../model/Theme';
import { readableFont } from '../model/UserPreferences';

@Entry
@Component
struct ResidenceEdit {
  @StorageProp('darkMode') darkMode: boolean = false;
  @StorageProp('textSize') textSize: string = 'normal';
  @State name: string = '';
  @State address: string = '';
  @State phone: string = '';
  @State living: string = '';
  @State contactName: string = '';
  @State contactPhone: string = '';
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
    this.ready = false;
    this.busy = true;
    this.message = '';
    try {
      if (!this.personId) throw new Error('缺少人员信息，请返回档案重新进入。');
      const person = await Api.person(this.personId);
      if (!person) throw new Error('登录或档案已失效，请重新登录。');
      const input = residenceInput(person, this.personId);
      this.name = person.name;
      this.revision = person.revision ?? 0;
      this.address = input.address;
      this.phone = input.phone;
      this.living = input.living;
      this.contactName = input.contactName;
      this.contactPhone = input.contactPhone;
      this.ready = true;
    } catch (e) { this.message = (e as Error).message || '读取失败，请重试。'; }
    finally { this.busy = false; }
  }

  private async save(): Promise<void> {
    if (this.busy || !this.ready) return;
    const input: ResidenceInput = { address: this.address.trim(), phone: this.phone.trim(),
      living: this.living.trim(), contactName: this.contactName.trim(), contactPhone: this.contactPhone.trim() };
    this.message = validateResidence(input);
    if (this.message) return;
    this.busy = true;
    try {
      await Api.updateResidence(this.personId, this.revision, input);
      router.back();
    } catch (e) { this.message = (e as Error).message || '保存失败，填写内容已保留。'; }
    finally { this.busy = false; }
  }

  @Builder
  field(label: string, placeholder: string, value: string, change: (value: string) => void) {
    Column({ space: 6 }) {
      Text(label).fontSize(this.font(16)).fontColor(this.p().ink)
      TextArea({ placeholder: placeholder, text: value })
        .fontSize(this.font(16)).fontColor(this.p().ink).backgroundColor(this.p().surface)
        .constraintSize({ minHeight: 52 }).borderRadius(12)
        .border({ width: 1, color: this.p().border }).enabled(this.ready && !this.busy).onChange(change)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Row() {
        Button('返回').backgroundColor(this.p().iconB).fontColor(this.p().accentText).onClick(() => router.back())
        Text('住所与联系信息').fontSize(this.font(18)).fontColor(this.p().ink).layoutWeight(1).textAlign(TextAlign.Center)
      }.padding(12).width('100%')
      Scroll() {
        Column({ space: 14 }) {
          Text(this.name).fontSize(this.font(20)).fontColor(this.p().ink)
          Text('当前住所为必填项，请核实后填写。修改地址后请重新核验地图入口。')
            .fontSize(this.font(16)).fontColor(this.p().muted)
          this.field('当前居住地址', '省市区、街道、小区、楼栋单元门牌', this.address, (v: string) => this.address = v)
          this.field('联系电话', '手机号或固定电话', this.phone, (v: string) => this.phone = v)
          this.field('居住情况', '如独居、与配偶同住', this.living, (v: string) => this.living = v)
          this.field('联系人姓名', '未知可留空', this.contactName, (v: string) => this.contactName = v)
          this.field('联系人电话', '手机号或固定电话', this.contactPhone, (v: string) => this.contactPhone = v)
          if (this.message) {
            Text(this.message).fontSize(this.font(16)).fontColor(this.p().danger)
            Button('重新读取档案（覆盖本页填写）').backgroundColor(this.p().iconB).fontColor(this.p().accentText)
              .enabled(!this.busy).onClick(() => this.load())
          }
          Button(this.busy ? '处理中…' : '保存住所与联系信息').width('100%').constraintSize({ minHeight: 48 })
            .fontSize(this.font(16)).backgroundColor(Theme.greenDeep).fontColor('#FFFFFF')
            .enabled(this.ready && !this.busy).onClick(() => this.save())
        }.padding(18).width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor(this.p().pageBg)
  }
}
