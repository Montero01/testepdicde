const {parseHTML}=await import(process.env.CDE_LINKEDOM_MODULE||'linkedom');
import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const html=fs.readFileSync(new URL('./pdi.fixture.html',import.meta.url),'utf8');
const main=fs.readFileSync(new URL('../desempenho.js',import.meta.url),'utf8'),cash=fs.readFileSync(new URL('../desempenho-caixa.js',import.meta.url),'utf8');
const wait=async()=>{for(let i=0;i<15;i++)await new Promise(r=>setImmediate(r));};let checks=0;
const ok=(x,label)=>{assert.ok(x,label);checks++;};
function setup(role='employee',position='Op. de Caixa'){
 const {window}=parseHTML(html),{document}=window;
 Object.defineProperty(window.HTMLSelectElement.prototype,'value',{configurable:true,get(){return this._value??this.querySelector('option')?.value??'';},set(v){this._value=v;}});
 let serial=0;Object.defineProperty(window,'crypto',{configurable:true,value:{randomUUID:()=>`10000000-0000-0000-0000-${String(++serial).padStart(12,'0')}`}});
 window.switchTab=name=>{document.querySelectorAll('.tab-btn').forEach(n=>n.classList.toggle('active',n.dataset.tab===name));document.querySelectorAll('.tab-content').forEach(n=>n.classList.toggle('hidden',n.id!==`tab-${name}`));};
 const user={id:'00000000-0000-0000-0000-000000000020'},profile={id:user.id,role,position,sector:'ADMINISTRATIVO',full_name:'<img src=x onerror=bad()>',is_master:false};
 const staff=role!=='employee';const ctx={today:'2026-11-16',is_cashier:position==='Op. de Caixa',can_manage:staff,can_collect:position==='Op. de Caixa'&&['employee','colaborador','supervisor'].includes(role),can_correct:role==='supervisor',dashboard_only:staff&&role!=='supervisor',can_view_logs:['gerente','diretoria'].includes(role),cashiers:[{id:user.id,name:profile.full_name,sector:profile.sector}]};
 const state={rows:[],logs:[],calls:[],uploads:0,reservations:0,saves:0,updates:0,files:{},uploadError:false,saveError:false,conflict:false,downloads:0,rpcError:false,statsError:false};let auth;
 const db={auth:{onAuthStateChange(fn){auth=fn;return{data:{subscription:{unsubscribe(){auth=null;}}}};}},async rpc(name,args){state.calls.push(name);
  if(state.rpcError)return{error:{code:'NETWORK'}};
  if(name==='pdi_cash_context')return{data:{...ctx}};
  if(name==='pdi_cash_reserve_pdf'){state.reservations++;state.reservationArgs=args;const id=`20000000-0000-0000-0000-${String(state.reservations).padStart(12,'0')}`;state.files[id]={id,storage_path:`${user.id}/${args.p_entry_id}/${id}.pdf`,original_name:args.p_original_name};return{data:{id,path:state.files[id].storage_path}};}
  if(name==='pdi_cash_dashboard'){state.dashboardArgs=args;if(state.statsError)return{error:{code:'NETWORK'}};const r=state.rows.filter(x=>!args.p_cashier_id||x.cashier_id===args.p_cashier_id);const s={};for(const key of ['result_cents','cash_cents','credit_cash_cents','credit_installment_cents','debit_cents','pix_cents'])s[key]=String(r.reduce((a,x)=>a+Number(x[key]||0),0));return{data:{...s,entry_count:r.length,cashier_count:new Set(r.map(x=>x.cashier_id)).size,updated_at:'2026-11-16T12:00:00Z'}};}
  if(name==='pdi_desempenho_context')return{data:{today:ctx.today,is_pcp:false,can_collect:false,can_correct:ctx.can_correct,dashboard_only:ctx.dashboard_only,can_manage:true,can_view_logs:ctx.can_view_logs,pcps:[]}};
  if(name==='pdi_pcp_dashboard')return{data:{total_m2:'0',pcp_count:0,entry_count:0,ranking:[],updated_at:'2026-11-16T12:00:00Z'}};
  throw new Error(name);
 },storage:{from(bucket){assert.equal(bucket,'pdi-cash-pdfs');return{async upload(path,file,options){state.uploads++;state.uploadOptions=options;state.uploadPath=path;if(state.uploadError)return{error:{code:'NETWORK'}};return{data:{path}};},async download(path){state.downloads++;return{data:new Blob(['%PDF-1.4 test'],{type:'application/pdf'})};}};}},from(table){
  const q={where:[],one:false,action:'read',payload:null,lo:0,hi:29,select(){return this;},eq(k,v){this.where.push([k,v]);return this;},gte(){return this;},lte(){return this;},lt(){return this;},order(){return this;},range(a,b){this.lo=a;this.hi=b;return this;},maybeSingle(){this.one=true;return this;},single(){this.one=true;return this;},insert(x){this.action='insert';this.payload=x;return this;},update(x){this.action='update';this.payload=x;return this;},then(resolve,reject){state.calls.push(`${table}:${this.action}`);let out;
   if(this.action==='insert'){
    state.saves++;if(state.saveError)out={error:{code:'NETWORK'}};else{const p=this.payload,r={...p,cashier_name_snapshot:profile.full_name,sector_snapshot:profile.sector,revision:1,updated_at:'2026-11-16T12:00:00Z',pdf_name_snapshot:state.files[p.pdf_file_id]?.original_name||null};r.credit_installment_cents=(r.installment_plans||[]).reduce((a,x)=>a+x.total_cents,0);state.rows.push(r);out={data:null};}
   }else if(this.action==='update'){
    state.updates++;const row=state.rows.find(r=>this.where.every(([k,v])=>r[k]===v));if(state.conflict||!row)out={data:[]};else{Object.assign(row,this.payload);row.revision++;row.credit_installment_cents=row.installment_plans.reduce((a,x)=>a+x.total_cents,0);row.pdf_name_snapshot=state.files[row.pdf_file_id]?.original_name||null;out={data:[{id:row.id,revision:row.revision}]};}
   }else{let items=table==='pdi_cash_files'?Object.values(state.files):table==='pdi_cash_daily'?state.rows:table==='pdi_cash_audit'?state.logs:[];items=items.filter(r=>this.where.every(([k,v])=>r[k]===v));out={data:this.one?(items[0]||null):items.slice(this.lo,this.hi+1),count:items.length};}
   return Promise.resolve(out).then(resolve,reject);
  }};return q;
 }};
 const urls={createObjectURL:()=>{state.blobURL=true;return'blob:test';},revokeObjectURL:()=>{state.revoked=true;}};
 const context=vm.createContext({window,document,Intl,Date,Error,console,Blob,Uint8Array,BigInt,URL:urls,setTimeout:(fn,ms)=>setTimeout(fn,ms===10000?0:ms),clearTimeout});vm.runInContext(cash,context);vm.runInContext(main,context);
 return{window,document,user,profile,ctx,state,db,api:window.CDEDesempenho,signout:()=>auth?.('SIGNED_OUT')};
}
function input(t,id,value){const n=t.document.querySelector(`#pdi-cash-${id}`);assert.ok(n,id);n.value=value;n.dispatchEvent(new t.window.Event('input'));return n;}
function submit(t,selector='.pdi-cash-form'){t.document.querySelector(selector).dispatchEvent(new t.window.Event('submit',{cancelable:true}));}
function click(t,text){const b=[...t.document.querySelectorAll('button')].find(x=>x.textContent===text);assert.ok(b,text);b.click();}
function pdf(name='fechamento.pdf',content='%PDF-1.4\nconteudo de teste'){const b=new Blob([content],{type:'application/pdf'});Object.defineProperty(b,'name',{value:name});return b;}
function file(t,value){const n=t.document.querySelector('.pdi-cash-form input[type=file]');Object.defineProperty(n,'files',{configurable:true,value:value?[value]:[]});return n;}
const c=setup();await c.api.setSession(c.db,c.user,c.profile);await c.api.open();
ok(c.document.querySelector('.pdi-cash-form'),'Cargo Op. de Caixa recebe formulário');ok(!c.document.querySelector('#pdi-perf-create-m2'),'Caixa não recebe formulário PCP');ok(!c.document.querySelector('#pdi-cash-audit'),'Caixa não vê logs');ok(!c.document.querySelector('#pdi-cash-dashboard'),'Caixa não recebe dashboard gerencial');
ok(!c.document.querySelector('#pdi-cash-history').open,'Histórico começa recolhido');
input(c,'create-result','100,00');input(c,'create-cash_cents','50,00');submit(c);await wait();ok(c.state.saves===0,'Diferença bloqueia fechamento');ok(c.state.reservations===0,'Validação ocorre antes de reservar PDF');
input(c,'create-credit_cash_cents','10,00');input(c,'create-debit_cents','5,00');input(c,'create-pix_cents','10,00');click(c,'Adicionar parcelamento');
input(c,'create-plan-1-total','25,00');input(c,'create-plan-1-amount','9,00');input(c,'create-plan-1-count','3');submit(c);await wait();ok(c.state.saves===0,'Parcelas inconsistentes recusadas');
input(c,'create-plan-1-amount','8,33');
ok(c.document.querySelector('.pdi-cash-plan-line').textContent.includes('R$ 8,34'),'Última parcela mostra ajuste de centavos');
file(c,pdf('fechamento.pdf','arquivo falso que nao e pdf'));submit(c);await wait();ok(c.state.uploads===0,'Cabeçalho falso bloqueia upload');
const selected=pdf();file(c,selected);c.state.uploadError=true;submit(c);await wait();ok(c.state.uploads===1&&c.state.saves===0,'Upload que falha não salva fechamento');
c.state.uploadError=false;c.state.saveError=true;submit(c);await wait();ok(c.state.uploads===2&&c.state.saves===1,'Arquivo só é vinculado após upload');
c.state.saveError=false;submit(c);submit(c);await wait();
ok(c.state.uploads===2,'Tentativa de salvar reaproveita PDF já enviado');ok(c.state.saves===2,'Duplo envio bloqueado');
ok(c.state.rows[0].result_cents===10000,'Moeda convertida para centavos exatos');ok(c.state.rows[0].cash_cents===5000,'Dinheiro preservado');ok(c.state.rows[0].credit_installment_cents===2500,'Total parcelado correto');
ok(c.state.rows[0].installment_plans[0].last_installment_cents===834,'Centavos da última parcela preservados');ok(c.state.reservationArgs.p_entry_id===c.state.rows[0].id,'PDF vinculado ao mesmo UUID do fechamento');
ok(c.state.uploadOptions.upsert===false&&c.state.uploadOptions.contentType==='application/pdf','Upload imutável e MIME PDF');
ok(!c.document.querySelector('.pdi-cash-form'),'Cadastro do dia bloqueado após concluir');ok(!c.document.querySelector('.pdi-cash-methods img'),'Dados não interpretam HTML');
ok(!c.state.calls.includes('pdi_cash_audit:read'),'Operadora não busca logs');
c.signout();ok(!c.document.querySelector('.pdi-perf'),'Logout remove dados de Caixa');
const s=setup('supervisor','Supervisão');await s.api.setSession(s.db,s.user,s.profile);s.state.rows=[{...c.state.rows[0],pdf_file_id:null,pdf_name_snapshot:null}];await s.api.open();click(s,'Caixa');await wait();
ok(s.document.querySelector('#pdi-cash-dashboard'),'Supervisão acessa dashboard Caixa');ok(!s.document.querySelector('.pdi-cash-form'),'Supervisor não cria em nome de outro');ok(!s.document.querySelector('#pdi-cash-audit'),'Supervisor sem painel de logs');
click(s,'Corrigir fechamento');input(s,'edit-result','110,00');input(s,'edit-cash_cents','60,00');input(s,'edit-reason','curta');submit(s);await wait();ok(s.state.updates===0,'Correção exige justificativa suficiente');
input(s,'edit-reason','Valor em dinheiro conferido no fechamento');s.state.conflict=true;submit(s);await wait();ok(s.document.querySelector('.pdi-perf-status').textContent.includes('fechamento mudou'),'Conflito não sobrescreve revisão');
s.state.conflict=false;submit(s);await wait();ok(s.state.rows[0].result_cents===11000&&s.state.rows[0].revision===2,'Supervisor corrige resultado');
ok(s.document.querySelector('#pdi-cash-dashboard').textContent.includes('R$ 110,00'),'Dashboard recarrega após correção');ok(!s.state.calls.includes('pdi_cash_audit:read'),'Supervisão não consulta API de logs');
click(s,'PCP');await wait();ok(s.document.querySelector('#pdi-perf-dashboard'),'Alternância mantém dashboard PCP');click(s,'Caixa');await wait();ok(s.document.querySelector('#pdi-cash-dashboard'),'Retorna ao Caixa');
const g=setup('gerente','Gerente');await g.api.setSession(g.db,g.user,g.profile);await g.api.open();click(g,'Caixa');await wait();ok(!g.document.querySelector('#pdi-cash-audit'),'Gerência sem painel operacional de auditoria');
ok(g.document.querySelector('#pdi-cash-dashboard'),'Gerência vê dashboard Caixa');ok(!g.state.calls.includes('pdi_cash_daily:read'),'Gerência não busca fechamentos individuais');ok(!g.document.querySelector('#pdi-cash-history'),'Gerência sem histórico operacional');
const gc=setup('gerente','Op. de Caixa');await gc.api.setSession(gc.db,gc.user,gc.profile);await gc.api.open();ok(!gc.document.querySelector('.pdi-cash-form'),'Gerente com cargo Caixa não recebe coleta');
const di=setup('diretoria','Diretor');await di.api.setSession(di.db,di.user,di.profile);await di.api.open();click(di,'Caixa');await wait();ok(di.document.querySelector('#pdi-cash-dashboard')&&!di.document.querySelector('.pdi-cash-form'),'Diretoria vê somente dashboard Caixa');
[...g.document.querySelectorAll('.pdi-perf-periods button')].find(n=>n.textContent==='Hoje').click();await wait();ok(g.state.dashboardArgs.p_start_date==='2026-11-16','Caixa tem o mesmo atalho Hoje');
ok(g.document.querySelectorAll('.pdi-cash-breakdown .pdi-perf-rank-fill').length===5,'Dashboard Caixa mostra as cinco formas em barras');
const z=setup();await z.api.setSession(z.db,z.user,z.profile);await z.api.open();input(z,'create-result','0,00');submit(z);await wait();ok(z.state.rows[0].result_cents===0&&!z.state.rows[0].pdf_file_id,'Fechamento zero e PDF opcional');
const p=setup();await p.api.setSession(p.db,p.user,p.profile);await p.api.open();input(p,'create-result','1.234,56');input(p,'create-cash_cents','1234.56');submit(p);await wait();ok(p.state.rows[0].result_cents===123456,'Formato brasileiro e ponto decimal aceitos');
const e=setup();await e.api.setSession(e.db,e.user,e.profile);e.state.rpcError=true;await e.api.open();ok(e.document.querySelector('.pdi-perf-status').textContent.includes('Não foi possível'),'Falha de conexão tratada');
console.log(`${checks} verificações de interface Caixa aprovadas (DOM/API simulados).`);
