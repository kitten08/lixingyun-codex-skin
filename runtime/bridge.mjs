/** Local Codex appearance bridge. No remote server, credentials, or app patching. */
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash, randomUUID} from 'node:crypto';
import {Script} from 'node:vm';

const exec = promisify(execFile);
const HERE = path.dirname(fileURLToPath(import.meta.url));
const STATE_KEY = '__CODEX_DREAM_SKIN_STATE__';
const SUPPORT = process.env.LIXINGYUN_STATE_DIR || path.join(os.homedir(), 'Library/Application Support/LiXingyunCodex');
const STATE_FILE = path.join(SUPPORT, 'appearance.json');
const DEFAULT = {enabled:false, preset:'wind', opacity:0.70, paused:false, revision:''};
const MAX_MEDIA = 64 * 1024 * 1024;
const WAITING = '已保存。当前 Codex 尚未开放背景连接；请在任务结束后完全退出 Codex，再从「星云 · Codex」启动。';
const PORT = 9222;

export function parseArgs(args) {
  const out = {command:args[0] || 'status', port:PORT};
  for(let i=1;i<args.length;i+=2) {
    if(!args[i].startsWith('--') || args[i+1] === undefined) throw new Error('参数不完整');
    out[args[i].slice(2)] = args[i+1];
  }
  out.port = Number(out.port);
  if(!Number.isInteger(out.port) || out.port<1024 || out.port>65535) throw new Error('端口无效');
  return out;
}
export function fraction(value) {
  if(value === undefined || value === '' || !Number.isFinite(Number(value)) || Number(value)<0 || Number(value)>1) throw new Error('透明度应为 0 到 1');
  return Number(value);
}
export async function readState() {
  try {return {...DEFAULT,...JSON.parse(await fs.readFile(STATE_FILE,'utf8'))};}
  catch(e) {if(e.code==='ENOENT') return {...DEFAULT}; throw e;}
}
async function saveState(patch) {
  const next={...await readState(),...patch,revision:randomUUID()};
  await fs.mkdir(SUPPORT,{recursive:true,mode:0o700});
  const tmp=STATE_FILE+'.'+process.pid+'.tmp';
  await fs.writeFile(tmp,JSON.stringify(next,null,2)+'\n',{mode:0o600});
  await fs.rename(tmp,STATE_FILE);
  return next;
}
export async function assetFile(root, relative) {
  if(typeof relative!=='string' || !relative || path.isAbsolute(relative)) throw new Error('素材路径无效');
  const base=await fs.realpath(root);
  const resolved=await fs.realpath(path.resolve(base,relative));
  if(!resolved.startsWith(base+path.sep)) throw new Error('素材不能位于素材库之外');
  const stat=await fs.stat(resolved);
  if(!stat.isFile() || stat.size===0 || stat.size>MAX_MEDIA) throw new Error('素材文件为空或超过 64 MB');
  return resolved;
}
export async function loadPreset(root,id) {
  const list=JSON.parse(await fs.readFile(await assetFile(root,'presets.json'),'utf8'));
  if(!Array.isArray(list) || list.length!==5 || new Set(list.map(p=>p.id)).size!==5) throw new Error('素材库应包含五个不同预设');
  const preset=list.find(p=>p.id===id);
  if(!preset) throw new Error('找不到所选预设');
  if(!['image','video'].includes(preset.wallpaperType)) throw new Error('不支持此壁纸类型');
  return {...preset,wallpaperPath:await assetFile(root,preset.wallpaper),posterPath:await assetFile(root,preset.poster)};
}

export function validTarget(target,port) {
  try {
    const url=new URL(target.url), ws=new URL(target.webSocketDebuggerUrl);
    return target.type==='page' && url.protocol==='app:' && !/avatar-overlay|devtools|extension|browser/i.test(url.pathname+url.search)
      && /^[A-Za-z0-9._-]{1,200}$/.test(target.id)
      && ws.protocol==='ws:' && ws.hostname==='127.0.0.1' && Number(ws.port)===port
      && !ws.username && !ws.password && !ws.search && !ws.hash
      && ws.pathname===`/devtools/page/${target.id}`;
  } catch {return false;}
}

