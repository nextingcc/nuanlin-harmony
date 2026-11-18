const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require('./ts');
const root = path.join(__dirname, '../entry/src/main/ets');
function load(file, modules = {}, globals = {}, component = '') {
  let source = fs.readFileSync(path.join(root, file), 'utf8');
  if (component) source = (source.slice(0, source.indexOf(component === 'Profile' ? '  @Builder' : '  build()')) + '}')
    .replace(/@Entry\s*|@Component\s*|@State\s*|@Builder\s*|@StorageProp\('[^']*'\)\s*/g, '')
    .replace('struct ' + component, 'export class ' + component);
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,
    {exports, require: name => modules[name] ?? {}, ...globals});
  return exports;
}
const rules = load('model/ResidenceState.ets');

test('profile edits residence inline, preserves failed draft, cancels and saves with displayed revision', async () => {
  let fail=true; let writes=0;
  const api={updateResidence:async(id,revision,input)=>{writes++;assert.equal(id,'p');assert.equal(revision,4);
    if(fail)throw Error('版本冲突');return {id,revision:5,...input};}};
  const {Profile}=load('pages/Profile.ets',{'../model/Api':{Api:api},'../model/ResidenceState':rules},
    {$r:()=>({})},'Profile');
  const page=new Profile();page.personId='p';page.residenceEditable=true;
  page.residencePerson={id:'p',revision:4,address:'虚构旧地址',phone:''};page.resetResidence();
  page.editPhone='01012345678';page.markResidence();assert.equal(page.residenceDirty,true);
  await page.load();assert.equal(page.editPhone,'01012345678');
  await page.saveResidence();assert.equal(page.residenceDirty,true);assert.match(page.residenceMessage,/版本冲突/);
  page.resetResidence();assert.equal(page.editPhone,'');assert.equal(page.residenceDirty,false);
  page.editAddress=' ';page.markResidence();await page.saveResidence();assert.equal(writes,1);
  page.editAddress='虚构新地址';page.markResidence();fail=false;await page.saveResidence();
  assert.equal(page.residenceDirty,false);assert.equal(page.residencePerson.revision,5);assert.equal(page.editAddress,'虚构新地址');
});
test('residence refuses masked or mismatched records, retains unknown values, validates phones', () => {
  const person = {id:'person', revision:2, address:null, phone:null};
  const input = rules.residenceInput(person, 'person');
  assert.equal(input.address, '');
  assert.equal(input.living, '');
  assert.match(rules.validateResidence(input), /居住地址/);
  assert.throws(() => rules.residenceInput({...person,address:'***'}, 'person'), /脱敏/);
  assert.throws(() => rules.residenceInput(person,'other'), /核对/);
  assert.throws(() => rules.residenceInput({...person,revision:undefined},'person'), /版本/);
  assert.match(rules.validateResidence({...input,address:'虚构地址',contactPhone:'123'}), /电话/);
});
test('residence save uses displayed revision and retains draft on version conflict', async () => {
  let back = 0;
  const writes = [];
  const api = {person:async () => ({id:'person', revision:4,name:'虚构居民',address:'虚构小区1号',phone:''}),
    updateResidence:async (...args) => {writes.push(args); throw new Error('版本冲突');}};
  const {ResidenceEdit} = load('pages/ResidenceEdit.ets', {'../model/Api':{Api:api},
    '../model/ResidenceState':rules, '@kit.ArkUI':{router:{back(){back++;}}}}, {}, 'ResidenceEdit');
  const page = new ResidenceEdit(); page.personId='person';
  await page.load(); page.address='新的虚构住址'; await page.save();
  assert.equal(writes[0][1], 4); assert.equal(writes[0][2].address, '新的虚构住址');
  assert.equal(page.address, '新的虚构住址'); assert.match(page.message, /版本冲突/); assert.equal(back,0);
  page.ready=false; await page.save(); assert.equal(writes.length,1);
});
test('import review carries address and contacts into manual form without inventing missing fields', () => {
  let draft;
  const {ImportPerson} = load('pages/ImportPerson.ets', {'@kit.ArkUI':{router:{pushUrl(){}}}},
    {AppStorage:{setOrCreate(key,value){draft=JSON.parse(value);}}}, 'ImportPerson');
  const page = new ImportPerson();
  page.applyResult({result:{fields:[{field:'address',value:'虚构地址'},{field:'phone',value:'01012345678'},
    {field:'living',value:'独居'},{field:'contactName',value:'虚构联系人'},{field:'contactPhone',value:'01087654321'}],noteFacts:[],issues:[]},blocks:[]});
  page.adopt();
  assert.equal(draft.address,'虚构地址'); assert.equal(draft.phone,'01012345678');
  assert.equal(draft.living,'独居'); assert.equal(draft.contactName,'虚构联系人'); assert.equal(draft.contactPhone,'01087654321');
});
test('new person restores reviewed residence draft and preserves the fields when saving', async () => {
  let saved;
  const draft={name:'虚构居民',age:'72',gender:'女',community:'虚构社区',address:'虚构地址',phone:'01012345678',
    living:'独居',contactName:'虚构联系人',contactPhone:'01087654321'};
  const {PersonForm}=load('pages/PersonForm.ets',{'../model/Api':{Api:{createPerson:async input => {saved=input;return {id:'created',name:input.name};}}},
    '@kit.ArkUI':{router:{replaceUrl(){}},promptAction:{showToast(){}}}},
    {AppStorage:{get(){return JSON.stringify(draft);},setOrCreate(){}},AlertDialog:{show(){throw new Error('unexpected validation');}}},'PersonForm');
  const page=new PersonForm();page.aboutToAppear();await page.save();
  for(const field of ['address','phone','living','contactName','contactPhone']) assert.equal(saved[field],draft[field]);
});
