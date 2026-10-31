// Use one viewport-sized image, just like the shared video wallpaper layer.
// This keeps the character in the same place while the intro reveals the UI.
export function installImageLayer() {
  const key='__LIXINGYUN_WALLPAPER_LAYER__';window[key]?.cleanup();
  const state=window.__CODEX_DREAM_SKIN_STATE__;
  if(!state?.artUrl || document.getElementById('codex-dream-skin-media'))return false;
  const body=document.body,oldValue=body.style.getPropertyValue('background-image'),oldPriority=body.style.getPropertyPriority('background-image');
  const image=document.createElement('img');image.id='lixingyun-codex-wallpaper-image';image.setAttribute('aria-hidden','true');image.alt='';
  Object.assign(image.style,{position:'fixed',inset:'0',width:'100vw',height:'100vh',zIndex:'-1',objectFit:'cover',objectPosition:'72% 50%',opacity:'var(--dream-wallpaper-reveal,1)',pointerEvents:'none'});
  const style=document.createElement('style');style.id='lixingyun-wallpaper-layout';
  style.textContent='html[data-lixingyun-wallpaper="image"]{--dream-skin-art:none!important}';
  document.documentElement.setAttribute('data-lixingyun-wallpaper','image');
  body.style.setProperty('background-image','none','important');
  image.src=state.artUrl;body.prepend(image);document.head.append(style);
  window[key]={cleanup(){
    image.remove();style.remove();document.documentElement.removeAttribute('data-lixingyun-wallpaper');
    if(oldValue)body.style.setProperty('background-image',oldValue,oldPriority);else body.style.removeProperty('background-image');
    if(window[key]===this)delete window[key];return true;
  }};
  return true;
}
