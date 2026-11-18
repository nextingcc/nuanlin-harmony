import { router } from '@kit.ArkUI';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { VoiceRecorder } from '../model/Voice';
import { picker, fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { util } from '@kit.ArkTS';
import { assistantDeviceId, executeAssistantMemo } from '../model/AssistantMemoStore';
import { Theme, Palette, palette } from '../model/Theme';
import { Api, Person } from '../model/Api';
import { AssistantConversation, AssistantMessage, AssistantSource, PendingAssistantMessage,
  pendingAssistantMessage, lastAssistantConversationId, appendAssistantDictation, AssistantAction,
  AssistantActionPayload, AssistantDuplicate, AssistantAttachment } from '../model/AssistantChat';
import { readableFont } from '../model/UserPreferences';
import { AssistantHistoryItem, AssistantHistoryMessage, readAssistantHistory, rememberAssistantConversation,
  renameAssistantConversation, forgetAssistantConversation } from '../model/AssistantHistory';
import { loadAvatar } from '../model/UserAvatar';
import { image } from '@kit.ImageKit';

const PERSONA_BG: string = '#FFF7EA';
const BUBBLE_PINK: string = 'rgba(251,231,234,0.78)';
const BUBBLE_CREAM: string = 'rgba(253,241,242,0.92)';
const BROWN: string = '#5B3A2A';
const BROWN_SOFT: string = '#8A6A54';
const DOT_GREEN: string = '#9DBE97';
const ICON_PINK: string = '#E39AA8';
const ICON_GREEN: string = '#9DBE97';
const ICON_YELLOW: string = '#EFD08C';

@Entry
@Component
struct Assistant {
  @StorageProp('darkMode') darkMode: boolean = false;
  @StorageProp('textSize') textSize: string = 'normal';
  @State conversation: AssistantConversation | null = null;
  @State input: string = '';
  @State busy: boolean = false;
  @State error: string = '';
  @State pending: PendingAssistantMessage | null = null;
  @State selecting: boolean = false;
  @State people: Person[] = [];
  @State personName: string = '';
  @State voicePhase: string = '';
  @State voicePreview: string = '';
  @State voiceError: string = '';
  @State voiceLevel: number = 0;
  @State editingActionId: string = '';
  @State editingKind: string = '';
  @State editingRevision: number = 0;
  @State editFields: string[] = [];
  @State duplicateAckId: string = '';
  @State historyOpen: boolean = false;
  @State historyItems: AssistantHistoryItem[] = [];
  @State historyQuery: string = '';
  @State userAvatarPm: image.PixelMap | undefined = undefined;
  @State hoveredId: string = '';
  @State renameOpen: boolean = false;
  @State renameId: string = '';
  @State renameText: string = '';
  @State renameOriginal: string = '';
  @State contextOpen: boolean = false;
  @State contextTitle: string = '';
  @State contextId: string = '';
  @State contextMessages: AssistantHistoryMessage[] = [];
  @State attachMenuOpen: boolean = false;
  @State attachBusy: boolean = false;
  @State attachError: string = '';
  @State attachmentName: string = '';
  @State attachmentText: string = '';
  @State attachmentChars: number = 0;
  @State actionStatus: string = '';
  private voiceRun: number = 0;
  private voiceTimer: number = -1;
  private active: boolean = true;
  private recorder: VoiceRecorder = new VoiceRecorder();
  private generation: number = 0;
  private scroller: Scroller = new Scroller();
  @State expandedActionIds: string[] = [];
  @State streamingText: string = '';

  private messageActions(messageId: string): AssistantAction[] {
    return (this.conversation?.actions || []).filter((action: AssistantAction) =>
      this.conversation?.messages.find((message: AssistantMessage) => (message.actionIds || []).includes(action.id))?.id === messageId);
  }

  private orphanActions(): AssistantAction[] {
    return (this.conversation?.actions || []).filter((action: AssistantAction) =>
      !this.conversation?.messages.some((message: AssistantMessage) => (message.actionIds || []).includes(action.id)));
  }

  private toggleActionDetails(id: string): void {
    this.expandedActionIds = this.expandedActionIds.includes(id) ? this.expandedActionIds.filter((value: string) => value !== id) :
      this.expandedActionIds.concat([id]);
  }
  private inputController: TextAreaController = new TextAreaController();

  private p(): Palette { return palette(this.darkMode); }
  private bg(): string { return this.darkMode ? this.p().pageBg : PERSONA_BG; }
  private ink(): string { return this.darkMode ? this.p().ink : BROWN; }
  private ink2(): string { return this.darkMode ? this.p().ink2 : BROWN_SOFT; }
  private bubble(): string { return this.darkMode ? this.p().surface : BUBBLE_PINK; }
  private bubbleSoft(): string { return this.darkMode ? this.p().surfaceSoft : BUBBLE_CREAM; }

  private historyList(): AssistantHistoryItem[] {
    const q = this.historyQuery.trim();
    if (q.length === 0) return this.historyItems;
    return this.historyItems.filter((item: AssistantHistoryItem) => item.title.indexOf(q) >= 0);
  }

  private historyTime(item: AssistantHistoryItem): string {
    const d = new Date(item.updatedAt);
    const month = (d.getMonth() + 1).toString().padStart(2, '0');
    const day = d.getDate().toString().padStart(2, '0');
    const hour = d.getHours().toString().padStart(2, '0');
    const minute = d.getMinutes().toString().padStart(2, '0');
    return month + '-' + day + ' ' + hour + ':' + minute;
  }

  private async refreshHistory(): Promise<void> {
    this.historyItems = await readAssistantHistory(getContext(this) as common.UIAbilityContext);
  }

  private titleOf(conversation: AssistantConversation): string {
    for (let i = 0; i < conversation.messages.length; i++) {
      const message = conversation.messages[i];
      if (message.role === 'user' && message.text.trim().length > 0) return message.text.trim();
    }
    return conversation.messages.length > 0 ? conversation.messages[0].text.trim() : '新对话';
  }

  private remember(): void {
    const conversation = this.conversation;
    if (!conversation || conversation.messages.length === 0) return;
    const messages: AssistantHistoryMessage[] = conversation.messages.map((message: AssistantMessage) => {
      const entry: AssistantHistoryMessage = { role: message.role, text: message.text };
      return entry;
    });
    rememberAssistantConversation(getContext(this) as common.UIAbilityContext, conversation.id,
      this.titleOf(conversation), Date.now(), messages).then(() => this.refreshHistory()).catch(() => {});
  }

  private beginRename(item: AssistantHistoryItem): void {
    this.renameId = item.id;
    this.renameText = '';
    this.renameOriginal = item.title;
    this.renameOpen = true;
  }

  private async confirmRename(): Promise<void> {
    if (this.renameId.length === 0 || this.renameText.trim().length === 0) return;
    await renameAssistantConversation(getContext(this) as common.UIAbilityContext, this.renameId, this.renameText);
    this.renameOpen = false;
    this.renameId = '';
    await this.refreshHistory();
  }

  private async openHistory(item: AssistantHistoryItem): Promise<void> {
    if (this.busy || this.voicePhase) return;
    this.historyOpen = false;
    this.contextOpen = false;
    this.busy = true;
    try {
      const conversation = await Api.assistantConversation(item.id);
      this.accept(conversation);
    } catch (e) {
      // 服务端会话不可用时，展示本机保存的上下文快照，至少能回看聊过什么。
      this.contextTitle = item.title;
      this.contextId = item.id;
      this.contextMessages = item.messages;
      this.contextOpen = true;
      this.error = '';
    } finally {
      this.busy = false;
    }
  }

  private async removeHistory(item: AssistantHistoryItem): Promise<void> {
    await forgetAssistantConversation(getContext(this) as common.UIAbilityContext, item.id);
    await this.refreshHistory();
  }

  private optionPrompt(index: number): string {
    const prompts: string[] = [
      '请根据这位老人的已有资料，帮我准备回访时的开场和沟通建议，并标明来源。',
      '我想了解一位居民的历史记录，请先帮我确认是哪位居民。',
      '我想为一位老人建档，请先告诉我需要提供哪些信息。',
      '我想添加一条本地备忘录，请先询问事项和是否需要提醒时间。',
      '我想安排上门回访计划，请先和我确认日期、出发与结束时间，以及步行还是驾车。'
    ];
    return index >= 0 && index < prompts.length ? prompts[index] : prompts[0];
  }

  private actionTint(kind: string): string {
    if (this.darkMode) return this.p().surfaceSoft;
    if (kind === 'create_visit_plan') return '#EDF4E8';
    if (kind === 'create_person') return '#FBF1DA';
    return '#FBE7EA';
  }

  private readBytes(uri: string): ArrayBuffer | undefined {
    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const size = fileIo.statSync(file.fd).size;
      if (size <= 0 || size > 5 * 1024 * 1024) return undefined;
      const buffer = new ArrayBuffer(size);
      const read = fileIo.readSync(file.fd, buffer);
      return read === size ? buffer : buffer.slice(0, read);
    } finally {
      fileIo.closeSync(file);
    }
  }

  private async compressImage(bytes: ArrayBuffer, name: string): Promise<ArrayBuffer> {
    try {
      const source = image.createImageSource(bytes);
      const info = await source.getImageInfo();
      const width = info.size.width;
      const height = info.size.height;
      if (Math.max(width, height) <= 1280) {
        source.release();
        return bytes;
      }
      const scale = 1280 / Math.max(width, height);
      const pixelMap = await source.createPixelMap({
        desiredSize: { width: Math.round(width * scale), height: Math.round(height * scale) }
      });
      const packer = image.createImagePacker();
      const format = name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      const packed = await packer.packing(pixelMap, { format: format, quality: 82 });
      packer.release();
      pixelMap.release();
      source.release();
      return packed;
    } catch (e) {
      return bytes;
    }
  }

  private clearAttachment(): void {
    this.attachmentName = '';
    this.attachmentText = '';
    this.attachmentChars = 0;
    this.attachError = '';
  }

  private async attachExampleImage(): Promise<void> {
    if (this.attachBusy || this.busy || this.voicePhase) return;
    this.attachMenuOpen = false;
    try {
      this.attachBusy = true;
      this.attachError = '';
      const context = getContext(this) as common.UIAbilityContext;
      const bytes = await context.resourceManager.getRawFileContent('nuanlin-demo-case.png');
      const base64 = new util.Base64Helper().encodeToStringSync(bytes);
      const result = await Api.extractAssistantAttachment('示例病例.png', base64);
      const text = (result['text'] as string) || '';
      if (text.length === 0) throw new Error('示例资料没有读到文字。');
      this.attachmentName = (result['name'] as string) || '示例病例.png';
      this.attachmentText = text;
      this.attachmentChars = (result['chars'] as number) || text.length;
      if (this.input.trim().length === 0) this.input = '请阅读这份示例资料，帮我核对并准备建档草稿：';
    } catch (e) {
      this.attachError = (e as Error).message || '示例资料读取失败。';
    } finally {
      this.attachBusy = false;
    }
  }

  private async importImageToPerson(): Promise<void> {
    if (this.attachBusy || this.busy || this.voicePhase) return;
    this.attachMenuOpen = false;
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const picked = await new photoAccessHelper.PhotoViewPicker().select(options);
      if (!picked.photoUris || picked.photoUris.length === 0) return;
      const context = getContext(this) as common.UIAbilityContext;
      const name = '建档资料-' + Date.now().toString() + '.jpg';
      const dest = context.cacheDir + '/' + name;
      const source = fileIo.openSync(picked.photoUris[0], fileIo.OpenMode.READ_ONLY);
      try {
        fileIo.copyFileSync(source.fd, dest);
      } finally {
        fileIo.closeSync(source);
      }
      router.pushUrl({ url: 'pages/ImportPerson', params: { path: dest, name: name } });
    } catch (e) {
      this.attachError = (e as Error).message || '读取图片失败，请重试。';
    }
  }

  private async pickAttachment(image: boolean): Promise<void> {
    if (this.attachBusy || this.busy || this.voicePhase) return;
    this.attachMenuOpen = false;
    try {
      let uri = '';
      let name = '';
      if (image) {
        const options = new photoAccessHelper.PhotoSelectOptions();
        options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
        options.maxSelectNumber = 1;
        const picked = await new photoAccessHelper.PhotoViewPicker().select(options);
        if (!picked.photoUris || picked.photoUris.length === 0) return;
        uri = picked.photoUris[0];
        name = '图片-' + Date.now().toString() + '.jpg';
      } else {
        const options = new picker.DocumentSelectOptions();
        options.maxSelectNumber = 1;
        const uris = await new picker.DocumentViewPicker().select(options);
        if (!uris || uris.length === 0) return;
        uri = uris[0];
        const parts = uri.split('/');
        name = decodeURIComponent(parts[parts.length - 1] || '资料');
      }
      this.attachBusy = true;
      this.attachError = '';
      const raw = this.readBytes(uri);
      if (raw === undefined) throw new Error('附件需小于 5MB，且能正常读取。');
      const bytes = await this.compressImage(raw, name);
      if (bytes.byteLength > 5 * 1024 * 1024) throw new Error('压缩后仍超过 5MB，请换一张图片。');
      const base64 = new util.Base64Helper().encodeToStringSync(new Uint8Array(bytes));
      const result = await Api.extractAssistantAttachment(name, base64);
      const text = (result['text'] as string) || '';
      if (text.length === 0) throw new Error('没有从这份资料里读到文字。');
      this.attachmentName = (result['name'] as string) || name;
      this.attachmentText = text;
      this.attachmentChars = (result['chars'] as number) || text.length;
      if (this.input.trim().length === 0) this.input = '请阅读这份资料并提炼要点：';
    } catch (e) {
      this.attachError = (e as Error).message || '附件读取失败，请换一份资料。';
    } finally {
      this.attachBusy = false;
    }
  }

  private font(base: number): number { return readableFont(base, this.textSize); }
  private pink(): string { return this.darkMode ? '#3A292D' : Theme.pinkSoft; }
  private yellow(): string { return this.darkMode ? '#342D20' : '#F7EBCB'; }

  onBackPress(): boolean {
    if (this.historyOpen) {
      this.historyOpen = false;
      return true;
    }
    return false;
  }

  private async reloadUserAvatar(): Promise<void> {
    this.userAvatarPm = await loadAvatar(getContext(this) as common.UIAbilityContext);
  }

  onPageShow(): void { this.active = true; this.reloadUserAvatar(); this.load(); }
  onPageHide(): void {
    this.active = false;
    this.cancelVoice();
    this.generation++;
    this.busy = false;
    this.conversation = null;
    this.pending = null;
    this.input = '';
    this.personName = '';
    this.people = [];
    this.selecting = false;
    this.editingActionId = '';
    this.editFields = [];
    this.duplicateAckId = '';
    this.actionStatus = '';
  }
  aboutToDisappear(): void { this.active = false; this.cancelVoice(); this.generation++; }

  private cancelVoice(): void {
    this.voiceRun++;
    clearTimeout(this.voiceTimer);
    this.recorder.cancel();
    this.voicePhase = '';
    this.voicePreview = '';
    this.voiceError = '';
    this.voiceLevel = 0;
  }

  private finishVoice(): void {
    if (this.voicePhase !== 'recording') return;
    clearTimeout(this.voiceTimer);
    this.voicePhase = 'transcribing';
    this.recorder.finish();
  }

  private async startVoice(): Promise<void> {
    if (!this.active || this.busy || this.pending || this.selecting || !this.conversation ||
      this.conversation.inflight || this.voicePhase || this.editingActionId) return;
    const run = ++this.voiceRun;
    this.voiceError = '';
    this.voicePreview = '';
    this.voiceLevel = 0;
    this.inputController.stopEditing();
    if (!(AppStorage.get<boolean>('voiceConsent') ?? false)) {
      this.voicePhase = 'consent';
      AlertDialog.show({
        title: '语音输入',
        message: '录音将发送至讯飞语音服务转成文字。转写后可以修改，点击发送才会交给AI助手。',
        primaryButton: { value: '取消', action: () => { if (run === this.voiceRun) this.cancelVoice(); } },
        secondaryButton: { value: '同意并录音', action: () => {
          if (!this.active || run !== this.voiceRun) return;
          AppStorage.setOrCreate('voiceConsent', true);
          this.voicePhase = '';
          this.startVoice();
        } }
      });
      return;
    }
    this.voicePhase = 'permission';
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context,
        ['ohos.permission.MICROPHONE']);
      if (!this.active || run !== this.voiceRun) return;
      if (permission.authResults[0] !== 0) {
        this.cancelVoice();
        this.voiceError = '未获得麦克风权限，可以在系统设置中开启，或直接打字。';
        return;
      }
      this.voicePhase = 'connecting';
      const started = await this.recorder.startDictation((text: string) => {
        if (this.active && run === this.voiceRun) this.voicePreview = text;
      }, (text: string) => {
        if (!this.active || run !== this.voiceRun) return;
        this.cancelVoice();
        try { this.input = appendAssistantDictation(this.input, text); }
        catch (e) { this.voicePreview = text; this.voiceError = (e as Error).message; }
      }, (message: string) => {
        if (!this.active || run !== this.voiceRun) return;
        const preview = this.voicePreview;
        this.cancelVoice();
        this.voicePreview = preview;
        this.voiceError = message + ' 原输入已保留，可重试或打字。';
      }, (level: number) => {
        if (this.active && run === this.voiceRun) this.voiceLevel = Math.max(0, Math.min(1, level));
      });
      if (started && this.active && run === this.voiceRun) {
        this.voicePhase = 'recording';
        this.voiceTimer = setTimeout(() => this.finishVoice(), 60000);
      } else if (this.active && run === this.voiceRun) {
        this.cancelVoice();
        this.voiceError = '语音未能开始，请重试或打字。';
      }
    } catch (e) {
      if (!this.active || run !== this.voiceRun) return;
      this.cancelVoice();
      this.voiceError = '无法开启语音，请检查麦克风权限或使用文字输入。';
    }
  }

  private async load(): Promise<void> {
    if (this.selecting) return;
    const generation = ++this.generation;
    this.busy = true;
    this.error = '';
    try {
      const id = this.conversation?.id || lastAssistantConversationId();
      let conversation: AssistantConversation;
      if (id) {
        try {
          conversation = await Api.assistantConversation(id);
        } catch (readError) {
          const message = (readError as Error).message || '';
          // 后端重启或换环境后旧会话已不存在：自动开一个新会话，避免输入框一直不可用。
          if (message.includes('不存在') || message.includes('404')) {
            conversation = await Api.createAssistantConversation();
          } else {
            throw readError as Error;
          }
        }
      } else {
        conversation = await Api.createAssistantConversation();
      }
      if (generation !== this.generation) return;
      this.accept(conversation);
      if (conversation.personId) {
        const person = await Api.person(conversation.personId);
        if (generation === this.generation) this.personName = person?.name || '当前居民';
      }
    } catch (e) {
      if (generation === this.generation) this.error = (e as Error).message || '对话读取失败，请重试。';
    } finally { if (generation === this.generation) this.busy = false; }
  }

  private accept(value: AssistantConversation): void {
    this.conversation = value;
    AppStorage.setOrCreate('assistantConversationId', value.id);
    this.selecting = false;
    this.remember();
    this.scrollEnd();
    if (value.inflight) {
      const generation = this.generation;
      setTimeout(() => { if (generation === this.generation) this.load(); }, 1600);
    }
  }

  private scrollEnd(): void {
    const generation = this.generation;
    setTimeout(() => {
      if (generation === this.generation) this.scroller.scrollEdge(Edge.Bottom);
    }, 80);
  }

  private async fresh(personId: string = '', name: string = ''): Promise<void> {
    if (this.busy || this.voicePhase) return;
    this.cancelVoice();
    this.inputController.stopEditing();
    const generation = ++this.generation;
    this.busy = true;
    this.error = '';
    try {
      const conversation = await Api.createAssistantConversation(personId);
      if (generation !== this.generation) return;
      this.personName = name;
      this.pending = null;
      this.input = '';
      this.editingActionId = '';
      this.duplicateAckId = '';
      this.accept(conversation);
    } catch (e) {
      if (generation === this.generation) this.error = (e as Error).message || '新对话创建失败。';
    } finally { if (generation === this.generation) this.busy = false; }
  }

  private async choose(): Promise<void> {
    if (this.busy || this.pending || this.voicePhase) return;
    const generation = ++this.generation;
    this.selecting = true;
    this.busy = true;
    this.error = '';
    try {
      const people = await Api.people();
      if (generation === this.generation) this.people = people;
    } catch (e) {
      if (generation === this.generation) this.error = (e as Error).message || '档案读取失败。';
    } finally { if (generation === this.generation) this.busy = false; }
  }

  private async send(retry: boolean = false): Promise<void> {
    const conversation = this.conversation;
    if (this.busy || this.selecting || !conversation || this.voicePhase || this.editingActionId) return;
    if (!retry && this.pending) return;
    try {
      if (!retry) {
      const attachments: AssistantAttachment[] = [];
      if (this.attachmentText.length > 0) {
        const item: AssistantAttachment = { name: this.attachmentName, text: this.attachmentText };
        attachments.push(item);
      }
      this.pending = pendingAssistantMessage(this.input, attachments);
      this.input = '';
    }
    } catch (e) { this.error = (e as Error).message; return; }
    const pending = this.pending;
    if (!pending) return;
    this.inputController.stopEditing();
    const generation = ++this.generation;
    this.busy = true;
    this.error = '';
    this.scrollEnd();
    try {
      this.streamingText = '';
      const result = await Api.sendAssistantMessage(conversation.id, pending, (text: string) => {
        if (generation === this.generation) { this.streamingText = text; this.scrollEnd(); }
      });
      if (generation !== this.generation) return;
      this.pending = null;
      this.clearAttachment();
      this.accept(result);
    } catch (e) {
      if (generation === this.generation) this.error = (e as Error).message || '暂时没有收到回答，请重试。';
    } finally { if (generation === this.generation) { this.busy = false; this.streamingText = ''; } }
  }

  private async openSource(source: AssistantSource): Promise<void> {
    if (this.busy || this.voicePhase) return;
    try {
      const person = await Api.person(source.personId);
      if (!person || person.id !== source.personId) throw new Error('该资料不可访问，请重新查询。');
      AppStorage.setOrCreate('selectedPerson', JSON.stringify(person));
      router.pushUrl({ url: 'pages/Profile', params: { assessmentId: source.assessmentId || '' } });
    } catch (e) { this.error = (e as Error).message || '来源暂时无法打开。'; }
  }

  private editAction(action: AssistantAction): void {
    if (this.busy || this.voicePhase || action.status !== 'draft') return;
    const p = action.payload;
    this.editingActionId = action.id;
    this.editingKind = action.kind;
    this.editingRevision = action.revision;
    this.editFields = action.kind === 'create_memo' ? [p.text || '', p.dueAt || ''] :
      [p.name || '', p.age === null || p.age === undefined ? '' : p.age.toString(), p.gender || '',
        p.community || '', p.address || '', p.phone || '', p.living || '', p.contactName || '', p.contactPhone || '', p.notes || ''];
    this.error = '';
  }

  private changeEditField(index: number, value: string): void {
    const fields = this.editFields.slice(); fields[index] = value; this.editFields = fields;
  }

  private replaceAction(action: AssistantAction): void {
    if (!this.conversation) return;
    this.conversation = { id: this.conversation.id, personId: this.conversation.personId,
      messages: this.conversation.messages, revision: this.conversation.revision, inflight: this.conversation.inflight,
      actions: (this.conversation.actions || [])
      .map((existing: AssistantAction) => existing.id === action.id ? action : existing) };
    this.duplicateAckId = '';
  }

  private async saveActionEdit(): Promise<void> {
    if (this.busy || !this.editingActionId) return;
    let payload: AssistantActionPayload;
    if (this.editingKind === 'create_memo') {
      payload = { text: this.editFields[0], dueAt: this.editFields[1] };
    } else {
      const age = this.editFields[1].trim();
      if (age && (!/^\d{1,3}$/.test(age) || Number(age) > 120)) {
        this.error = '请填写0～120岁的整数年龄，未知可以暂留空。'; return;
      }
      payload = { name: this.editFields[0], age: age ? Number(age) : null, gender: this.editFields[2],
        community: this.editFields[3], address: this.editFields[4], phone: this.editFields[5],
        living: this.editFields[6], contactName: this.editFields[7], contactPhone: this.editFields[8], notes: this.editFields[9] };
    }
    const generation = ++this.generation;
    this.busy = true; this.error = ''; this.actionStatus = '正在保存草稿…';
    try {
      const result = await Api.updateAssistantAction(this.editingActionId, this.editingRevision, payload);
      if (generation !== this.generation) return;
      this.replaceAction(result); this.editingActionId = '';
    } catch (e) { if (generation === this.generation) this.error = (e as Error).message || '草稿保存失败，修改已保留。'; }
    finally { if (generation === this.generation) { this.busy = false; this.actionStatus = ''; } }
  }

  private async runAction(action: AssistantAction, cancel: boolean = false): Promise<void> {
    if (this.busy || this.voicePhase || this.editingActionId) return;
    if (!cancel && action.kind === 'create_person' && action.status === 'draft' && !action.payload.address?.trim()) {
      AlertDialog.show({ title: '请补充当前住所', message: '建档必须填写已核实的居住地址，请先编辑草稿补充地址。',
        confirm: { value: '返回补充', action: () => {} } });
      return;
    }
    const generation = ++this.generation;
    this.busy = true; this.error = ''; this.actionStatus = cancel ? '正在取消草稿…' : '正在确认操作…';
    let localSaved = false;
    try {
      const deviceId = action.kind === 'create_memo' ? assistantDeviceId() : '';
      let result = cancel ? await Api.cancelAssistantAction(action) :
        await Api.confirmAssistantAction(action, deviceId, this.duplicateAckId === action.id);
      if (generation !== this.generation) return;
      this.replaceAction(result);
      if (!cancel && result.kind === 'create_memo' && result.status === 'awaiting_device') {
        this.actionStatus = '正在保存到本机备忘录…';
        let memoId: string;
        try { memoId = await executeAssistantMemo(result, Api.assistantOwnerKey()); localSaved = true; }
        catch (e) {
          if (generation === this.generation && Api.assistantOwnerKey() === result.ownerKey) {
            try { this.replaceAction(await Api.receiptAssistantAction(result, deviceId, '', '本机保存失败，请重试。')); }
            catch (ignored) {}
          }
          throw new Error('本机备忘录保存未完成，未显示成功。请重试。');
        }
        if (generation !== this.generation || Api.assistantOwnerKey() !== result.ownerKey) return;
        this.actionStatus = '正在核对保存回执…';
        result = await Api.receiptAssistantAction(result, deviceId, memoId);
        if (generation !== this.generation) return;
        this.replaceAction(result);
      }
    } catch (e) {
      if (generation !== this.generation) return;
      this.error = localSaved ? '备忘录已写入本机，但回执暂未送达。点击继续本机保存可安全重试，不会重复添加。' :
        ((e as Error).message || '操作未完成，请重试。');
      if (this.conversation) {
        try {
          const latest = await Api.assistantConversation(this.conversation.id);
          if (generation === this.generation) { this.conversation = latest; this.duplicateAckId = ''; }
        } catch (ignored) {}
      }
    } finally { if (generation === this.generation) { this.busy = false; this.actionStatus = ''; } }
  }

  private actionSummary(action: AssistantAction): string {
    const p = action.payload;
    if (action.kind === 'create_visit_plan') return '日期：' + (p.date || '待补充') + '\n时间：' +
      (p.startTime || '待补充') + '～' + (p.endTime || '待补充') + '（武汉时间）\n方式：' +
      (p.transport === 'driving' ? '驾车' : '步行') + '\n结束：' + (p.returnToStart ? '返回出发点' : '最后一站结束');
    if (action.kind === 'create_memo') return (p.text || '内容待补充') + '\n时间：' + (p.dueAt || '不设提醒时间') + '（武汉时间）';
    return '姓名：' + (p.name || '待补充') + '\n年龄：' + (p.age === null || p.age === undefined ? '待补充' : p.age.toString()) +
      '\n性别：' + (p.gender || '未填写') + '\n社区：' + (p.community || '未填写') + '\n住所：' + (p.address || '未填写') +
      '\n电话：' + (p.phone || '未填写') + '\n居住情况：' + (p.living || '未填写') +
      '\n联系人：' + (p.contactName || '未填写') + '\n联系人电话：' + (p.contactPhone || '未填写') + '\n备注：' + (p.notes || '未填写');
  }

  private async openCreatedPerson(id: string): Promise<void> {
    await this.openSource({ id: 'created:' + id, label: '已建档人员', personId: id });
  }

  private openVisitPlan(action: AssistantAction): void {
    if (this.busy || this.voicePhase || this.editingActionId) return;
    router.pushUrl({ url: 'pages/VisitPlan', params: { actionId: action.id } });
  }

  @Builder
  private editorField(label: string, index: number) {
    Column({ space: 6 }) {
      Text(label).fontSize(this.font(14)).fontColor(this.p().ink2)
      if (index === 9 || (this.editingKind === 'create_memo' && index === 0)) {
        TextArea({ text: this.editFields[index] || '', placeholder: '未填写' }).height(110)
          .fontSize(this.font(16)).fontColor(this.p().ink).backgroundColor(this.p().surfaceSoft)
          .placeholderColor(this.p().muted).borderRadius(14).maxLength(this.editingKind === 'create_memo' ? 1000 : 5000)
          .enabled(!this.busy).onChange((value: string) => this.changeEditField(index, value))
      } else {
        TextInput({ text: this.editFields[index] || '', placeholder: this.editingKind === 'create_memo' ? 'YYYY-MM-DD HH:mm，留空不提醒' : '未填写' })
          .fontSize(this.font(16)).fontColor(this.p().ink).backgroundColor(this.p().surfaceSoft)
          .placeholderColor(this.p().muted).borderRadius(14).height(50).maxLength(500)
          .enabled(!this.busy).onChange((value: string) => this.changeEditField(index, value))
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private actionCard(action: AssistantAction) {
    Column({ space: 12 }) {
      Text(action.kind === 'create_visit_plan' ? '回访计划' : (action.kind === 'create_person' ? '建档草稿' : '本地备忘录草稿'))
        .fontSize(this.font(19)).fontWeight(FontWeight.Medium).fontColor(this.p().ink)
      Text(action.status === 'completed' ? (action.result?.message || '执行完成，已收到回执') :
        (action.status === 'cancelled' ? '已取消，未执行' :
          (action.status === 'awaiting_device' ? '已确认，等待本机保存回执' : '待核对 · 尚未执行')))
        .fontSize(this.font(14)).fontColor(this.p().accentText)
      if (this.editingActionId === action.id) {
        if (action.kind === 'create_memo') {
          this.editorField('事项内容', 0)
          this.editorField('提醒时间 · 武汉时间', 1)
        } else {
          ForEach(['姓名', '年龄', '性别', '社区', '详细住所', '联系电话', '居住情况', '联系人', '联系人电话', '备注'],
            (label: string, index: number) => { this.editorField(label, index) }, (label: string) => label)
        }
        Button('保存修改后的草稿').width('100%').constraintSize({ minHeight: 48 }).fontSize(this.font(16))
          .backgroundColor(Theme.greenDeep).fontColor('#FFFFFF').borderRadius(16).enabled(!this.busy)
          .onClick(() => this.saveActionEdit())
        Button('放弃修改').width('100%').constraintSize({ minHeight: 44 }).fontSize(this.font(15))
          .backgroundColor(this.p().surfaceSoft).fontColor(this.p().ink2).borderRadius(16).enabled(!this.busy)
          .onClick(() => { this.editingActionId = ''; this.editFields = []; })
      } else {
        Text(this.actionSummary(action)).fontSize(this.font(16)).fontColor(this.p().ink2)
          .lineHeight(this.font(26)).width('100%').copyOption(CopyOptions.LocalDevice)
          .maxLines(this.expandedActionIds.includes(action.id) ? 300 : (action.status === 'cancelled' || action.status === 'completed' ? 1 : 4))
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Button(this.expandedActionIds.includes(action.id) ? '收起详情' : '展开详情')
          .fontSize(this.font(14)).fontColor(this.p().accentText).backgroundColor(this.p().surfaceSoft)
          .onClick(() => this.toggleActionDetails(action.id))
      }
      if (action.kind === 'create_visit_plan' && action.status !== 'cancelled') {
        Text('核对到期任务、住所位置和预约后，按实际道路耗时规划。未安排对象会单独列出。')
          .fontSize(this.font(14)).fontColor(this.p().ink2)
        Button(action.status === 'completed' ? '打开已保存计划与导航' : '核对人员并规划路线')
          .width('100%').constraintSize({ minHeight: 48 }).fontSize(this.font(16))
          .backgroundColor(Theme.greenDeep).fontColor('#FFFFFF').borderRadius(16)
          .enabled(!this.busy && !this.voicePhase && !this.editingActionId).onClick(() => this.openVisitPlan(action))
        if (action.status === 'draft') {
          Button('取消计划草稿').width('100%').constraintSize({ minHeight: 44 }).fontSize(this.font(15))
            .backgroundColor(this.p().surfaceSoft).fontColor(this.p().ink2).borderRadius(16)
            .enabled(!this.busy && !this.voicePhase && !this.editingActionId).onClick(() => this.runAction(action, true))
        }
      }
      if (action.status === 'draft' && action.kind !== 'create_visit_plan' && this.editingActionId !== action.id) {
        if (action.duplicates.length > 0) {
          Column({ space: 8 }) {
            Text('发现疑似重复档案，请先核对').fontSize(this.font(15)).fontColor(this.p().ink)
            ForEach(action.duplicates, (person: AssistantDuplicate) => {
              Text(person.name + ' · ' + person.age + '岁 · ' + (person.community || '社区未填写'))
                .fontSize(this.font(14)).fontColor(this.p().ink2)
              Button('查看已有档案').fontSize(this.font(14)).backgroundColor(this.p().surface)
                .fontColor(this.p().accentText).borderRadius(14).enabled(!this.busy && !this.voicePhase)
                .onClick(() => this.openCreatedPerson(person.id))
            }, (person: AssistantDuplicate) => person.id)
            Row({ space: 8 }) {
              Checkbox({ name: 'duplicate-' + action.id }).select(this.duplicateAckId === action.id)
                .selectedColor(Theme.greenDeep).enabled(!this.busy)
                .onChange((value: boolean) => { this.duplicateAckId = value ? action.id : ''; })
              Text('已核对，确需另建档案').fontSize(this.font(14)).fontColor(this.p().ink).layoutWeight(1)
            }
          }.padding(12).width('100%').alignItems(HorizontalAlign.Start).backgroundColor(this.yellow()).borderRadius(16)
        }
        Button('编辑草稿').width('100%').constraintSize({ minHeight: 44 }).fontSize(this.font(15))
          .backgroundColor(this.p().surfaceSoft).fontColor(this.p().ink2).borderRadius(16)
          .enabled(!this.busy && !this.voicePhase).onClick(() => this.editAction(action))
        Button(action.kind === 'create_person' ? '确认创建档案' : '确认添加到本机备忘录')
          .width('100%').constraintSize({ minHeight: 48 }).fontSize(this.font(16)).backgroundColor(Theme.greenDeep)
          .fontColor('#FFFFFF').borderRadius(16).enabled(!this.busy && !this.voicePhase && !this.editingActionId &&
            (action.duplicates.length === 0 || this.duplicateAckId === action.id)).onClick(() => this.runAction(action))
        Button('取消草稿').width('100%').constraintSize({ minHeight: 44 }).fontSize(this.font(15))
          .backgroundColor(this.p().surfaceSoft).fontColor(this.p().ink2).borderRadius(16)
          .enabled(!this.busy && !this.voicePhase && !this.editingActionId).onClick(() => this.runAction(action, true))
      }
      if (action.status === 'awaiting_device') {
        Text(action.result?.message || '请在确认的这台设备继续完成保存，未收到回执前不会显示成功。')
          .fontSize(this.font(14)).fontColor(this.p().ink2)
        Button('继续本机保存并回传结果').width('100%').constraintSize({ minHeight: 48 }).fontSize(this.font(16))
          .backgroundColor(Theme.greenDeep).fontColor('#FFFFFF').borderRadius(16)
          .enabled(!this.busy && !this.voicePhase).onClick(() => this.runAction(action))
      }
      if (action.status === 'completed') {
        if (action.result?.personId) {
          Button('查看已创建的档案').width('100%').constraintSize({ minHeight: 44 }).fontSize(this.font(15))
            .backgroundColor(this.p().iconB).fontColor(this.p().accentText).borderRadius(16)
            .enabled(!this.busy && !this.voicePhase).onClick(() => this.openCreatedPerson(action.result?.personId || ''))
        }
        if (action.result?.memoId && action.deviceId === assistantDeviceId()) {
          Button('打开本机备忘录').width('100%').constraintSize({ minHeight: 44 }).fontSize(this.font(15))
            .backgroundColor(this.p().iconB).fontColor(this.p().accentText).borderRadius(16)
            .onClick(() => router.pushUrl({ url: 'pages/Memo' }))
        }
      }
    }.padding(18).width('100%').alignItems(HorizontalAlign.Start).backgroundColor(this.actionTint(action.kind))
      .border({ width: 1, color: this.p().border }).borderRadius(22)
  }

  @Builder
  private personaHead(size: number) {
    Image($r('app.media.assistant_persona_head'))
      .width(size).height(size).borderRadius(size / 2)
      .objectFit(ImageFit.Cover)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: 'rgba(227,154,168,0.45)' })
  }

  @Builder
  private userBadge(size: number) {
    if (this.userAvatarPm !== undefined) {
      Image(this.userAvatarPm).width(size).height(size).borderRadius(size / 2)
        .objectFit(ImageFit.Cover)
        .border({ width: 1, color: 'rgba(227,154,168,0.5)' })
        .accessibilityText('我的头像')
    } else {
      Text('用').fontSize(12).fontColor(this.ink2()).width(size).height(size)
        .textAlign(TextAlign.Center).borderRadius(size / 2)
        .backgroundColor(this.darkMode ? this.p().iconB : '#F5E4D6')
    }
  }

  @Builder
  private messageCard(message: AssistantMessage) {
    if (message.role === 'user') {
      Row({ space: 8 }) {
        Blank()
        Text(message.text).fontSize(this.font(16)).fontColor(this.ink())
          .lineHeight(this.font(25)).copyOption(CopyOptions.LocalDevice)
          .constraintSize({ maxWidth: '76%' })
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundColor(this.bubbleSoft())
          .border({ width: 1, color: 'rgba(227,154,168,0.35)' })
          .borderRadius({ topLeft: 18, topRight: 18, bottomLeft: 18, bottomRight: 6 })
        this.userBadge(30)
      }.width('100%').alignItems(VerticalAlign.Top)
    } else {
      Row({ space: 8 }) {
        this.personaHead(34)
        Column({ space: 6 }) {
          Text('小暖').fontSize(this.font(11)).fontColor(ICON_PINK)
          Text(message.text).fontSize(this.font(16)).fontColor(this.ink())
            .lineHeight(this.font(25)).copyOption(CopyOptions.LocalDevice)
          if (message.sources.length > 0) {
            Text('资料来源 · 点击核对').fontSize(this.font(11)).fontColor(this.ink2())
            ForEach(message.sources, (source: AssistantSource) => {
              Button(source.label + (source.date ? ' · ' + source.date.slice(0, 10) : ''))
                .fontSize(this.font(12)).fontColor(this.ink2())
                .backgroundColor(this.darkMode ? this.p().surfaceSoft : '#F7E7C3')
                .borderRadius(14).constraintSize({ minHeight: 38 })
                .enabled(!this.busy && !this.voicePhase).onClick(() => this.openSource(source))
            }, (source: AssistantSource) => source.id)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ maxWidth: '80%' })
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(this.bubble())
        .border({ width: 1, color: 'rgba(255,255,255,0.7)' })
        .borderRadius({ topLeft: 18, topRight: 18, bottomLeft: 6, bottomRight: 18 })
        Blank()
      }.width('100%').alignItems(VerticalAlign.Top)
    }
  }

  @Builder
  private historyRow(item: AssistantHistoryItem) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text('●').fontSize(9).fontColor(DOT_GREEN)
        Column({ space: 2 }) {
          Text(item.title).fontSize(this.font(14)).fontColor(this.ink())
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.historyTime(item)).fontSize(this.font(11)).fontColor(this.ink2())
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          .onClick(() => { this.openHistory(item); })
        Text('✎').fontSize(15).fontColor(ICON_YELLOW).width(28).textAlign(TextAlign.Center)
          .accessibilityText('重命名会话')
          .onClick(() => { this.beginRename(item); })
        Text('×').fontSize(16).fontColor(ICON_PINK).width(28).textAlign(TextAlign.Center)
          .accessibilityText('删除会话')
          .onClick(() => { this.removeHistory(item); })
      }
      .width('100%').padding({ top: 10, bottom: 10 })
      .onHover((isHover: boolean) => {
        this.hoveredId = isHover ? item.id : (this.hoveredId === item.id ? '' : this.hoveredId);
      })

      if (this.hoveredId === item.id) {
        Column({ space: 4 }) {
          Text('最近上下文').fontSize(this.font(10)).fontColor(ICON_PINK)
          if (item.messages.length === 0) {
            Text('本机还没有保存这条会话的上下文').fontSize(this.font(11)).fontColor(this.ink2())
          } else {
            ForEach(item.messages.slice(-3), (message: AssistantHistoryMessage, index: number) => {
              Text((message.role === 'user' ? '我：' : '小暖：') + message.text)
                .fontSize(this.font(11)).fontColor(this.ink2())
                .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            }, (message: AssistantHistoryMessage, index: number) => item.id + ':' + index.toString())
          }
        }.padding(8).width('100%').alignItems(HorizontalAlign.Start)
        .backgroundColor(this.darkMode ? this.p().surfaceSoft : 'rgba(255,255,255,0.75)')
        .borderRadius(12)
      }
    }.width('100%')
  }

  @Builder
  private sidebar() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Image($r('app.media.assistant_persona')).height(122).objectFit(ImageFit.Contain)
        Column({ space: 4 }) {
          Text('小暖').fontSize(this.font(20)).fontColor(this.ink()).fontWeight(FontWeight.Medium)
          Text('18岁 · 活泼开朗 · 办事高效').fontSize(this.font(11)).fontColor(this.ink2())
          Text('暖邻 AI 助手').fontSize(this.font(11)).fontColor(ICON_PINK)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%')

      Button('＋ 新对话').width('100%').height(46).fontSize(this.font(15))
        .fontColor('#FFFFFF').backgroundColor(this.darkMode ? this.p().accent : '#8FAE84').borderRadius(23)
        .onClick(() => { this.historyOpen = false; this.fresh(); })

      Text('历史会话').fontSize(this.font(12)).fontColor(this.ink2()).letterSpacing(1).width('100%')

      Row({ space: 6 }) {
        Text('⌕').fontSize(17).fontColor(ICON_PINK)
        TextInput({ text: this.historyQuery, placeholder: '搜索历史会话' })
          .layoutWeight(1).height(38).fontSize(this.font(13)).fontColor(this.ink())
          .placeholderColor(this.ink2())
          .backgroundColor(this.darkMode ? this.p().surfaceSoft : '#FFF9EE')
          .borderRadius(19)
          .onChange((value: string) => { this.historyQuery = value; })
      }.width('100%').padding({ left: 12, right: 10 })
      .backgroundColor(this.darkMode ? this.p().surface : '#FFFDF8')
      .border({ width: 1, color: 'rgba(227,154,168,0.35)' }).borderRadius(19)

      Scroll() {
        Column({ space: 2 }) {
          if (this.historyList().length === 0) {
            Text('还没有历史会话').fontSize(this.font(13)).fontColor(this.ink2()).padding(12)
          }
          ForEach(this.historyList(), (item: AssistantHistoryItem) => { this.historyRow(item) },
            (item: AssistantHistoryItem) => item.id)
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)

      Button('返回').width('100%').height(42).fontSize(this.font(14)).fontColor(this.ink2())
        .backgroundColor(this.bubbleSoft()).borderRadius(21)
        .onClick(() => { this.historyOpen = false; })
    }
    .width('78%').height('100%')
    .padding({ left: 18, right: 18, top: 28, bottom: 18 })
    .backgroundColor(this.darkMode ? this.p().surface : '#FFFCF5')
    .borderRadius({ topRight: 26, bottomRight: 26 })
    .shadow({ radius: 24, color: 'rgba(91,58,42,0.18)', offsetX: 6 })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 0 }) {
        Row() {
          Text('‹ 返回').fontSize(this.font(14)).fontColor(this.ink())
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .backgroundColor(this.darkMode ? this.p().surface : '#FFFDF8')
            .borderRadius(18)
            .onClick(() => {
              if (Number(router.getLength()) > 1) router.back();
              else router.replaceUrl({ url: 'pages/Home' });
            })
          Blank()
          Column({ space: 1 }) {
            Text('暖邻助手').fontSize(this.font(19)).fontColor(this.ink()).fontWeight(FontWeight.Medium)
            Text('小暖 · 18岁 · 活泼高效').fontSize(this.font(10)).fontColor(this.ink2())
          }.alignItems(HorizontalAlign.Center)
          Blank()
          Text('☰').fontSize(24).fontColor(ICON_PINK).width(40).height(40)
            .textAlign(TextAlign.Center).borderRadius(20)
            .backgroundColor(this.darkMode ? this.p().surface : 'rgba(251,231,234,0.8)')
            .accessibilityText('历史会话')
            .onClick(() => { this.historyOpen = true; this.refreshHistory(); })
        }.width('100%').padding({ top: 10, bottom: 8, left: 12, right: 12 })

        Row({ space: 8 }) {
          Text(this.conversation?.personId ? '当前居民 · ' + this.personName : '可以直接提问，或先选择一位居民')
            .fontSize(this.font(13)).fontColor(this.ink2()).layoutWeight(1)
          Text(this.selecting ? '返回聊天' : '选居民').fontSize(this.font(13)).fontColor(ICON_PINK)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(this.darkMode ? this.p().surface : '#FFFDF8').borderRadius(14)
            .enabled(!this.busy && !this.pending && !this.voicePhase)
            .onClick(() => { if (this.selecting) this.selecting = false; else this.choose(); })
        }.padding(10).margin({ left: 12, right: 12, bottom: 6 })
        .backgroundColor(this.darkMode ? this.p().surfaceSoft : 'rgba(247,231,195,0.65)').borderRadius(18)

        Scroll(this.scroller) {
          Column({ space: 14 }) {
            if (this.selecting) {
              Text('最近返回的最多50份档案；其他居民也可以在聊天中按姓名查询。')
                .fontSize(this.font(13)).fontColor(this.ink2())
              if (!this.busy && this.people.length === 0) {
                Text('暂无可选档案').fontSize(this.font(15)).fontColor(this.ink2())
              }
              ForEach(this.people, (person: Person) => {
                Button(person.name + ' · ' + person.age + '岁 · ' + (person.community || '社区未填写'))
                  .width('100%').fontSize(this.font(15)).fontColor(this.ink())
                  .backgroundColor(this.bubbleSoft()).borderRadius(18).padding(14)
                  .constraintSize({ minHeight: 50 }).enabled(!this.busy).onClick(() => this.fresh(person.id, person.name))
              }, (person: Person) => person.id)
            } else {
              if (!this.conversation || this.conversation.messages.length === 0) {
                Column({ space: 14 }) {
                  Row({ space: 10 }) {
                    this.personaHead(46)
                    Column({ space: 2 }) {
                      Text('小暖').fontSize(this.font(16)).fontColor(this.ink())
                      Text('18岁 · 活泼开朗 · 办事高效').fontSize(this.font(11)).fontColor(this.ink2())
                    }.alignItems(HorizontalAlign.Start)
                  }.width('100%')
                  Text('今天有什么想交给我？').fontSize(this.font(20)).fontColor(this.ink())
                  Text('可以帮你查授权资料、准备回访沟通、建档、记备忘或排回访路线。涉及诊断、用药、违法或伤害他人的请求，我会拒绝并建议联系专业人员或紧急服务。')
                    .fontSize(this.font(13)).fontColor(this.ink2()).lineHeight(this.font(20))
                  ForEach(['帮我准备回访前的沟通', '查一查居民的历史记录', '帮我为老人建档', '帮我记一条本地备忘录', '帮我安排上门回访计划'],
                    (label: string, index: number) => {
                      Button(label).width('100%').fontSize(this.font(14)).fontColor(this.ink())
                        .backgroundColor([this.darkMode ? this.p().surfaceSoft : '#F6DDE2',
                          this.darkMode ? this.p().surfaceSoft : '#DDEBD8',
                          this.darkMode ? this.p().surfaceSoft : '#F7E7C3'][index % 3])
                        .borderRadius(16).padding(14).constraintSize({ minHeight: 46 })
                        .enabled(!this.voicePhase)
                        .onClick(() => { this.input = this.optionPrompt(index); })
                    }, (label: string) => label)
                  Text('建档、备忘录和回访计划都先出草稿，核对确认后才保存。')
                    .fontSize(this.font(11)).fontColor(this.ink2())
                }.padding(18).width('100%').alignItems(HorizontalAlign.Start)
                .backgroundColor(this.bubble()).borderRadius(22)
                .border({ width: 1, color: 'rgba(255,255,255,0.7)' })
              }
              if (this.conversation) {
                ForEach(this.conversation.messages, (message: AssistantMessage) => {
                  this.messageCard(message)
                  ForEach(this.messageActions(message.id), (action: AssistantAction) => {
                    this.actionCard(action)
                  }, (action: AssistantAction) => action.id + ':' + action.revision.toString() + ':' + action.status)
                }, (message: AssistantMessage) => message.id)
                ForEach(this.orphanActions(), (action: AssistantAction) => {
                  this.actionCard(action)
                }, (action: AssistantAction) => action.id + ':' + action.revision.toString() + ':' + action.status)
              }
              if (this.pending) {
                Row({ space: 8 }) {
                  Blank()
                  Text(this.pending.text).fontSize(this.font(15)).fontColor(this.ink())
                    .padding(14).constraintSize({ maxWidth: '76%' })
                    .backgroundColor(this.bubbleSoft()).borderRadius(18)
                  this.userBadge(30)
                }.width('100%').alignItems(VerticalAlign.Top)
              }
              if (this.busy && this.streamingText) {
                Text(this.streamingText).fontSize(this.font(16)).fontColor(this.ink()).lineHeight(this.font(26))
                  .padding(16).width('100%').backgroundColor(this.bubble()).borderRadius(18)
                Text('小暖正在回答…').fontSize(this.font(12)).fontColor(this.ink2())
              }
            }
            if (this.busy) {
              Row({ space: 10 }) {
                LoadingProgress().width(22).height(22).color(ICON_PINK)
                Text(this.actionStatus || (this.pending ? '小暖正在整理回答…' : '正在读取…')).fontSize(this.font(13)).fontColor(this.ink2())
              }.padding(12).alignSelf(ItemAlign.Start)
            }
            if (!this.busy && this.conversation?.inflight) {
              Text('上一条消息仍在处理，回答完成后会显示在这里。').fontSize(this.font(13)).fontColor(this.ink2())
            }
            if (this.error) {
              Column({ space: 10 }) {
                Text(this.error).fontSize(this.font(13)).fontColor(this.ink())
                Button(this.pending ? '重试这条消息' : '重新读取').fontSize(this.font(13))
                  .backgroundColor(this.darkMode ? this.p().accent : '#8FAE84').fontColor('#FFFFFF').borderRadius(16)
                  .constraintSize({ minHeight: 42 }).enabled(!this.busy)
                  .onClick(() => { if (this.pending) this.send(true); else if (this.selecting) this.choose(); else this.load(); })
              }.padding(14).width('100%').alignItems(HorizontalAlign.Start)
                .backgroundColor(this.darkMode ? this.p().surfaceSoft : '#F7E7C3').borderRadius(18)
            }
          }.width('100%').padding({ left: 14, right: 14, top: 6, bottom: 14 }).alignItems(HorizontalAlign.Start)
        }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)

        Column({ space: 8 }) {
          if (this.voicePhase) {
            Column({ space: 8 }) {
              Text(this.voicePhase === 'recording' ? '正在聆听 · 最长60秒' :
                (this.voicePhase === 'transcribing' ? '正在转写，请稍候…' : '正在准备语音输入…'))
                .fontSize(this.font(14)).fontColor(this.ink())
              if (this.voicePhase === 'recording') {
                Row() {
                  Column().height(5).width((10 + this.voiceLevel * 90).toString() + '%')
                    .backgroundColor(DOT_GREEN).borderRadius(3)
                }.width('100%').height(5).backgroundColor(this.bubbleSoft()).borderRadius(3)
              }
              if (this.voicePreview) {
                Text(this.voicePreview).fontSize(this.font(14)).fontColor(this.ink2())
                  .maxLines(3).copyOption(CopyOptions.LocalDevice).width('100%')
              }
              Row({ space: 12 }) {
                Button('取消录音').fontSize(this.font(14)).fontColor(this.ink2())
                  .backgroundColor(this.bubbleSoft()).borderRadius(16).constraintSize({ minHeight: 42 })
                  .onClick(() => this.cancelVoice())
                Button('完成录音').fontSize(this.font(14)).fontColor('#FFFFFF')
                  .backgroundColor(this.darkMode ? this.p().accent : '#8FAE84').borderRadius(16)
                  .constraintSize({ minHeight: 42 })
                  .enabled(this.voicePhase === 'recording').onClick(() => this.finishVoice())
              }
            }.padding(12).width('100%').alignItems(HorizontalAlign.Start)
            .backgroundColor(this.bubble()).borderRadius(18)
          }
          if (this.voiceError) {
            Text(this.voiceError).fontSize(this.font(12)).fontColor(this.ink2()).width('100%')
          }
          if (this.attachBusy) {
            Row({ space: 8 }) {
              LoadingProgress().width(18).height(18).color(ICON_PINK)
              Text('正在解析附件，图片可能需要更久…').fontSize(this.font(12)).fontColor(this.ink2())
            }.width('100%')
          } else if (this.attachmentName.length > 0) {
            Row({ space: 8 }) {
              Text('▣').fontSize(14).fontColor(ICON_GREEN)
              Text(this.attachmentName + ' · ' + this.attachmentChars.toString() + ' 字')
                .fontSize(this.font(12)).fontColor(this.ink()).layoutWeight(1).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text('×').fontSize(15).fontColor(ICON_PINK).width(24).textAlign(TextAlign.Center)
                .accessibilityText('移除附件')
                .onClick(() => this.clearAttachment())
            }.width('100%').padding({ left: 10, right: 8, top: 6, bottom: 6 })
            .backgroundColor(this.darkMode ? this.p().surfaceSoft : 'rgba(221,235,216,0.8)').borderRadius(14)
          }
          if (this.attachError.length > 0) {
            Text(this.attachError).fontSize(this.font(11)).fontColor('#B45A5A').width('100%')
          }
          Row({ space: 8 }) {
            Text('＋').fontSize(22).fontColor(ICON_PINK).width(42).height(42)
              .textAlign(TextAlign.Center).borderRadius(21)
              .backgroundColor(this.bubbleSoft())
              .accessibilityText('添加资料或图片')
              .onClick(() => { this.attachMenuOpen = true; })
            TextArea({ text: this.input, placeholder: 'Message…', controller: this.inputController })
              .layoutWeight(1).height(48).fontSize(this.font(15)).fontColor(this.ink())
              .placeholderColor(this.ink2())
              .backgroundColor(this.darkMode ? this.p().surfaceSoft : '#FFFDF8')
              .borderRadius(24).maxLength(2000)
              .enabled(!this.busy && !this.pending && !this.conversation?.inflight && !this.voicePhase)
              .onChange((value: string) => { this.input = value; })
            Image($r('app.media.assistant_mic')).width(20).height(20)
              .width(42).height(42).padding(11).borderRadius(21)
              .backgroundColor(this.bubbleSoft())
              .accessibilityText('语音输入')
              .enabled(!this.busy && !this.pending && !this.selecting && this.conversation !== null &&
                !this.conversation?.inflight && !this.editingActionId)
              .onClick(() => this.startVoice())
            Text('↑').fontSize(22).fontColor('#FFFFFF').width(42).height(42)
              .textAlign(TextAlign.Center).borderRadius(21)
              .backgroundColor(this.darkMode ? this.p().accent : '#8FAE84')
              .opacity(this.input.trim().length > 0 && !this.busy && this.conversation !== null ? 1 : 0.45)
              .accessibilityText('发送')
              .enabled(!this.busy && !this.pending && !this.selecting && !this.conversation?.inflight && !this.voicePhase &&
                this.conversation !== null && this.input.trim().length > 0 && !this.editingActionId)
              .onClick(() => this.send())
          }.width('100%')
          Text('小暖会先核对资料；AI 建议仅供工作参考，重要信息请核对原始资料。')
            .fontSize(this.font(10)).fontColor(this.ink2())
        }.padding({ left: 12, right: 12, top: 10, bottom: 10 }).width('100%')
        .backgroundColor(this.darkMode ? this.p().surface : 'rgba(255,253,248,0.92)')
      }.width('100%').height('100%')

      if (this.historyOpen) {
        this.sidebar()
      }

      if (this.renameOpen) {
        Column() {
          Column({ space: 12 }) {
            Text('重命名会话').fontSize(this.font(17)).fontColor(this.ink()).fontWeight(FontWeight.Medium)
            TextInput({ text: $$this.renameText, placeholder: '当前：' + this.renameOriginal })
              .width('100%').height(46).fontSize(this.font(15)).fontColor(this.ink()).placeholderColor(this.ink2())
              .backgroundColor(this.darkMode ? this.p().surfaceSoft : '#FFFDF8').borderRadius(14).maxLength(24)
            Row({ space: 10 }) {
              Button('取消').layoutWeight(1).height(42).fontSize(this.font(14)).fontColor(this.ink2())
                .backgroundColor(this.bubbleSoft()).borderRadius(21)
                .onClick(() => { this.renameOpen = false; })
              Button('保存').layoutWeight(1).height(42).fontSize(this.font(14)).fontColor('#FFFFFF')
                .backgroundColor(this.darkMode ? this.p().accent : '#8FAE84').borderRadius(21)
                .onClick(() => { this.confirmRename(); })
            }.width('100%')
          }.width(320).padding(20).backgroundColor(this.darkMode ? this.p().surface : '#FFFCF5')
          .borderRadius(22).shadow({ radius: 24, color: 'rgba(91,58,42,0.2)' })
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(0,0,0,0.35)').zIndex(50)
      }

      if (this.attachMenuOpen) {
        Column() {
          Column({ space: 10 }) {
            Text('添加资料或图片').fontSize(this.font(16)).fontColor(this.ink()).fontWeight(FontWeight.Medium)
            Text('资料会先在本机上传解析成文字，再随消息发给小暖；请勿上传与工作无关的隐私资料。')
              .fontSize(this.font(11)).fontColor(this.ink2()).lineHeight(this.font(18))
            Button('选择资料（txt / docx / pdf / xlsx）').width('100%').height(44).fontSize(this.font(13))
              .fontColor(this.ink()).backgroundColor(this.bubbleSoft()).borderRadius(16)
              .onClick(() => { this.pickAttachment(false); })
            Button('选择图片（相册，OCR 后交给小暖）').width('100%').height(44).fontSize(this.font(13))
              .fontColor(this.ink()).backgroundColor(this.bubbleSoft()).borderRadius(16)
              .onClick(() => { this.pickAttachment(true); })
            Button('使用示例图片（演示，OCR 后交给小暖）').width('100%').height(44).fontSize(this.font(13))
              .fontColor(this.ink2()).backgroundColor('rgba(247,231,195,0.7)').borderRadius(16)
              .onClick(() => { this.attachExampleImage(); })
            Button('取消').width('100%').height(40).fontSize(this.font(13)).fontColor(this.ink2())
              .backgroundColor('rgba(0,0,0,0)').onClick(() => { this.attachMenuOpen = false; })
          }.width(330).padding(18).backgroundColor(this.darkMode ? this.p().surface : '#FFFCF5')
          .borderRadius(22).shadow({ radius: 24, color: 'rgba(91,58,42,0.2)' })
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(0,0,0,0.35)').zIndex(60)
      }

      if (this.contextOpen) {
        Column() {
          Column({ space: 10 }) {
            Text(this.contextTitle).fontSize(this.font(17)).fontColor(this.ink()).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('本机保存的最近上下文').fontSize(this.font(11)).fontColor(ICON_PINK)
            Scroll() {
              Column({ space: 8 }) {
                if (this.contextMessages.length === 0) {
                  Text('这条会话还没有保存上下文').fontSize(this.font(13)).fontColor(this.ink2())
                }
                ForEach(this.contextMessages, (message: AssistantHistoryMessage, index: number) => {
                  Row({ space: 6 }) {
                    Text(message.role === 'user' ? '我' : '小暖').fontSize(this.font(10)).fontColor(ICON_PINK).width(34)
                    Text(message.text).fontSize(this.font(13)).fontColor(this.ink()).layoutWeight(1)
                  }.width('100%').alignItems(VerticalAlign.Top)
                }, (message: AssistantHistoryMessage, index: number) => this.contextId + ':' + index.toString())
              }.width('100%').alignItems(HorizontalAlign.Start)
            }.width('100%').constraintSize({ maxHeight: 360 }).scrollBar(BarState.Off)
            Row({ space: 10 }) {
              Button('关闭').layoutWeight(1).height(42).fontSize(this.font(14)).fontColor(this.ink2())
                .backgroundColor(this.bubbleSoft()).borderRadius(21)
                .onClick(() => { this.contextOpen = false; })
              Button('继续此对话').layoutWeight(1).height(42).fontSize(this.font(14)).fontColor('#FFFFFF')
                .backgroundColor(this.darkMode ? this.p().accent : '#8FAE84').borderRadius(21)
                .onClick(() => {
                  this.contextOpen = false;
                  const item: AssistantHistoryItem = { id: this.contextId, title: this.contextTitle,
                    updatedAt: Date.now(), preview: '', messages: this.contextMessages };
                  this.openHistory(item);
                })
            }.width('100%')
          }.width(330).padding(20).backgroundColor(this.darkMode ? this.p().surface : '#FFFCF5')
          .borderRadius(22).shadow({ radius: 24, color: 'rgba(91,58,42,0.2)' })
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(0,0,0,0.35)').zIndex(55)
      }
    }
    .width('100%').height('100%').backgroundColor(this.bg())
  }
}
