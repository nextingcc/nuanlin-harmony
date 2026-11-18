const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require('./ts');
const root = path.join(__dirname, '../entry/src/main/ets');
function load(file, modules = {}, globals = {}, component = '') {
 let source = fs.readFileSync(path.join(root,file),'utf8');
 if(component) source=(source.slice(0,source.indexOf('  build()'))+'}')
  .replace(/@Entry\s*|@Component\s*|@State\s*|@StorageProp\('[^']*'\)\s*/g,'')
  .replace('struct '+component,'export class '+component);
 const exports={};
 vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,
 {exports,require:name=>modules[name]??{},setTimeout,clearTimeout,...globals});
 return exports;
}
const rules=load('model/MapLocationState.ets');
const amap=load('model/AmapNavigation.ets',{'./MapLocationState':rules});
const point={latitude:30.6,longitude:114.3,coordinateSystem:'GCJ02',provider:'huawei',cityCode:'420100',
 addressSnapshot:'武汉虚构住所',entranceLabel:'核对入口',status:'confirmed'};
const context=()=>({personId:'person',revision:4,address:point.addressSnapshot,location:{...point}});
function page(api={}, kit={}, globals={}, visitMap={openWebMap:async()=>{}}) {
 const {MapLocation}=load('pages/MapLocation.ets',{'../model/Api':{Api:api},'../model/MapLocationState':rules,
  '../model/AmapNavigation':{...amap,...visitMap},'../model/VisitPlanMap':visitMap,'@kit.MapKit':kit},
 {getContext:()=>({}),...globals},'MapLocation');
 const p=new MapLocation(); p.personId='person'; return p;
}

test('entering an unverified address automatically searches and waits for map readiness',async()=>{
 let searches=0,selected=0;
 const item={siteId:'one',addressComponent:{adminLevel2:'武汉市'},location:{latitude:30.6,longitude:114.3}};
 const p=page({residenceLocation:async()=>({...context(),location:null})},{site:{searchByText:async(params)=>{searches++;return{sites:[item]};}}});
 await p.load();assert.equal(searches,1);assert.equal(p.query,point.addressSnapshot);assert.equal(p.searchPreview.siteId,'one');
 p.mapLoaded=true;p.controller={};p.selectPoint=async()=>{selected++;};await p.showSearchPreview();
 assert.equal(selected,1);assert.equal(p.acknowledged,false);
});

test('saved address avoids searches while ambiguous matches only preview without confirming',async()=>{
 let searches=0,markers=0,selected=0;
 const p=page({residenceLocation:async()=>context()},{site:{searchByText:async()=>{searches++;return{sites:[]};}},map:{newLatLng:p=>p}});
 await p.load();assert.equal(searches,0);
 p.mapLoaded=true;p.controller={moveCamera(){},addMarker:async()=>{markers++;return{remove(){}};}};
 p.results=[{},{}];p.searchPreview={location:{latitude:30.6,longitude:114.3}};
 p.selectPoint=async()=>{selected++;};await p.showSearchPreview();
 assert.equal(markers,1);assert.equal(selected,0);assert.equal(p.candidate,null);assert.equal(p.acknowledged,false);
});
test('navigation refuses stale, masked, mismatched or unconfirmed residence',()=>{
 assert.equal(rules.navigableLocation(context(),'person').latitude,30.6);
 for(const c of [{...context(),personId:'other'},{...context(),address:'新住址'},{...context(),address:'***'},
 {...context(),location:{...point,status:'candidate'}},{...context(),location:{...point,coordinateSystem:'unknown'}},
 {...context(),location:{...point,latitude:NaN}}]) assert.throws(()=>rules.navigableLocation(c,'person'));
 assert.throws(()=>rules.requireLocationContext({...context(),revision:0},'person'));
 assert.equal(rules.isWuhanCity('武汉市'),true); assert.equal(rules.isWuhanCity('武汉路'),false);
});
test('failed searches clear prior candidates and never create fallback locations',async()=>{
 const p=page({}, {site:{searchByText:async()=>{throw Error('service unavailable')}}});
 p.context=context();p.query='武汉公共地点';p.candidate={...point};p.acknowledged=true;
 await p.search();assert.equal(p.candidate,null);assert.equal(p.results.length,0);assert.equal(p.acknowledged,false);
 assert.match(p.message,/失败/);assert.equal(p.busy,false);
});
test('late search results after leaving cannot update resident context',async()=>{
 let resolve;
 const p=page({}, {site:{searchByText:()=>new Promise(r=>resolve=r)}});
 p.context=context();p.query='武汉公共地点';const pending=p.search();p.aboutToDisappear();
 resolve({sites:[{siteId:'one',addressComponent:{adminLevel2:'武汉市'},location:{latitude:30.6,longitude:114.3}}]});
 await pending;assert.equal(p.results.length,0);
});
test('map save requires loaded map, explicit acknowledgement and authoritative revision',async()=>{
 let writes=0;
 const p=page({saveResidenceLocation:async(id,revision,input)=>{
  writes++;assert.equal(id,'person');assert.equal(revision,4);assert.equal(input.addressSnapshot,point.addressSnapshot);
  throw Error('版本冲突');
 }});
 p.context=context();p.candidate={...point,confirmed:true};
 await p.save();p.mapLoaded=true;await p.save();assert.equal(writes,0);
 p.acknowledged=true;await p.save();assert.equal(writes,1);assert.match(p.message,/版本冲突/);
 assert.ok(p.candidate);assert.equal(p.busy,false);
});
test('navigation reloads residence and rejects changed address before calling map app',async()=>{
 let calls=0;
 const p=page({residenceLocation:async()=>({...context(),address:'新地址'})},{petalMaps:{openMapNavi:async()=>{calls++}}});
 p.context=context();await p.navigate();assert.equal(calls,0);assert.match(p.message,/未打开导航/);
});
test('navigation opens Amap route with GCJ02 or address search without stale coordinates',async()=>{
 let url='';
 const p=page({residenceLocation:async()=>context()},{},{},{openAmapUrl:async(ctx,value)=>{url=value;}});
 await p.navigate();assert.match(url,/uri.amap.com\/navigation/);assert.match(url,/to=114.3,30.6/);assert.match(url,/mode=walk/);assert.match(url,/callnative=1/);
 const changed={...context(),address:'武汉新住所&测试'};
 url=amap.amapResidenceUrl(changed,'person',false);assert.match(url,/\/search/);assert.ok(url.includes(encodeURIComponent(changed.address)));assert.ok(!url.includes('114.3'));
 assert.throws(()=>amap.amapResidenceUrl({...context(),personId:'other'},'person',false));
 assert.throws(()=>amap.amapResidenceUrl({...context(),address:'***'},'person',false));
 assert.match(amap.amapResidenceUrl({...context(),location:{...point,coordinateSystem:'WGS84'}},'person',false),/\/search/);
});
