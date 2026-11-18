const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require('./ts');
const root = path.join(__dirname, '../entry/src/main/ets');
function evaluate(source, modules = {}, globals = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, require: name => modules[name], setTimeout: () => {},
    AppStorage: { get() {}, setOrCreate() {} }, Scroller: class { scrollEdge() {} },
    TextAreaController: class { stopEditing() {} }, ...globals });
  return exports;
}
const rules = evaluate(fs.readFileSync(path.join(root, 'model/AssistantChat.ets'), 'utf8'));
function conversation(id = 'chat1', messages = []) { return {id, personId: null, messages, revision: 1}; }
function page(api, options = {}) {
  let source = fs.readFileSync(path.join(root, 'pages/Assistant.ets'), 'utf8');
  source = source.slice(0, source.indexOf('  @Builder')) + '}';
  source = source.replace(/@Entry\s*|@Component\s*|@State\s*/g, '')
    .replace(/@StorageProp\('[^']*'\)\s*/g, '').replace('struct Assistant', 'export class Assistant');
  const recorder = {cancel() {}, finish() {}, startDictation: async () => true, ...options.recorder};
  return new (evaluate(source, {'../model/Api': {Api: api}, '../model/AssistantChat': rules,
    '../model/Theme': {}, '../model/UserPreferences': {}, '@kit.ArkUI': {router: {}},
    '../model/Voice': {VoiceRecorder: class {constructor() {return recorder;}}},
    '../model/AssistantMemoStore': {assistantDeviceId: () => 'device-fictional',
      executeAssistantMemo: options.executeMemo || (async action => 'assistant-' + action.id)},
    '@kit.AbilityKit': {abilityAccessCtrl: {createAtManager: () => ({requestPermissionsFromUser:
      options.permission || (async () => ({authResults: [0]}))})}}
  }, {getContext: () => ({}), clearTimeout() {},
    AppStorage: {get: () => options.consent !== false, setOrCreate() {}},
    AlertDialog: {show: options.dialog || (() => {})}}).Assistant)();
}

test('draft cards stay with their originating message without duplication and can collapse', () => {
  const p=page({});
  p.conversation={id:'c',messages:[{id:'old',actionIds:['a']},{id:'repeat',actionIds:['a']},{id:'new',actionIds:['b']}],
    actions:[{id:'a',status:'cancelled'},{id:'b',status:'draft'},{id:'legacy',status:'completed'}]};
  assert.deepEqual(Array.from(p.messageActions('old'),a=>a.id),['a']);
  assert.equal(p.messageActions('repeat').length,0);
  assert.deepEqual(Array.from(p.messageActions('new'),a=>a.id),['b']);
  assert.deepEqual(Array.from(p.orphanActions(),a=>a.id),['legacy']);
  p.toggleActionDetails('a');assert.equal(p.expandedActionIds.includes('a'),true);
  p.toggleActionDetails('a');assert.equal(p.expandedActionIds.includes('a'),false);
});
test('chat preserves the same message identity after a lost response and prevents double taps', async () => {
  const calls = [];
  let resolve;
  const screen = page({sendAssistantMessage: async (id, pending) => {
    calls.push({...pending});
    if (calls.length === 1) throw new Error('响应丢失');
    return new Promise(done => {resolve = () => done(conversation(id));});
  }});
  screen.conversation = conversation(); screen.input = '请帮我准备沟通';
  await screen.send();
  assert.match(screen.error, /响应丢失/);
  assert.equal(screen.pending.text, '请帮我准备沟通');
  const retry = screen.send(true);
  await screen.send(true);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].clientMessageId, calls[1].clientMessageId);
  resolve(); await retry;
  assert.equal(screen.pending, null);
});
test('leaving the page drops late answers and clears resident text from the hidden page', async () => {
  let done;
  const screen = page({sendAssistantMessage: () => new Promise(resolve => {done = resolve;})});
  screen.conversation = conversation(); screen.input = '虚构工作内容';
  const sending = screen.send();
  screen.onPageHide();
  done(conversation()); await sending;
  assert.equal(screen.conversation, null);
  assert.equal(screen.pending, null);
  assert.equal(screen.input, '');
});
test('switching residents starts a separate chat and retains old context when creation fails', async () => {
  let fail = true;
  const screen = page({createAssistantConversation: async personId => {
    if (fail) throw new Error('网络失败');
    return {...conversation('chat2'), personId};
  }});
  screen.conversation = conversation();
  screen.voiceError = '上一次录音失败'; screen.voicePreview = '上一次部分文字';
  await screen.fresh('person2', '虚构乙');
  assert.equal(screen.voiceError, '');
  assert.equal(screen.voicePreview, '');
  assert.equal(screen.conversation.id, 'chat1');
  fail = false; await screen.fresh('person2', '虚构乙');
  assert.equal(screen.conversation.id, 'chat2');
  assert.equal(screen.conversation.personId, 'person2');
  assert.equal(screen.personName, '虚构乙');
});
test('chat rejects a mismatched conversation response rather than displaying another thread', () => {
  assert.throws(() => rules.requireAssistantConversation(conversation('other'), 'wanted'), /不一致/);
  assert.throws(() => rules.pendingAssistantMessage('  '), /请输入/);
});

