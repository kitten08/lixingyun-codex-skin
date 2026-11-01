// Runs in Electron's main process. Uses webContents directly; no debugging port.
const fs=require('node:fs/promises');
const path=require('node:path');
const os=require('node:os');
const {pathToFileURL}=require('node:url');
const {randomUUID,createHash}=require('node:crypto');
module.exports.install=function({app,root=__dirname,support=process.env.LIXINGYUN_STATE_DIR || path.join(os.homedir(),'Library/Application Support/LiXingyunCodex')}={}) {
  const electron=require('electron');app ||= electron.app;
  const stateFile=path.join(support,'appearance.json'),statusFile=path.join(support,'native-status.json');
  const key='__CODEX_DREAM_SKIN_STATE__',introKey='__LIXINGYUN_INTRO_STATE__';
  let contents=null,busy=false,stopped=false,played=false,revision=null,lastPreset=null,error=null,timer;
  const probe=`(() => ({valid:!!document.querySelector('main,[role="main"],[data-testid="app-shell-main"]'),hidden:document.hidden,version:window.${key}?.version||null,theme:window.${key}?.themeId||null,intro:window.${introKey}?.probe()||window.__LIXINGYUN_INTRO_LAST__||null,video:(()=>{const v=document.getElementById('codex-dream-skin-media');return v?{ready:v.readyState,paused:v.paused,time:v.currentTime,error:v.error?.message||null}:null})()}))()`;
  const modules=Promise.all(['intro-renderer.mjs','wallpaper-layer.mjs'].map(p=>import(pathToFileURL(path.join(root,p)).href)));
  const manifests=fs.readFile(path.join(root,'Assets/presets.json'),'utf8').then(JSON.parse);
  const readState=async()=>{try{return JSON.parse(await fs.readFile(stateFile,'utf8'));}catch(e){if(e.code==='ENOENT')return {enabled:true,preset:'wind',startup:'wind',opacity:.7};throw e;}};
  const evaluate=s=>contents.executeJavaScript(s,true);
  async function status(state,renderer){
    await fs.mkdir(support,{recursive:true,mode:0o700});
    const value={mode:'native',pid:process.pid,updatedAt:Date.now(),bundleVersion:app.getVersion(),bundlePath:path.resolve(process.resourcesPath,'../..'),connected:Boolean(renderer&&(renderer.valid||renderer.version==='lixingyun-1.2.0')),enabled:Boolean(state.enabled),preset:state.preset,startup:state.startup,opacity:state.opacity,paused:Boolean(state.paused),revision:state.revision,introPending:renderer?.intro?.phase==='preparing',introPhase:renderer?.intro?.phase||'done',results:renderer?[renderer]:[],error};
    const temp=statusFile+'.'+process.pid+'.tmp';await fs.writeFile(temp,JSON.stringify(value),{mode:0o600});await fs.rename(temp,statusFile);
  }
  async function tick(){
    if(stopped||busy)return;
    if(!contents||contents.isDestroyed()){
      contents=electron.webContents.getAllWebContents().find(wc=>{try{const u=new URL(wc.getURL());return u.protocol==='app:'&&u.pathname.endsWith('/index.html');}catch{return false;}});
      if(!contents){
        const state=await readState();await status(state,null).catch(()=>{});return;
      }
    }
    busy=true;let state={};
    try{
      state=await readState();
      const list=await manifests;
      const preset=list.find(p=>p.id===state.preset)||list.find(p=>p.id==='wind');
      const startup=list.find(p=>p.id===(state.startup||state.preset))||preset;
      const [{installIntro},{installImageLayer}]=await modules;
      if(!state.enabled){
        await evaluate(`window.${introKey}?.cleanup('restore');window.__LIXINGYUN_WALLPAPER_LAYER__?.cleanup();window.${key}?.cleanup();true`);
        revision=null;lastPreset=null;await status(state,await evaluate(probe));return;
      }
      let result=await evaluate(probe);
      // Prepare the modal before React's main area is ready, once per process.
      if(!played){
        const data=await fs.readFile(path.join(root,'Assets',startup.startup));
        const pending=state.introRequest;
        const token=pending?.status==='pending'&&Date.now()-pending.queuedAt<120000?pending.token:randomUUID();
        const config={token,mediaSize:data.length,mediaMime:'video/mp4',handoffTime:startup.introHandoff,fadeMs:700,appearance:startup.id.startsWith('white')?'light':'dark',syncBackground:startup.id===preset.id};
        await evaluate(`(${installIntro.toString()})(${JSON.stringify(config)})`);
        await transfer(introKey,data);played=true;
      }
      // The app's React main area can wait for sign-in or network. The verified
      // index document itself is sufficient to prepare the local movie/layer.
      if(lastPreset!==preset.id||result.version!=='lixingyun-1.2.0'){
        const [template,css,poster]=await Promise.all([fs.readFile(path.join(root,'vendor/renderer-inject.js'),'utf8'),fs.readFile(path.join(root,'vendor/dream-skin.css'),'utf8'),fs.readFile(path.join(root,'Assets',preset.poster))]);
        const video=preset.wallpaperType==='video',art=video?poster:await fs.readFile(path.join(root,'Assets',preset.wallpaper));
        const media=video?await fs.readFile(path.join(root,'Assets',preset.wallpaper)):null;
        const theme={id:preset.id,name:preset.name,tagline:'你欲何为',quote:'你欲何为',brandSubtitle:'李星云 · CODEX',statusText:'',appearance:'auto',colorMode:'adaptive',artKey:createHash('sha256').update(art).digest('hex'),art:{focusX:.72,focusY:.5,safeArea:'none',taskMode:'full'},userTransparency:40,media:{type:video?'video':'image',mime:'video/mp4',size:media?.length||0,opacity:state.opacity??.7}};
        let source=template;
        for(const [k,v] of Object.entries({CSS:css,ART:`data:image/jpeg;base64,${art.toString('base64')}`,THEME:theme,VERSION:'lixingyun-1.2.0',STYLE_REVISION:'lixingyun-1.2',PAYLOAD_REVISION:state.revision||'native'}))source=source.replace(`__DREAM_SKIN_${k}_JSON__`,()=>JSON.stringify(v));
        await evaluate('window.__LIXINGYUN_WALLPAPER_LAYER__?.cleanup();true');await evaluate(source);
        if(media)await transfer(key,media);else await evaluate(`(${installImageLayer.toString()})()`);
        lastPreset=preset.id;revision=null;
      }
      if(revision!==state.revision){await evaluate(`window.${key}.setWallpaperReveal(${Math.max(0,Math.min(1,Number(state.opacity)||.7))});window.${key}.setPaused(${Boolean(state.paused)});window.__LIXINGYUN_USER_PAUSED__=${Boolean(state.paused)};true`);revision=state.revision;}
      // A native preview request is consumed once, without restarting Codex.
      const pending=state.introRequest;
      result=await evaluate(probe);
      if(pending?.status==='pending'&&Date.now()-pending.queuedAt<120000&&result.intro?.token!==pending.token){
        const movie=list.find(p=>p.id===pending.startup)||startup;
        const data=await fs.readFile(path.join(root,'Assets',movie.startup));
        await evaluate(`(${installIntro.toString()})(${JSON.stringify({token:pending.token,mediaSize:data.length,mediaMime:'video/mp4',handoffTime:movie.introHandoff,fadeMs:700,appearance:movie.id.startsWith('white')?'light':'dark',syncBackground:movie.id===preset.id})})`);await transfer(introKey,data);
      }
      await evaluate(`window.${introKey}?.start();true`);
      result=await evaluate(probe);
      if(state.introRequest?.status==='pending'&&result.intro?.token===state.introRequest.token&&['playing','revealing','done'].includes(result.intro.phase)){
        const latest=await readState();
        if(latest.introRequest?.token===state.introRequest.token){
          latest.introRequest={...latest.introRequest,status:result.intro.phase==='done'?'done':'started',updatedAt:Date.now()};
          const temp=stateFile+'.'+process.pid+'.tmp';await fs.writeFile(temp,JSON.stringify(latest,null,2),{mode:0o600});await fs.rename(temp,stateFile);
        }
      }
      error=null;await status(state,result);
    }catch(e){error=String(e.message||e);await status(state,null).catch(()=>{});}
    finally{busy=false;}
  }
  async function transfer(controller,data){
    if(!await evaluate(`window.${controller}.beginMedia(${JSON.stringify({mime:'video/mp4',size:data.length})})`))throw Error('Media initialization failed');
    for(let i=0;i<data.length;i+=384*1024)if(!await evaluate(`window.${controller}.appendMedia(${JSON.stringify(data.subarray(i,i+384*1024).toString('base64'))})`))throw Error('Media transfer failed');
    if(!await evaluate(`window.${controller}.commitMedia()`))throw Error('Media commit failed');
  }
  app.on('web-contents-created',(_,wc)=>{
    wc.on('dom-ready',()=>{
      let url;try{url=new URL(wc.getURL());}catch{return;}
      if(url.protocol!=='app:'||!url.pathname.endsWith('/index.html'))return;
      if(contents&&contents!==wc&&!contents.isDestroyed())return;
      contents=wc;revision=null;lastPreset=null;tick();
    });
  });
  timer=setInterval(tick,500);timer.unref();
  app.whenReady().then(tick);
  app.on('will-quit',()=>{stopped=true;clearInterval(timer);});
};
