import { readableFont, readableLineHeight } from '../model/UserPreferences';
import { router } from '@kit.ArkUI';
import { Theme, Palette, palette } from '../model/Theme';
import { Avatar, Tag } from '../components/Common';
import { Api, Person, Assessment, ResidenceInput } from '../model/Api';
import { validateResidence } from '../model/ResidenceState';
import { common } from '@kit.AbilityKit';
import { amapResidenceUrl, openAmapUrl } from '../model/AmapNavigation';
import { TopicSession, TopicRecord, topicView, readableTopicReport } from '../model/TopicInterviewState';
import { residentAvatar } from '../model/ResidentAvatar';
import { reportSources } from '../model/InterviewProgress';
import { confirmRiskAndArchive, displayFollowupTime } from '../model/RescreenWorkflow';

interface Selected {
  id: string;
  name: string;
  age: number;
  gender: string;
  community: string;
  status: string;
}

@Entry
@Component
struct Profile {
  @StorageProp('textSize') preferenceTextSize: string = 'normal';
  @StorageProp('darkMode') darkMode: boolean = false;

  private font(base: number): number { return readableFont(base, this.preferenceTextSize); }
  private line(base: number): number { return readableLineHeight(base, this.preferenceTextSize); }

  private p(): Palette {
    return palette(this.darkMode);
  }

  @State pName: string = '王秀兰';
  @State pAge: number = 72;
  @State pGender: string = '女';
  @State pCommunity: string = '青禾社区 3 栋';
  @State pAvatar: Resource = $r('app.media.avatar_f1');
  @State pStatus: string = '已建档 1 年';
  @State hasCompleted: boolean = false;
  @State aScore: string = '—';
  @State aScoreValue: number = 0;
  @State aStatus: string = '暂无已完成评估';
  @State aDate: string = '—';
  @State aCount: number = 0;
  @State hasPerson: boolean = false;
  @State isTopicInterview: boolean = true;
  @State topicDone: number = 0;
  @State reportText: string = '';
  @State sourceLines: string[] = [];
  @State recordState: string = '暂无访谈';
  @State latestSessionId: string = '';
  @State loadError: string = '';
  @State loading: boolean = false;
  @State readyForRisk: boolean = false;
  @State needsSupplement: boolean = false;
  @State supplementPlanned: boolean = false;
  @State completionDetail: string = '';
  private reviewRevision: number = 0;
  @State archivedRecord: boolean = false;
  @State nextDueText: string = '';
  @State residenceText: string = '';
  @State residenceEditable: boolean = false;
  @State residencePerson: Person | null = null;
  @State editAddress: string = '';
  @State editPhone: string = '';
  @State editLiving: string = '';
  @State editContact: string = '';
  @State editContactPhone: string = '';
  @State residenceDirty: boolean = false;
  @State residenceSaving: boolean = false;
  @State residenceMessage: string = '';
  private addressReminded: string = '';
  private personId: string = '';

  aboutToAppear(): void {
    this.load();
  }

  onPageShow(): void {
    this.load();
  }

