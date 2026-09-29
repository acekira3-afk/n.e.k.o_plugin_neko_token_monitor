/* Click YUI to advance the melody. User gestures determine its rhythm. */
(() => {
 'use strict';
 const $=id=>document.getElementById(id),panel=$('musicPanel'),settings=$('musicSettingsPanel');
 let context,master,buffer,score,loading,playing=false,enabled=false,loop=false,cursor=0,generation=0;
 const sources=new Set(),timers=new Set();
 function saved(key,fallback,min,max){const n=Number(localStorage.getItem(key)??fallback);return Math.max(min,Math.min(max,Number.isFinite(n)?n:fallback));}
 let volume=saved('catfood-music-volume',.45,0,1),pitch=Math.round(saved('catfood-music-pitch',0,-12,12));
 $('musicVolume').value=String(volume);$('musicPitch').value=String(pitch);
 function pitchLabel(){$('musicPitchValue').textContent=pitch===0?'原音高':`${pitch>0?'+':''}${pitch} 半音`;}
 pitchLabel();
 const status=text=>$('musicStatus').textContent=text;
 const hint=()=>status(document.body.classList.contains('record-inactive')?'开始记录后点 YUI 喵～':'跟着节奏点 YUI 喵～');
 async function ready(){
  const Audio=window.AudioContext||window.webkitAudioContext;
  if(!Audio)throw Error('当前窗口不支持音频喵～');
  if(!context){context=new Audio();master=context.createGain();master.gain.value=volume;master.connect(context.destination);}
  await context.resume();
  if(!loading)loading=Promise.all([
   fetch('/music-grain.wav').then(r=>{if(!r.ok)throw Error('音色未加载');return r.arrayBuffer();}).then(b=>context.decodeAudioData(b)),
   fetch('/music-score.json').then(r=>{if(!r.ok)throw Error('曲谱未加载');return r.json();})
  ]).then(([b,s])=>{buffer=b;score=s;}).catch(e=>{loading=null;throw e;});
  await loading;
 }
 function later(fn,ms){const id=setTimeout(()=>{timers.delete(id);fn();},ms);timers.add(id);}
 function note(midi,time=context.currentTime,duration=.3){
  const source=context.createBufferSource(),gain=context.createGain();
  source.buffer=buffer;source.playbackRate.value=2**((midi+pitch-69)/12)*440/score.baseHz;
  const length=Math.min(duration,buffer.duration/source.playbackRate.value),v=.65;
  gain.gain.setValueAtTime(0,time);gain.gain.linearRampToValueAtTime(v,time+.006);
  gain.gain.setValueAtTime(v,time+Math.max(.007,length-.035));gain.gain.linearRampToValueAtTime(0,time+length);
  source.connect(gain);gain.connect(master);sources.add(source);
  source.onended=()=>{sources.delete(source);source.disconnect();gain.disconnect();};
  source.start(time);source.stop(time+length+.01);
  later(()=>window.dispatchEvent(new CustomEvent('catfood:musicbeat')),Math.max(0,(time-context.currentTime)*1000));
 }
 function stop(){generation++;playing=false;for(const id of timers)clearTimeout(id);timers.clear();for(const s of sources){try{s.stop();}catch{}}sources.clear();$('musicPlay').textContent='试听';hint();}
 function close(){enabled=false;stop();panel.hidden=true;settings.hidden=true;document.body.classList.remove('music-active');}
 async function play(){
  stop();const ticket=generation;await ready();if(ticket!==generation||!enabled)return;playing=true;
  $('musicPlay').textContent='重播';status('跟着这段节奏点喵～');
  const begin=context.currentTime+.08;
  for(const n of score.notes)note(n.midi,begin+n.time,n.duration);
  later(()=>{if(ticket!==generation)return;playing=false;if(loop)play().catch(fail);else{$('musicPlay').textContent='试听';hint();}},(score.duration+.12)*1000);
 }
 function fail(e){stop();status(e.message||'音频暂时不可用喵～');}
 window.catfoodMusic={
  pet(){
   if(!enabled)return false;
   if(playing)stop();const ticket=generation;
   ready().then(()=>{if(!enabled||ticket!==generation)return;const n=score.notes[cursor++%score.notes.length];note(n.midi,context.currentTime,n.duration);status(`第 ${((cursor-1)%score.notes.length)+1} 音 · 喵～`);}).catch(e=>{if(enabled&&ticket===generation)fail(e);});
   return true;
  },stop
 };
 $('musicOpen').onclick=()=>{$('menu').hidden=true;panel.hidden=false;settings.hidden=true;enabled=true;cursor=0;document.body.classList.add('music-active');hint();};
 $('musicClose').onclick=close;
 $('musicPlay').onclick=()=>play().catch(fail);$('musicStop').onclick=()=>{stop();cursor=0;};
 $('musicSettingsOpen').onclick=()=>{settings.hidden=false;};$('musicSettingsClose').onclick=()=>{settings.hidden=true;};
 $('musicLoop').onchange=e=>{loop=e.target.checked;};
 $('musicVolume').oninput=e=>{volume=Math.max(0,Math.min(1,Number(e.target.value)||0));localStorage.setItem('catfood-music-volume',String(volume));if(master)master.gain.setTargetAtTime(volume,context.currentTime,.015);if(volume===0)stop();};
 $('musicPitch').oninput=e=>{pitch=Math.round(Math.max(-12,Math.min(12,Number(e.target.value)||0)));localStorage.setItem('catfood-music-pitch',String(pitch));pitchLabel();if(playing)stop();};
 document.addEventListener('keydown',e=>{if(!panel.hidden&&e.key==='Escape'){if(!settings.hidden)settings.hidden=true;else close();}});
 document.addEventListener('visibilitychange',()=>{if(document.hidden)stop();});
 window.addEventListener('pagehide',close);window.addEventListener('catfood:recordend',close);
})();
