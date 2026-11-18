import { router } from '@kit.ArkUI';
import { Theme, Palette, palette } from '../model/Theme';
import { Avatar } from '../components/Common';
import { Api } from '../model/Api';
import { VoiceRecorder, TtsPlayer } from '../model/Voice';
import { TopicAutomation, TopicSession, TopicRecord, topicView, readableTopicReport } from '../model/TopicInterviewState';
import { InterviewEvent, analysisSteps, analysisSummary, retrievalSteps, reportSources } from '../model/InterviewProgress';
import { residentAvatar } from '../model/ResidentAvatar';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { OpeningPlayer, OpeningState } from '../model/OpeningPlayer';
import { OpeningContent } from '../model/OpeningState';
import { FIXED_OPENING_SENTENCES, fixedOpeningAudio } from '../model/FixedOpening';
import { readableFont } from '../model/UserPreferences';

interface SelectedInterviewPerson {
  id: string;
  name: string;
  age: number | string;
  gender: string;
  community: string;
}

@Entry
@Component
struct Interview {
  private p(): Palette { return palette(this.darkMode); }
  @StorageProp('textSize') settingTextSize: string = 'normal';
  @StorageProp('darkMode') darkMode: boolean = false;
  @State patientName: string = '未选择人员';
  @State pAge: string = '—';
  @State pGender: string = '—';
  @State pAvatar: Resource = $r('app.media.avatar_f2');
  @State pCommunity: string = '—';
  @State questionText: string = '正在读取话题…';
  @State topicName: string = '心理关怀话题访谈';
  @State sessionId: string = '';
  @State revision: number = 1;
  @State topicId: string = '';
  @State questionId: string = '';
  @State statusMsg: string = '';
  @State genFailed: boolean = false;
  @State retrying: boolean = false;
  @State typedAnswer: string = '';
  @State transcript: string = '';
  @State voicePanelVisible: boolean = false;
  @State voiceStatus: string = '';
  @State recording: boolean = false;
  @State ttsBusy: boolean = false;
  @State submitting: boolean = false;
  @State answered: number = 0;
  @State currentIndex: number = 0;
  @State total: number = 7;
  @State canAnswer: boolean = false;
  @State pending: boolean = false;
  @State finished: boolean = false;
  @State reportText: string = '';
  @State needsPrecheck: boolean = false;
  @State openingVisible: boolean = false;
  @State openingSentences: string[] = [];
  @State openingState: OpeningState = 'idle';
  @State openingIndex: number = -1;
  @State openingMessage: string = '';
  private openingContent: OpeningContent | null = null;
  private openingPlayer: OpeningPlayer = new OpeningPlayer();
  private openingGeneration: number = 0;
  private openingOffered: boolean = false;
  private openingSafetyTimer: number = -1;
  private openingStarted: boolean = false;
  @State recordSeconds: number = 0;
  @State analysisLines: string[] = [];
  @State reviewLines: string[] = [];
  @State ragLines: string[] = [];
  @State sourceLines: string[] = [];
  @State retrievalExpanded: boolean = false;
  @State reportPreview: string = '';
  @State analysisLive: boolean = false;
  @State analysisStage: string = '';
  private recorder: VoiceRecorder = new VoiceRecorder();
  private ttsPlayer: TtsPlayer = new TtsPlayer();
  private alive: boolean = false;
  private initialized: boolean = false;
  private epoch: number = 0;
  private readSequence: number = 0;
  private pollTimer: number = -1;
  private recordTimer: number = -1;
  private closeEvents: (() => void) | null = null;
  private streamId: string = '';
  private streamSequence: number = -1;
  private reconnectAt: number = 0;
  private analysisJobId: string = '';
  private analysisRevision: number = 0;
  private heights: number[] = [4,14,22,10,26,16,8,24,18,30,12,20,26,14,6,22,16,28,10,24,18,8,26,14,20,30,12,22,16,10,24,18];

  aboutToAppear(): void {
    this.alive = true;
    if (!this.initialized) { this.initialized = true; this.bootstrap(); }
    else { this.refresh(); }
  }

  aboutToDisappear(): void {
    this.suspend();
  }

  onPageHide(): void {
    this.suspend();
  }

  onPageShow(): void {
    this.alive = true;
    if (this.openingVisible) this.watchOpeningSafety();
    if (this.initialized && this.sessionId.length > 0) this.refresh();
  }

