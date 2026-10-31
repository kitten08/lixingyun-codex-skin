// Run only against an intentionally started Codex test instance, never the active work session.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const port=process.argv[2];
if(!port || port==='9222')throw new Error('Pass the separate test instance port, e.g. 9223');
const env={...process.env,LIXINGYUN_STATE_DIR:path.join(root,'build/integration-state')};
function call(args){const result=JSON.parse(execFileSync(process.execPath,[path.join(root,'runtime/bridge.mjs'),...args,'--assets',path.join(root,'Assets'),'--port',port],{env,encoding:'utf8'}));assert.equal(result.ok,true,result.message);return result;}
const delay=ms=>new Promise(r=>setTimeout(r,ms));
for(const id of ['line-reveal','wind','still','white-wind','white-still']) {
 call(['apply','--preset',id,'--opacity','.65']);
 await delay(650);
 const s=call(['status']);const r=s.results.find(x=>x.valid);
 assert.equal(r.theme,id);
 if(['wind','white-wind'].includes(id)){
   assert.ok(r.video.ready>=2);assert.equal(r.video.error,null);
   call(['pause','--paused','true']);await delay(1000);
   const a=call(['status']).results.find(x=>x.valid).video;
   await delay(600);const b=call(['status']).results.find(x=>x.valid).video;
   assert.equal(a.paused,true);assert.ok(Math.abs(a.time-b.time)<.05);
   call(['pause','--paused','false']);await delay(800);
   assert.equal(call(['status']).results.find(x=>x.valid).video.paused,false);
 }
 console.log('PASS',id);
}
call(['restore']);const r=call(['status']).results.find(x=>x.valid);assert.equal(r.theme,null);assert.equal(r.video,null);console.log('PASS restore');
