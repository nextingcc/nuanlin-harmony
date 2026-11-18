const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');const vm=require('node:vm');const test=require('node:test');const ts=require('./ts');
const flush=async()=>{for(let i=0;i<15;i++)await Promise.resolve();};
function page(api){
 let source=fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/pages/Interview.ets'),'utf8').replace(/\r\n/g,'\n');
 source=source.slice(0,source.indexOf('  @Builder\n  openingDialog()'))+'}';
 source=source.replace(/@Entry\s*|@Component\s*|@State\s*|@StorageProp\('[^']*'\)\s*/g,'').replace('struct Interview','export class Interview');
 let starts=0,stops=0;const exports={};
 class OpeningPlayer{async stop(){stops++;}async start(...args){starts++;this.args=args;}}
 class VoiceRecorder{cancel(){}}class TtsPlayer{async stop(){}}
 const modules={'../model/FixedOpening':{FIXED_OPENING_SENTENCES:['固定第一句','固定第二句','固定第三句','固定第四句'],fixedOpeningAudio:async()=>'/cache/fixed.mp3'},'../model/Api':{Api:api},'../model/Voice':{VoiceRecorder,TtsPlayer},'../model/OpeningPlayer':{OpeningPlayer},
 '../model/TopicInterviewState':{topicView:()=>({total:7,done:0,current:0,topicId:'t',topicName:'t',questionId:'',question:'q',canAnswer:false,pending:false,retry:false,completed:false,report:'',message:''})},
 '../model/InterviewProgress':{reportSources:()=>[],analysisSteps:()=>[],retrievalSteps:()=>[],analysisSummary:()=>[]}};
 vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,
 {exports,require:n=>modules[n]??{},$r:()=>({}),getContext:()=>({}),AppStorage:{get:()=>1},setTimeout,clearTimeout,setInterval:()=>1,clearInterval(){}});
 const p=new exports.Interview();p.alive=true;p.sessionId='session';return{p,starts:()=>starts,stops:()=>stops};
}
test('start-answer closes opening immediately and late manifest cannot start speech',async()=>{
 let resolve;const {p,starts,stops}=page({opening:()=>new Promise(r=>resolve=r)});
 p.openingVisible=true;const pending=p.playOpening();await flush();p.closeOpening();
 assert.equal(p.openingVisible,false);assert.ok(stops()>0);
 resolve({sentences:['完整开场。'],revision:1});await pending;assert.equal(starts(),0);
});

test('opening uses one bundled clip for all four displayed sentences, never sentence TTS',async()=>{
 const {p,starts}=page({opening:async()=>({sentences:['旧动态文字'],revision:1}),openingTts:()=>{throw Error('must not synthesize');}});
 p.openingVisible=true;await p.playOpening();assert.equal(starts(),1);
 assert.equal(p.openingSentences.length,4);assert.equal(p.openingPlayer.args[0],1);
 assert.equal(await p.openingPlayer.args[1](0),'/cache/fixed.mp3');assert.equal(p.openingPlayer.args[2],1);
 p.closeOpening();assert.equal(p.openingVisible,false);
});
test('leaving while opening metadata is loading prevents later popup or playback',async()=>{
 let resolve;const {p,starts}=page({opening:()=>new Promise(r=>resolve=r)});
 const pending=p.offerOpening({openingText:'完整开场。',openingSentences:['完整开场。']});
 assert.equal(p.openingVisible,true);assert.equal(p.openingSentences[0],'固定第一句');p.suspend();
 resolve({sentences:['迟到开场。'],revision:1});await pending;assert.equal(starts(),0);assert.equal(p.openingSentences[0],'固定第一句');
});
test('fresh safety block closes active opening and releases speech',async()=>{
 const session={id:'session',revision:3,precheckDone:true,completed:false,archived:false,paused:false,safety:{blocked:true},topics:[],summary:{},automation:{status:'idle'}};
 const {p,stops}=page({getInterview:async()=>session});p.openingVisible=true;p.openingOffered=true;await p.refresh();
 assert.equal(p.openingVisible,false);assert.ok(stops()>0);
});

