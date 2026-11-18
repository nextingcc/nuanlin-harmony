import { router, promptAction } from '@kit.ArkUI';
import { picker, fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { Theme, Palette, palette } from '../model/Theme';
import { Api, PersonInput, Person } from '../model/Api';

@Entry
@Component
struct PersonForm {
  @State name: string = '';
  @State age: string = '';
  @State gender: string = '女';
  @State community: string = '青禾社区';
  @State phone: string = '';
  @State address: string = '';
  @State living: string = '';
  @State contactName: string = '';
  @State contactPhone: string = '';
  @State notes: string = '';
  @State saving: boolean = false;
  @State message: string = '';
  @State attachmentName: string = '';
  @State hasAttachment: boolean = false;
  @StorageProp('darkMode') darkMode: boolean = false;

  private p(): Palette { return palette(this.darkMode); }

  aboutToAppear(): void {
    const raw = AppStorage.get<string>('draftPerson');
    if (!raw) return;
    try {
      const draft = JSON.parse(raw) as Record<string, string>;
      this.name = draft['name'] ?? '';
      this.age = draft['age'] ?? '';
      this.gender = draft['gender'] !== undefined && draft['gender'].length > 0 ? draft['gender'] : '女';
      this.community = draft['community'] !== undefined && draft['community'].length > 0 ? draft['community'] : '青禾社区';
      this.notes = draft['notes'] ?? '';
      this.phone = draft['phone'] ?? '';
      this.address = draft['address'] ?? '';
      this.living = draft['living'] ?? '';
      this.contactName = draft['contactName'] ?? '';
      this.contactPhone = draft['contactPhone'] ?? '';
      AppStorage.setOrCreate('draftPerson', '');
    } catch (e) {
      // ignore malformed draft
    }
  }

  private async pickAttachment(): Promise<void> {
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const uris = await new picker.DocumentViewPicker().select(options);
      if (uris.length === 0) return;
      const uri = uris[0];
      const name = uri.split('/').pop() ?? 'attachment';
      const context = getContext(this) as common.UIAbilityContext;
      const source = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const dest = context.cacheDir + '/' + name;
      fileIo.copyFileSync(source.fd, dest);
      fileIo.closeSync(source);
      this.attachmentName = name;
      this.hasAttachment = true;
      this.message = '';
    } catch (e) {
      this.message = '选择附件失败：' + JSON.stringify(e);
    }
  }

  private async save(): Promise<void> {
    if (this.saving) return;
    this.message = '';
    const missing: string[] = [];
    if (this.name.trim().length === 0) missing.push('姓名');
    const age = this.age.trim();
    if (age.length === 0) missing.push('年龄');
    if (this.community.trim().length === 0) missing.push('所属社区');
    if (this.address.trim().length === 0) missing.push('当前居住地址');
    if (missing.length > 0) {
      AlertDialog.show({
        title: '信息不完整，请补全信息',
        message: '请填写' + missing.join('、') + '。',
        confirm: { value: '返回填写', action: () => {} }
      });
      return;
    }
    const phone = this.phone.trim();
    const ageValue = Number(age);
    const invalid: string[] = [];
    if (!/^\d{1,3}$/.test(age) || ageValue > 120) {
      invalid.push('年龄请输入 0～120 的整数。');
    }
    if (phone.length > 0 && !/^[+\d\s()-]{7,24}$/.test(phone)) {
      invalid.push('联系电话请输入完整的手机号或固定电话，没有号码可以留空。');
    }
    if (this.contactPhone.trim().length > 0 && !/^[+\d\s()-]{7,24}$/.test(this.contactPhone.trim())) {
      invalid.push('联系人电话格式无效，可以留空。');
    }
    if (invalid.length > 0) {
      AlertDialog.show({
        title: '信息格式错误',
        message: invalid.join('\n'),
        confirm: { value: '返回修改', action: () => {} }
      });
      return;
    }
    this.saving = true;
    const input: PersonInput = {
      name: this.name.trim(),
      age: ageValue,
      gender: this.gender,
      community: this.community.trim(),
      phone: phone,
      address: this.address.trim(),
      living: this.living.trim(),
      contactName: this.contactName.trim(),
      contactPhone: this.contactPhone.trim(),
      notes: this.notes.trim()
    };
    try {
      const created: Person | null = await Api.createPerson(input);
      if (created === null) {
        this.message = '登录已失效，请重新登录后再保存。';
      } else {
        if (this.hasAttachment) {
          const context = getContext(this) as common.UIAbilityContext;
          const uploaded = await Api.uploadAttachment(context, created.id, this.attachmentName);
          promptAction.showToast({ message: uploaded ? '已保存并上传附件' : '已保存，附件上传失败', duration: 2000 });
        } else {
          promptAction.showToast({ message: '已保存：' + created.name, duration: 2000 });
        }
        router.replaceUrl({ url: 'pages/ResidentList' });
      }
    } catch (e) {
      this.message = (e as Error).message || '保存失败，请检查网络连接后重试。';
    } finally {
      this.saving = false;
    }
  }

  @Builder
  field(label: string, placeholder: string, value: string, onChange: (v: string) => void) {
    Column({ space: 5 }) {
      Text(label).fontSize(10).fontColor((this.darkMode ? this.p().section : '#9C7E66'))
      TextInput({ placeholder: placeholder, text: value })
        .height(42)
        .fontSize(13)
        .fontColor(this.p().ink)
        .placeholderColor(this.darkMode ? this.p().segSub : '#B39A85')
        .backgroundColor((this.darkMode ? this.p().surface : '#FFFDF8'))
        .borderRadius(8)
        .border({ width: 1, color: (this.darkMode ? this.p().border : '#EBDCCF') })
        .onChange(onChange)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  build() {
    Column() {
      Row() {
        Text('‹').accessibilityText('返回')
          .fontSize(26)
          .fontColor(this.p().ink)
          .width(32)
          .textAlign(TextAlign.Center)
          .onClick(() => router.replaceUrl({ url: 'pages/ResidentList' }))
        Text('新建人员')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.p().ink)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('取消')
          .fontSize(12)
          .fontColor((this.darkMode ? this.p().segInk : '#8A6B54'))
          .width(44)
          .textAlign(TextAlign.End)
          .onClick(() => router.replaceUrl({ url: 'pages/ResidentList' }))
      }
      .width('100%')
      .height(52)
      .padding({ left: 10, right: 18 })

      Scroll() {
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Image($r('app.media.archive_envelope')).width(26).height(26).objectFit(ImageFit.Contain)
              .backgroundColor(this.darkMode ? '#F6E9DB' : Color.Transparent).borderRadius(6)
            Text('建档').fontSize(20).fontFamily('serif').fontColor(this.p().ink)
          }.width('100%')
          Text('保存后会写入社区后端；也可以先从资料识别带入字段。')
            .fontSize(9)
            .fontColor(this.p().muted)
            .width('100%')

          Text('📄 从资料识别带入')
            .fontSize(11)
            .fontColor((this.darkMode ? this.p().accent : Theme.greenDeep))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 10, bottom: 10 })
            .borderRadius(10)
            .border({ width: 1, color: (this.darkMode ? this.p().border : '#CBD8B4') })
            .onClick(() => router.pushUrl({ url: 'pages/ImportPerson' }))

          Column({ space: 10 }) {
            this.field('姓名', '请输入姓名', this.name, (v: string) => { this.name = v; })
            this.field('年龄', '0–120', this.age, (v: string) => { this.age = v; })
            Column({ space: 5 }) {
              Text('性别').fontSize(10).fontColor((this.darkMode ? this.p().section : '#9C7E66'))
              Row({ space: 8 }) {
                ForEach(['女', '男', '其他'], (item: string) => {
                  Text(item)
                    .fontSize(11)
                    .fontColor(this.gender === item ? '#FFFFFF' : this.p().ink2)
                    .backgroundColor(this.gender === item ? (this.darkMode ? this.p().accent : Theme.greenDeep) : (this.darkMode ? this.p().surface : '#FFFDF8'))
                    .borderRadius(14)
                    .border({ width: 1, color: this.gender === item ? (this.darkMode ? this.p().accent : Theme.greenDeep) : (this.darkMode ? this.p().border : '#EBDCCF') })
                    .padding({ left: 16, right: 16, top: 7, bottom: 7 })
                    .onClick(() => { this.gender = item; })
                }, (item: string) => item)
              }
              .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            this.field('所属社区', '青禾社区', this.community, (v: string) => { this.community = v; })
            this.field('联系电话', '手机号或固定电话', this.phone, (v: string) => { this.phone = v; })
            this.field('当前居住地址 *', '必填：省市区、街道、小区、楼栋单元门牌', this.address, (v: string) => { this.address = v; })
            Text('用于上门联系，请核对当前住所；文字地址尚未经过地图位置核验。').fontSize(13).fontColor(this.p().muted)
            this.field('居住情况', '如独居、与配偶同住；未知可留空', this.living, (v: string) => { this.living = v; })
            this.field('联系人姓名', '未知可留空', this.contactName, (v: string) => { this.contactName = v; })
            this.field('联系人电话', '手机号或固定电话；未知可留空', this.contactPhone, (v: string) => { this.contactPhone = v; })
            this.field('备注', '补充信息', this.notes, (v: string) => { this.notes = v; })
            Row({ space: 8 }) {
              Text('添加附件')
                .fontSize(11)
                .fontColor((this.darkMode ? this.p().accent : Theme.greenDeep))
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .borderRadius(16)
                .border({ width: 1, color: (this.darkMode ? this.p().border : '#CBD8B4') })
                .onClick(() => this.pickAttachment())
              Text(this.hasAttachment ? this.attachmentName : '未选择')
                .fontSize(9)
                .fontColor(this.p().muted)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
          }
          .width('100%')
          .padding(14)
          .borderRadius(18)
          .backgroundColor((this.darkMode ? this.p().surface : '#FFFCF6'))
          .border({ width: 1, color: (this.darkMode ? this.p().border : '#F0DED1') })

          if (this.message.length > 0) {
            Text(this.message)
              .fontSize(10)
              .fontColor((this.darkMode ? this.p().danger : '#9C4A45'))
              .width('100%')
          }

          Button(this.saving ? '保存中…' : '保存人员')
            .width('100%')
            .height(50)
            .fontSize(15)
            .fontColor('#FFFFFF')
            .backgroundColor((this.darkMode ? this.p().accent : Theme.greenDeep))
            .borderRadius(25)
            .enabled(!this.saving)
            .onClick(() => this.save())
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 6, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor((this.darkMode ? this.p().pageBg : '#F8E8E2'))
  }
}

