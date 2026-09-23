const el=id=>document.getElementById(id);let state=null,csrf='',talk=false,timer=null,quipIndex=0,mode=localStorage.getItem('neko-budget-mode')||'balance';
function native(action){const bridge=window.webkit?.messageHandlers?.nekoWidget;if(bridge){bridge.postMessage(action);return true;}if(window.chrome?.webview){window.chrome.webview.postMessage(action);return true;}return false;}
let agentState='unknown',idleCard=false;
function render(){if(!state)return;if(state.config.source==='manual_quota'){const c=state.config;el('heading').textContent='猫粮余额';el('amount').classList.remove('idle-label');el('amount').textContent=c.quota_remaining===null?'未填写':c.quota_remaining.toLocaleString()+' '+c.quota_unit;el('detail').textContent=(c.model||'额度')+' · 手动记录';el('connection').textContent=(c.quota_total!==null?'总额度 '+c.quota_total+' '+c.quota_unit+'\n':'')+(c.quota_reset?'重置备注 '+c.quota_reset:'不会自动扣减或重置');return;}if(state.config.source==='codex'){const windows=state.codex_quota?.windows||[];const w=windows.length?[...windows].sort((a,b)=>a.remaining-b.remaining)[0]:null;el('heading').textContent='猫粮余额';el('amount').classList.remove('idle-label');el('amount').textContent=w?w.remaining+'%':'待查询';el('detail').textContent=w?(state.stale?'上次数据 · ':'')+'Codex '+w.label+'剩余':'Codex 套餐额度';el('connection').textContent=state.error||(w?'重置 '+new Date(w.resets_at*1000).toLocaleString('zh-CN',{month:'numeric',day:'numeric',hour:'2-digit',minute:'2-digit'})+'\n'+windows.filter(x=>x!==w).map(x=>x.label+'剩余 '+x.remaining+'%').join('；'):'正在查询喵～');return;}if(state.config.source==='jev'){const u=state.reported_usage||{};el('heading').textContent='猫粮余额';el('amount').textContent='未提供';el('amount').classList.remove('idle-label');el('detail').textContent='JEV 已记录 '+((u.input_tokens||0)+(u.output_tokens||0)).toLocaleString()+' token';el('connection').textContent='输入 '+(u.input_tokens||0)+' · 输出 '+(u.output_tokens||0)+'\n仅本机上报用量';return;}el('amount').classList.remove('idle-label');const row=state.selected;const sym=row?.currency==='USD'?'$':'¥';el('heading').textContent=mode==='token'?'估算可用 token':'猫粮余额';el('amount').textContent=mode==='token'?(state.estimated_tokens===null?'待估算':'≈ '+new Intl.NumberFormat('zh-CN',{notation:'compact',maximumFractionDigits:1}).format(state.estimated_tokens)):(row?sym+' '+Number(row.balance).toFixed(2):state.configured?'待查询':'未连接');el('detail').textContent=mode==='token'?'按自填单价估算':row?(state.stale?'旧数据 · ':'')+state.basis:'点击 ≡ 设置账户';el('connection').textContent=state.error?'查询失败\n保留上次结果':state.stale&&row?'上次数据\n等待更新':'';}
function renderAgentCard(){if(talk||!state)return;if(idleCard&&mode==='balance'){el('heading').textContent='当前时间段为：';el('amount').textContent=agentState==='idle'?'空闲时段':agentState==='busy'?'忙碌时段':'状态未连接';el('amount').classList.toggle('idle-label',agentState==='idle');el('detail').textContent=agentState==='idle'?'Agent 没在忙，本喵陪你喵～':agentState==='busy'?'Agent 正在工作喵～':'暂时读不到 Agent 状态';}else render();}
function say(text){talk=true;el('readout').hidden=true;el('quip').hidden=false;el('quip').textContent=text;el('quip').classList.remove('fade');void el('quip').offsetWidth;el('quip').classList.add('fade');clearTimeout(timer);timer=setTimeout(restore,4200);}
function restore(){clearTimeout(timer);talk=false;el('quip').hidden=true;el('readout').hidden=false;renderAgentCard();}
const quips=['哼，本喵在呢。\n碳基生物，安心忙吧喵～','猫粮本喵盯着，\n你记得按时吃饭喵～','才不是特意等你。\n只是这里待着舒服喵～','累了就歇一会。\n本喵又不会跑掉喵～','有事就叫本喵。\n别一个人硬撑喵～','又偷看本喵？\n好啦，陪你一会喵～'];
quips.push('哦喵喵…','深眠……喵～','坏了…用户彻底怒了喵～！','好猫娘…喵～↓');

const clickAnimations=new WeakMap();
function bounce(id){
 const target=el(id);clickAnimations.get(target)?.cancel();
 if(window.matchMedia('(prefers-reduced-motion: reduce)').matches)return;
 const character=id==='character';
 const frames=character?[
  {transform:'translateY(0) scale(1,1)',offset:0},
  {transform:'translateY(1px) scale(1.035,.94)',offset:.16},
  {transform:'translateY(-15px) scale(.985,1.025)',offset:.43},
  {transform:'translateY(0) scale(1.02,.97)',offset:.7},
  {transform:'translateY(-4px) scale(1,1)',offset:.85},
  {transform:'translateY(0) scale(1,1)',offset:1}
 ]:[
  {transform:'translateY(0) scale(1)',offset:0},
  {transform:'translateY(2px) scale(.965)',offset:.2},
  {transform:'translateY(-4px) scale(1.012)',offset:.5},
  {transform:'translateY(0) scale(.994)',offset:.77},
  {transform:'translateY(0) scale(1)',offset:1}
 ];
 clickAnimations.set(target,target.animate(frames,{duration:character?500:380,easing:'ease-out'}));
}