  private suspend(): void {
    this.alive = false;
    this.stopPolling();
    clearInterval(this.recordTimer);
    this.recorder.cancel();
    this.ttsPlayer.stop();
    this.stopOpening();
    this.recording = false;
    this.voicePanelVisible = false;
    this.ttsBusy = false;
  }

  private stopPolling(): void {
    this.epoch++;
    clearTimeout(this.pollTimer);
    this.stopEvents();
  }

  private stopEvents(): void {
    const close = this.closeEvents;
    this.closeEvents = null;
    if (close) close();
    this.streamId = '';
    this.streamSequence = -1;
    this.analysisLive = false;
  }

  private reconnectEvents(): void {
    this.stopEvents();
    this.reconnectAt = Date.now() + 2500;
    if (this.alive && this.pending) this.refresh();
  }

  private startEvents(): void {
    if (this.closeEvents || Date.now() < this.reconnectAt) return;
    try {
      this.closeEvents = Api.subscribeInterview(this.sessionId, (event: InterviewEvent) => {
        if (this.alive) this.receiveEvent(event);
      }, () => this.reconnectEvents());
    } catch (e) {
      this.reconnectAt = Date.now() + 2500;
    }
  }

  private showAnalysis(job: TopicAutomation, revision: number): void {
    if (revision < this.analysisRevision) return;
    const jobId = job.jobId ?? '';
    if (jobId !== this.analysisJobId || revision !== this.analysisRevision) this.reportPreview = '';
    this.analysisJobId = jobId;
    this.analysisRevision = revision;
    this.analysisStage = job.stage ?? '';
    this.analysisLines = analysisSteps(job);
    this.ragLines = retrievalSteps(job);
  }

  private receiveEvent(event: InterviewEvent): void {
    if (event.interviewId !== this.sessionId) return;
    if (event.streamId === this.streamId && event.seq <= this.streamSequence) return;
    if (event.type !== 'snapshot' && (event.streamId !== this.streamId || event.seq !== this.streamSequence + 1)) {
      this.reconnectEvents();
      return;
    }
    this.streamId = event.streamId;
    this.streamSequence = event.seq;
    this.analysisLive = true;
    if (event.type === 'snapshot' && event.session) {
      const session = event.session;
      if (session.revision < this.analysisRevision) return;
      if (!topicView(session).pending) {
        this.reportPreview = '';
        this.refresh();
        return;
      }
      this.showAnalysis(session.automation, session.revision);
      this.reportPreview = this.analysisStage === 'summary' ? (event.preview ?? '').slice(0, 32000) : '';
      if (session.revision > this.revision) this.refresh();
    } else if (event.type === 'delta' && event.target === 'summary' && this.analysisStage === 'summary' &&
      event.jobId === this.analysisJobId && event.basedOnRevision === this.analysisRevision &&
      typeof event.text === 'string' && this.reportPreview.length + event.text.length <= 32000) {
      this.reportPreview += event.text;
    } else if (event.type === 'stage' && event.automation && event.revision !== undefined) {
      this.showAnalysis(event.automation, event.revision);
      if (event.revision > this.revision) this.refresh();
    } else if (['committed', 'failed', 'interrupted'].includes(event.type)) {
      this.reportPreview = '';
      if (event.automation && event.revision !== undefined) this.showAnalysis(event.automation, event.revision);
      this.refresh();
    }
  }

  private draftKey(questionId: string): string {
    return 'topicDraft:' + this.sessionId + ':' + questionId;
  }

  private async bootstrap(): Promise<void> {
    this.submitting = true;
    try {
      const raw = AppStorage.get<string>('selectedPerson');
      const selected = raw ? JSON.parse(raw) as SelectedInterviewPerson : null;
      if (selected !== null) {
        this.patientName = selected.name;
        this.pAge = selected.age.toString();
        this.pGender = selected.gender || '未填写';
        this.pAvatar = residentAvatar(this.pGender, selected.id);
        this.pCommunity = selected.community || '未填写';
      }
      const existing = AppStorage.get<string>('sessionId') ?? '';
      if (existing.length > 0) {
        this.sessionId = existing;
        AppStorage.setOrCreate('sessionId', '');
      } else {
        if (selected === null || selected.id.length === 0) {
          this.statusMsg = '请先返回名单选择人员。';
          return;
        }
        const created = await Api.startInterview(selected.id);
        if (created === null) throw new Error('无法创建访谈，请检查登录与连接。');
        this.sessionId = created.id;
      }
      const data = await Api.getInterview(this.sessionId) as TopicSession | null;
      if (data === null) throw new Error('无法读取访谈，请重新登录后重试。');
      if (raw && selected !== null && !data.completed && !data.archived) {
        AppStorage.setOrCreate('widgetInterviewId', this.sessionId);
        AppStorage.setOrCreate('widgetInterviewResident', raw);
      }
      await this.refresh();
    } catch (e) { this.statusMsg = (e as Error).message; }
    finally { this.submitting = false; }
  }