async function verifyPortOwner(port) {
  let output;
  try {output=(await exec('/usr/sbin/lsof',['-nP',`-iTCP:${port}`,'-sTCP:LISTEN','-FpLn'],{timeout:3000})).stdout;}
  catch {return false;}
  const pids=[...new Set([...output.matchAll(/^p(\d+)$/gm)].map(m=>m[1]))];
  if(!pids.length || /\n n/.test(output)) return false;
  // All listening addresses must be loopback. Never attach to an exposed endpoint.
  for(const line of output.split('\n').filter(s=>s.startsWith('n'))) {
    if(line!==`n127.0.0.1:${port}` && line!==`n[::1]:${port}`) return false;
  }
  for(const listener of pids) {
    // Official helper subprocesses may inherit the listening descriptor. Accept
    // them only when their same-user ancestry reaches a verified Codex binary.
    let pid=listener,verified=false;
    for(let depth=0;depth<16 && Number(pid)>1;depth++) {
      const info=(await exec('/bin/ps',['-p',pid,'-o','uid=,ppid=,comm='],{timeout:2000})).stdout.trim();
      const match=/^(\d+)\s+(\d+)\s+(.+)$/.exec(info);
      if(!match || Number(match[1])!==process.getuid())break;
      const exe=match[3];
      if(/\/(ChatGPT|Codex)\.app\/Contents\/MacOS\/(ChatGPT|Codex)$/.test(exe)) {
        const bundle=exe.slice(0,exe.indexOf('.app/')+4);
        const identity=(await exec('/usr/libexec/PlistBuddy',['-c','Print :CFBundleIdentifier',path.join(bundle,'Contents/Info.plist')],{timeout:2000})).stdout.trim();
        if(identity!=='com.openai.codex')break;
        const signed=await exec('/usr/bin/codesign',['-dv','--verbose=4',bundle],{timeout:5000});
        verified=signed.stderr.includes('TeamIdentifier=2DC432GLL2');break;
      }
      pid=match[2];
    }
    if(!verified)return false;
  }
  return true;
}

export class Session {
  constructor(url) {this.ws=new WebSocket(url);this.seq=0;this.pending=new Map();}
  async open() {
    await new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{this.ws.close();reject(new Error('连接超时'));},4000);
      this.ws.addEventListener('open',()=>{clearTimeout(timer);resolve();},{once:true});
      this.ws.addEventListener('error',()=>{clearTimeout(timer);reject(new Error('连接失败'));},{once:true});
    });
    this.ws.addEventListener('message',e=>{
      const data=JSON.parse(e.data), item=this.pending.get(data.id);
      if(!item)return;
      this.pending.delete(data.id);clearTimeout(item.timer);
      data.error?item.reject(new Error(data.error.message)):item.resolve(data.result);
    });
    this.ws.addEventListener('close',()=>this.cancel());
    this.ws.addEventListener('error',()=>this.cancel());
    return this;
  }
  cancel() {for(const v of this.pending.values()){clearTimeout(v.timer);v.reject(new Error('连接已关闭'));}this.pending.clear();}
  request(method,params={}) {
    return new Promise((resolve,reject)=>{
      const id=++this.seq;
      const timer=setTimeout(()=>{this.pending.delete(id);reject(new Error('操作超时'));},10000);
      this.pending.set(id,{resolve,reject,timer});
      try {this.ws.send(JSON.stringify({id,method,params}));} catch(e){clearTimeout(timer);this.pending.delete(id);reject(e);}
    });
  }
  async evaluate(expression) {
    const value=await this.request('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});
    if(value.exceptionDetails)throw new Error(value.exceptionDetails.exception?.description || value.exceptionDetails.text);
    return value.result?.value;
  }
  close(){this.cancel();this.ws.close();}
}

async function targets(port) {
  if(!await verifyPortOwner(port))return [];
  const response=await fetch(`http://127.0.0.1:${port}/json/list`,{redirect:'error',signal:AbortSignal.timeout(2000)});
  if(!response.ok)return [];
  const result=await response.json();
  return Array.isArray(result)?result.filter(t=>validTarget(t,port)):[];
}
const PROBE=`(() => ({valid: location.protocol==='app:' && !!document.querySelector('main,[role="main"],[data-testid="app-shell-main"]'),theme:window.${STATE_KEY}?.themeId || null,revision:window.__LIXINGYUN_REVISION__ || null,video: (()=>{const v=document.getElementById('codex-dream-skin-media');return v?{ready:v.readyState,paused:v.paused,time:v.currentTime,error:v.error?.message || null}:null})()}))()`;

async function payload(root,preset,state) {
  const [template,css,poster]=await Promise.all([
    fs.readFile(path.join(HERE,'vendor/renderer-inject.js'),'utf8'),
    fs.readFile(path.join(HERE,'vendor/dream-skin.css'),'utf8'),
    fs.readFile(preset.posterPath)
  ]);
  const isVideo=preset.wallpaperType==='video';
  const art=isVideo?poster:await fs.readFile(preset.wallpaperPath);
  const imagePath=isVideo?preset.posterPath:preset.wallpaperPath;
  const mime=/\.jpe?g$/i.test(imagePath)?'image/jpeg':'image/png';
  const media=isVideo?await fs.readFile(preset.wallpaperPath):null;
  const theme={id:preset.id,name:preset.name,tagline:'你欲何为',quote:'你欲何为',brandSubtitle:'李星云 · CODEX',statusText:'',appearance:'auto',colorMode:'adaptive',artKey:createHash('sha256').update(art).digest('hex'),art:{focusX:0.72,focusY:0.5,safeArea:'none',taskMode:'full'},userTransparency:40,media:{type:isVideo?'video':'image',mime:'video/mp4',size:media?.length || 0,opacity:state.opacity}};
  const substitutions={CSS:css,ART:`data:${mime};base64,${art.toString('base64')}`,THEME:theme,VERSION:'lixingyun-1.0.0',STYLE_REVISION:'lixingyun-1',PAYLOAD_REVISION:state.revision};
  let source=template;
  for(const [key,value]of Object.entries(substitutions))source=source.replace(`__DREAM_SKIN_${key}_JSON__`,()=>JSON.stringify(value));
  if(/__DREAM_SKIN_[A-Z0-9_]+_JSON__/.test(source))throw new Error('背景模板不完整');
  new Script(source);
  return {source,media};
}

