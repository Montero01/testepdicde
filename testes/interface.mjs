const {parseHTML} = await import(process.env.CDE_LINKEDOM_MODULE || 'linkedom');
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const source=fs.readFileSync(new URL('../desempenho.js',import.meta.url),'utf8');
const original=fs.readFileSync(new URL('./pdi.fixture.html',import.meta.url),'utf8');
const wait=async()=>{for(let i=0;i<8;i++) await new Promise(resolve=>setImmediate(resolve));};
let assertions=0;
const ok=(value,label)=>{assert.ok(value,label);assertions++;};
function setup(role='employee',position='PCP') {
 const {window}=parseHTML(original); const {document}=window;
 // LinkeDOM não implementa edição de select.value, como um navegador.
 Object.defineProperty(window.HTMLSelectElement.prototype,'value',{configurable:true,get(){return this._testValue??this.querySelector('option')?.value??'';},set(v){this._testValue=v;}});
 window.switchTab=name=>{document.querySelectorAll('.tab-btn').forEach(n=>n.classList.toggle('active',n.dataset.tab===name));document.querySelectorAll('.tab-content').forEach(n=>n.classList.toggle('hidden',n.id!==`tab-${name}`));};
 const profile={id:'pcp-1',role,position,full_name:'<img src=x onerror=alert(1)>',sector:'PRODUÇÃO',is_master:false};
 const staff=role!=='employee';
 const data={today:'2026-11-16',is_pcp:position==='PCP',can_manage:staff,can_collect:position==='PCP'&&['employee','colaborador','supervisor'].includes(role),can_correct:role==='supervisor',dashboard_only:staff&&role!=='supervisor',can_view_logs:['gerente','diretoria'].includes(role),pcps:[{id:'pcp-1',name:profile.full_name,sector:'PRODUÇÃO'}]};
 const state={rows:[],audit:[],calls:[],inserts:0,updates:0,rpcFailure:false,listFailure:false,conflict:false,unsubscribe:null,dashboardFailure:false,summary:{total_m2:'0',pcp_count:0,entry_count:0,ranking:[],updated_at:'2026-11-16T12:00:00Z'}};
 let authCallback;
 const db={auth:{onAuthStateChange(cb){authCallback=cb;return{data:{subscription:{unsubscribe(){authCallback=null;}}}};}},async rpc(name,args){state.calls.push(name);if(name==='pdi_pcp_dashboard'){state.dashboardArgs=args;return state.dashboardFailure?{error:{code:'NETWORK'}}:{data:state.summary};}if(state.rpcFailure)return{error:{code:'PGRST202'}};return{data:{...data}};},from(table){
   const q={action:'read',conditions:[],lo:0,hi:29,payload:null,one:false,
    select(){return this;},order(){return this;},range(a,b){this.lo=a;this.hi=b;return this;},eq(a,b){this.conditions.push([a,b]);return this;},gte(){return this;},lte(){return this;},lt(){return this;},maybeSingle(){this.one=true;return this;},insert(payload){this.action='insert';this.payload=payload;return this;},update(payload){this.action='update';this.payload=payload;return this;},
    then(resolve,reject){state.calls.push(`${table}:${this.action}`);let out;
      if(this.action==='insert'){
        state.inserts++; const row={...this.payload,id:'record-'+state.inserts,revision:1,pcp_name_snapshot:profile.full_name,sector_snapshot:profile.sector,created_at:'2026-11-16T12:00:00Z',updated_at:'2026-11-16T12:00:00Z'};
        state.rows.push(row);out={data:null,error:null};
      }else if(this.action==='update'){
        state.updates++;const row=state.rows.find(r=>this.conditions.every(([a,b])=>r[a]===b));
        if(row&&!state.conflict){Object.assign(row,this.payload);row.revision++;out={data:[{id:row.id,revision:row.revision}]};}else out={data:[]};
      }else if(state.listFailure)out={error:{code:'NETWORK'}};
      else {const values=(table==='pdi_performance_audit'?state.audit:state.rows).filter(row=>this.conditions.every(([a,b])=>row[a]===b));out={data:this.one?(values[0]||null):values.slice(this.lo,this.hi+1),count:values.length};}
      return Promise.resolve(out).then(resolve,reject);
    }};return q;
 }};
 const context=vm.createContext({window,document,Intl,Date,Error,console,setTimeout,clearTimeout});vm.runInContext(source,context);
 return {window,document,profile,db,state,data,signout:()=>authCallback?.('SIGNED_OUT'),api:window.CDEDesempenho};
}
function input(t,name,value){const n=t.document.querySelector(`#pdi-perf-${name}`);assert.ok(n,name);n.value=value;return n;}
function submit(t,selector){t.document.querySelector(selector).dispatchEvent(new t.window.Event('submit',{cancelable:true}));}
const p=setup();await p.api.setSession(p.db,{id:'pcp-1'},p.profile);
ok(p.document.querySelector('#pdi-perf-employee-nav'),'PCP tem navegação própria');
ok(p.document.querySelector('#emp-score'),'IDs do PDI preservados');
await p.api.open();
ok(p.document.querySelector('#pdi-perf-create-m2'),'Formulário para PCP');
ok(!p.document.querySelector('#pdi-perf-audit'),'Sem logs para PCP');
ok(!p.document.querySelector('#pdi-perf-dashboard'),'PCP não recebe dashboard gerencial');
ok(!p.state.calls.includes('pdi_pcp_dashboard'),'PCP não consulta agregação gerencial');
ok(!p.document.querySelector('details').open,'Histórico começa recolhido');
for(const value of ['-1','1.2345','1.234,56','NaN','1e3']){input(p,'create-m2',value);input(p,'create-orders','001');submit(p,'.pdi-perf-form');await wait();}
ok(p.state.inserts===0,'Valores inválidos não são enviados');
input(p,'create-m2','12,345');input(p,'create-orders','001 001');submit(p,'.pdi-perf-form');await wait();ok(p.state.inserts===0,'Pedidos duplicados recusados');
input(p,'create-orders','');submit(p,'.pdi-perf-form');await wait();ok(p.state.inserts===0,'M² positivo exige pedidos');
input(p,'create-orders','001, 002\n003');submit(p,'.pdi-perf-form');submit(p,'.pdi-perf-form');await wait();
ok(p.state.inserts===1,'Duplo clique não duplica envio');ok(p.state.rows[0].m2_saved==='12.345','Decimal brasileiro preservado');ok(p.state.rows[0].order_numbers[0]==='001','Zeros do pedido preservados');
ok(!p.document.querySelector('#pdi-perf-create-m2'),'Formulário retirado após registro');
ok(!p.state.calls.some(x=>x.startsWith('pdi_performance_audit')),'PCP nunca busca logs');
ok(!p.document.querySelector('.pdi-perf-record img'),'Nome não executa HTML');
ok(p.document.querySelector('.pdi-perf-record h3').textContent.includes('<img'),'Nome exibido como texto');
ok(p.document.querySelector('.pdi-perf-pager button').disabled,'Paginação respeita primeira página');
p.signout();ok(!p.document.querySelector('.pdi-perf'),'Logout remove dados');ok(!p.document.querySelector('#pdi-perf-employee-base').hidden,'PDI restaurado no logout');
const s=setup('supervisor','Líder');await s.api.setSession(s.db,{id:'sup-1'},s.profile);
s.state.rows=[{id:'a',pcp_id:'pcp-1',work_date:'2026-11-16',m2_saved:4,order_numbers:['001'],revision:1,pcp_name_snapshot:'PCP',updated_at:'2026-11-16T12:00:00Z'}];await s.api.open();
ok(s.document.querySelector('.pdi-perf-menu'),'Supervisão tem menu no PDI');ok(!s.document.querySelector('#pdi-perf-create-m2'),'Supervisor não cria em nome de PCP');ok(!s.document.querySelector('#pdi-perf-audit'),'Supervisor não vê auditoria');
[...s.document.querySelectorAll('button')].find(n=>n.textContent==='Corrigir').click();
input(s,'edit-m2','5,5');input(s,'edit-reason','curta');submit(s,'.pdi-perf-edit-form');await wait();ok(s.state.updates===0,'Justificativa curta recusada');
input(s,'edit-reason','Conferência dos pedidos realizada');s.state.conflict=true;submit(s,'.pdi-perf-edit-form');await wait();ok(s.document.querySelector('.pdi-perf-status').textContent.includes('registro mudou'),'Conflito informado sem sobrescrever');
s.state.conflict=false;submit(s,'.pdi-perf-edit-form');await wait();ok(s.state.rows[0].m2_saved==='5.5','Correção salva');ok(s.state.rows[0].revision===2,'Revisão incrementada');
ok(!s.state.calls.some(x=>x.startsWith('pdi_performance_audit')),'Supervisão não consulta logs');
const g=setup('gerente','Gerente');await g.api.setSession(g.db,{id:'ger-1'},g.profile);await g.api.open();
ok(!g.document.querySelector('#pdi-perf-audit'),'Gerência fica apenas com dashboard');ok(!g.state.calls.some(x=>x.startsWith('pdi_performance_audit')),'Auditoria é carregada sob demanda');
ok(!g.state.calls.includes('pdi_pcp_daily:read'),'Gerência não busca lista operacional');
const c=setup('employee','Caixa');await c.api.setSession(c.db,{id:'caixa'},c.profile);ok(!c.document.querySelector('.pdi-perf-menu'),'Outros cargos não recebem formulário PCP');
const n=setup();await n.api.setSession(n.db,{id:'pcp-1'},n.profile);n.state.rpcFailure=true;await n.api.open();ok(n.document.querySelector('.pdi-perf-status').textContent.includes('Não foi possível'),'Falha de contexto tratada');ok(!n.document.querySelector('.pdi-perf-menu')?.disabled,'Navegação liberada após falha');
ok(s.document.querySelector('#pdi-perf-dashboard'),'Dashboard para supervisor');
ok(s.document.querySelector('.pdi-perf-filters').parentElement.tagName==='SECTION','Filtros da gestão ficam visíveis');
ok(s.document.querySelector('#pdi-perf-dashboard .pdi-perf-metrics'),'Indicadores de supervisão visíveis');
ok(g.document.querySelector('#pdi-perf-dashboard .pdi-perf-empty'),'Período vazio explica ausência do ranking');
const d=setup('diretoria','Diretor');await d.api.setSession(d.db,{id:'diretor'},d.profile);
d.state.rows=Array.from({length:35},(_,i)=>({id:'row'+i,pcp_id:'pcp-1',work_date:'2026-11-16',m2_saved:1,order_numbers:['1'],revision:1,pcp_name_snapshot:'PCP',updated_at:'2026-11-16T12:00:00Z'}));
d.state.summary={total_m2:'1234.567',pcp_count:3,entry_count:35,updated_at:'2026-11-16T12:00:00Z',ranking:[
{pcp_id:'a',name:'<img src=x onerror=alert(1)>',place:1,total_m2:'1000',entry_count:20,share_percent:'81.00',bar_percent:'100'},
{pcp_id:'b',name:'PCP B',place:2,total_m2:'234.567',entry_count:10,share_percent:'19.00',bar_percent:'23.46'},
{pcp_id:'c',name:'PCP C',place:3,total_m2:'0',entry_count:5,share_percent:'0',bar_percent:'0'}]};
await d.api.open();
ok(d.document.querySelectorAll('.pdi-perf-record').length===0,'Diretoria não exibe histórico operacional');
ok(d.document.querySelector('.pdi-perf-metric dd').textContent==='1.234,567 m²','Total usa a agregação de todo o período');
ok(d.document.querySelectorAll('.pdi-perf-rank-row').length===3,'Ranking usa todos os PCPs agregados');
ok(!d.document.querySelector('.pdi-perf-rank-name img'),'Nomes do ranking não interpretam HTML');
ok(d.document.querySelectorAll('.pdi-perf-rank-fill')[2].style.width==='0%','Resultado zero não produz divisão por zero');
ok(!d.document.querySelector('details'),'Diretoria não exibe listas ou logs expansíveis');
input(d,'start','2026-10-01');input(d,'end','2026-10-31');input(d,'pcp','pcp-1');submit(d,'.pdi-perf-filters');await wait();
ok(d.state.dashboardArgs.p_start_date==='2026-10-01'&&d.state.dashboardArgs.p_end_date==='2026-10-31'&&d.state.dashboardArgs.p_pcp_id==='pcp-1','Filtros enviados à agregação no servidor');
d.state.dashboardFailure=true;await d.api.open();
ok(d.document.querySelector('#pdi-perf-dashboard').textContent.includes('Não foi possível carregar'),'Falha de dashboard não é apresentada como zero');
ok(!d.document.querySelector('.pdi-perf-metrics'),'Números anteriores retirados após falha de dashboard');
ok(!d.document.querySelector('.pdi-perf-record'),'Falha do dashboard não revela histórico operacional');
d.state.dashboardFailure=false;d.state.listFailure=true;await d.api.open();
ok(d.document.querySelector('#pdi-perf-dashboard'),'Diretoria consulta apenas agregação, sem depender da lista diária');
ok(!d.state.calls.includes('pdi_pcp_daily:read'),'Diretoria não consulta tabela operacional pela interface');
const quick=label=>[...d.document.querySelectorAll('.pdi-perf-periods button')].find(n=>n.textContent===label).click();
quick('Hoje');await wait();ok(d.state.dashboardArgs.p_start_date==='2026-11-16'&&d.state.dashboardArgs.p_end_date==='2026-11-16','Atalho Hoje usa o dia informado pelo servidor');
quick('Mês anterior');await wait();ok(d.state.dashboardArgs.p_start_date==='2026-10-01'&&d.state.dashboardArgs.p_end_date==='2026-10-31','Atalho anterior considera o mês completo');
d.data.today='2028-03-01';await d.api.open();quick('Mês anterior');await wait();ok(d.state.dashboardArgs.p_end_date==='2028-02-29','Atalho mensal respeita ano bissexto');
ok(d.document.querySelectorAll('button').length>0&&[...d.document.querySelectorAll('button')].filter(n=>n.textContent==='Atualizar dados').length===1,'Uma ação de atualização no cabeçalho');
ok(d.document.querySelector('.pdi-perf-access-badge').textContent==='Somente consulta','Cabeçalho indica o tipo de acesso');
d.signout();ok(!d.document.querySelector('#pdi-perf-dashboard'),'Logout limpa dashboard');
const gp=setup('gerente','PCP');await gp.api.setSession(gp.db,{id:'gestor-pcp'},gp.profile);await gp.api.open();
ok(!gp.document.querySelector('.pdi-perf-form'),'Cargo PCP não libera coleta para gerente');
ok(!gp.document.querySelector('.pdi-perf-edit-form'),'Sem correção para gerente');
console.log(`${assertions} verificações de interface aprovadas (DOM simulado; não substitui teste visual).`);