  private async refresh(): Promise<void> {
    if (!this.alive || this.sessionId.length === 0) return;
    clearTimeout(this.pollTimer);
    const epoch = this.epoch;
    const sequence = ++this.readSequence;
    try {
      const data = await Api.getInterview(this.sessionId) as TopicSession | null;
      if (!this.alive || epoch !== this.epoch || sequence !== this.readSequence) return;
      if (data === null) throw new Error('登录已失效，请重新登录。');
      const view = topicView(data);
      const openingAllowed = data.precheckDone && !data.completed && !data.archived && !data.paused &&
        !data.safety.blocked && !data.topics.some((topic: TopicRecord) => topic.turns.length > 0);
      if (!openingAllowed && this.openingVisible) this.closeOpening();
      else if (openingAllowed && !this.openingOffered) this.offerOpening(data);
      this.revision = data.revision;
      this.needsPrecheck = data.scale === 'TOPIC-INTERVIEW' && data.workflow === 'automatic' &&
        data.topics.length === 7 && !data.precheckDone && !data.archived && !data.paused && !data.safety.blocked;
      this.total = view.total;
      this.answered = view.done;
      this.currentIndex = view.current;
      this.topicId = view.topicId;
      this.topicName = view.topicName;
      if (view.questionId !== this.questionId) {
        this.recorder.cancel();
        this.ttsPlayer.stop();
        this.recording = false;
        this.voicePanelVisible = false;
        clearInterval(this.recordTimer);
        this.questionId = view.questionId;
        this.typedAnswer = view.questionId.length > 0 ? (AppStorage.get<string>(this.draftKey(view.questionId)) ?? '') : '';
        this.transcript = '';
      }
      this.questionText = view.question || (view.completed ? '七个话题已结束。' : '正在准备访谈问题…');
      this.canAnswer = view.canAnswer;
      this.pending = view.pending;
      this.genFailed = view.retry;
      this.finished = view.completed;
      this.reportText = view.report;
      this.sourceLines = reportSources(data.summary);
      this.statusMsg = view.message;
      if (view.pending) {
        this.reviewLines = [];
        if (!this.analysisLive || data.revision > this.analysisRevision) this.showAnalysis(data.automation, data.revision);
        this.startEvents();
        this.pollTimer = setTimeout(() => { this.refresh(); }, this.analysisLive ? 5000 : 1000);
      } else {
        this.stopEvents();
        this.reportPreview = '';
        const showDetails = view.canAnswer || view.retry || (view.completed && view.report.length > 0);
        this.analysisLines = showDetails ? analysisSteps(data.automation) : [];
        this.ragLines = showDetails ? retrievalSteps(data.automation) : [];
        this.analysisStage = data.automation.stage ?? '';
        this.reviewLines = view.canAnswer ? analysisSummary(data) : [];
      }
    } catch (e) {
      if (this.alive && epoch === this.epoch && sequence === this.readSequence) {
        this.canAnswer = false;
        this.statusMsg = '状态读取失败，已提交的回答不要重复发送。' + (e as Error).message;
        if (this.pending) this.pollTimer = setTimeout(() => { this.refresh(); }, 2000);
      }
    }
  }

  private async retry(): Promise<void> {
    if (this.retrying || this.submitting || this.sessionId.length === 0) return;
    this.retrying = true;
    this.stopPolling();
    try { await Api.retryInterview(this.sessionId, this.revision); await this.refresh(); }
    catch (e) { await this.refresh(); this.statusMsg = (e as Error).message; }
    finally { this.retrying = false; }
  }

  private qFontSize(): number {
    const size = this.settingTextSize;
    return size === 'extra' ? 25 : (size === 'large' ? 22 : 19);
  }