  private async load(): Promise<void> {
    if (this.loading || this.residenceDirty || this.residenceSaving) return;
    this.loading = true;
    try {
      this.loadError = '';
      this.readyForRisk = false;
      this.needsSupplement = false; this.supplementPlanned = false; this.completionDetail = '';
      this.archivedRecord = false;
      this.nextDueText = '';
      this.residenceText = '';
      this.residencePerson = null;
      this.residenceEditable = false;
      this.latestSessionId = '';
      this.reportText = '';
      this.sourceLines = [];
      this.topicDone = 0;
      this.hasCompleted = false;
      this.isTopicInterview = true;
      this.recordState = '暂无访谈';
      this.aDate = '—';
      const raw = AppStorage.get<string>('selectedPerson');
      if (raw) {
        const selected = JSON.parse(raw) as Selected;
        this.personId = selected.id;
        this.pName = selected.name;
        this.pAge = selected.age;
        this.pGender = selected.gender.length > 0 ? selected.gender : '未填写';
        this.pCommunity = selected.community;
        this.pStatus = selected.status;
        this.pAvatar = residentAvatar(this.pGender, selected.id);
        this.hasPerson = true;
        const list: Assessment[] = await Api.assessments(selected.id);
        this.aCount = list.length;
        if (list.length > 0) {
          const params = router.getParams() as Record<string, Object>;
          const requested = (params?.['assessmentId'] as string) ?? '';
          const latest = requested ? list.find((assessment: Assessment) => assessment.id === requested) : list[0];
          if (!latest) throw new Error('指定复筛记录暂不可用，请返回名单刷新核对。');
          this.isTopicInterview = latest.scale === 'TOPIC-INTERVIEW';
          this.latestSessionId = latest.id;
          this.aDate = latest.startedAt.length >= 10 ? latest.startedAt.slice(0, 10) : latest.startedAt;
          this.aStatus = latest.status === 'completed' || latest.status === 'archived' ? '已完成' : '进行中';
          if (latest.score !== null) {
            this.hasCompleted = true;
            this.aScoreValue = latest.score;
            this.aScore = latest.score.toString();
          }
          if (this.isTopicInterview) {
            const session = await Api.getInterview(latest.id) as TopicSession | null;
            if (session !== null) {
              this.readyForRisk = session.archived || session.completed;
              this.archivedRecord = session.archived;
              if (session.nextFollowupId) {
                try {
                  const context = await Api.followupContext(session.nextFollowupId);
                  if (context.task.personId !== this.personId) throw new Error('排期人员不一致');
                  const date = displayFollowupTime(context.task.dueAt || context.task.plannedDate || '');
                  this.nextDueText = date ? '下次复筛：' + date : '下次复筛时间暂不可读，请稍后刷新。';
                } catch (e) { this.nextDueText = '下次复筛时间暂不可读，请稍后刷新。'; }
              }
              const view = topicView(session);
              this.topicDone = view.done;
              this.hasCompleted = session.completed;
              this.reviewRevision = session.revision;
              this.needsSupplement = session.completed && session.scoringEnabled === false && session.topics.some((t: TopicRecord) => t.status !== 'answered');
              this.supplementPlanned = !!session.supplementalFollowupId;
              const answered = session.topics.filter((t: TopicRecord) => t.status === 'answered').length;
              const refused = session.topics.filter((t: TopicRecord) => t.status === 'refused').length;
              this.completionDetail = '已了解 ' + answered + ' 项 · 暂未明确 ' + (session.topics.filter((t: TopicRecord) => t.status !== 'open' && t.status !== 'answered' && t.status !== 'refused').length) + ' 项 · 拒答 ' + refused + ' 项';
              if (this.needsSupplement) this.completionDetail += '\n' + session.topics.filter((t: TopicRecord) => t.status !== 'answered').map((t: TopicRecord) => t.name + '：' + (t.status === 'refused' ? '拒答，尊重本人意愿' : '暂未明确')).join('；');
              this.reportText = view.report;
              this.sourceLines = reportSources(session.summary);
              this.recordState = session.archived ? '已归档' : (session.confirmedRevision === session.revision &&
                session.summary.confirmedText !== null ? '已人工确认' : (view.report.length > 0 ? '待复核' :
                (session.completed ? '报告生成中' : '访谈进行中')));
              if (this.needsSupplement) this.recordState = this.supplementPlanned ? '已安排补充回访' : '已结束 · 信息不完整';
            }
          }
        }
        const fresh: Person | null = await Api.person(selected.id);
        if (fresh !== null) {
          this.residenceText = '当前住址：' + (fresh.address || '待补全') + '\n联系电话：' + (fresh.phone || '未填写') +
            '\n居住情况：' + (fresh.living || '未填写') + '\n联系人：' + (fresh.contactName || '未填写') +
            '\n联系人电话：' + (fresh.contactPhone || '未填写');
          this.residenceEditable = Number.isInteger(fresh.revision) && (fresh.revision ?? 0) > 0 &&
            ![fresh.address, fresh.phone, fresh.contactName || '', fresh.contactPhone || ''].some(value => value.includes('*'));
          this.residencePerson = fresh;
          this.resetResidence();
          if (!fresh.address.trim() && this.addressReminded !== fresh.id) {
            this.addressReminded = fresh.id;
            AlertDialog.show({ title: '请补充当前住所', message: '此档案缺少地址，请点击“当前地址”补充。必要的安全访谈仍可继续。',
              confirm: { value: '知道了', action: () => {} } });
          }
          this.pName = fresh.name;
          this.pAge = fresh.age;
          this.pGender = fresh.gender.length > 0 ? fresh.gender : '未填写';
          this.pAvatar = residentAvatar(this.pGender, selected.id);
          this.pCommunity = fresh.community.length > 0 ? fresh.community : this.pCommunity;
        }
      }
    } catch (e) {
      this.loadError = (e as Error).message || '无法读取档案，请重试。';
      this.hasCompleted = false;
      this.latestSessionId = '';
    } finally { this.loading = false; }
  }

