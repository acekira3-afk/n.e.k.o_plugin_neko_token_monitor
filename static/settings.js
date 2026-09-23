const panel=document.getElementById('accountPanel');
panel.innerHTML=`<header><div><small>YUI · 猫粮</small><h2>猫粮余额</h2></div><button id="closeAccount" type="button" aria-label="返回人物">×</button></header>
<p class="note">各平台分别记录，不合并余额。选择卡片设置，点「气泡展示」切换挂件喵～</p><label>查找模型或平台<input id="profileSearch" type="search" placeholder="例如 GPT、Claude、Gemini"></label><div id="quotaCards"></div>
<form id="accountForm"><h3 id="editingName">账户设置</h3><p id="sourceHint" class="note"></p>
<label>模型备注<input id="model" maxlength="100" placeholder="可填写具体模型或套餐名称"></label>
<label id="keyLabel">查询密钥（留空保留此平台的密钥）<input id="accountKey" type="password" autocomplete="new-password"></label>
<div id="customFields"><label>余额接口（HTTPS GET）<input id="endpoint" type="url"></label><label>金额字段路径<input id="value_path" placeholder="data.balance"></label><p class="note">密钥仅以 Bearer 认证发给此地址，请确认服务商。</p></div>
<div id="quotaFields"><p class="note">此来源尚未接入自动额度查询。按平台页面填写；不会自动扣减或重置。</p><label>剩余额度<input id="quota_remaining" type="number" min="0" max="1000000000000" step="any"></label><label>总额度（可选）<input id="quota_total" type="number" min="0" max="1000000000000" step="any"></label><label>单位<select id="quota_unit"><option>次</option><option>token</option><option>%</option></select></label><label>重置时间备注（可选）<input id="quota_reset" maxlength="80" placeholder="例如：周五 20:00"></label></div>
<div id="budgetFields"><label>预算金额<input id="budget" type="number" min="0" max="1000000000" step="any"></label><label id="dateLabel">预算起始日期（UTC）<input id="budget_start" type="date"></label></div>
<label id="currencyLabel">币种<select id="currency"><option>CNY</option><option>USD</option></select></label>
<details id="estimateFields"><summary>估算与提醒</summary><label>每百万 token 综合价格（选填）<input id="price_per_million" type="number" min="0.000001" step="any"></label><label>低余额提醒阈值<input id="low_balance" type="number" min="0" step="any"></label><label><input id="alerts" type="checkbox"> 低余额提醒喵～</label></details><label id="intervalLabel">查询间隔（秒）<input id="interval" type="number" min="60" max="86400"></label>
<button id="saveAccount" class="primary" type="submit">保存并展示</button><p id="accountFeedback" role="status"></p><p class="note">密钥保存在本机。API 预算、订阅额度和账户余额是不同指标；共享账户金额不代表某个模型的独立额度。</p></form>`;
const field=id=>document.getElementById(id);
const configFields=['model','endpoint','value_path','budget','budget_start','currency','price_per_million','low_balance','interval','quota_remaining','quota_total','quota_unit','quota_reset'];
let accountCsrf='',profileRows=[],editingProfile='';
function quotaSummary(s){
 if(s.config.source==='manual_quota'){const c=s.config;return c.quota_remaining===null?'未填写':`${c.quota_remaining.toLocaleString()} ${c.quota_unit}`;}
 if(s.config.source==='codex'){const w=s.codex_quota?.windows||[];return w.length?w.map(x=>`${x.label} ${x.remaining}%`).join(' · '):'待查询';}
 if(s.config.source==='jev'){const u=s.reported_usage||{};return `${((u.input_tokens||0)+(u.output_tokens||0)).toLocaleString()} token`;}
 return s.selected?`${s.selected.currency==='USD'?'$':'¥'} ${Number(s.selected.balance).toFixed(2)}`:s.configured?'待查询':'未连接';
}
function fillProfile(id){
 const row=profileRows.find(r=>r.id===id);if(!row)return;editingProfile=id;const c=row.snapshot.config,s=c.source;
 field('editingName').textContent=row.name+' · 设置';field('sourceHint').textContent=row.hint+({openai:'。需要组织 Admin Key；非 ChatGPT 订阅额度。',anthropic:'。需要组织费用查询权限；不含 Priority Tier。',codex:'。读取本机已登录的 Codex，无需密钥。',openrouter:'。需要 Management Key；不是普通聊天 Key。',jev:'。仅本机 JEV 桥接上报，不代表完整账户用量。'}[s]||'');
 for(const id of configFields)field(id).value=c[id]??'';field('alerts').checked=c.alerts;field('accountKey').value='';
 field('keyLabel').hidden=['codex','jev','manual','manual_quota'].includes(s);field('customFields').hidden=s!=='custom';field('quotaFields').hidden=s!=='manual_quota';field('budgetFields').hidden=!['openai','anthropic','manual'].includes(s);field('dateLabel').hidden=s==='manual';
 const nonMoney=['codex','jev','manual_quota'].includes(s);field('currencyLabel').hidden=nonMoney;field('estimateFields').hidden=nonMoney;field('intervalLabel').hidden=['jev','manual','manual_quota'].includes(s);
 field('currency').disabled=['openai','anthropic','openrouter','siliconflow'].includes(s);if(['openai','anthropic','openrouter'].includes(s))field('currency').value='USD';if(s==='siliconflow')field('currency').value='CNY';
 field('accountFeedback').textContent='';
}
function drawCards(state){
 profileRows=state.profiles||[];const container=field('quotaCards');container.replaceChildren();
 for(const row of [...profileRows].sort((a,b)=>(b.id===state.profile)-(a.id===state.profile)||Number(b.enabled)-Number(a.enabled))){
  if(row.source==='jev')row.snapshot.reported_usage=state.reported_usage;
  const card=document.createElement('article');card.className='quota-card';card.classList.toggle('selected',state.profile===row.id);
  const name=document.createElement('strong');name.textContent=row.name;
  const amount=document.createElement('b');amount.textContent=row.enabled?quotaSummary(row.snapshot):'未接入';
  const note=document.createElement('small');const manual=row.source==='manual_quota';note.textContent=row.hint+(row.enabled&&row.snapshot.error?' · 查询失败，保留旧数据':row.enabled&&row.snapshot.stale&&!manual&&row.source!=='jev'?' · 等待更新':'');
  const stamp=document.createElement('small');stamp.textContent=row.snapshot.updated_at?'更新于 '+new Date(row.snapshot.updated_at*1000).toLocaleString('zh-CN'):'';
  const edit=document.createElement('button');edit.type='button';edit.textContent=row.enabled?'设置':'接入 / 记录';edit.onclick=()=>{fillProfile(row.id);field('accountForm').scrollIntoView({block:'start'});};
  card.append(name,amount);
  const snap=row.snapshot,c=snap.config;
  const percentages=c.source==='codex'?(snap.codex_quota?.windows||[]).map(w=>({label:w.label,value:w.remaining,reset:'重置 '+new Date(w.resets_at*1000).toLocaleString('zh-CN')})):c.source==='manual_quota'&&c.quota_remaining!==null&&(c.quota_unit==='%'||c.quota_total>0)?[{label:'手动剩余',value:c.quota_unit==='%'?c.quota_remaining:c.quota_remaining/c.quota_total*100,reset:c.quota_reset?'重置备注 '+c.quota_reset:''}]:[];
  if(row.enabled)for(const q of percentages){const label=document.createElement('small');label.textContent=q.label+' · '+q.value.toFixed(1)+'%';const bar=document.createElement('progress');bar.max=100;bar.value=q.value;bar.setAttribute('aria-label',q.label+'剩余百分比');card.append(label,bar);if(q.reset){const reset=document.createElement('small');reset.textContent=q.reset;card.append(reset);}}
  card.append(note,stamp,edit);
  if(row.enabled){const show=document.createElement('button');show.type='button';show.textContent=state.profile===row.id?'正在展示':'气泡展示';show.onclick=async()=>{try{const r=await fetch('/api/select',{method:'POST',headers:{'Content-Type':'application/json','X-Neko-CSRF':accountCsrf},body:JSON.stringify({profile:row.id})});if(!r.ok)throw Error('切换失败');drawCards(await r.json());if(typeof update==='function')update();}catch(e){field('accountFeedback').textContent=e.message;}};card.append(show);}
  card.dataset.search=(row.name+' '+row.id).toLowerCase();card.hidden=!card.dataset.search.includes(field('profileSearch').value.trim().toLowerCase());container.append(card);
 }
}
field('profileSearch').oninput=()=>{for(const card of field('quotaCards').children)card.hidden=!card.dataset.search.includes(field('profileSearch').value.trim().toLowerCase());};
window.openAccount=async()=>{panel.hidden=false;try{const r=await fetch('/api/status');if(!r.ok)throw Error();const s=await r.json();accountCsrf=s.csrf;drawCards(s);fillProfile(s.profile);}catch{field('accountFeedback').textContent='插件未连接，请稍后重试喵～';}};
field('closeAccount').onclick=()=>{panel.hidden=true;};
field('accountForm').onsubmit=async e=>{e.preventDefault();field('saveAccount').disabled=true;try{const body={profile:editingProfile,api_key:field('accountKey').value,alerts:field('alerts').checked};for(const id of configFields)body[id]=field(id).value;const r=await fetch('/api/config',{method:'POST',headers:{'Content-Type':'application/json','X-Neko-CSRF':accountCsrf},body:JSON.stringify(body)});const s=await r.json();if(!r.ok)throw Error(s.error||'保存失败');field('accountKey').value='';drawCards(s);field('accountFeedback').textContent=s.error?'已保存；'+s.error:'已保存并切换气泡展示喵～';if(typeof update==='function')update();}catch(e){field('accountFeedback').textContent=e.message;}finally{field('saveAccount').disabled=false;}};
setInterval(async()=>{if(panel.hidden||!accountCsrf)return;try{const r=await fetch('/api/status');if(r.ok)drawCards(await r.json());}catch{}},15000);
