const assert=require('node:assert/strict');
const fs=require('node:fs'); const path=require('node:path'); const vm=require('node:vm');const test=require('node:test');const ts=require('./ts');
const root=path.join(__dirname,'../entry/src/main/ets');
function load(file, modules={}, globals={}, component=''){
 let source=fs.readFileSync(path.join(root,file),'utf8');
 if(component)source=source.slice(0,source.indexOf('  @Builder\n  openingDialog()'))+'}';
 if(component)source=source.replace(/@Entry\s*|@Component\s*|@State\s*|@StorageProp\('[^']*'\)\s*/g,'').replace('struct '+component,'export class '+component);
 const exports={};vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,
 {exports,require:name=>modules[name]??{},setTimeout,clearTimeout,clearInterval,...globals});return exports;
}
const flush=async()=>{for(let i=0;i<12;i++)await Promise.resolve();};
function playerHarness(){
 const players=[];
 const media={PlaybackSpeed:{SPEED_FORWARD_1_00_X:1},createAVPlayer:async()=>{
  const handlers={}; const p={state:'idle',on(n,fn){handlers[n]=fn;},setSpeed(){},
   async prepare(){this.emit('prepared');},async play(){this.emit('playing');},async pause(){this.emit('paused');},
   async release(){this.released=true;this.state='released';},emit(state){this.state=state;handlers.stateChange?.(state);}};
  Object.defineProperty(p,'fdSrc',{set(){p.emit('initialized');}});players.push(p);return p;
 }};
 const fileIo={OpenMode:{READ_ONLY:0},openSync:()=>({fd:1}),statSync:()=>({size:10}),closeSync(){}};
 const {OpeningPlayer}=load('model/OpeningPlayer.ets',{'@kit.MediaKit':{media},'@kit.CoreFileKit':{fileIo}});
 return{controller:new OpeningPlayer(),players};
}
test('opening highlights actual playing sentence, pause/resume keeps same player and ends once',async()=>{
 const {controller,players}=playerHarness();const states=[];
 await controller.start(2,async i=>'sentence-'+i,1,(s,i)=>states.push([s,i]));await flush();
 assert.ok(states.some(([s,i])=>s==='playing'&&i===0));
 await controller.pause();assert.equal(players[0].state,'paused');await controller.resume();assert.equal(players.length,1);
 players[0].emit('completed');await flush();assert.equal(players.length,2);assert.ok(states.some(([s,i])=>s==='playing'&&i===1));
 players[1].emit('completed');await flush();assert.equal(states.filter(([s])=>s==='ended').length,1);assert.equal(players.length,2);await controller.stop();
});
test('stopping during synthesis discards late audio and cannot create a player',async()=>{
 const {controller,players}=playerHarness();let resolve;
 await controller.start(1,()=>new Promise(r=>resolve=r),1,()=>{});await flush();await controller.stop();resolve('late');await flush();assert.equal(players.length,0);
});
test('pause during synthesis waits for explicit resume before playing',async()=>{
 const {controller,players}=playerHarness();let resolve;
 await controller.start(1,()=>new Promise(r=>resolve=r),1,()=>{});await flush();await controller.pause();resolve('clip');await flush();assert.equal(players.length,0);
 await controller.resume();await flush();assert.equal(players[0].state,'playing');await controller.stop();
});
test('replay releases old player and restarts sentence zero; late completion cannot advance new run',async()=>{
 const {controller,players}=playerHarness();const states=[];
 await controller.start(2,async i=>'old-'+i,1,(s,i)=>states.push([s,i]));await flush();
 const old=players[0];await controller.start(2,async i=>'new-'+i,1,(s,i)=>states.push([s,i]));await flush();
 assert.equal(old.released,true);old.emit('completed');await flush();assert.equal(players.length,2);assert.equal(players[1].state,'playing');assert.equal(states.at(-1)[1],0);await controller.stop();
});
test('synthesis errors preserve a retryable error state and do not loop',async()=>{
 const {controller,players}=playerHarness();const states=[];let calls=0;
 await controller.start(1,async()=>{calls++;throw Error('tts unavailable');},1,(s)=>states.push(s));await flush();
 assert.equal(calls,1);assert.equal(players.length,0);assert.equal(states.at(-1),'error');await controller.stop();
});