test('dictation previews separately and appends only final text without sending to the model', async () => {
  let callbacks;
  let sends = 0;
  const screen = page({sendAssistantMessage: async () => {sends++;}}, {recorder: {
    startDictation: async (...args) => {callbacks = args; return true;}
  }});
  screen.conversation = conversation(); screen.input = '已有输入';
  await screen.startVoice();
  assert.equal(screen.voicePhase, 'recording');
  callbacks[0]('实时转写');
  assert.equal(screen.input, '已有输入');
  assert.equal(screen.voicePreview, '实时转写');
  await screen.send();
  assert.equal(sends, 0);
  screen.finishVoice();
  assert.equal(screen.voicePhase, 'transcribing');
  callbacks[1]('补充内容');
  assert.equal(screen.input, '已有输入\n补充内容');
  assert.equal(screen.voicePhase, '');
  assert.equal(sends, 0);
});
test('cancelling dictation ignores a late final result and leaves the typed draft unchanged', async () => {
  let callbacks;
  const screen = page({}, {recorder: {startDictation: async (...args) => {callbacks = args; return true;}}});
  screen.conversation = conversation(); screen.input = '原草稿';
  await screen.startVoice();
  screen.cancelVoice(); callbacks[1]('迟到结果');
  assert.equal(screen.input, '原草稿');
  assert.equal(screen.voicePhase, '');
});
test('leaving during microphone permission never starts a late recorder', async () => {
  let resolve, starts = 0;
  const screen = page({}, {permission: () => new Promise(done => {resolve = done;}),
    recorder: {startDictation: async () => {starts++; return true;}}});
  screen.conversation = conversation();
  const starting = screen.startVoice();
  screen.onPageHide(); resolve({authResults: [0]}); await starting;
  assert.equal(starts, 0);
});
test('denied permission and recognition failure retain the draft and expose editable fallback', async () => {
  const denied = page({}, {permission: async () => ({authResults: [-1]})});
  denied.conversation = conversation(); denied.input = '原草稿';
  await denied.startVoice();
  assert.equal(denied.input, '原草稿');
  assert.match(denied.voiceError, /麦克风权限/);
  let callbacks;
  const failed = page({}, {recorder: {startDictation: async (...args) => {callbacks = args; return true;}}});
  failed.conversation = conversation(); failed.input = '原草稿'; await failed.startVoice();
  callbacks[0]('部分文字'); callbacks[2]('网络中断');
  assert.equal(failed.input, '原草稿');
  assert.equal(failed.voicePreview, '部分文字');
  assert.match(failed.voiceError, /网络中断/);
});
test('stale consent callbacks cannot reopen the microphone after leaving', async () => {
  let dialog;
  const screen = page({}, {consent: false, dialog: value => {dialog = value;}});
  screen.conversation = conversation(); await screen.startVoice();
  screen.onPageHide(); dialog.secondaryButton.action();
  assert.equal(screen.voicePhase, '');
});
test('overlong speech is retained for copying without silently truncating the typed draft', () => {
  assert.throws(() => rules.appendAssistantDictation('原'.repeat(1999), '超出长度'), /2000/);
  assert.throws(() => rules.appendAssistantDictation('原草稿', ' '), /没有识别/);
});