  private async playQuestion(): Promise<void> {
    if (this.openingVisible || !this.canAnswer || this.ttsBusy || this.recording || this.submitting) return;
    this.ttsBusy = true;
    const questionId = this.questionId;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const path = await Api.tts(context, this.sessionId, questionId, this.revision);
      if (!this.alive || this.questionId !== questionId || this.submitting || !this.canAnswer) return;
      if (!await this.ttsPlayer.play(context, path, AppStorage.get<number>('ttsRate') ?? 1)) {
        throw new Error('音频播放失败，请检查音量或重试。');
      }
      this.statusMsg = '';
    } catch (e) { if (this.alive) this.statusMsg = (e as Error).message; }
    finally { this.ttsBusy = false; }
  }

  private async toggleRecord(): Promise<void> {
    if (this.openingVisible) return;
    if (this.recording) {
      this.recording = false;
      clearInterval(this.recordTimer);
      this.voiceStatus = '正在整理录音，核对文字后再提交…';
      await this.recorder.finish();
      return;
    }
    if (!this.canAnswer || this.submitting || this.recorder.isBusy()) return;
    this.transcript = '';
    this.recordSeconds = 0;
    this.voicePanelVisible = true;
    if (!(AppStorage.get<boolean>('voiceConsent') ?? false)) {
      this.voiceStatus = '请在右上角设置中开启云端语音授权，也可直接打字回答。';
      return;
    }
    this.voiceStatus = '正在检查麦克风权限…';
    const context = getContext(this) as common.UIAbilityContext;
    let permissionGranted = false;
    try {
      const permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE']);
      permissionGranted = permission.authResults[0] === 0;
    } catch (e) {
      this.voiceStatus = '麦克风授权未完成，可直接文字输入。';
      return;
    }
    if (!this.alive || !this.canAnswer || !permissionGranted) {
      this.voiceStatus = '未获得麦克风权限，可直接文字输入。';
      return;
    }
    await this.ttsPlayer.stop();
    const questionId = this.questionId;
    const original = this.typedAnswer.trim();
    this.voiceStatus = '正在连接语音服务…';
    const started = await this.recorder.start(this.sessionId, questionId, this.revision,
      (text: string) => { if (this.alive && questionId === this.questionId) this.transcript = text; },
      (text: string) => {
        if (!this.alive || questionId !== this.questionId) return;
        clearInterval(this.recordTimer);
        this.recording = false;
        this.transcript = text;
        this.typedAnswer = [original, text.trim()].filter((value: string) => value.length > 0).join('\n');
        AppStorage.setOrCreate(this.draftKey(questionId), this.typedAnswer);
        this.voiceStatus = text.trim().length > 0 ? '已录入回答，请核对或修改后提交。' : '没有识别到内容，可重录或打字。';
      },
      (message: string) => {
        if (!this.alive || questionId !== this.questionId) return;
        clearInterval(this.recordTimer);
        this.recording = false;
        this.voiceStatus = message;
      });
    if (!this.alive || questionId !== this.questionId) { this.recorder.cancel(); return; }
    this.recording = started;
    if (started) {
      this.voiceStatus = '正在聆听，再次点击结束';
      this.recordTimer = setInterval(() => {
        this.recordSeconds++;
        if (this.recordSeconds >= 180) this.toggleRecord();
      }, 1000);
    }
  }

  private async submitAnswer(): Promise<void> {
    if (this.openingVisible) return;
    if (this.submitting || this.recorder.isBusy() || !this.canAnswer) return;
    const answer = this.typedAnswer.trim();
    if (answer.length === 0) { this.statusMsg = '请先输入回答，或使用语音转成文字。'; return; }
    this.submitting = true;
    this.stopPolling();
    const questionId = this.questionId;
    try {
      await this.ttsPlayer.stop();
      await Api.submitTurn(this.sessionId, this.revision, this.topicId, questionId, answer);
      AppStorage.setOrCreate(this.draftKey(questionId), '');
      this.typedAnswer = '';
      this.transcript = '';
      this.voicePanelVisible = false;
      await this.refresh();
    } catch (e) {
      await this.refresh();
      this.statusMsg = (e as Error).message + ' 已保留原问题的文字草稿，请先刷新状态。';
    } finally { this.submitting = false; }
  }

  private primaryAction(): void {
    if (this.openingVisible) return;
    if (this.submitting || this.retrying || this.pending) return;
    if (this.needsPrecheck) {
      AlertDialog.show({
        title: '开始前确认', message: '请确认已获得本次访谈同意，并完成安全与沟通条件核查。',
        primaryButton: { value: '返回核对', action: () => {} },
        secondaryButton: { value: '确认开始', action: async () => {
          if (this.submitting) return;
          this.submitting = true;
          try { await Api.precheckInterview(this.sessionId, this.revision); await this.refresh(); }
          catch (e) { this.statusMsg = (e as Error).message; }
          finally { this.submitting = false; }
        } }
      });
      return;
    }
    if (this.genFailed) { this.retry(); return; }
    if (this.finished && !this.pending) { this.returnToCaller(); return; }
    if (!this.canAnswer) { this.refresh(); return; }
    this.submitAnswer();
  }

  private returnToCaller(): void {
    if (Number(router.getLength()) > 1) router.back();
    else router.replaceUrl({ url: 'pages/ResidentList' });
  }

  private stopOpening(): void {
    clearInterval(this.openingSafetyTimer);
    this.openingSafetyTimer = -1;
    this.openingGeneration++;
    this.openingPlayer.stop();
    this.openingState = 'idle';
    this.openingIndex = -1;
    this.openingStarted = false;
  }

  private watchOpeningSafety(): void {
    clearInterval(this.openingSafetyTimer);
    this.openingSafetyTimer = setInterval(() => {
      if (this.alive && this.openingVisible) this.refresh();
    }, 1000);
  }

  private closeOpening(): void {
    this.openingVisible = false;
    this.stopOpening();
  }

  private async offerOpening(session: TopicSession): Promise<void> {
    this.openingOffered = true;
    const generation = ++this.openingGeneration;
    if (session.openingText) {
      this.openingSentences = FIXED_OPENING_SENTENCES;
      this.openingVisible = true;
      this.watchOpeningSafety();
    }
    this.openingMessage = '';
    try {
      const content = await Api.opening(this.sessionId);
      if (!this.alive || generation !== this.openingGeneration) return;
      this.openingContent = content;
      this.openingSentences = FIXED_OPENING_SENTENCES;
      this.openingVisible = true;
      this.watchOpeningSafety();
      this.playOpening();
    } catch (e) {
      if (this.alive && generation === this.openingGeneration) this.openingMessage = '开场语音暂未准备好，您可阅读文字并开始答题。';
    }
  }

  private async playOpening(): Promise<void> {
    if (!this.alive || !this.openingVisible) return;
    const generation = ++this.openingGeneration;
    this.openingMessage = '';
    this.openingState = 'loading';
    this.openingIndex = -1;
    this.openingStarted = false;
    try {
      await this.openingPlayer.stop();
      const content = await Api.opening(this.sessionId);
      if (!this.alive || !this.openingVisible || generation !== this.openingGeneration) return;
      this.openingContent = content;
      this.openingSentences = FIXED_OPENING_SENTENCES;
      this.recorder.cancel(); this.recording = false;
      await this.ttsPlayer.stop();
      if (!this.alive || !this.openingVisible || generation !== this.openingGeneration) return;
      if (this.openingIsPaused()) return;
      const context = getContext(this) as common.UIAbilityContext;
      this.openingStarted = true;
      await this.openingPlayer.start(1,
        async (index: number): Promise<string> => {
          if (!this.alive || !this.openingVisible || generation !== this.openingGeneration) throw new Error('开场已停止。');
          return fixedOpeningAudio(context);
        },
        1,
        (state: OpeningState, index: number, error: string) => {
          if (!this.alive || !this.openingVisible || generation !== this.openingGeneration) return;
          this.openingState = state;
          if (state === 'playing') this.openingIndex = -1;
          else if (state !== 'paused') this.openingIndex = -1;
          this.openingMessage = error;
        });
    } catch (e) {
      if (this.alive && this.openingVisible && generation === this.openingGeneration) {
        this.openingState = 'error';
        this.openingMessage = '开场音频暂时无法播放，您可阅读文字并开始答题。';
      }
    }
  }

  private openingIsPaused(): boolean {
    return this.openingState === 'paused';
  }

  private async toggleOpening(): Promise<void> {
    try {
      if (this.openingState === 'playing' || this.openingState === 'loading') {
        this.openingState = 'paused';
        await this.openingPlayer.pause();
      } else if (this.openingState === 'paused') {
        if (this.openingStarted) await this.openingPlayer.resume();
        else this.playOpening();
      }
      else this.playOpening();
    } catch (e) { this.openingState = 'error'; this.openingMessage = '播放未完成，可重播或开始答题。'; }
  }

  @Builder
  openingDialog() {
    Column({ space: 14 }) {
      Text('暖邻语音助手').fontSize(readableFont(20, this.settingTextSize)).fontColor(this.p().ink)
      Scroll() {
        Column({ space: 10 }) {
          ForEach(this.openingSentences, (sentence: string, index: number) => {
            Text(sentence).width('100%').fontSize(readableFont(18, this.settingTextSize))
              .fontColor(index === this.openingIndex ? this.p().accentText : this.p().ink)
              .fontWeight(index === this.openingIndex ? FontWeight.Bold : FontWeight.Normal)
              .padding(10).borderRadius(12)
              .backgroundColor(index === this.openingIndex ? this.p().iconB : Color.Transparent)
          }, (sentence: string, index: number) => index + ':' + sentence)
          if (this.openingMessage) { Text(this.openingMessage).fontSize(readableFont(16, this.settingTextSize)).fontColor(this.p().ink2) }
          if (this.openingState === 'loading') { Text('正在准备语音…').fontSize(readableFont(16, this.settingTextSize)).fontColor(this.p().muted) }
          if (this.openingState === 'ended') { Text('开场播放结束，可以开始答题。').fontSize(readableFont(16, this.settingTextSize)).fontColor(this.p().muted) }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').align(Alignment.Top)
      Button('开始答题').width('100%').constraintSize({ minHeight: 48 }).fontSize(readableFont(16, this.settingTextSize))
        .backgroundColor(this.darkMode ? '#6F4852' : '#F4D5DE').fontColor(this.darkMode ? '#FFF2F5' : '#754353').onClick(() => this.closeOpening())
    }.width('92%').height('85%').padding(20).borderRadius(24).backgroundColor(this.p().surface)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
    Column() {
      Scroll() {
        Column() {
          Row() {
            Text('‹').accessibilityText('返回')
              .fontSize(26)
              .fontColor(this.p().ink)
              .width(32)
              .textAlign(TextAlign.Center)
              .onClick(() => this.returnToCaller())
            Text('心理关怀访谈')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.p().ink)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
            Text('⋮')
              .onClick(() => router.pushUrl({ url: 'pages/Settings' }))
              .fontSize(18)
              .fontColor(this.p().ink2)
              .width(32)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .height(52)
          .padding({ left: 10, right: 10 })

          Row({ space: 10 }) {
            Avatar({ src: this.pAvatar, diameter: 38 })
            Column({ space: 2 }) {
              Text(this.patientName)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.p().ink)
              Text(`${this.pAge} 岁 · ${this.pGender} · ${this.pCommunity}`)
                .fontSize(9)
                .fontColor(this.p().muted)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding(10)
          .margin({ left: 20, right: 20 })
          .borderRadius(16)
          .backgroundColor((this.darkMode ? this.p().surface : 'rgba(255,252,247,0.8)'))
          .border({ width: 1, color: (this.darkMode ? this.p().border : '#EFDCD2') })

          Row() {
            Text('访谈进度')
              .fontSize(9)
              .fontColor((this.darkMode ? this.p().section : '#9C7E66'))
            Blank()
            Text(`${this.answered} / ${this.total} 个话题`)
              .fontSize(9)
              .fontColor('#5C6B45')
          }
          .width('100%')
          .padding({ left: 22, right: 22, top: 14, bottom: 6 })

          Row({ space: 3 }) {
            ForEach(Array.from({ length: this.total }, (_: number, i: number) => i), (i: number) => {
              Row()
                .layoutWeight(1)
                .height(5)
                .borderRadius(3)
                .backgroundColor(i < this.answered ? Theme.green : (!this.finished && i === this.currentIndex ? Theme.pink : (this.darkMode ? this.p().border : '#EBD8CC')))
            }, (i: number) => i.toString())
          }
          .width('100%')
          .padding({ left: 22, right: 22 })

          Column({ space: 8 }) {
            Row() {
              Text(this.topicName)
                .fontSize(9)
                .fontColor((this.darkMode ? this.p().muted : '#B08A72'))
                .letterSpacing(1)
              Blank()
              Text(this.ttsBusy ? '◍ 生成中…' : '◍ 听问题')
                .fontSize(9)
                .fontColor((this.darkMode ? this.p().accentText : '#8A6338'))
                .padding({ left: 8, right: 8, top: 5, bottom: 5 })
                .borderRadius(12)
                .backgroundColor((this.darkMode ? this.p().iconA : '#F6E9DD'))
                .onClick(() => this.playQuestion())
            }
            .width('100%')
            Text(this.questionText)
              .fontSize(this.qFontSize())
              .fontFamily('serif')
              .fontColor(this.p().ink)
              .lineHeight(31)
              .width('100%')
            if (this.statusMsg.length > 0) {
            Text(this.statusMsg.length > 0 ? this.statusMsg : '模型生成失败')
              .fontSize(9)
              .fontColor((this.darkMode ? this.p().danger : '#9C4A45'))
              .width('100%')
          }
          Text('ⓘ 可慢慢说，访谈会记录原始回答并保留依据')
              .fontSize(9)
              .fontColor(this.p().muted)
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .padding(15)
          .margin({ left: 20, right: 20, top: 12 })
          .borderRadius(20)
          .backgroundColor((this.darkMode ? this.p().surface : '#FFFCF6'))
          .border({ width: 1, color: (this.darkMode ? this.p().border : '#F2DFD2') })
          .shadow({ radius: 12, color: 'rgba(120,72,60,0.08)', offsetY: 5 })

          if (this.pending || this.analysisLines.length > 0 || this.reviewLines.length > 0) {
            Column({ space: 7 }) {
              Row({ space: 7 }) {
                Circle().width(6).height(6).fill(this.pending ? Theme.pink : Theme.green)
                Text(this.analysisStage === 'summary' ? '报告生成过程' : 'AI 分析过程')
                  .fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.p().ink)
                Blank()
                if (this.pending && this.analysisLive) {
                  Text('实时更新').fontSize(9).fontColor('#5C6B45')
                }
              }.width('100%')
              ForEach(this.analysisLines, (line: string) => {
                Text(line).fontSize(10).lineHeight(16).fontColor((this.darkMode ? this.p().ink2 : '#795D49')).width('100%')
              }, (line: string) => line)
              ForEach(this.reviewLines, (line: string, index: number) => {
                Text(line).fontSize(11).lineHeight(18).fontColor(this.p().ink).width('100%')
              }, (line: string, index: number) => `${index}:${line}`)
              if (this.ragLines.length > 0) {
                Button(this.retrievalExpanded ? '收起处理与检索过程' : '查看处理与检索过程')
                  .fontSize(12).fontColor(Theme.green).backgroundColor(Color.Transparent)
                  .onClick(() => this.retrievalExpanded = !this.retrievalExpanded)
                if (this.retrievalExpanded) {
                  ForEach(this.ragLines, (line: string, index: number) => {
                    Text(line).fontSize(11).fontColor(this.p().ink).lineHeight(18).width('100%')
                  }, (line: string, index: number) => index + ':' + line)
                }
              }
              if (this.pending && this.reportPreview.length > 0) {
                Text('报告草稿 · 正在生成').fontSize(10).fontColor((this.darkMode ? this.p().ink2 : '#795D49')).width('100%')
                Text(readableTopicReport(this.reportPreview)).fontSize(11).lineHeight(18)
                  .fontColor(this.p().ink).width('100%')
              }
            }
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .margin({ left: 20, right: 20, top: 10 })
            .borderRadius(16)
            .backgroundColor((this.darkMode ? this.p().surface : '#FFF9F0'))
            .border({ width: 1, color: (this.darkMode ? this.p().border : '#EDDCD0') })
          }

          if (this.finished && this.reportText.length > 0) {
            Column({ space: 8 }) {
              Text('本次访谈报告').fontSize(18).fontColor(this.p().ink)
              Text(readableTopicReport(this.reportText)).fontSize(this.qFontSize() - 3).lineHeight(26).fontColor(this.p().ink)
              ForEach(this.sourceLines, (line: string, index: number) => {
                Text(line).fontSize(12).fontColor(this.p().ink2).lineHeight(19).width('100%').copyOption(CopyOptions.LocalDevice)
              }, (line: string, index: number) => index + ':' + line)
            }.width('100%').padding(16).margin({ top: 12 }).backgroundColor((this.darkMode ? this.p().surfaceSoft : Theme.cream)).borderRadius(20)
          }
          Button('刷新状态').fontSize(12).height(44).backgroundColor(Color.Transparent).fontColor(this.p().ink2)
            .enabled(!this.submitting).onClick(() => this.refresh())
        }
        .width('100%')
        .padding({ bottom: 12 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)

      Column({ space: 8 }) {
        if (this.canAnswer) {
          if (this.voicePanelVisible) {
            Column({ space: 6 }) {
              Row({ space: 6 }) {
                Circle().width(6).height(6).fill(Theme.pink)
                Text(this.voiceStatus)
                  .layoutWeight(1)
                  .fontSize(10)
                  .fontColor((this.darkMode ? this.p().segInk : '#8A6B54'))
                Text(`${this.recordSeconds} 秒`)
                  .fontSize(9)
                  .fontColor((this.darkMode ? this.p().segInk : '#8A6B54'))
              }
              .width('100%')
              Row({ space: 3 }) {
                ForEach(this.heights, (h: number, i: number) => {
                  Row()
                    .layoutWeight(1)
                    .height(h)
                    .borderRadius(4)
                    .backgroundColor('#C9A98F')
                }, (h: number, i: number) => i.toString())
              }
              .width('100%')
              .height(32)
              .alignItems(VerticalAlign.Center)
              if (this.transcript.length > 0) {
                Text(this.transcript)
                  .fontSize(11)
                  .fontColor(this.p().ink)
                  .lineHeight(20)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .width('100%')
            .padding(12)
            .borderRadius(16)
            .backgroundColor((this.darkMode ? this.p().surface : 'rgba(255,255,255,0.76)'))
            .border({ width: 1, color: (this.darkMode ? this.p().border : '#EDDCD0') })
          }
          Row({ space: 8 }) {
            Column({ space: 0 }) {
              Text('◉').accessibilityText('语音输入')
                .fontSize(18)
                .fontColor('#FFFFFF')
              Text(')))')
                .fontSize(7)
                .fontColor('rgba(255,255,255,0.9)')
            }
            .width(44)
            .height(44)
            .justifyContent(FlexAlign.Center)
            .borderRadius(22)
            .backgroundColor(Theme.pink)
            .shadow({ radius: 10, color: 'rgba(167,94,114,0.24)', offsetY: 4 })
            .onClick(() => this.toggleRecord())

            Row() {
              TextArea({ placeholder: '输入老人原话…', text: this.typedAnswer })
                .layoutWeight(1)
                .height(42)
                .fontSize(12)
                .fontColor(this.p().ink)
                .placeholderColor((this.darkMode ? this.p().segSub : '#B39A85'))
                .backgroundColor(Color.Transparent)
                .border({ width: 0 })
                .padding({ left: 0, right: 0, top: 9, bottom: 9 })
                .enabled(this.canAnswer && !this.submitting && !this.recorder.isBusy())
                .onChange((v: string) => { this.typedAnswer = v; AppStorage.setOrCreate(this.draftKey(this.questionId), v); })
              Button('↑').width(34).height(34).padding(0).fontSize(20)
                .backgroundColor((this.darkMode ? this.p().accent : Theme.greenDeep)).fontColor(Color.White).accessibilityText('提交回答')
                .enabled(this.canAnswer && !this.submitting && !this.recording && this.typedAnswer.trim().length > 0)
                .onClick(() => this.submitAnswer())
            }
            .layoutWeight(1)
            .height(46)
            .padding({ left: 14, right: 8 })
            .borderRadius(23)
            .backgroundColor((this.darkMode ? this.p().surface : '#FFFDF8'))
            .border({ width: 1, color: (this.darkMode ? this.p().border : '#EBDCCF') })

          }
          .width('100%')
        }
        Column() {
          Text(this.needsPrecheck ? '开始前确认' : (this.genFailed ? '重试处理' : (this.pending ? '正在处理…' : (this.finished ? '返回' : (this.canAnswer ? '提交回答' : '刷新状态')))))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
          Text('核对原话后提交 · 自动进入追问或下一话题')
            .fontSize(8)
            .fontColor('rgba(255,255,255,0.82)')
        }
        .width('100%')
        .height(52)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .borderRadius(26)
        .backgroundColor((this.darkMode ? this.p().accent : Theme.greenDeep))
        .enabled(!this.submitting && !this.retrying && !this.pending)
        .onClick(() => this.primaryAction())
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 8, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor((this.darkMode ? this.p().pageBg : '#FBF2ED'))
    if (this.openingVisible) {
      Column() { this.openingDialog() }
        .width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('rgba(0,0,0,0.45)')
    }
    }.width('100%').height('100%')
  }
}
