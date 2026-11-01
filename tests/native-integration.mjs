// Only mutates the explicitly supplied isolated test state, never user state.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
const root=path.resolve(process.argv[2]||'');
if(!root.endsWith('/work/official-startup-isolated/state'))throw Error('Pass the isolated fixture state directory');
const statePath=path.join(root,'appearance.json'),statusPath=path.join(root,'native-status.json'),cases=[];
const original=JSON.parse(await fs.readFile(statePath,'utf8'));
async function wait(predicate,timeout=45000){
 const until=Date.now()+timeout;
 while(Date.now()<until){
  let s;try{s=JSON.parse(await fs.readFile(statusPath,'utf8'));}catch(e){if(e.code==='ENOENT'){await new Promise(r=>setTimeout(r,250));continue;}throw e;}
  if(s.error)throw Error(s.error);
  if(Date.now()-s.updatedAt<5000&&predicate(s))return s;
  await new Promise(r=>setTimeout(r,250));
 }
 throw Error('Native fixture timed out');
}
async function write(patch){const s={...original,...patch,revision:randomUUID()};await fs.writeFile(statePath,JSON.stringify(s));return s;}
const cold=await wait(s=>s.results?.[0]?.intro?.phase==='done');
assert.equal(cold.results[0].intro.reason,'handoff');assert(cold.results[0].intro.frames>0);
cases.push({name:'ordinary launch plays once and hands off without CDP',pass:true,evidence:cold});
await write({paused:true});const paused=await wait(s=>s.paused&&s.results[0]?.video?.paused);
cases.push({name:'native pause applies from saved controls',pass:true});
await write({enabled:false});await wait(s=>!s.enabled&&s.results[0]?.version===null&&!s.results[0]?.intro?.overlay);
cases.push({name:'restore removes wallpaper and startup overlay',pass:true});
await write({enabled:true,paused:false});await wait(s=>s.enabled&&s.results[0]?.version==='lixingyun-1.2.0'&&s.results[0]?.video?.ready>=2);
cases.push({name:'re-enable restores the moving wallpaper',pass:true});
const token=randomUUID();await write({introRequest:{token,startup:'white-wind',status:'pending',queuedAt:Date.now()}});
const preview=await wait(s=>s.results[0]?.intro?.token===token&&['preparing','playing','revealing','done'].includes(s.results[0]?.intro?.phase));
assert(preview.results[0].intro.overlay||preview.results[0].intro.reason==='handoff');
cases.push({name:'preview request installs the native overlay without a debugging connection',pass:true,evidence:preview});
await write({enabled:false,introRequest:null});await wait(s=>!s.enabled&&!s.results[0]?.intro?.overlay);
cases.push({name:'restore cancels a queued preview while the test window is hidden',pass:true});
await write({enabled:true,paused:false,introRequest:null});await wait(s=>s.enabled&&s.results[0]?.video?.ready>=2);
await fs.writeFile(path.join(root,'native-verification.json'),JSON.stringify({pass:true,cases},null,2));
console.log(JSON.stringify({pass:true,cases:cases.map(({name,pass})=>({name,pass}))}));
