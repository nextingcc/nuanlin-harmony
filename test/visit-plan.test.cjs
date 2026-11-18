const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require('./ts');
const root = path.join(__dirname, '../entry/src/main/ets');
function load(file, modules = {}, page = false) {
  let source = fs.readFileSync(path.join(root, file), 'utf8');
  if (page) source = (source.slice(0, source.indexOf('  build()')) + '}')
    .replace(/@Entry\s*|@Component\s*|@State\s*|@StorageProp\('[^']*'\)\s*/g, '').replace('struct VisitPlan', 'export class VisitPlan');
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText,
    { exports, require: name => modules[name] ?? {}, getContext: () => ({}), setTimeout, clearTimeout });
  return exports;
}
const rules = load('model/VisitPlanState.ets');
const payload = {date:'2099-01-02',startTime:'09:00',endTime:'17:00',transport:'walking',returnToStart:false};
const context = () => ({actionId:'a',revision:2,action:{id:'a',revision:2,kind:'create_visit_plan',status:'draft',expiresAt:'2099-01-03T00:00:00Z'},payload,candidates:[],saved:false});
const stop = () => ({personId:'p',windowStart:'09:00',windowEnd:'17:00',serviceMinutes:30,appointmentConfirmed:true});
const prepared = () => ({actionId:'a',revision:2,token:'t',nodeIds:['origin','p'],points:[{latitude:30.6,longitude:114.3},{latitude:30.7,longitude:114.4}],transport:'walking',returnToStart:false});
function maps(kit = {}) { return load('model/VisitPlanMap.ets', {'./VisitPlanState':rules,'./MapLocationState':{mapRequest:p=>p,isWuhanCity:s=>s==='武汉市'},'@kit.MapKit':kit}); }
test('strict plan dates, appointments, revision/order and expiry reject unsafe requests', () => {
  assert.equal(rules.visitPayloadError(payload), '');
  assert.ok(rules.visitPayloadError({...payload,date:'2027-02-30'}));
  assert.ok(rules.visitStopsError([{...stop(),appointmentConfirmed:false}]));
  assert.ok(rules.visitStopsError(Array.from({length:9},(_,i)=>({...stop(),personId:String(i)}))));
  assert.ok(rules.visitStopsError([{...stop(),serviceMinutes:0}]));
  assert.throws(()=>rules.requireVisitPlanEditable({...context(),action:{...context().action,expiresAt:'2000-01-01'}}));
  assert.throws(()=>rules.requireVisitPlanEditable({...context(),action:{...context().action,status:'cancelled'}}));
  assert.throws(()=>rules.requireVisitPrepared({...prepared(),nodeIds:['origin','wrong']},context(),[stop()]));
  assert.throws(()=>rules.requireVisitPrepared({...prepared(),revision:1},context(),[stop()]));
});
test('matrix preserves asymmetric roads and unreachable cells without zero fabrication', () => {
  const {visitMatrix} = maps();
  const result = visitMatrix({rows:[{cells:[{duration:0,distance:0},{duration:90,distance:60}]},{cells:[{}, {duration:0,distance:0}]}]},2);
  assert.equal(result.durations[0][1],90); assert.equal(result.durations[1][0],null); assert.equal(result.distances[1][0],null);
  assert.throws(()=>visitMatrix({rows:[{cells:[{},{}]},{cells:[{},{}]}]},2));
  assert.throws(()=>visitMatrix({rows:[]},2));
});
test('native route call contains coordinates only and uses future Wuhan departure',async()=>{
  let sent;
  const {VisitPlanMap}=maps({navi:{getDrivingMatrix:async(ctx,input)=>{sent=input;return {rows:[{cells:[{duration:0,distance:0},{duration:1,distance:2}]},{cells:[{duration:3,distance:4},{duration:0,distance:0}]}]};}}});
  await VisitPlanMap.matrix({}, {...prepared(),transport:'driving'}, {...payload,transport:'driving'});
  assert.equal(sent.departAt,Date.parse('2099-01-02T09:00:00+08:00')/1000);
  assert.deepEqual(Object.keys(sent.origins[0]).sort(),['latitude','longitude']);
});
test('out of city origin is rejected after reverse verification',async()=>{
  const {VisitPlanMap}=maps({site:{reverseGeocode:async()=>({addressComponent:{adminLevel2:'北京市'}})}});
  await assert.rejects(()=>VisitPlanMap.origin({}, {name:'地点',location:{latitude:39.9,longitude:116.4}}),/武汉/);
});
test('leaving while native matrix is pending prevents solve or save',async()=>{
  let resolve, solves=0;
  const api={prepareVisitPlan:async()=>prepared(),solveVisitPlan:async()=>{solves++;return context();}};
  const {VisitPlan}=load('pages/VisitPlan.ets',{'../model/Api':{Api:api},'../model/VisitPlanState':rules,'../model/VisitPlanMap':{VisitPlanMap:{matrix:()=>new Promise(r=>resolve=r)}}},true);
  const page=new VisitPlan(); page.active=true;page.actionId='a';page.plan=context();page.origin={latitude:30.6,longitude:114.3,label:'公共出发点'};page.originConfirmed=true;page.stops=[stop()];
  const pending=page.calculate(); await new Promise(r=>setImmediate(r));page.onPageHide();resolve({durations:[[0,1],[2,0]],distances:[[0,1],[2,0]]});await pending;
  assert.equal(solves,0);assert.equal(page.solved,false);
});
test('restored plan shows authoritative origin without automatically confirming it',async()=>{
  const origin={latitude:30.6,longitude:114.3,label:'已核验社区出发点'};
  const value={...context(),origin,saved:true};
  const {VisitPlan}=load('pages/VisitPlan.ets',{'../model/Api':{Api:{visitPlan:async()=>value}},'../model/VisitPlanState':rules},true);
  const page=new VisitPlan();page.active=true;page.actionId='a';page.originConfirmed=true;await page.load();
  assert.equal(page.origin.label,origin.label);assert.equal(page.originConfirmed,false);assert.equal(page.editable(),false);
  page.plan={...context(),stale:true};assert.equal(page.editable(),false);
  page.plan={...context(),action:{...context().action,status:'cancelled'}};assert.equal(page.editable(),false);
});
test('all plan checkboxes are green and inputs follow dark and large font palette',()=>{
  const source=fs.readFileSync(path.join(root,'pages/VisitPlan.ets'),'utf8');
  for(const line of source.split('\n')) {
    if(line.includes('Checkbox()')) assert.match(line,/selectedColor\(Theme.greenDeep\)/);
    if(line.includes('TextInput(')) {assert.match(line,/fontColor\(this.p\(\).ink\)/);assert.match(line,/fontSize\(this.font\(16\)\)/);}
  }
});
test('saved list loads without action id, supports pagination and retry, opens selected detail',async()=>{
  let calls=[], fail=false;
  const item={actionId:'a',planId:'plan',date:payload.date,startTime:'09:00',endTime:'17:00',transport:'walking',createdAt:'2099-01-01'};
  const api={visitPlanList:async(cursor)=>{calls.push(cursor);if(fail)throw Error('offline');return {items:[{...item,actionId:cursor?'b':'a'}],nextCursor:cursor?null:'next'};},visitPlan:async()=>context()};
  const {VisitPlan}=load('pages/VisitPlan.ets',{'../model/Api':{Api:api},'../model/VisitPlanState':rules},true);
  const page=new VisitPlan();page.active=true;page.listMode=true;
  await page.load();assert.equal(page.savedPlans.length,1);assert.equal(page.nextCursor,'next');
  await page.loadList(true);assert.equal(page.savedPlans.length,2);assert.equal(page.nextCursor,'');
  assert.deepEqual(calls,['','next']);fail=true;await page.loadList();assert.equal(page.savedPlans.length,2);assert.match(page.message,/offline/);
  fail=false;await page.loadList();assert.equal(page.savedPlans.length,1);
  page.openSaved(item);await new Promise(r=>setImmediate(r));assert.equal(page.actionId,'a');assert.equal(page.listMode,false);assert.equal(page.plan.actionId,'a');
});
test('leaving while saved list is loading ignores delayed results',async()=>{
  let resolve;
  const {VisitPlan}=load('pages/VisitPlan.ets',{'../model/Api':{Api:{visitPlanList:()=>new Promise(r=>resolve=r)}},'../model/VisitPlanState':rules},true);
  const page=new VisitPlan();page.active=true;const pending=page.loadList();page.onPageHide();resolve({items:[{actionId:'a'}],nextCursor:null});await pending;
  assert.equal(page.savedPlans.length,0);
});

test('restoring unchanged form controls never marks the plan dirty or blocks selection', async () => {
  const value = context();
  const {VisitPlan}=load('pages/VisitPlan.ets',{'../model/Api':{Api:{visitPlan:async()=>value}},'../model/VisitPlanState':rules},true);
  const page=new VisitPlan(); page.active=true;page.actionId='a';await page.load();
  page.changed(); assert.equal(page.dirty,false);
  page.start='10:00';page.changed(); assert.equal(page.dirty,true);
  page.start='09:00';page.changed(); assert.equal(page.dirty,false);
});

test('stale overall ETA still allows server revalidation of an unchanged individual stop', async () => {
  let called=0, opened=0;
  const {VisitPlan}=load('pages/VisitPlan.ets',{'../model/Api':{Api:{visitPlanNavigation:async()=>{called++;return {latitude:30.6,longitude:114.3,transport:'walking'};}}},
    '../model/VisitPlanMap':{VisitPlanMap:{navigate:async()=>{opened++;}}},'../model/VisitPlanState':rules},true);
  const page=new VisitPlan();page.active=true;page.actionId='a';page.plan={...context(),saved:true,stale:true};
  await page.navigate('p'); assert.equal(called,1); assert.equal(opened,1);
});
