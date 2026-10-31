import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fraction,validTarget,assetFile,loadPreset,parseArgs} from '../runtime/bridge.mjs';

test('only the expected loopback Codex page endpoint is accepted',()=>{
 const target={id:'ABC123',type:'page',url:'app://-/index.html',webSocketDebuggerUrl:'ws://127.0.0.1:9222/devtools/page/ABC123'};
 assert.equal(validTarget(target,9222),true);
 for(const changes of [{url:'https://example.com'},{url:'app://-/index.html?initialRoute=%2Favatar-overlay'},{url:'app://-/index.html?initialRoute=/avatar-overlay'},{type:'webview'},{webSocketDebuggerUrl:'ws://192.168.1.1:9222/devtools/page/ABC123'},{webSocketDebuggerUrl:'ws://127.0.0.1:9222/devtools/page/OTHER'},{webSocketDebuggerUrl:'ws://127.0.0.1:9222/devtools/page/ABC123?token=x'}]) assert.equal(validTarget({...target,...changes},9222),false,JSON.stringify(changes));
});
test('asset validation rejects traversal and symlink escape',async()=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'lixingyun-assets-'));
 try{await fs.mkdir(path.join(root,'inside'));await fs.writeFile(path.join(root,'outside'),'asset');await fs.symlink(path.join(root,'outside'),path.join(root,'inside','escape'));await assert.rejects(assetFile(path.join(root,'inside'),'../outside'));await assert.rejects(assetFile(path.join(root,'inside'),'escape'));}finally{await fs.rm(root,{recursive:true,force:true});}
});
test('all five real presets have complete media paths',async()=>{
 const root=new URL('../Assets/',import.meta.url).pathname;
 for(const id of ['line-reveal','wind','still','white-wind','white-still']){const preset=await loadPreset(root,id);await assetFile(root,preset.startup);assert.ok(preset.posterPath);}
 await assert.rejects(loadPreset(root,'missing'));
});
test('invalid opacity and port values cannot reach the renderer',()=>{
 for(const value of [-1,2,'NaN','',undefined])assert.throws(()=>fraction(value));
 assert.equal(fraction('0.7'),.7);assert.throws(()=>parseArgs(['status','--port','0']));
});