function memoAction(status = 'draft') {
  return {id: 'action-1', kind: 'create_memo', status, revision: status === 'draft' ? 1 : 2,
    ownerKey: 'org:worker', payload: {text: '虚构待办', dueAt: ''}, duplicates: [],
    deviceId: 'device-fictional', executionToken: 'token-fictional'};
}
test('memo completion waits for both durable device execution and the real receipt', async () => {
  const order = [];
  const draft = memoAction();
  const confirmed = memoAction('awaiting_device');
  const screen = page({
    confirmAssistantAction: async () => {order.push('confirm'); return confirmed;},
    assistantOwnerKey: () => 'org:worker',
    receiptAssistantAction: async (action, deviceId, memoId) => {
      order.push('receipt'); assert.equal(memoId, 'assistant-action-1');
      return {...confirmed, status: 'completed', revision: 3, result: {memoId}};
    }
  }, {executeMemo: async () => {order.push('flush'); return 'assistant-action-1';}});
  screen.conversation = {...conversation(), actions: [draft]};
  await screen.runAction(draft);
  assert.deepEqual(order, ['confirm', 'flush', 'receipt']);
  assert.equal(screen.conversation.actions[0].status, 'completed');
});
test('lost receipt leaves the action pending and retry uses the same local memo identity', async () => {
  let attempts = 0;
  const ids = [];
  const confirmed = memoAction('awaiting_device');
  const screen = page({
    confirmAssistantAction: async () => confirmed,
    assistantOwnerKey: () => 'org:worker',
    receiptAssistantAction: async (action, deviceId, memoId) => {
      ids.push(memoId); if (++attempts === 1) throw new Error('回执丢失');
      return {...confirmed, status: 'completed', revision: 3};
    },
    assistantConversation: async () => ({...conversation(), actions: [confirmed]})
  });
  screen.conversation = {...conversation(), actions: [memoAction()]};
  await screen.runAction(memoAction());
  assert.match(screen.error, /回执暂未送达/);
  assert.equal(screen.conversation.actions[0].status, 'awaiting_device');
  await screen.runAction(confirmed);
  assert.equal(ids[0], ids[1]);
  assert.equal(screen.conversation.actions[0].status, 'completed');
});
test('device write failure reports failure and never fabricates a completed card', async () => {
  let receiptStatus = '';
  const confirmed = memoAction('awaiting_device');
  const screen = page({confirmAssistantAction: async () => confirmed,
    assistantOwnerKey: () => 'org:worker',
    receiptAssistantAction: async (action, deviceId, memoId, error) => {
      receiptStatus = error ? 'failed' : 'completed'; return confirmed;
    }, assistantConversation: async () => ({...conversation(), actions: [confirmed]})
  }, {executeMemo: async () => {throw new Error('磁盘写入失败');}});
  screen.conversation = {...conversation(), actions: [memoAction()]};
  await screen.runAction(memoAction());
  assert.equal(receiptStatus, 'failed');
  assert.equal(screen.conversation.actions[0].status, 'awaiting_device');
});
test('person edits are saved as drafts and require a separate confirm operation', async () => {
  const action = {...memoAction(), kind: 'create_person', payload: {name: '虚构老人', age: null}};
  let saved;
  const screen = page({updateAssistantAction: async (id, revision, payload) => {
    saved = payload; return {...action, payload, revision: 2};
  }});
  screen.conversation = {...conversation(), actions: [action]};
  screen.editAction(action); screen.changeEditField(1, '74'); screen.changeEditField(4, '虚构街道1号');
  await screen.saveActionEdit();
  assert.equal(saved.age, 74);
  assert.equal(saved.address, '虚构街道1号');
  assert.equal(screen.conversation.actions[0].status, 'draft');
});