async function applySession(session,root,state,cache) {
  const probe=await session.evaluate(PROBE);
  if(!probe?.valid)return {skipped:true};
  if(!state.enabled) {
    await session.evaluate(`window.${STATE_KEY}?.cleanup(); delete window.__LIXINGYUN_REVISION__; true`);
    return {restored:true};
  }
  if(probe.theme!==state.preset || probe.revision!==state.revision) {
    const sameMedia=probe.theme===state.preset && probe.revision && cache.lastPreset===state.preset;
    if(!sameMedia) {
      const preset=await loadPreset(root,state.preset);
      const built=cache.revision===state.revision?cache.built:await payload(root,preset,state);
      cache.revision=state.revision;cache.built=built;
      await session.evaluate(built.source);
      if(built.media) {
        const begun=await session.evaluate(`window.${STATE_KEY}.beginMedia(${JSON.stringify({mime:'video/mp4',size:built.media.length})})`);
        if(!begun)throw new Error('壁纸传输初始化失败');
        for(let i=0;i<built.media.length;i+=384*1024) {
          const chunk=built.media.subarray(i,i+384*1024).toString('base64');
          if(!await session.evaluate(`window.${STATE_KEY}.appendMedia(${JSON.stringify(chunk)})`))throw new Error('壁纸数据校验失败');
        }
        if(!await session.evaluate(`window.${STATE_KEY}.commitMedia()`))throw new Error('壁纸传输不完整');
      }
    }
    await session.evaluate(`window.${STATE_KEY}.setWallpaperReveal(${state.opacity}); window.${STATE_KEY}.setPaused(${Boolean(state.paused)}); window.__LIXINGYUN_REVISION__=${JSON.stringify(state.revision)}; true`);
    cache.lastPreset=state.preset;
  }
  return await session.evaluate(PROBE);
}

async function withTargets(options,action) {
  const list=await targets(options.port);
  const results=[];
  for(const target of list){const session=await new Session(target.webSocketDebuggerUrl).open();try{results.push(await action(session));}finally{session.close();}}
  return results;
}

async function run(options) {
  const root=path.resolve(options.assets || path.join(HERE,'../Assets'));
  if(options.command==='validate'){
    const list=JSON.parse(await fs.readFile(path.join(root,'presets.json'),'utf8'));
    for(const p of list){await loadPreset(root,p.id);await assetFile(root,p.startup);}
    return {ok:true,message:'五套素材校验通过',count:list.length};
  }
  if(options.command==='watch') {
    let stopped=false;process.on('SIGTERM',()=>stopped=true);process.on('SIGINT',()=>stopped=true);
    const parentPid=process.ppid;
    const cache={};
    while(!stopped && process.ppid===parentPid && parentPid>1){try{const state=await readState();await withTargets(options,s=>applySession(s,root,state,cache));}catch(e){process.stderr.write(`background: ${e.message}\n`);}await new Promise(r=>setTimeout(r,2500));}
    return {ok:true,message:'背景连接已停止'};
  }
  if(options.command==='status') {
    const state=await readState();
    const results=await withTargets(options,s=>s.evaluate(PROBE));
    const connected=results.some(r=>r.valid);
    return {ok:true,connected,enabled:state.enabled,preset:state.preset,paused:state.paused,opacity:state.opacity,results,message:connected?'Codex 背景已连接':'等待 Codex 背景连接'};
  }
  let state;
  switch(options.command){
    case 'apply':await loadPreset(root,options.preset);state=await saveState({enabled:true,preset:options.preset,opacity:fraction(options.opacity ?? .7),paused:false});break;
    case 'pause':if(!['true','false'].includes(options.paused))throw new Error('暂停参数无效');state=await saveState({paused:options.paused==='true'});break;
    case 'opacity':state=await saveState({opacity:fraction(options.value)});break;
    case 'restore':state=await saveState({enabled:false});break;
    default:throw new Error('未知命令');
  }
  const results=await withTargets(options,s=>applySession(s,root,state,{}));
  const connected=results.some(r=>!r.skipped);
  return {ok:connected || options.command==='restore',connected,enabled:state.enabled,message:options.command==='restore'?'已恢复默认，自动背景已关闭':connected?'已应用到 Codex':WAITING};
}

if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try{console.log(JSON.stringify(await run(parseArgs(process.argv.slice(2)))));}
  catch(e){console.log(JSON.stringify({ok:false,message:e.message}));process.exitCode=1;}
}