el('thought').onclick=()=>{recordAction('ask');bounce('thought');idleCard=!idleCard;mode='balance';localStorage.setItem('neko-budget-mode',mode);restore();};
const petLines=['突、突然摸头干嘛……\n只许再摸一下喵～','哼，头发都被你揉乱了。\n……也没说不让你摸喵～','好啦，本喵在这里。\n今天也辛苦你了喵～','碳基生物，轻一点。\n本喵又不会跑喵～'];let petIndex=0;
function pet(){recordAction("pet");bounce('character');bounce('thought');const lines=[...quips,...petLines];const line=lines[petIndex++%lines.length];say(line);requestSpokenLine(line);}
let drag=false,start=null;el('character').onpointerdown=e=>{clickAnimations.get(el('character'))?.cancel();start={x:e.screenX,y:e.screenY};drag=false;el('character').setPointerCapture(e.pointerId);native('dragStart');};el('character').onpointermove=e=>{if(!start)return;if(Math.hypot(e.screenX-start.x,e.screenY-start.y)>4)drag=true;if(drag)native('dragMove');};el('character').onpointerup=()=>{native('dragEnd');start=null;if(drag)return;pet();};el('character').onpointercancel=()=>{start=null;native('dragEnd');};
el('menuToggle').onclick=()=>el('menu').hidden=!el('menu').hidden;
for(const [id,value] of [['balanceMode','balance'],['tokenMode','token']])el(id).onclick=()=>{mode=value;idleCard=false;localStorage.setItem('neko-budget-mode',mode);el('menu').hidden=true;restore();};
el('settings').onclick=()=>{el('menu').hidden=true;openAccount();};el('hide').onclick=async()=>{el('menu').hidden=true;if(recordingActive){await finishRecording();return;}if(!native('hide'))say('关闭窗口就能收起我喵～');};
async function update(refresh=false){try{const r=await fetch(refresh?'/api/refresh':'/api/status',refresh?{method:'POST',headers:{'Content-Type':'application/json','X-Neko-CSRF':csrf},body:'{}'}:{});if(!r.ok)throw Error();state=await r.json();csrf=state.csrf||csrf;renderAgentCard();}catch{el('connection').textContent='插件连接中断';if(state){state.stale=true;state.estimated_tokens=null;render();el('connection').textContent='插件连接中断';}}}
el('refreshNow').onclick=()=>{el('menu').hidden=true;update(true);};update();setInterval(()=>update(),15000);

el('yuiReply').onclick=async()=>{el('menu').hidden=true;try{const r=await fetch('/api/reply',{method:'POST',headers:{'Content-Type':'application/json','X-Neko-CSRF':csrf},body:'{}'});const result=await r.json();if(!r.ok||!result.submitted)throw Error(result.error||'原软件暂时没有接收');say('已经叫她啦喵～\n请看 NEKO 的回应。');el('connection').textContent='是否出声由原软件语音设置决定';}catch(e){say(e.message);}};

async function pollAgent(){try{const r=await fetch('/api/agent');if(!r.ok)throw Error();const a=await r.json();agentState=['idle','busy'].includes(a.status)?a.status:'unknown';}catch{agentState='unknown';}el('agentStatus').textContent=agentState==='idle'?'空闲时段 · 喵～':agentState==='busy'?'Agent 运行中 · 本喵忙着喵～':'Agent 状态未连接';el('agentStatus').classList.toggle('idle',agentState==='idle');renderAgentCard();}
pollAgent();setInterval(pollAgent,5000);

async function requestSpokenLine(line){if(!csrf)return;try{const r=await fetch('/api/reply',{method:'POST',headers:{'Content-Type':'application/json','X-Neko-CSRF':csrf},body:JSON.stringify({line})});const result=await r.json();el('connection').textContent=r.ok&&result.submitted?'已请求原软件回应\n出声取决于语音状态':r.status===429?'语音稍等一下喵～':result.error||'原软件语音暂不可用';}catch{el('connection').textContent='原软件语音未连接';}}

let recordingActive=false, recordQueue=Promise.resolve();
function recordAction(action){
 const work=async()=>{if(!csrf)return null;const r=await fetch('/api/recording',{method:'POST',headers:{'Content-Type':'application/json','X-Neko-CSRF':csrf},body:JSON.stringify({action})});if(!r.ok)throw Error('记录未保存喵～');const data=await r.json();recordingActive=!!data.active;el('recordMode').textContent=recordingActive?'退出记录模式':'开始记录模式';return data;};
 const result=recordQueue.then(work);recordQueue=result.catch(()=>{el('connection').textContent='记录连接中断喵～';});return result;
}
async function finishRecording(){native('recordEnd');const d=await recordAction('end');if(d?.summary){say(d.summary);clearTimeout(timer);el('connection').textContent=d.memory_saved?'已写入 YUI 记忆喵～':'记录已保存在本机，记忆写入未成功；可重试喵～';}return d;}
el('recordMode').onclick=async()=>{el('menu').hidden=true;if(recordingActive)await finishRecording();else{const d=await recordAction('start');if(d?.active){native('recordStart');restore();}else if(d?.error)say(d.error);}};
el('retryMemory').onclick=async()=>{el('menu').hidden=true;const d=await recordAction('retry');say(d?.memory_saved?'已写入 YUI 的记忆喵～':'记忆尚未写入，记录仍保存在本机喵～');};
const beginRecording=setInterval(async()=>{if(!csrf)return;clearInterval(beginRecording);const d=await recordAction('start');if(d?.active)native('recordStart');else if(d?.error)say(d.error);},200);
