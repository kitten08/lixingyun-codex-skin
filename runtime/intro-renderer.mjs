// This function is serialized into the verified local Codex renderer.
// Keep it self-contained: no imports, remote resources, or host application APIs.
export function installIntro(config) {
  const KEY='__LIXINGYUN_INTRO_STATE__', LAST='__LIXINGYUN_INTRO_LAST__';
  const token=String(config?.token || '');
  if(!/^[a-z0-9-]{1,128}$/i.test(token))throw new Error('Invalid intro token');
  if(window[KEY]?.token===token)return window[KEY].probe();
  if(window[LAST]?.token===token)return {...window[LAST],alreadyCompleted:true};
  const size=Number(config.mediaSize);
  if(!Number.isSafeInteger(size)||size<1||size>64*1024*1024||config.mediaMime!=='video/mp4')throw new Error('Invalid intro media');
  window[KEY]?.cleanup('replaced');
  const previousFocus=document.activeElement;
  const host=document.createElement('div');host.id='lixingyun-codex-intro';host.tabIndex=-1;
  host.setAttribute('role','dialog');host.setAttribute('aria-label','Codex 启动动画');host.setAttribute('aria-modal','true');
  for(const [key,value]of Object.entries({position:'fixed',inset:'0',width:'100vw',height:'100vh','z-index':'2147483647',isolation:'isolate',margin:'0',padding:'0',border:'0',opacity:'1','pointer-events':'auto',overflow:'hidden','background-color':config.appearance==='light'?'#fff':'#050608'}))host.style.setProperty(key,value,'important');
  const shadow=host.attachShadow({mode:'open'}),style=document.createElement('style');
  style.textContent=`:host{color-scheme:dark}*{box-sizing:border-box}.film{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;object-position:center;opacity:0;transition:opacity 140ms linear;pointer-events:none}.loading{position:absolute;inset:0;display:grid;place-content:center;text-align:center;color:${config.appearance==='light'?'#30343b':'#d5d9e0'};font-family:-apple-system,BlinkMacSystemFont,sans-serif;letter-spacing:6px;transition:opacity 160ms}.loading small{font-size:11px;letter-spacing:3px;opacity:.45;margin-top:15px}.skip{position:absolute;right:24px;bottom:22px;z-index:2;border:1px solid #ffffff26;border-radius:18px;padding:8px 13px;background:#111b;color:#e8e9ec;font:11px -apple-system,sans-serif;cursor:pointer;backdrop-filter:blur(10px);-webkit-app-region:no-drag}.skip:hover{background:#262a32e6}.drag{position:absolute;left:85px;right:110px;top:0;height:30px;-webkit-app-region:drag}`;
  const video=document.createElement('video');video.className='film';video.setAttribute('aria-hidden','true');
  video.muted=true;video.defaultMuted=true;video.playsInline=true;video.controls=false;video.disablePictureInPicture=true;video.preload='auto';
  const loading=document.createElement('div');loading.className='loading';
  const word=document.createElement('div');word.textContent='CODEX';const note=document.createElement('small');note.textContent='你欲何为';loading.append(word,note);
  const skip=document.createElement('button');skip.className='skip';skip.textContent='跳过  Esc';skip.type='button';
  const drag=document.createElement('div');drag.className='drag';shadow.append(style,video,loading,drag,skip);
  (document.body || document.documentElement).appendChild(host);host.focus({preventScroll:true});
  const state={token,phase:'preparing',createdAt:Date.now(),startedAt:null,completedAt:null,frames:0,reason:null,error:null,mediaTime:0};
  let transfer=null,blobURL=null,startRequested=false,playing=false,dead=false,frameHandle=null,frameKind=null;
  let readyTimer=null,fadeTimer=null,hardTimer=null;
  const listeners=[];
  const listen=(target,event,handler,options)=>{target.addEventListener(event,handler,options);listeners.push(()=>target.removeEventListener(event,handler,options));};
  const fadeMs=Math.max(150,Math.min(1500,Number(config.fadeMs)||700));
  const wallpaper=()=>document.getElementById('codex-dream-skin-media') || document.getElementById('lixingyun-codex-wallpaper-image');
  const probe=()=>({...state,ready:video.readyState,hasMedia:Boolean(blobURL),mediaTime:Number(video.currentTime)||state.mediaTime,overlay:host.isConnected});
  function cleanup(reason='restore') {
    if(dead)return false;dead=true;
    state.reason=state.reason || reason;state.mediaTime=Number(video.currentTime)||state.mediaTime;
    state.phase='done';state.completedAt=Date.now();
    if(frameHandle!==null){if(frameKind==='video')video.cancelVideoFrameCallback?.(frameHandle);else cancelAnimationFrame(frameHandle);}
    clearTimeout(readyTimer);clearTimeout(fadeTimer);clearTimeout(hardTimer);
    for(const remove of listeners)remove();
    video.pause();video.removeAttribute('src');video.load();transfer=null;
    if(blobURL)URL.revokeObjectURL(blobURL);blobURL=null;host.remove();
    window[LAST]={...state,overlay:false};
    if(window[KEY]?.token===token)delete window[KEY];
    if(previousFocus?.isConnected && typeof previousFocus.focus==='function')previousFocus.focus({preventScroll:true});
    return true;
  }
  function alignWithBackground() {
    const background=wallpaper();
    if(background){const computed=getComputedStyle(background);video.style.objectFit=computed.objectFit || 'cover';video.style.objectPosition=computed.objectPosition || '50% 50%';}
    else{video.style.objectFit='cover';video.style.objectPosition=config.objectPosition || '50% 50%';}
  }
  function synchronizeBackground() {
    const background=document.getElementById('codex-dream-skin-media');
    if(!config.syncBackground || window.__LIXINGYUN_USER_PAUSED__ || !background || !Number.isFinite(background.duration) || background.duration<=0)return;
    try{background.currentTime=video.currentTime%background.duration;if(background.paused)background.play()?.catch(()=>{});}catch{}
  }
  function finish(reason='skip') {
    if(dead || state.phase==='revealing')return false;
    state.reason=reason;state.mediaTime=Number(video.currentTime)||0;state.phase='revealing';
    clearTimeout(readyTimer);clearTimeout(hardTimer);
    synchronizeBackground();
    // Keep both films moving through the dissolve when there is room before
    // the original video's outro. Otherwise hold the last complete frame.
    if(reason!=='handoff' || !Number.isFinite(video.duration) || video.duration-video.currentTime<fadeMs/1000+.12)video.pause();
    host.style.setProperty('transition',`opacity ${fadeMs}ms cubic-bezier(.2,.7,.3,1)`,'important');
    host.style.setProperty('opacity','0','important');
    fadeTimer=setTimeout(()=>cleanup(reason),fadeMs+80);
    return true;
  }
  function watchFrames() {
    if(dead || !playing || state.phase!=='playing')return;
    const frame=()=>{
      if(dead || state.phase!=='playing')return;
      state.frames++;state.mediaTime=Number(video.currentTime)||0;
      const duration=Number(video.duration),requested=Number(config.handoffTime);
      const handoff=Number.isFinite(requested)&&requested>0?Math.min(requested,Number.isFinite(duration)?Math.max(.1,duration-.08):requested):Math.max(.1,duration-.12);
      if(state.mediaTime>=handoff){finish('handoff');return;}
      watchFrames();
    };
    if(typeof video.requestVideoFrameCallback==='function'){frameKind='video';frameHandle=video.requestVideoFrameCallback(frame);}
    else{frameKind='raf';frameHandle=requestAnimationFrame(frame);}
  }
  function backgroundReady() {
    if(config.backgroundRequired===false)return true;
    if(!window.__CODEX_DREAM_SKIN_STATE__)return false;
    const background=wallpaper();
    if(background?.tagName==='VIDEO')return background.readyState>=2 && !background.error;
    if(background?.tagName==='IMG')return background.complete && background.naturalWidth>0;
    return false;
  }
  function attemptStart() {
    clearTimeout(readyTimer);
    if(dead || playing || !startRequested || state.phase!=='preparing')return;
    if(document.hidden || video.readyState<2 || !backgroundReady()){readyTimer=setTimeout(attemptStart,75);return;}
    alignWithBackground();
    video.play()?.catch(error=>{state.error=String(error?.message || error);finish('playback-error');});
  }
  listen(video,'playing',()=>{
    if(dead || playing)return;
    playing=true;state.phase='playing';state.startedAt=Date.now();loading.style.opacity='0';video.style.opacity='1';
    synchronizeBackground();watchFrames();
  });
  listen(video,'canplay',attemptStart);
  listen(video,'ended',()=>finish('ended'));
  listen(video,'error',()=>{state.error=video.error?.message || 'Video decode failed';finish('decode-error');});
  listen(skip,'click',()=>finish('skip'));
  listen(document,'visibilitychange',attemptStart);
  listen(window,'resize',alignWithBackground);
  listen(document,'focusin',event=>{if(!dead && state.phase!=='revealing' && !host.contains(event.target))host.focus({preventScroll:true});},true);
  listen(document,'keydown',event=>{
    if(dead || state.phase==='revealing')return;
    if(event.key==='Escape'){event.preventDefault();event.stopImmediatePropagation();finish('escape');}
    else if(event.composedPath?.().includes(skip) && (event.key==='Enter' || event.key===' ')){return;}
    else if(event.key==='Tab'){event.preventDefault();event.stopImmediatePropagation();skip.focus({preventScroll:true});}
    else{event.preventDefault();event.stopImmediatePropagation();}
  },true);
  hardTimer=setTimeout(()=>{state.error='Intro preparation timed out';finish('timeout');},45000);
  const controller={token,probe,cleanup,finish,
    beginMedia({mime,size:expected}={}){if(dead || mime!==config.mediaMime || expected!==size)return false;transfer={chunks:[],received:0};return true;},
    appendMedia(encoded){
      if(dead || !transfer || typeof encoded!=='string' || encoded.length>1024*1024)return false;
      let raw;try{raw=atob(encoded);}catch{return false;}
      if(transfer.received+raw.length>size)return false;
      const bytes=new Uint8Array(raw.length);for(let i=0;i<raw.length;i++)bytes[i]=raw.charCodeAt(i);
      transfer.chunks.push(bytes);transfer.received+=bytes.length;return true;
    },
    commitMedia(){
      if(dead || !transfer || transfer.received!==size)return false;
      if(blobURL)URL.revokeObjectURL(blobURL);
      blobURL=URL.createObjectURL(new Blob(transfer.chunks,{type:config.mediaMime}));transfer=null;video.src=blobURL;video.load();return true;
    },
    start(){if(dead)return false;startRequested=true;attemptStart();return true;}
  };
  window[KEY]=controller;
  return probe();
}
