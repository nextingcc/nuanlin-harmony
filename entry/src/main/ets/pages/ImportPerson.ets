import { router } from '@kit.ArkUI';
import { picker, fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { Theme, Palette, palette } from '../model/Theme';
import { Api, ImportBatch, ImportField, NoteFact, ImportIssue } from '../model/Api';

interface ReviewNote {
  id: string;
  text: string;
  quote: string;
  selected: boolean;
}

interface Draft {
  name: string;
  age: string;
  gender: string;
  community: string;
  notes: string;
  phone: string;
  address: string;
  living: string;
  contactName: string;
  contactPhone: string;
}

@Entry
@Component
struct ImportPerson {
  @StorageProp('darkMode') darkMode: boolean = false;

  private p(): Palette { return palette(this.darkMode); }
  @State busy: boolean = false;
  @State statusText: string = '选择一份虚构资料，开始识别';
  @State fileName: string = '';
  @State error: string = '';
  @State name: string = '';
  @State age: string = '';
  @State gender: string = '';
  @State community: string = '';
  @State phone: string = '';
  @State address: string = '';
  @State living: string = '';
  @State contactName: string = '';
  @State contactPhone: string = '';
  @State notes: ReviewNote[] = [];
  @State issues: ImportIssue[] = [];
  private issueNotes: Map<number, string> = new Map<number, string>();
  @State sourceText: string = '';
  @State sourceImage: string = '';
  @State showSource: boolean = false;
  @State hasResult: boolean = false;
  @State capabilityText: string = '正在检查服务…';
  @State capEnabled: boolean = false;

  aboutToAppear(): void {
    this.checkCaps();
    try {
      const params = router.getParams() as Record<string, Object> | undefined;
      if (params !== undefined && params !== null && typeof params['path'] === 'string') {
        const path = params['path'] as string;
        const name = typeof params['name'] === 'string' ? params['name'] as string : 'image.jpg';
        if (path.length > 0) {
          const lower = name.toLowerCase();
          const mime = lower.endsWith('.png') ? 'image/png' : 'image/jpeg';
          this.recognize(path, name, mime);
        }
      } else if (params !== undefined && params !== null && params['example'] === true) {
        this.tryExample(true);
      }
    } catch (ignored) {}
  }

  private async checkCaps(): Promise<void> {
    try {
      this.capEnabled = await Api.capabilities();
      this.capabilityText = this.capEnabled ? 'OCR + 模型' : '识别未启用';
    } catch (e) {
      this.capEnabled = false;
      this.capabilityText = '暂未能确认服务状态';
    }
  }

  private async sleep(ms: number): Promise<void> {
    await new Promise<void>((resolve) => setTimeout(resolve, ms));
  }

  private async recognize(filePath: string, filename: string, mime: string): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.error = '';
    this.hasResult = false;
    this.fileName = filename;
    this.name = '';
    this.age = '';
    this.gender = '';
    this.community = '';
    this.phone = ''; this.address = ''; this.living = ''; this.contactName = ''; this.contactPhone = '';
    this.notes = [];
    this.issues = [];
    this.issueNotes.clear();
    this.sourceText = '';
    this.sourceImage = mime.startsWith('image/') ? 'file://' + filePath : '';
    this.showSource = false;
    try {
      this.statusText = '正在创建识别批次…';
      const batch: ImportBatch | null = await Api.createImport();
      if (batch === null) {
        this.error = '创建批次失败，请确认后端与 hdc rport';
        return;
      }
      this.capEnabled = true;
      this.capabilityText = 'OCR + 模型';
      this.statusText = '正在上传资料…';
      const fresh = await Api.uploadImportDocument(batch, filePath, filename, mime);
      this.statusText = '正在识别（OCR + 模型）…';
      if (!await Api.runImport(fresh)) {
        this.error = '启动识别失败，请重试。';
        return;
      }
      for (let i = 0; i < 100; i++) {
        await this.sleep(3000);
        this.statusText = '正在识别（OCR + 模型）… 已等待 ' + ((i + 1) * 3).toString() + ' 秒';
        let current: ImportBatch | null = null;
        try {
          current = await Api.getImport(batch.id);
        } catch (e) {
          continue;
        }
        if (current === null) continue;
        if (current.result && ['partial', 'ready', 'completed', 'needs_review'].includes(current.status)) {
          this.applyResult(current);
          this.statusText = '识别完成，请人工核对';
          return;
        }
        if (current.status === 'interrupted') {
          this.statusText = '识别已中断';
          this.error = '后端服务重启，本次识别已停止。请重新选择资料发起识别，无需继续等待。';
          return;
        }
        if (['failed', 'cancelled', 'expired'].includes(current.status)) {
          this.statusText = current.status === 'failed' ? '识别失败' :
            current.status === 'expired' ? '识别记录已过期' : '识别已取消';
          this.error = current.errors?.map(item => item.message).join('\n') || '请重新选择资料。';
          return;
        }
        if (current.status === 'selecting_subject') {
          this.error = '资料中未能确定单一人员，请选择只包含一位居民的资料。';
          this.statusText = '请重新选择资料';
          return;
        }
        this.statusText = current.status === 'parsing' ? '正在 OCR 与解析文档…' : '正在生成字段与备注…';
      }
      this.error = '识别仍在后台进行，可稍后在工具中查看，或重新选择资料。';
    } catch (e) {
      this.error = (e as Error).message || '识别失败，请重试。';
      this.statusText = '可重新选择资料';
    } finally {
      this.busy = false;
    }
  }

  private applyResult(batch: ImportBatch): void {
    const result = batch.result;
    if (result === null) return;
    const fields: ImportField[] = result.fields;
    for (let i = 0; i < fields.length; i++) {
      const f = fields[i];
      const value = f.value === null || f.value === undefined ? '' : f.value.toString();
      if (f.field === 'name') this.name = value;
      if (f.field === 'age') this.age = value;
      if (f.field === 'gender') this.gender = value;
      if (f.field === 'community') this.community = value;
      if (f.field === 'phone') this.phone = value;
      if (f.field === 'address') this.address = value;
      if (f.field === 'living') this.living = value;
      if (f.field === 'contactName') this.contactName = value;
      if (f.field === 'contactPhone') this.contactPhone = value;
    }
    this.notes = result.noteFacts.map((fact: NoteFact): ReviewNote => ({
      id: fact.id, text: fact.statement, quote: fact.evidence?.map(item => item.quote).join('\n') ?? '',
      selected: false
    }));
    this.issues = result.issues ?? [];
    this.sourceText = batch.blocks?.map(block => block.text).join('\n\n') ?? '';
    this.hasResult = true;
  }

  private async copyRawfile(filename: string): Promise<string> {
    const context = getContext(this) as common.UIAbilityContext;
    const bytes = await context.resourceManager.getRawFileContent(filename);
    const path = context.cacheDir + '/' + filename;
    const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    fileIo.writeSync(file.fd, bytes.buffer);
    fileIo.closeSync(file);
    return path;
  }

  private async pickFile(): Promise<void> {
    if (this.busy) return;
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const uris = await new picker.DocumentViewPicker().select(options);
      if (uris.length === 0) return;
      const context = getContext(this) as common.UIAbilityContext;
      const filename = uris[0].split('/').pop() ?? 'document';
      const dest = context.cacheDir + '/' + Date.now().toString() + '-' + filename;
      const source = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
      fileIo.copyFileSync(source.fd, dest);
      fileIo.closeSync(source);
      const lower = filename.toLowerCase();
      const mime = lower.endsWith('.pdf') ? 'application/pdf' :
        lower.endsWith('.png') ? 'image/png' :
        lower.endsWith('.jpg') || lower.endsWith('.jpeg') ? 'image/jpeg' :
        lower.endsWith('.docx') ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' :
        lower.endsWith('.doc') ? 'application/msword' :
        lower.endsWith('.xlsx') ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' :
        lower.endsWith('.json') ? 'application/json' :
        lower.endsWith('.csv') ? 'text/csv' : 'text/plain';
      await this.recognize(dest, filename, mime);
    } catch (e) {
      this.error = '选择文件失败：' + JSON.stringify(e);
    }
  }

  private chooseSource(image: boolean): void {
    if (this.busy) return;
    AlertDialog.show({
      title: image ? '导入图片' : '导入文件',
      message: image ? '可选内置演示病例 PNG，或浏览设备文件。' : '可选内置演示病例 PDF，或浏览设备文件。',
      primaryButton: { value: '浏览设备', action: () => { this.pickFile(); } },
      secondaryButton: { value: '使用演示病例', action: () => { this.tryExample(image); } }
    });
  }

  private async tryExample(image: boolean = true): Promise<void> {
    if (this.busy) return;
    const filename = image ? 'nuanlin-demo-case.png' : 'nuanlin-demo-case.pdf';
    try {
      const path = await this.copyRawfile(filename);
      await this.recognize(path, filename, image ? 'image/png' : 'application/pdf');
    } catch (e) {
      this.error = '示例资料准备失败，请重试。';
    }
  }

  private updateNote(index: number, text: string, selected: boolean): void {
    const copy = this.notes.slice();
    const note = copy[index];
    copy[index] = { id: note.id, text: text, quote: note.quote, selected: selected };
    this.notes = copy;
  }

  private adopt(): void {
    if (!this.hasResult) return;
    if (!this.address.trim()) {
      AlertDialog.show({ title: '未识别到居住地址', message: '识别内容将保留为草稿，请在下一页补充并核对当前住所后再保存档案。',
        confirm: { value: '知道了', action: () => {} } });
    }
    const draft: Draft = {
      name: this.name,
      age: this.age,
      gender: this.gender,
      community: this.community,
      phone: this.phone, address: this.address, living: this.living,
      contactName: this.contactName, contactPhone: this.contactPhone,
      notes: this.notes.filter(note => note.selected && note.text.trim().length > 0)
        .map(note => note.text.trim()).concat(Array.from(this.issueNotes.values()).filter(note => note.length > 0))
        .join('\n')
    };
    AppStorage.setOrCreate('draftPerson', JSON.stringify(draft));
    router.pushUrl({ url: 'pages/PersonForm' });
  }

  @Builder
  tile(icon: Resource, label: string, zoom: number, offsetY: number, action: () => void) {
    Column({ space: 8 }) {
      Stack() {
        Image(icon).width(36).height(36).objectFit(ImageFit.Contain)
          .scale({ x: zoom, y: zoom }).translate({ y: offsetY })
      }.width(36).height(36).borderRadius(18).backgroundColor('#FFFFFF').clip(true)
      Text(label)
        .fontSize(11)
        .fontColor(this.p().ink2)
    }
    .layoutWeight(1)
    .height(86)
    .justifyContent(FlexAlign.Center)
    .borderRadius(16)
    .backgroundColor((this.darkMode ? this.p().surface : 'rgba(255,253,249,0.92)'))
    .border({ width: 1, color: (this.darkMode ? this.p().border : '#EFDCD0') })
    .onClick(action)
  }

  @Builder
  fieldCell(label: string, value: string, update: (value: string) => void) {
    Column({ space: 3 }) {
      Text(label).fontSize(9).fontColor((this.darkMode ? this.p().muted : '#B0927C'))
      TextInput({ text: value, placeholder: '未识别，可手填' })
        .height(32).padding(0).fontSize(13).fontColor(this.p().ink)
        .backgroundColor(Color.Transparent).onChange(update)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(12)
    .backgroundColor((this.darkMode ? this.p().surface : '#FFFCF7'))
    .border({ width: 1, color: (this.darkMode ? this.p().iconA : '#F0E1D4') })
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          Row() {
            Text('‹').accessibilityText('返回')
              .fontSize(26)
              .fontColor(this.p().ink)
              .width(32)
              .textAlign(TextAlign.Center)
              .onClick(() => router.replaceUrl({ url: 'pages/ResidentList' }))
            Text('导入资料')
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

          Row({ space: 8 }) {
            Text('1').fontSize(9).fontColor('#FFFFFF').width(16).height(16).textAlign(TextAlign.Center).borderRadius(8).backgroundColor((this.darkMode ? this.p().accent : Theme.greenDeep))
            Text('导入识别').fontSize(10).fontColor((this.darkMode ? this.p().accent : Theme.greenDeep))
            Divider().layoutWeight(1).color((this.darkMode ? this.p().border : '#E7D2C4'))
            Text('2 人工核对').fontSize(10).fontColor((this.darkMode ? this.p().muted : '#B0927C'))
            Divider().layoutWeight(1).color((this.darkMode ? this.p().border : '#E7D2C4'))
            Text('3 确认建档').fontSize(10).fontColor((this.darkMode ? this.p().muted : '#B0927C'))
          }
          .width('100%')
          .padding({ left: 22, right: 22 })

          Row() {
            Text('资料识别')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.p().ink)
            Blank()
            Text(this.capabilityText)
              .fontSize(9)
              .fontColor(this.capEnabled ? (this.darkMode ? this.p().accent : Theme.greenDeep) : (this.darkMode ? this.p().danger : '#9C4A45'))
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 18, bottom: 9 })

          Row({ space: 10 }) {
            this.tile($r('app.media.import_camera'), '拍照/相册', 1.65, -2, () => this.chooseSource(true))
            this.tile($r('app.media.import_folder'), '选择文件', 1.27, 2, () => this.chooseSource(false))
            this.tile($r('app.media.import_resources'), '示例资料', 1.36, -2, () => this.tryExample())
          }
          .width('100%')
          .padding({ left: 20, right: 20 })

          Text('◈ 仅接受完全虚构的模拟资料；真实病历请勿上传。PDF/Word/Excel/图片上限 10MB。')
            .fontSize(9)
            .fontColor(this.p().muted)
            .width('100%')
            .padding({ left: 20, right: 20, top: 8 })

          Column({ space: 6 }) {
            Row({ space: 7 }) {
              Circle().width(7).height(7).fill(this.busy ? Theme.pink : (this.hasResult ? Theme.green : '#C9A98F'))
              Text(this.statusText)
                .fontSize(10)
                .fontColor(this.p().ink2)
                .layoutWeight(1)
              if (this.fileName.length > 0) {
                Text(this.fileName)
                  .fontSize(8)
                  .fontColor(this.p().muted)
                  .maxLines(1)
                  .constraintSize({ maxWidth: 120 })
              }
            }
            .width('100%')
            if (this.error.length > 0) {
              Text(this.error).fontSize(9).fontColor((this.darkMode ? this.p().danger : '#9C4A45')).width('100%')
            }
          }
          .width('100%')
          .padding(12)
          .margin({ left: 20, right: 20, top: 10 })
          .borderRadius(14)
          .backgroundColor((this.darkMode ? this.p().surface : 'rgba(255,253,248,0.9)'))
          .border({ width: 1, color: (this.darkMode ? this.p().border : '#F0DED2') })

          if (this.hasResult) {
            Column({ space: 8 }) {
              Row({ space: 7 }) {
                Text('✓').fontSize(10).fontColor('#5C6B45')
                Text('识别结果 · 请人工核对')
                  .fontSize(12)
                  .fontColor(this.p().ink)
                Blank()
                Button(this.showSource ? '收起原文' : '查看原文')
                  .fontSize(11).backgroundColor((this.darkMode ? this.p().accent : Theme.greenDeep))
                  .onClick(() => this.showSource = !this.showSource)
              }
              .width('100%')

              Column({ space: 10 }) {
                this.fieldCell('姓名', this.name, (value: string) => this.name = value)
                this.fieldCell('年龄', this.age, (value: string) => this.age = value)
                this.fieldCell('性别', this.gender, (value: string) => this.gender = value)
                this.fieldCell('所属社区', this.community, (value: string) => this.community = value)
                this.fieldCell('联系电话', this.phone, (value: string) => this.phone = value)
                this.fieldCell('当前住址', this.address, (value: string) => this.address = value)
                this.fieldCell('居住情况', this.living, (value: string) => this.living = value)
                this.fieldCell('联系人姓名', this.contactName, (value: string) => this.contactName = value)
                this.fieldCell('联系人电话', this.contactPhone, (value: string) => this.contactPhone = value)
              }
              .width('100%')

              if (this.showSource) {
                if (this.sourceImage) {
                  Image(this.sourceImage).width('100%').objectFit(ImageFit.Contain)
                }
                Text(this.sourceText || '未取得可展示的原文文本。')
                  .width('100%').fontSize(12).fontColor(this.p().ink).padding(10)
              }

              Text('备注事项核对').fontSize(14).fontColor(this.p().ink).width('100%')
              Text('只勾选与本次关怀有关的事项，核对后可逐条修改。')
                .fontSize(11).fontColor(this.p().muted).width('100%')
              ForEach(this.notes, (note: ReviewNote, index: number) => {
                Column({ space: 5 }) {
                  Row() {
                    Checkbox().select(note.selected).onChange((checked: boolean) => {
                      this.updateNote(index, this.notes[index].text, checked);
                    })
                    Text('采用此项').fontSize(11).fontColor(this.p().ink)
                  }.width('100%')
                  TextArea({ text: note.text }).width('100%').height(66).fontSize(13)
                    .onChange((value: string) => { this.notes[index].text = value; })
                  if (note.quote) {
                    Text('原文：' + note.quote).width('100%').fontSize(10).fontColor(this.p().muted)
                  }
                }.padding(8).width('100%').borderRadius(10).backgroundColor((this.darkMode ? '#2A2438' : '#F4EDF8'))
              }, (note: ReviewNote) => note.id)
              if (this.notes.length === 0) {
                Text('暂无候选备注。').fontSize(11).fontColor(this.p().muted).width('100%')
              }
              if (this.issues.length > 0) {
                Text('待确认').fontSize(14).fontColor(this.p().ink).width('100%')
                ForEach(this.issues, (issue: ImportIssue, index: number) => {
                  Column({ space: 4 }) {
                    Text(issue.candidatePreview || issue.message).width('100%').fontSize(12).fontColor(this.p().ink)
                    Text(issue.message).width('100%').fontSize(10).fontColor(this.p().muted)
                    if (issue.evidence?.length) {
                      Text(issue.evidence[0].quote).width('100%').fontSize(10).fontColor(this.p().muted)
                    }
                    if (issue.candidateField) {
                      Text('请在上方对应字段中核实或手填。').width('100%').fontSize(11).fontColor(this.p().ink)
                    } else {
                      TextInput({ placeholder: '核实后可手工补充，留空则忽略' })
                        .width('100%').fontSize(12)
                        .onChange((value: string) => { this.issueNotes.set(index, value.trim()); })
                    }
                  }.width('100%').padding(8).backgroundColor((this.darkMode ? this.p().surfaceSoft : '#F9EEE6')).borderRadius(8)
                })
              }
            }
            .width('100%')
            .padding(12)
            .margin({ left: 20, right: 20, top: 10 })
            .borderRadius(18)
            .backgroundColor((this.darkMode ? this.p().surface : '#FFFCF6'))
            .border({ width: 1, color: (this.darkMode ? this.p().border : '#F0DED2') })
          }
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .padding({ bottom: 96 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Row({ space: 10 }) {
        Text('▣')
          .fontSize(17)
          .fontColor(this.p().ink2)
          .width(50)
          .height(50)
          .textAlign(TextAlign.Center)
          .borderRadius(16)
          .backgroundColor((this.darkMode ? this.p().surface : 'rgba(255,253,249,0.96)'))
          .border({ width: 1, color: (this.darkMode ? this.p().border : '#EDDACC') })
        Button(this.hasResult ? '采用并建档' : (this.busy ? '识别中…' : '开始识别'))
          .layoutWeight(1)
          .height(50)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .backgroundColor(this.hasResult ? (this.darkMode ? this.p().accent : Theme.greenDeep) : '#8A9A72')
          .borderRadius(25)
          .enabled(this.hasResult)
          .onClick(() => this.adopt())
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor((this.darkMode ? this.p().pageBg : '#F8E8E2'))
  }
}

