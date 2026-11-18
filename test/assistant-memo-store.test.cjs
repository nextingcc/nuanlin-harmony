const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require('./ts');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/model/AssistantMemoStore.ets'), 'utf8');
function runtime(disk = new Map(), legacy = []) {
  const current = new Map([['memoItems', JSON.stringify(legacy)]]);
  const cache = new Map(disk);
  let fail = false; let flushes = 0; let gate = null;
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText, {
    exports, AppStorage: {get:key=>current.get(key),setOrCreate:(key,value)=>current.set(key,value)},
    require(name) {
      if(name==='@kit.ArkData') return {preferences:{async getPreferences(context,options){
        assert.equal(options.name,'nuanlin_assistant_memos');
        return {async get(key,fallback){return cache.get(key)??fallback;},async put(key,value){cache.set(key,value);},
          async flush(){flushes++;if(gate) await gate;if(fail)throw Error('disk unavailable');for(const [k,v] of cache)disk.set(k,v);}};
      }}};
      if(name==='@kit.ArkTS')return {util:{generateRandomUUID:()=> 'fictional-device-uuid'}};
      if(name==='./MemoReminders')return {readMemoItems:()=>JSON.parse(current.get('memoItems')??'[]')};
      return {};
    }
  });
  return {store:exports,current,disk,cache,fail(value=true){fail=value;},hold(value){gate=value;},flushes:()=>flushes,
    items:()=>JSON.parse(current.get('memoItems'))};
}
function action(store, patch = {}) {
  return {id:'action-1',kind:'create_memo',status:'awaiting_device',revision:2,ownerKey:'org:user',
    deviceId:store.assistantDeviceId(),executionToken:'fictional-execution-token',expiresAt:new Date(Date.now()+60000).toISOString(),payload:{text:'虚构回访提醒',dueAt:'2026-11-20 09:00'},...patch};
}
const memo={id:'legacy-1',text:'虚构旧事项',dueAt:'',done:false};

test('migration flushes legacy items before exposing a stable device identity and survives restart',async()=>{
 const first=runtime(new Map(),[memo]);await first.store.initializeAssistantMemoStore({});
 assert.deepEqual(first.items(),[memo]);assert.ok(first.store.assistantDeviceId());assert.equal(first.flushes(),1);
 const id=first.store.assistantDeviceId();
 const next=runtime(first.disk,[]);await next.store.initializeAssistantMemoStore({});
 assert.deepEqual(next.items(),[memo]);assert.equal(next.store.assistantDeviceId(),id);assert.equal(next.flushes(),0);
});

test('failed migration does not claim a device or corrupt legacy state and can retry',async()=>{
 const r=runtime(new Map(),[memo]);r.fail();
 await assert.rejects(r.store.initializeAssistantMemoStore({}),/写入/);
 assert.equal(r.store.assistantDeviceId(),'');assert.deepEqual(r.items(),[memo]);assert.equal(r.disk.has('state'),false);
 r.fail(false);await r.store.initializeAssistantMemoStore({});assert.deepEqual(r.items(),[memo]);assert.ok(r.store.assistantDeviceId());
});

test('assistant execution is atomic and repeated after restart or deletion never duplicates or revives',async()=>{
 const r=runtime();await r.store.initializeAssistantMemoStore({});const a=action(r.store);
 assert.equal(await r.store.executeAssistantMemo(a,'org:user'),'assistant-action-1');
 assert.equal(await r.store.executeAssistantMemo(a,'org:user'),'assistant-action-1');assert.equal(r.items().length,1);
 await r.store.saveAssistantMemoItems([]);assert.equal(r.items().length,0);
 assert.equal(await r.store.executeAssistantMemo(a,'org:user'),'assistant-action-1');assert.equal(r.items().length,0);
 const restarted=runtime(r.disk);await restarted.store.initializeAssistantMemoStore({});
 assert.equal(await restarted.store.executeAssistantMemo(a,'org:user'),'assistant-action-1');assert.equal(restarted.items().length,0);
});

