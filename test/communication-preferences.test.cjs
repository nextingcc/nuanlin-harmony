const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const test=require('node:test');
const ts=require('./ts');
function page(api) {
 const file=path.join(__dirname,'../entry/src/main/ets/pages/CommunicationPreferences.ets');
 let source=fs.readFileSync(file,'utf8');
 source=(source.slice(0,source.indexOf('  build()'))+'}').replace(/@Entry\s*|@Component\s*|@State\s*|@StorageProp\('[^']*'\)\s*/g,'')
  .replace('struct CommunicationPreferences','export class CommunicationPreferences');
 const exports={};let back=0;
 vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,
 {exports,require:n=>n==='../model/Api'?{Api:api}:n==='@kit.ArkUI'?{router:{back(){back++}}}:{}});
 const p=new exports.CommunicationPreferences();p.personId='person';return {p,back:()=>back};
}
test('communication preferences load authoritative version and preserve explicit confirmation only',async()=>{
 const {p}=page({person:async()=>({id:'person',name:'虚构居民',revision:4,preferredAddress:'王奶奶',preferredAddressConfirmed:false,communicationNeeds:['slower']})});
 await p.load();assert.equal(p.ready,true);assert.equal(p.confirmed,false);assert.equal(p.slower,true);assert.equal(p.revision,4);
});
test('communication preference save refuses empty confirmed address and retains input on conflict',async()=>{
 let writes=0;
 const {p,back}=page({updateCommunicationPreferences:async(id,revision,title,confirmed,needs)=>{
 writes++;assert.equal(revision,4);assert.equal(id,'person');assert.equal(title,'王奶奶');assert.equal(confirmed,true);
 assert.equal(needs[0],'slower');throw Error('版本冲突');}});
 p.ready=true;p.revision=4;p.confirmed=true;await p.save();assert.equal(writes,0);
 p.address='王奶奶';p.slower=true;await p.save();assert.equal(writes,1);assert.equal(p.address,'王奶奶');assert.match(p.message,/版本冲突/);assert.equal(back(),0);
});