  @State riskBusy: boolean = false;

  private reviewAndSupplement(): void {
    if (this.riskBusy || this.loading || this.supplementPlanned) return;
    AlertDialog.show({ title: '复核报告与未明确项',
      message: this.completionDetail + '\n\n' + this.reportText + '\n\n保留未明确及拒答记录。本次只安排补充回访，不确认风险、不常规归档；后续尊重老人意愿。',
      primaryButton: { value: '返回核对', action: () => {} },
      secondaryButton: { value: '已核对，选择回访日期', action: () => {
        DatePickerDialog.show({ start: new Date(), end: new Date(2035, 11, 31), selected: new Date(),
          onDateAccept: (value: Date) => {
            const day = value.getFullYear().toString() + '-' + (value.getMonth() + 1).toString().padStart(2, '0') + '-' + value.getDate().toString().padStart(2, '0');
            AlertDialog.show({ title: '确认补充回访', message: '安排日期：' + day + '\n不会把未明确项改为已回答，也不会默认判为无风险。',
              primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '确认安排', action: () => this.saveSupplement(day) } });
          } });
      } } });
  }

  private async saveSupplement(day: string): Promise<void> {
    if (this.riskBusy) return;
    this.riskBusy = true;
    try { await Api.reviewSupplement(this.latestSessionId, this.reviewRevision, day); await this.load();
      AlertDialog.show({ title: '已安排补充回访', message: '请在回访列表核对。原回答及未明确、拒答状态均保留。', confirm: { value: '知道了', action: () => {} } });
    } catch (e) { AlertDialog.show({ title: '未完成安排', message: (e as Error).message, confirm: { value: '知道了', action: () => {} } }); }
    finally { this.riskBusy = false; }
  }
  @State navigationBusy: boolean = false;

  private async navigateResidence(): Promise<void> {
    if (this.navigationBusy || this.residenceDirty || this.residenceSaving) return;
    this.navigationBusy = true; this.residenceMessage = '';
    try {
      const record = await Api.residenceLocation(this.personId);
      await openAmapUrl(getContext(this) as common.UIAbilityContext, amapResidenceUrl(record, this.personId, false));
    } catch (e) { this.residenceMessage = (e as Error).message || '无法打开高德，请检查地图应用或浏览器。'; }
    finally { this.navigationBusy = false; }
  }

  private resetResidence(): void {
    this.editAddress = this.residencePerson?.address || '';
    this.editPhone = this.residencePerson?.phone || '';
    this.editLiving = this.residencePerson?.living || '';
    this.editContact = this.residencePerson?.contactName || '';
    this.editContactPhone = this.residencePerson?.contactPhone || '';
    this.residenceDirty = false; this.residenceMessage = '';
  }

  private markResidence(): void {
    const p = this.residencePerson;
    this.residenceDirty = this.editAddress !== (p?.address || '') || this.editPhone !== (p?.phone || '') ||
      this.editLiving !== (p?.living || '') || this.editContact !== (p?.contactName || '') ||
      this.editContactPhone !== (p?.contactPhone || '');
  }

  private async saveResidence(): Promise<void> {
    if (!this.residenceEditable || this.residenceSaving || !this.residenceDirty || !this.residencePerson) return;
    const input: ResidenceInput = { address: this.editAddress.trim(), phone: this.editPhone.trim(),
      living: this.editLiving.trim(), contactName: this.editContact.trim(), contactPhone: this.editContactPhone.trim() };
    this.residenceMessage = validateResidence(input);
    if (this.residenceMessage) return;
    this.residenceSaving = true;
    try {
      this.residencePerson = await Api.updateResidence(this.personId, this.residencePerson.revision ?? 0, input);
      this.resetResidence(); this.residenceMessage = '已保存';
    } catch (e) { this.residenceMessage = (e as Error).message || '保存失败，填写内容已保留。'; }
    finally { this.residenceSaving = false; }
  }

  @Builder
  residenceField(label: string, value: string, change: (value: string) => void) {
    Row({ space: 10 }) {
      Text(label).fontSize(this.font(15)).fontColor(this.p().ink2).width(100)
      TextArea({ text: value, placeholder: label === '当前地址 *' ? '请输入当前住所（必填）' : '点击填写' })
        .fontSize(this.font(16)).fontColor(this.p().ink).placeholderColor(this.p().muted)
        .backgroundColor(this.p().surface).layoutWeight(1).constraintSize({ minHeight: 48 })
        .enabled(this.residenceEditable && !this.loading && !this.residenceSaving)
        .onChange((text: string) => { change(text); this.markResidence(); })
    }.width('100%').padding({ top: 8, bottom: 8 })
      .border({ width: { bottom: 1 }, color: this.p().border })
  }

  @Builder
  informationRow(label: string, value: string, page: string) {
    Row({ space: 10 }) {
      Text(label).fontSize(this.font(15)).fontColor(this.p().ink2).width(100)
      Text(value || '未填写').fontSize(this.font(16)).fontColor(this.p().ink).layoutWeight(1)
      Text('›').fontSize(this.font(22)).fontColor(this.p().accentText)
    }.width('100%').padding({ top: 15, bottom: 15 })
      .border({ width: { bottom: 1 }, color: this.p().border })
      .enabled(this.residenceEditable && !this.loading)
      .onClick(() => router.pushUrl({ url: page, params: { personId: this.personId } }))
  }

  private chooseRisk(): void {
    if (this.riskBusy) return;
    if (!this.latestSessionId || !this.hasCompleted) {
      AlertDialog.show({ title: '请先完成访谈', message: '完成后可确认风险等级并安排回访。',
        confirm: { value: '知道了', action: () => {} } });
      return;
    }
    AlertDialog.show({
      title: '工作人员确认风险',
      message: '无风险：半年后复筛。低风险：一周后复筛。中／高风险：进入重点关怀，请联系居民或家属安排就诊。',
      buttons: [
        { value: '无风险', action: () => { this.confirmRiskChoice('none'); } },
        { value: '低风险', action: () => { this.confirmRiskChoice('low'); } },
        { value: '中风险', action: () => { this.confirmRiskChoice('medium'); } },
        { value: '高风险', action: () => { this.confirmRiskChoice('high'); } }
      ]
    });
  }

  private confirmRiskChoice(level: string): void {
    if (this.riskBusy || this.loading) return;
    AlertDialog.show({ title: '确认风险与归档操作',
      message: '本次操作将提交所选风险；未归档的记录会尝试归档，并由服务端更新后续任务。',
      primaryButton: { value: '返回核对', action: () => {} },
      secondaryButton: { value: '确认提交', action: () => { this.saveRisk(level); } } });
  }

  private async saveRisk(level: string): Promise<void> {
    if (this.riskBusy) return;
    this.riskBusy = true;
    try {
      const id = this.latestSessionId;
      await confirmRiskAndArchive(id, level);
      await this.load();
      AlertDialog.show({
        title: level === 'medium' || level === 'high' ? '已进入重点关怀' : '已更新回访安排',
        message: level === 'medium' || level === 'high' ? '请联系居民或家属安排就诊，并在重点关怀名单核实就医情况。' :
          (this.nextDueText || '服务端已更新后续安排，请刷新档案核对；到期任务进入回访名单。'),
        confirm: { value: '知道了', action: () => {} }
      });
    } catch (e) {
      AlertDialog.show({ title: '未完成安排', message: (e as Error).message,
        confirm: { value: '知道了', action: () => {} } });
    } finally {
      this.riskBusy = false;
    }
  }

  private openInterview(newInterview: boolean = false): void {
    if (this.personId.length > 0) {
      const person: Selected = {
        id: this.personId, name: this.pName, age: this.pAge,
        gender: this.pGender, community: this.pCommunity, status: this.pStatus
      };
      AppStorage.setOrCreate('selectedPerson', JSON.stringify(person));
    }
    AppStorage.setOrCreate('sessionId', !newInterview ? this.latestSessionId : '');
    router.pushUrl({ url: 'pages/Interview' });
  }

  private statusImage(): Resource {
    const n = this.aScoreValue;
    if (n <= 6) return $r('app.media.status_excellent');
    if (n <= 12) return $r('app.media.status_normal');
    if (n <= 18) return $r('app.media.status_warning');
    return $r('app.media.status_overload');
  }

  private statusLabel(): string {
    const n = this.aScoreValue;
    if (n <= 6) return '状态优秀';
    if (n <= 12) return '状态正常';
    if (n <= 18) return '注意压力';
    return '压力过载';
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
              .onClick(() => {
                if (Number(router.getLength()) > 1) router.back();
                else router.replaceUrl({ url: 'pages/ResidentList' });
              })
            Text('人员档案')
              .fontSize(this.font(18))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.p().ink)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
            Text('↥').accessibilityText('导出')
              .fontSize(this.font(18))
              .fontColor(this.p().ink2)
              .width(32)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .height(52)
          .padding({ left: 10, right: 10 })

          if (this.loadError.length > 0) {
            Text(this.loadError).fontSize(this.font(15)).fontColor(this.p().ink2).padding(16)
            Button('重新读取档案').enabled(!this.loading).onClick(() => this.load())
          }

          Row({ space: 13 }) {
            Avatar({ src: this.pAvatar, diameter: 62 })
            Column({ space: 5 }) {
              Text(this.pName)
                .fontSize(this.font(19))
                .fontWeight(FontWeight.Medium)
                .fontColor(this.p().ink)
              Text(`${this.pAge} 岁 · ${this.pGender} · ${this.pCommunity}`)
                .fontSize(this.font(10))
                .fontColor(this.p().muted)
              Row({ space: 5 }) {
                Tag({ text: this.hasPerson ? '社区档案' : '高血压', kind: 'amber' })
                Tag({ text: this.hasPerson ? '家属：未填写' : '家属：女儿', kind: 'sky' })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('✎').accessibilityText('编辑')
              .fontSize(this.font(14))
              .fontColor(this.darkMode ? this.p().accentText : '#8A6338')
              .width(30)
              .height(30)
              .textAlign(TextAlign.Center)
              .borderRadius(15)
              .backgroundColor(this.darkMode ? this.p().iconA : '#F6E9DB')
          }
          .width('100%')
          .padding(14)
          .margin({ left: 20, right: 20 })
          .borderRadius(22)
          .backgroundColor((this.darkMode ? this.p().surface : '#FFFCF6'))
          .border({ width: 1, color: (this.darkMode ? this.p().border : '#F0DED1') })
          .shadow({ radius: 14, color: 'rgba(120,72,60,0.09)', offsetY: 6 })

          if (this.residenceText.length > 0) {
            Column({ space: 10 }) {
              Text('住所与联系信息').fontSize(this.font(16)).fontColor(this.p().ink)
              Text('直接在右侧填写，修改后点击保存').fontSize(this.font(13)).fontColor(this.p().muted)
              this.residenceField('当前地址 *', this.editAddress, (v: string) => this.editAddress = v)
              this.residenceField('联系电话', this.editPhone, (v: string) => this.editPhone = v)
              this.residenceField('居住情况', this.editLiving, (v: string) => this.editLiving = v)
              this.residenceField('联系人', this.editContact, (v: string) => this.editContact = v)
              this.residenceField('联系人电话', this.editContactPhone, (v: string) => this.editContactPhone = v)
              if (this.residenceMessage) { Text(this.residenceMessage).fontSize(this.font(14)).fontColor(this.p().ink2) }
              if (this.residenceDirty) {
                Row({ space: 12 }) {
                  Button(this.residenceSaving ? '保存中…' : '保存修改').backgroundColor(Theme.greenDeep).fontColor('#FFFFFF')
                    .enabled(!this.residenceSaving).onClick(() => this.saveResidence())
                  Button('取消修改').backgroundColor(this.p().iconB).fontColor(this.p().accentText)
                    .enabled(!this.residenceSaving).onClick(() => this.resetResidence())
                }
              }
              Text('地址保存后请在地图上核对上门入口；修改地址需要重新核验位置。')
                .fontSize(this.font(14)).fontColor(this.p().muted)
              Button(this.navigationBusy ? '正在打开高德…' : '导航到住所 · 高德地图').fontSize(this.font(16)).constraintSize({ minHeight: 48 })
                .backgroundColor(this.p().iconB).fontColor(this.p().accentText)
                .enabled(this.residenceEditable && !this.loading && !this.residenceDirty && !this.residenceSaving && !this.navigationBusy)
                .onClick(() => this.navigateResidence())
              Button('修改地图位置（可选）').fontSize(this.font(14)).constraintSize({ minHeight: 40 })
                .backgroundColor(this.p().iconB).fontColor(this.p().accentText).enabled(this.residenceEditable && !this.loading && !this.residenceDirty && !this.residenceSaving)
                .onClick(() => router.pushUrl({ url: 'pages/MapLocation', params: { personId: this.personId } }))
              Text('称呼与沟通').fontSize(this.font(16)).fontColor(this.p().ink).margin({ top: 12 })
              this.informationRow('偏好称呼', this.residencePerson?.preferredAddressConfirmed ? (this.residencePerson?.preferredAddress || '您好呀') : '未确认 · 使用“您好呀”', 'pages/CommunicationPreferences')
              this.informationRow('沟通方式', (this.residencePerson?.communicationNeeds || []).map((v: string) => v === 'hearing' ? '听得更清楚' : v === 'slower' ? '说慢一些' : '问题简短').join('、') || '未记录', 'pages/CommunicationPreferences')
              Text('建档备注').fontSize(this.font(16)).fontColor(this.p().ink).margin({ top: 12 })
              Text(this.residencePerson?.notes || '暂无已保存备注').fontSize(this.font(15)).fontColor(this.p().ink2).width('100%')
              Text('已保存备注会用于新建访谈的背景参考；正在进行的访谈保留开始时的资料，不会因后续修改而自动变化。')
                .fontSize(this.font(13)).fontColor(this.p().muted)
            }.width('100%').padding(18).alignItems(HorizontalAlign.Start)
              .backgroundColor(this.p().surface).borderRadius(22).margin({ top: 12 })
              .border({ width: 1, color: this.p().border })
          }

          Row({ space: 14 }) {
            Stack({ alignContent: Alignment.Center }) {
              Progress({ value: this.isTopicInterview ? this.topicDone : this.aScoreValue,
                total: this.isTopicInterview ? 7 : 24, type: ProgressType.Ring })
                .width(82)
                .height(82)
                .color(Theme.pink)
                .backgroundColor(this.darkMode ? this.p().segActive : '#F0E2D6')
                .style({ strokeWidth: 7 })
              Column({ space: 1 }) {
                Text(this.isTopicInterview ? `${this.topicDone}/7` : (this.hasCompleted ? this.aScore : '—'))
                  .fontSize(this.font(22))
                  .fontFamily('serif')
                  .fontColor(this.p().ink)
                Text(this.isTopicInterview ? '已结束话题' : '总分')
                  .fontSize(this.font(8))
                  .fontColor(this.p().muted)
              }
            }
            Column({ space: 6 }) {
              Row({ space: 7 }) {
                Text(this.isTopicInterview ? '心理关怀访谈' : (this.hasCompleted ? '评估结论 · 已归档' : '评估进行中'))
                  .fontSize(this.font(13))
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.p().ink)
                Tag({ text: this.isTopicInterview ? this.recordState : (this.hasCompleted ? '已归档' : '待评估'), kind: this.hasCompleted ? 'green' : 'amber' })
              }
              Text(this.isTopicInterview ? `最近访谈 ${this.aDate} · ${this.recordState}` :
                (this.hasCompleted ? `最近评估 ${this.aDate}，已归档。` : `最近评估 ${this.aDate} · ${this.aStatus}，尚未产生总分。`))
                .fontSize(this.font(10))
                .fontColor(this.p().segInk)
                .lineHeight(this.line(18))
              Text(this.isTopicInterview ? this.completionDetail : '✓ 分值来自人工确认 · 不作临床诊断')
                .fontSize(this.font(this.needsSupplement ? 13 : 10))
                .fontColor(this.p().muted)
              if (this.nextDueText.length > 0) {
                Text(this.nextDueText).fontSize(this.font(15)).fontColor(this.p().ink2).lineHeight(this.line(24))
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            if (this.hasCompleted && !this.isTopicInterview) {
              Column({ space: 3 }) {
                Image(this.statusImage())
                  .width(52)
                  .height(52)
                  .borderRadius(15)
                  .border({ width: 2, color: (this.darkMode ? this.p().surface : '#FFFCF6') })
                Text(this.statusLabel())
                  .fontSize(this.font(7))
                  .fontColor(this.p().segInk)
              }
            }
          }
          .width('100%')
          .padding(14)
          .margin({ left: 20, right: 20, top: 12 })
          .borderRadius(22)
          .backgroundColor((this.darkMode ? this.p().surface : '#FFFCF6'))
          .border({ width: 1, color: (this.darkMode ? this.p().border : '#F0DED1') })

          Column({ space: 8 }) {
            Row({ space: 7 }) {
              Text('✦').fontSize(this.font(12)).fontColor(this.darkMode ? '#C9B8E0' : '#6A4B7D')
              Text(this.reportText.length > 0 ? '访谈报告 · ' + this.recordState : 'AI 摘要 · 待生成')
                .fontSize(this.font(12))
                .fontColor(this.darkMode ? '#D6C6E8' : '#5F4472')
              Blank()
              Tag({ text: this.reportText.length > 0 ? 'AI 生成' : '待生成', kind: 'lilac' })
            }
            Text(this.reportText.length > 0 ? readableTopicReport(this.reportText) : (this.isTopicInterview ?
              '完成七话题访谈后查看服务端生成的报告。' :
              (this.hasCompleted ? '• 本次评估已完成；后端摘要服务未返回内容，暂不展示推断。' : '• 暂无已归档评估，完成访谈后生成摘要与依据。')))
              .fontSize(this.font(10))
              .fontColor(this.darkMode ? '#CBB9DF' : '#54415F')
              .lineHeight(this.line(18))
            ForEach(this.sourceLines, (line: string, index: number) => {
              Text(line).fontSize(this.font(11)).fontColor(this.darkMode ? '#CBB9DF' : '#54415F').lineHeight(this.line(18)).width('100%').copyOption(CopyOptions.LocalDevice)
            }, (line: string, index: number) => index + ':' + line)
            Text('')
              .fontSize(this.font(10))
              .fontColor(this.darkMode ? '#CBB9DF' : '#54415F')
              .lineHeight(this.line(18))
            Text('')
              .fontSize(this.font(10))
              .fontColor(this.darkMode ? '#CBB9DF' : '#54415F')
              .lineHeight(this.line(18))
            Row() {
              Text(this.hasCompleted ? '查看完整报告与逐项依据' : '完成访谈后可查看完整报告')
                .fontSize(this.font(9))
                .fontColor(this.darkMode ? '#B3A2C8' : '#7A6288')
              Blank()
              Text('→').accessibilityText('发送').fontSize(this.font(11)).fontColor(this.darkMode ? '#B3A2C8' : '#7A6288')
            }
            .width('100%')
            .padding({ top: 8 })
            .border({ width: { top: 1 }, color: this.darkMode ? '#3C3048' : '#E0D1EA' })
            .onClick(() => { if (this.latestSessionId.length > 0 && this.isTopicInterview) this.openInterview(); })
          }
          .alignItems(HorizontalAlign.Start)
          .padding(13)
          .margin({ left: 20, right: 20, top: 12 })
          .borderRadius(20)
          .backgroundColor(this.darkMode ? '#2A2438' : '#F4EDF8')
          .border({ width: 1, color: this.darkMode ? '#403450' : '#E5D7EE' })

          Column({ space: 2 }) {
            Row() {
              Text('评估记录')
                .fontSize(this.font(12))
                .fontWeight(FontWeight.Medium)
                .fontColor(this.p().ink)
              Blank()
              Text(`共 ${this.aCount} 次`)
                .fontSize(this.font(9))
                .fontColor(this.p().muted)
            }
            .width('100%')
            .padding({ top: 14, bottom: 8 })
            Row({ space: 10 }) {
              Circle().width(8).height(8).fill(Theme.pink)
              Column({ space: 2 }) {
                Text(this.isTopicInterview ? (this.latestSessionId.length > 0 ? `${this.aDate} · 七话题访谈` : '暂无访谈记录') :
                  (this.hasCompleted ? `${this.aDate} · 量表访谈` : '暂无评估记录'))
                  .fontSize(this.font(11))
                  .fontColor(this.p().ink)
                Text(this.isTopicInterview ? `${this.topicDone} / 7 个话题 · ${this.recordState}` :
                  (this.hasCompleted ? `总分 ${this.aScore} / 24 · 已归档` : ''))
                  .fontSize(this.font(9))
                  .fontColor(this.p().muted)
              }
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })
            .border({ width: { bottom: 1 }, color: (this.darkMode ? this.p().border : '#F0DED1') })
            Row({ space: 10 }) {
              Circle().width(8).height(8).fill(Theme.green)
              Column({ space: 2 }) {
                Text('')
                  .fontSize(this.font(11))
                  .fontColor(this.p().ink)
                Text('')
                  .fontSize(this.font(9))
                  .fontColor(this.p().muted)
              }
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })
          }
          .width('100%')
          .padding({ left: 22, right: 22 })
        }
        .width('100%')
        .padding({ bottom: 20 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Column({ space: 8 }) {
        Button(this.isTopicInterview && this.latestSessionId.length > 0 && !this.hasCompleted ? '继续访谈' : '开始访谈')
          .width('100%')
          .constraintSize({ minHeight: 48 })
          .padding({ top: 12, bottom: 12, left: 16, right: 16 })
          .fontSize(this.font(14))
          .fontColor(this.p().ink2)
          .backgroundColor((this.darkMode ? this.p().surface : '#FFFCF6'))
          .border({ width: 1, color: (this.darkMode ? this.p().border : '#F0DED1') })
          .borderRadius(25)
          .onClick(() => this.openInterview(!(this.isTopicInterview && this.latestSessionId.length > 0 && !this.hasCompleted)))
        Button(this.needsSupplement ? (this.supplementPlanned ? '已安排补充回访' : '复核报告并安排补充回访') : (this.archivedRecord ? '调整风险与回访' : '确认风险与归档'))
          .enabled(!this.loading && !this.riskBusy && this.hasCompleted && !this.supplementPlanned)
          .width('100%')
          .constraintSize({ minHeight: 48 })
          .padding({ top: 12, bottom: 12, left: 16, right: 16 })
          .fontSize(this.font(14))
          .fontColor('#FFFFFF')
          .backgroundColor(this.darkMode ? this.p().accent : Theme.greenDeep)
          .borderRadius(25)
          .onClick(() => { if (this.needsSupplement) this.reviewAndSupplement(); else this.chooseRisk(); })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 10, bottom: 16 })
      .backgroundColor(this.p().pageBg)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.darkMode ? this.p().pageBg : '#F7E7E1')
  }
}