test('flush failure publishes neither item nor receipt; retry commits once and preserves other local items',async()=>{
 const r=runtime(new Map(),[memo]);await r.store.initializeAssistantMemoStore({});const before=r.disk.get('state');const a=action(r.store);
 r.fail();await assert.rejects(r.store.executeAssistantMemo(a,'org:user'),/写入/);
 assert.deepEqual(r.items(),[memo]);assert.equal(r.disk.get('state'),before);assert.equal(r.cache.get('state'),before);
 r.fail(false);await r.store.executeAssistantMemo(a,'org:user');assert.equal(r.items().length,2);
 assert.equal(JSON.parse(r.disk.get('state')).receipts.length,1);
});

test('ordinary edits and clearing preserve receipts, and a failed ordinary save keeps shared state unchanged',async()=>{
 const r=runtime();await r.store.initializeAssistantMemoStore({});const a=action(r.store);await r.store.executeAssistantMemo(a,'org:user');
 const edited={...r.items()[0],done:true,text:'人工修改后的虚构提醒'};
 await r.store.saveAssistantMemoItems([edited]);await r.store.executeAssistantMemo(a,'org:user');assert.deepEqual(r.items(),[edited]);
 r.fail();await assert.rejects(r.store.saveAssistantMemoItems([]),/写入/);assert.deepEqual(r.items(),[edited]);
 r.fail(false);await r.store.saveAssistantMemoItems([]);await r.store.executeAssistantMemo(a,'org:user');assert.equal(r.items().length,0);
});

test('bridge rejects wrong kind, status, owner, device, missing token, invalid date and changed receipt payload',async()=>{
 const r=runtime();await r.store.initializeAssistantMemoStore({});const a=action(r.store);
 for(const patch of [{kind:'create_person'},{status:'draft'},{ownerKey:'other'},{deviceId:'other-device'},
  {executionToken:''},{payload:{text:'x',dueAt:'2026-02-29 09:00'}},{payload:{text:'x',dueAt:'2026-11-20 24:00'}},
  {payload:{text:' '.repeat(4),dueAt:''}},{payload:{text:'x'.repeat(1001),dueAt:''}}]) {
  await assert.rejects(r.store.executeAssistantMemo({...a,...patch},'org:user'));
 }
 assert.equal(r.items().length,0);await r.store.executeAssistantMemo(a,'org:user');
 await assert.rejects(r.store.executeAssistantMemo({...a,payload:{text:'篡改的虚构内容',dueAt:a.payload.dueAt}},'org:user'),/变化/);
 await assert.rejects(r.store.executeAssistantMemo({...a,ownerKey:'other'},'other'),/回执/);
 assert.equal(r.items().length,1);
});

test('overlapping deliveries are serialized around actual flush and create only one receipt',async()=>{
 const r=runtime();await r.store.initializeAssistantMemoStore({});const a=action(r.store);
 let release;const pending=new Promise(resolve=>release=resolve);r.hold(pending);
 const first=r.store.executeAssistantMemo(a,'org:user');const second=r.store.executeAssistantMemo(a,'org:user');
 await Promise.resolve();assert.equal(r.items().length,0);release();
 assert.deepEqual(await Promise.all([first,second]),['assistant-action-1','assistant-action-1']);assert.equal(r.items().length,1);
 assert.equal(JSON.parse(r.disk.get('state')).receipts.length,1);
});

test('corrupted receipt storage fails closed rather than discarding the idempotency history',async()=>{
 const disk=new Map([['state',JSON.stringify({version:1,deviceId:'device',items:[],receipts:[{actionId:'a'}]})]]);
 const r=runtime(disk,[memo]);await assert.rejects(r.store.initializeAssistantMemoStore({}),/回执/);
 assert.deepEqual(r.items(),[memo]);assert.equal(r.flushes(),0);
});

test('first execution needs a valid future expiry, while a committed receipt remains retryable after expiry',async()=>{
 const r=runtime();await r.store.initializeAssistantMemoStore({});const a=action(r.store);
 for(const expiresAt of [undefined,'not-a-date','2000-01-01T00:00:00Z']) {
  await assert.rejects(r.store.executeAssistantMemo({...a,expiresAt},'org:user'),/有效期|过期/);
 }
 assert.equal(r.items().length,0);await r.store.executeAssistantMemo(a,'org:user');await r.store.saveAssistantMemoItems([]);
 assert.equal(await r.store.executeAssistantMemo({...a,expiresAt:'2000-01-01T00:00:00Z'},'org:user'),'assistant-action-1');
 assert.equal(r.items().length,0);
});
