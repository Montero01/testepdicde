// Mostra/esconde o botão do Academy conforme a tela
function updateAcademyFabVisibility() {
  const fab = document.querySelector('.academy-fab');
  const loginView = document.getElementById('login-view');
  if (!fab || !loginView) return;
  const loginVisible = !loginView.classList.contains('hidden');
  fab.style.display = loginVisible ? 'none' : 'flex';
}

// ==================== CONFIG ====================
const SUPABASE_URL = 'https://whjyvphamkbjcrdzhzoc.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_EyZgqDQTSV-M-O3_l63V7Q_LFcFDl69';
const { createClient } = supabase;
const db = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    storage: window.localStorage,
    storageKey: 'cde-auth-session',
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true
  }
});

// ==================== ESTADO ====================
let currentUser = null;
let currentProfile = null;
let pendingCertsCache = {};
let pendingApproval = null;
let pendingDelete = null;
let pendingEdit = null;
let cachedRankingData = [];
let cachedAllGoals = [];
let currentSectorFilter = 'all';
let isManagement = false, isDiretor = false, isSupervisor = false, isGerente = false, isMaster = false, canManageAll = false;

// Avatar
let selectedAvatarFile = null;

const SECTORS = [
  { key: 'COMERCIAL', label: 'Comercial', cls: 'comercial' },
  { key: 'PRODUCAO', label: 'Produção', cls: 'producao' },
  { key: 'ADMINISTRATIVO', label: 'Administrativo', cls: 'administrativo' }
];

// ==================== AUXILIARES ====================
let messageTimer = null;
function showMessage(text, type = 'success') {
  const box = document.getElementById('message-box');
  if (!box) return;
  const message = document.createElement('div');
  message.className = 'msg ' + (type === 'error' ? 'error' : 'success');
  message.textContent = String(text ?? '');
  box.replaceChildren(message);
  clearTimeout(messageTimer);
  messageTimer = setTimeout(() => box.replaceChildren(), 5000);
}
function wholePoints(value) {
  if (value === null || value === undefined || String(value).trim() === '') return null;
  const number = Number(value);
  return Number.isSafeInteger(number) && number >= 0 ? number : null;
}

function initials(name) {
  if (!name) return 'CD';
  const parts = String(name).trim().split(/\s+/);
  if (parts.length === 1) return parts[0].substring(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

function formatDate(dateStr) {
  if (!dateStr) return '—';
  const d = new Date(dateStr + (dateStr.length === 10 ? 'T00:00:00' : ''));
  return d.toLocaleDateString('pt-BR');
}
function escapeHtml(str) {
  if (str === null || str === undefined) return '';
  return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}
function normalizeSector(s) {
  if (!s) return null;
  return String(s).toUpperCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim();
}
function getSectorBadge(sector) {
  const n = normalizeSector(sector);
  if (!n) return '<span class="sector-badge none">Sem setor</span>';
  if (n === 'COMERCIAL') return '<span class="sector-badge comercial">Comercial</span>';
  if (n === 'PRODUCAO') return '<span class="sector-badge producao">Produção</span>';
  if (n === 'ADMINISTRATIVO') return '<span class="sector-badge administrativo">Administrativo</span>';
  return `<span class="sector-badge none">${escapeHtml(sector)}</span>`;
}
function getRoleBadge(role, isMasterUser = false) {
  const r = (role || '').toLowerCase();
  if (isMasterUser || r === 'master') return '<span class="role-badge master">Diretoria</span>';
  if (r === 'gerente') return '<span class="role-badge" style="background:#2563EB; color:#fff;">Gerente</span>';
  if (r === 'supervisor') return '<span class="role-badge" style="background:#0E7490; color:#fff;">Supervisor</span>';
  if (r.includes('diretor') || r.includes('director') || r === 'diretoria') return '<span class="role-badge">Diretoria</span>';
  return '';
}
function canEditOrDeleteGoal(goal) {
  if (canManageAll) return true;
  // Gerente pode editar metas do seu setor
  if (isGerente && normalizeSector(currentProfile.sector) === normalizeSector(goal.profiles?.sector || goal.sector)) return true;
  // Criador da meta pode editar
  return goal && goal.created_by && String(goal.created_by) === String(currentUser.id);
}

// ==================== TRIMESTRES ====================
function currentYear() { return new Date().getFullYear(); }
function currentQuarter() { return Math.floor(new Date().getMonth() / 3) + 1; }
function computeQuarters(certs) {
  const year = currentYear(), curQ = currentQuarter();
  const buckets = { 1: 0, 2: 0, 3: 0, 4: 0 };
  const hasData = { 1: false, 2: false, 3: false, 4: false };
  (certs || []).forEach(c => {
    if (!c.validated_at) return;
    const d = new Date(c.validated_at);
    if (d.getFullYear() !== year) return;
    const q = Math.floor(d.getMonth() / 3) + 1;
    buckets[q] += (c.points_awarded || 0);
    hasData[q] = true;
  });
  const labels = ['1º TRI', '2º TRI', '3º TRI', '4º TRI'];
  return [1, 2, 3, 4].map(q => ({ label: labels[q - 1], value: buckets[q], hasData: hasData[q], isCurrent: q === curQ }));
}
function renderQuarters(containerId, quarters) {
  const el = document.getElementById(containerId);
  el.innerHTML = quarters.map(q => {
    const cls = q.isCurrent ? 'quarter-col current' : 'quarter-col';
    if (q.hasData) return `<div class="${cls}"><div class="q-label">${q.label}</div><div class="q-value">${q.value}</div></div>`;
    return `<div class="${cls}"><div class="q-label">${q.label}</div><div class="q-value empty">—</div></div>`;
  }).join('');
}
function calcCoefficient(p, m) { if (!m || m <= 0) return 0; return Math.min(100, Math.round((p / m) * 100)); }

// ==================== TABS ====================
function switchTab(name) {
  document.querySelectorAll('.tab-btn').forEach(b => b.classList.toggle('active', b.dataset.tab === name));
  document.querySelectorAll('.tab-content').forEach(c => c.classList.toggle('hidden', c.id !== 'tab-' + name));
}

// ==================== AUTH ====================
let loginInProgress = false;
async function login() {
  if (loginInProgress) return;
  const email = document.getElementById('login-email').value.trim();
  const password = document.getElementById('login-password').value;
  if (!email || !password) return showMessage('Preencha e-mail e senha.', 'error');
  const button = document.getElementById('login-submit');
  loginInProgress = true;
  if (button) { button.disabled = true; button.textContent = 'Entrando…'; }
  try {
    const { error } = await db.auth.signInWithPassword({ email, password });
    if (error) return showMessage(error.message, 'error');
    await loadUser();
  } catch (error) {
    showMessage('Não foi possível entrar. Verifique sua conexão e tente novamente.', 'error');
  } finally {
    loginInProgress = false;
    if (button) { button.disabled = false; button.textContent = 'Entrar'; }
  }
}
async function logout() {
  try {
    const { error } = await db.auth.signOut();
    if (error) return showMessage('Não foi possível sair. Tente novamente.', 'error');
    location.reload();
  } catch (error) {
    showMessage('Não foi possível sair. Verifique sua conexão.', 'error');
  }
}
let userLoadPromise = null;
function loadUser() {
  if (!userLoadPromise) userLoadPromise = _loadUser().catch(() => {
    showMessage('Não foi possível carregar o perfil. Verifique sua conexão e tente novamente.', 'error');
  }).finally(() => { userLoadPromise = null; });
  return userLoadPromise;
}
function showLoginView() {
  currentUser = null; currentProfile = null;
  isManagement = isDiretor = isSupervisor = isGerente = isMaster = canManageAll = false;
  pendingCertsCache = {}; cachedRankingData = []; cachedAllGoals = [];
  pendingApproval = pendingDelete = pendingEdit = null;
  document.getElementById('login-view').classList.remove('hidden');
  document.getElementById('employee-view').classList.add('hidden');
  document.getElementById('management-view').classList.add('hidden');
  document.querySelectorAll('.modal-overlay').forEach(modal => modal.classList.add('hidden'));
  updateAcademyFabVisibility();
}

async function _loadUser() {
  const { data: { user } } = await db.auth.getUser();
  if (!user) { showLoginView(); return; }
  currentUser = user;
  const { data: profile, error } = await db.from('profiles').select('*').eq('id', user.id).single();
  if (error || !profile) return showMessage('Perfil não encontrado.', 'error');
  currentProfile = profile;
  document.getElementById('login-view').classList.add('hidden');
  updateAcademyFabVisibility();
  currentProfile = profile;
window.CDEDesempenho?.setSession(db, user, profile);
document.getElementById('login-view').classList.add('hidden');

  const roleLower = (profile.role || '').toLowerCase();
  isMaster = profile.is_master === true || roleLower === 'master';
  isSupervisor = roleLower === 'supervisor';
  isGerente = roleLower === 'gerente';
  isDiretor = roleLower.includes('diretor') || roleLower.includes('director') || roleLower === 'diretoria';
  canManageAll = isDiretor || isMaster;
  isManagement = isSupervisor || isGerente || isDiretor || isMaster;

  if (isManagement) {
    document.getElementById('management-view').classList.remove('hidden');
    document.getElementById('employee-view').classList.add('hidden');
    const titleEl = document.getElementById('mgmt-title');
    if (isMaster) titleEl.textContent = 'Painel da Diretoria';
    else if (isDiretor) titleEl.textContent = 'Painel da Diretoria';
    else if (isGerente) titleEl.textContent = 'Painel do Gerente';
    else if (isSupervisor) titleEl.textContent = 'Painel do Supervisor(a)';

    document.getElementById('mgmt-user-info').innerHTML = `${escapeHtml(profile.full_name)} ${getRoleBadge(profile.role, isMaster)} ${(isSupervisor || isGerente || profile.sector) ? getSectorBadge(profile.sector) : ''}`;

    const mgmtPos = document.getElementById('mgmt-position');
    if (mgmtPos) mgmtPos.textContent = profile.position || '';
    applyAvatarToUI(profile.full_name || user.email, profile.avatar_url || null);

    const noticeEl = document.getElementById('director-notice');
    if (canManageAll) {
      document.getElementById('director-notice-role').textContent = isMaster ? 'Diretoria' : 'Diretoria';
      noticeEl.classList.toggle('master', isMaster);
      noticeEl.classList.remove('hidden');
    } else noticeEl.classList.add('hidden');

    // Regra da Aba "Meu PDI"
    document.getElementById('tab-btn-mypdi').classList.toggle('hidden', !isSupervisor && !isGerente);

    // Regra da Aba "Gerenciar Metas" (Apenas Gerente, Diretoria e Master)
    const goalsTabBtn = document.querySelector('button[data-tab="goals"]');
    if (goalsTabBtn) {
      if (isSupervisor && !isGerente && !canManageAll) {
        return showMessage('Esse nível de acesso não permite criar metas', 'error');
      } else {
        goalsTabBtn.classList.remove('hidden');
      }
    }

    const filterSel = document.getElementById('ranking-sector-filter');
    const filterLock = document.getElementById('filter-lock-msg');
    
    // Gerente e Supervisor ficam restritos ao seu setor
    if ((isSupervisor || isGerente) && !canManageAll && profile.sector) {
      const n = normalizeSector(profile.sector);
      if (['COMERCIAL', 'PRODUCAO', 'ADMINISTRATIVO'].includes(n)) {
        filterSel.value = n; filterSel.disabled = true;
        currentSectorFilter = n; filterLock.classList.remove('hidden');
      }
    } else {
      filterSel.value = 'all'; filterSel.disabled = false;
      currentSectorFilter = 'all'; filterLock.classList.add('hidden');
    }
    
    const goalsFilter = document.getElementById('goals-sector-filter');
    if ((isSupervisor || isGerente) && !canManageAll && profile.sector) {
      goalsFilter.value = normalizeSector(profile.sector); goalsFilter.disabled = true;
    } else {
      goalsFilter.value = 'all'; goalsFilter.disabled = false;
    }

    if (isSupervisor || isGerente) loadMgmtPersonalData();
    loadGoalAssignmentOptions();
    loadAllGoals();
    loadSectorComparisonAndRanking();
    loadPendingCertificates();
    loadValidatedCertificates();
  } else {
    document.getElementById('employee-view').classList.remove('hidden');
    document.getElementById('management-view').classList.add('hidden');
    document.getElementById('emp-user-info').innerHTML = `${escapeHtml(profile.full_name)} (Colaborador) ${getSectorBadge(profile.sector)}`;

    const empPos = document.getElementById('emp-position');
    if (empPos) empPos.textContent = profile.position || '';
    applyAvatarToUI(profile.full_name || user.email, profile.avatar_url || null);

    loadEmployeeData();
  }
}

// ==================== COLABORADOR ====================
async function loadEmployeeData() {
  await loadGoalsFor(currentUser.id, 'goals-list', 'cert-goal');
  await loadCertificatesFor(currentUser.id, 'emp-certs-list');
  await loadScoreFor(currentUser.id, 'emp-score', 'emp-quarters', 'emp-coef', 'emp-coef-bar');
}
async function loadMgmtPersonalData() {
  await loadGoalsFor(currentUser.id, 'mgmt-goals-list', 'mgmt-cert-goal');
  await loadCertificatesFor(currentUser.id, 'mgmt-certs-list');
  await loadScoreFor(currentUser.id, 'mgmt-score', 'mgmt-quarters', 'mgmt-coef', 'mgmt-coef-bar');
}

// ==================== GENERICOS ====================
async function loadGoalsFor(userId, listId, selectId) {
  const { data: goals, error } = await db.from('goals').select('*').eq('user_id', userId).order('deadline', { ascending: true });
  const list = document.getElementById(listId);
  const select = document.getElementById(selectId);
  if (error || !goals || goals.length === 0) {
    list.innerHTML = '<p style="color:#6D6E71;">Nenhuma meta cadastrada.</p>';
    if (select) select.innerHTML = '<option value="">Nenhuma meta disponível</option>';
    return;
  }
  list.innerHTML = goals.map(g => {
    const isDerived = g.goal_type === 'sector_derived';
    return `<div class="goal-item ${isDerived ? 'goal-derived' : ''}">
      <div class="info">
        <div class="title">${escapeHtml(g.title)}</div>
        <div class="meta">Prazo: ${formatDate(g.deadline)} | Pontos máx: ${g.max_points}${isDerived ? ' | <em style="color:#D4650F;">Meta setorial (30% do setor)</em>' : ''}</div>
        ${g.description ? `<div class="meta">${escapeHtml(g.description)}</div>` : ''}
      </div>
    </div>`;
  }).join('');
  if (select) {
    select.innerHTML = goals.map(g => `<option value="${g.id}">${escapeHtml(g.title)} (prazo: ${formatDate(g.deadline)})</option>`).join('');
  }
}
async function loadCertificatesFor(userId, listId) {
  const { data: certs, error } = await db.from('certificates').select('*, goals(title)').eq('user_id', userId).order('submitted_at', { ascending: false });
  const list = document.getElementById(listId);
  if (error || !certs || certs.length === 0) {
    list.innerHTML = '<p style="color:#6D6E71;">Nenhum certificado enviado ainda.</p>';
    return;
  }
  list.innerHTML = certs.map(c => {
    const dois = c.file_url_2 ? '<span style="font-size:0.72rem; color:#6D6E71; margin-left:6px;">• 2 arquivos anexados</span>' : '';
    return `
    <div class="cert-item">
      <div class="info">
        <div class="title">${escapeHtml(c.goals?.title || 'Meta')}${dois}</div>
        <div class="meta">Enviado em ${formatDate(c.submitted_at)}</div>
      </div>
      <div>
        <span class="badge ${c.status}">${c.status === 'pending' ? 'Pendente' : c.status === 'approved' ? 'Aprovado' : 'Rejeitado'}</span>
        ${c.status === 'approved' ? `<strong style="margin-left:8px; color:#158A49;">+${c.points_awarded} pts</strong>` : ''}
      </div>
    </div>`;
  }).join('');
}
async function loadScoreFor(userId, scoreId, quartersId, coefId, coefBarId) {
  const { data: approved } = await db.from('certificates').select('points_awarded, validated_at').eq('user_id', userId).eq('status', 'approved');
  const { data: goals } = await db.from('goals').select('max_points, goal_type').eq('user_id', userId);
  const totalPoints = (approved || []).reduce((s, c) => s + (c.points_awarded || 0), 0);
  const maxPossible = (goals || []).reduce((s, g) => s + (g.max_points || 0), 0);
  const coef = calcCoefficient(totalPoints, maxPossible);
  document.getElementById(scoreId).textContent = totalPoints;
  renderQuarters(quartersId, computeQuarters(approved || []));
  document.getElementById(coefId).textContent = coef + '%';
  document.getElementById(coefBarId).style.width = coef + '%';
}

// ==================== UPLOAD ====================
async function submitCertificate(e) {
  e.preventDefault();
  if (!currentUser) return showMessage('Entre novamente antes de enviar.', 'error');
  const sent = await _doUpload(currentUser.id, 'cert-goal', 'cert-file', 'emp-certs-list');
  if (!sent) return;
  await loadScoreFor(currentUser.id, 'emp-score', 'emp-quarters', 'emp-coef', 'emp-coef-bar');
}
async function submitMgmtCertificate(e) {
  e.preventDefault();
  if (!currentUser) return showMessage('Entre novamente antes de enviar.', 'error');
  const sent = await _doUpload(currentUser.id, 'mgmt-cert-goal', 'mgmt-cert-file', 'mgmt-certs-list');
  if (!sent) return;
  await loadScoreFor(currentUser.id, 'mgmt-score', 'mgmt-quarters', 'mgmt-coef', 'mgmt-coef-bar');
}

function onCertFileChange(inputId, labelId) {
  const input = document.getElementById(inputId);
  const label = document.getElementById(labelId);
  if (!input || !label) return;
  const f = input.files[0];
  label.textContent = f ? '✓ ' + f.name : '';
}

const uploadsInProgress = new Set();
async function _doUpload(userId, goalSelectId, fileInputId, listId) {
  if (uploadsInProgress.has(fileInputId)) return false;
  const goalId = document.getElementById(goalSelectId).value;
  const fileInput1 = document.getElementById(fileInputId);
  const fileInput2 = document.getElementById(fileInputId + '-2');

  const files = [];
  if (fileInput1 && fileInput1.files[0]) files.push(fileInput1.files[0]);
  if (fileInput2 && fileInput2.files[0]) files.push(fileInput2.files[0]);

  if (!fileInput1?.files[0]) return showMessage('Selecione o primeiro arquivo obrigatório.', 'error');
  if (!goalId) return showMessage('Selecione a meta relacionada.', 'error');
  if (files.length === 0) return showMessage('Selecione pelo menos 1 arquivo.', 'error');
  if (files.length > 2) return showMessage('Máximo de 2 arquivos por envio.', 'error');

  const TIPOS = ['application/pdf', 'image/jpeg', 'image/jpg', 'image/png'];
  for (const f of files) {
    const extOk = /\.(pdf|jpe?g|png)$/i.test(f.name);
    if (!extOk || (f.type && !TIPOS.includes(f.type))) {
      return showMessage(`Tipo não permitido: "${f.name}". Use PDF, JPG ou PNG.`, 'error');
    }
    if (f.size > 10 * 1024 * 1024) {
      return showMessage(`Arquivo muito grande: "${f.name}". Máximo 10MB.`, 'error');
    }
  }

  const form = fileInput1.closest?.('form');
  const button = form?.querySelector('button[type="submit"]');
  const previousText = button?.textContent;
  uploadsInProgress.add(fileInputId);
  if (button) { button.disabled = true; button.textContent = 'Enviando…'; }
  try {
    const uploadOne = async (file) => {
      const ext = file.name.split('.').pop().toLowerCase();
      const cleanName = `${Date.now()}_${Math.random().toString(36).substring(2, 8)}.${ext}`;
      const filePath = `${userId}/${cleanName}`;
      const { error } = await db.storage.from('certificates').upload(filePath, file);
      if (error) throw error;
      return { path: filePath, name: file.name };
    };

    const primeiro = await uploadOne(files[0]);
    let segundo = null;
    if (files[1]) segundo = await uploadOne(files[1]);

    const payload = {
      user_id: userId,
      goal_id: goalId,
      file_url: primeiro.path,
      file_name: primeiro.name,
      status: 'pending'
    };
    if (segundo) {
      payload.file_url_2 = segundo.path;
      payload.file_name_2 = segundo.name;
    }

    const { error: dbErr } = await db.from('certificates').insert(payload);
    if (dbErr) throw dbErr;

    showMessage('Documento enviado! Aguarde validação.', 'success');

    if (fileInput1) fileInput1.value = '';
    if (fileInput2) fileInput2.value = '';
    const lbl1 = document.getElementById(fileInputId + '-name');
    if (lbl1) lbl1.textContent = '';
    const lbl2 = document.getElementById(fileInputId + '-2-name');
    if (lbl2) lbl2.textContent = '';

    try { await loadCertificatesFor(userId, listId); } catch { showMessage('Documento enviado, mas a lista não pôde ser atualizada. Recarregue a página para conferir.', 'error'); }
    return true;
  } catch (e) {
    console.error('Erro no upload:', e);
    showMessage('Erro: ' + (e.message || 'falha no upload'), 'error');
    return false;
  } finally {
    uploadsInProgress.delete(fileInputId);
    if (button) { button.disabled = false; button.textContent = previousText; }
  }
}

// ==================== GERENCIAR METAS ====================
async function loadGoalAssignmentOptions() {
  const select = document.getElementById('goal-assignee');
  const hint = document.getElementById('goal-scope-hint');
  const { data, error } = await db.rpc('get_goal_assignees');
  if (error) return loadGoalAssignmentOptionsFallback();
  if (!data || data.length === 0) { select.innerHTML = `<option value="">Nenhum colaborador encontrado</option>`; return; }
  if (canManageAll) hint.innerHTML = `Você tem acesso <strong>total</strong>.`;
  else hint.innerHTML = `Você está criando metas para o setor <strong>${escapeHtml(currentProfile.sector || '')}</strong>.`;
  select.innerHTML = '<option value="">— Selecione —</option>' +
    data.map(p => {
      const isSup = (p.role || '').toLowerCase() === 'supervisor';
      const isGer = (p.role || '').toLowerCase() === 'gerente';
      const tag = isSup ? ' [Supervisor]' : (isGer ? ' [Gerente]' : '');
      const sec = p.sector ? ` — ${p.sector}` : '';
      return `<option value="${p.id}">${escapeHtml(p.full_name || p.email)}${tag}${sec}</option>`;
    }).join('');
}
async function loadGoalAssignmentOptionsFallback() {
  const select = document.getElementById('goal-assignee');
  const hint = document.getElementById('goal-scope-hint');
  const scopeSector = (!canManageAll && (isSupervisor || isGerente)) ? currentProfile.sector : null;
  const roles = canManageAll ? ['employee', 'colaborador', 'supervisor', 'gerente'] : ['employee', 'colaborador'];
  let query = db.from('profiles').select('id, full_name, email, sector, role').in('role', roles);
  if (scopeSector) query = query.eq('sector', scopeSector);
  hint.innerHTML = scopeSector ? `Você está criando metas para o setor <strong>${escapeHtml(scopeSector)}</strong>.` : `Você tem acesso <strong>total</strong>.`;
  const { data, error } = await query;
  if (error || !data || data.length === 0) { select.innerHTML = `<option value="">Nenhum colaborador encontrado</option>`; return; }
  data.sort((a, b) => (a.full_name || '').localeCompare(b.full_name || ''));
  select.innerHTML = '<option value="">— Selecione —</option>' +
    data.map(p => {
      const isSup = (p.role || '').toLowerCase() === 'supervisor';
      const isGer = (p.role || '').toLowerCase() === 'gerente';
      const tag = isSup ? ' [Supervisor]' : (isGer ? ' [Gerente]' : '');
      return `<option value="${p.id}">${escapeHtml(p.full_name || p.email)}${tag}${p.sector ? ' — ' + p.sector : ''}</option>`;
    }).join('');
}
async function createGoal(e) {
  e.preventDefault();
  
  // Trava de segurança (Supervisor não pode criar)
  if (isSupervisor && !isGerente && !canManageAll) {
    return showMessage('Você não tem permissão para criar metas.', 'error');
  }

  const assigneeId = document.getElementById('goal-assignee').value;
  const title = document.getElementById('goal-title').value.trim();
  const description = document.getElementById('goal-desc').value.trim();
  const deadline = document.getElementById('goal-deadline').value;
  const maxPoints = wholePoints(document.getElementById('goal-points').value);
  if (!assigneeId || !title || !deadline || maxPoints === null || maxPoints < 1) return showMessage('Preencha todos os campos.', 'error');
  const { data: assignee } = await db.from('profiles').select('id, sector, role').eq('id', assigneeId).single();
  if (!assignee) return showMessage('Colaborador não encontrado.', 'error');
  
  if (!canManageAll && isGerente) {
    if (normalizeSector(currentProfile.sector) !== normalizeSector(assignee.sector)) return showMessage('Você só pode criar metas para o seu setor.', 'error');
  }
  
  const payload = { user_id: assigneeId, title, description: description || null, deadline, max_points: maxPoints, goal_type: 'individual', sector: assignee.sector || null, created_by: currentUser.id };
  let { error } = await db.from('goals').insert(payload);
  if (error && /created_by/i.test(error.message || '')) {
    delete payload.created_by;
    const retry = await db.from('goals').insert(payload);
    error = retry.error;
  }
  if (error) return showMessage('Erro ao criar meta: ' + error.message, 'error');
  showMessage('Meta criada com sucesso! ⚡', 'success');
  document.getElementById('create-goal-form').reset();
  document.getElementById('goal-points').value = 10;
  loadAllGoals();
  loadGoalAssignmentOptions();
}
async function loadAllGoals() {
  const container = document.getElementById('all-goals-list');
  container.innerHTML = '<div class="rank-empty">Carregando metas…</div>';
  const { data, error } = await db.from('goals').select('*, profiles!goals_user_id_fkey(id, full_name, email, sector, role)').eq('goal_type', 'individual').order('deadline', { ascending: true });
  if (error) { container.innerHTML = `<div class="rank-empty" style="color:#C8102E;">Erro: ${escapeHtml(error.message)}</div>`; return; }
  let goals = data || [];
  if (!canManageAll && (isGerente || isSupervisor)) {
    goals = goals.filter(g => normalizeSector(g.profiles?.sector) === normalizeSector(currentProfile.sector));
  }
  cachedAllGoals = goals;
  renderAllGoals();
}
function renderAllGoals() {
  const container = document.getElementById('all-goals-list');
  const filterSel = document.getElementById('goals-sector-filter');
  const searchEl = document.getElementById('goals-search');
  let goals = [...cachedAllGoals];
  if (filterSel.value !== 'all') goals = goals.filter(g => normalizeSector(g.profiles?.sector) === filterSel.value);
  const search = (searchEl?.value || '').toLowerCase().trim();
  if (search) goals = goals.filter(g => (g.profiles?.full_name || '').toLowerCase().includes(search) || (g.title || '').toLowerCase().includes(search));
  if (goals.length === 0) { container.innerHTML = '<div class="rank-empty">Nenhuma meta encontrada.</div>'; return; }
  goals.sort((a, b) => {
    const na = a.profiles?.full_name || '', nb = b.profiles?.full_name || '';
    if (na !== nb) return na.localeCompare(nb);
    return new Date(a.deadline) - new Date(b.deadline);
  });
  container.innerHTML = goals.map(g => {
    const isSup = (g.profiles?.role || '').toLowerCase() === 'supervisor';
    const isGer = (g.profiles?.role || '').toLowerCase() === 'gerente';
    const supTag = isSup ? ' <span class="role-badge" style="font-size:0.6rem; background:#0E7490; color:#fff;">Supervisor</span>' : (isGer ? ' <span class="role-badge" style="font-size:0.6rem; background:#2563EB; color:#fff;">Gerente</span>' : '');
    const canModify = canEditOrDeleteGoal(g);
    const editBtn = canModify ? `<button class="small secondary" onclick="openEditModal('${g.id}')">✏️ Editar</button>` : `<button class="small secondary" disabled>🔒 Editar</button>`;
    const delBtn = canModify ? `<button class="small danger" onclick="openDeleteModal('${g.id}')">🗑️ Excluir</button>` : `<button class="small secondary" disabled>🔒 Excluir</button>`;
    return `<div class="goal-item">
      <div class="info">
        <div class="title">${escapeHtml(g.profiles?.full_name || 'Colaborador')}${supTag} ${getSectorBadge(g.profiles?.sector)}</div>
        <div class="meta" style="font-weight:600; color:#414042; margin-top:4px;">🎯 ${escapeHtml(g.title)}</div>
        <div class="meta">Prazo: ${formatDate(g.deadline)} | Pontos máx: <strong>${g.max_points}</strong></div>
        ${g.description ? `<div class="meta" style="font-style:italic;">${escapeHtml(g.description)}</div>` : ''}
      </div>
      <div class="goal-actions">${editBtn}${delBtn}</div>
    </div>`;
  }).join('');
}

// ==================== EDITAR META ====================
async function openEditModal(goalId) {
  let goal = cachedAllGoals.find(g => String(g.id) === String(goalId));
  if (!goal) {
    const { data, error } = await db.from('goals').select('*, profiles!goals_user_id_fkey(id, full_name, email, sector, role)').eq('id', goalId).single();
    if (error || !data) return showMessage('Meta não encontrada.', 'error');
    goal = data;
  }
  if (!canEditOrDeleteGoal(goal)) return showMessage('Sem permissão.', 'error');
  pendingEdit = { goalId: goal.id };
  document.getElementById('edit-modal-info').innerHTML = `Editando meta de <strong>${escapeHtml(goal.profiles?.full_name || '')}</strong>`;
  document.getElementById('edit-goal-title').value = goal.title || '';
  document.getElementById('edit-goal-desc').value = goal.description || '';
  document.getElementById('edit-goal-deadline').value = goal.deadline || '';
  document.getElementById('edit-goal-points').value = goal.max_points || 10;
  document.getElementById('edit-modal').classList.remove('hidden');
  setTimeout(() => document.getElementById('edit-goal-title').focus(), 60);
}
function closeEditModal() { pendingEdit = null; document.getElementById('edit-modal').classList.add('hidden'); }
async function confirmEditGoal() {
  if (!pendingEdit) return;
  const title = document.getElementById('edit-goal-title').value.trim();
  const description = document.getElementById('edit-goal-desc').value.trim();
  const deadline = document.getElementById('edit-goal-deadline').value;
  const maxPoints = wholePoints(document.getElementById('edit-goal-points').value);
  if (!title || !deadline || maxPoints === null || maxPoints < 1) return showMessage('Preencha todos os campos.', 'error');
  const goalId = pendingEdit.goalId;
  closeEditModal();
  const { error } = await db.from('goals').update({ title, description: description || null, deadline, max_points: maxPoints }).eq('id', goalId);
  if (error) return showMessage('Erro ao editar: ' + error.message, 'error');
  showMessage('Meta atualizada!', 'success');
  loadAllGoals();
  loadSectorComparisonAndRanking();
}

// ==================== EXCLUIR META ====================
async function openDeleteModal(goalId) {
  let goal = cachedAllGoals.find(g => String(g.id) === String(goalId));
  if (!goal) {
    const { data, error } = await db.from('goals').select('*, profiles!goals_user_id_fkey(id, full_name, email, sector, role)').eq('id', goalId).single();
    if (error || !data) return showMessage('Meta não encontrada.', 'error');
    goal = data;
  }
  if (!canEditOrDeleteGoal(goal)) return showMessage('Sem permissão.', 'error');
  pendingDelete = { goalId: goal.id };
  document.getElementById('delete-modal-info').innerHTML = `Excluir a meta <strong>"${escapeHtml(goal.title)}"</strong> de <strong>${escapeHtml(goal.profiles?.full_name || '')}</strong>?`;
  document.getElementById('delete-modal').classList.remove('hidden');
}
function closeDeleteModal() { pendingDelete = null; document.getElementById('delete-modal').classList.add('hidden'); }
async function confirmDeleteGoal() {
  if (!pendingDelete) return;
  const { goalId } = pendingDelete;
  closeDeleteModal();
  const { error } = await db.from('goals').delete().eq('id', goalId);
  if (error) return showMessage('Erro ao excluir: ' + error.message, 'error');
  showMessage('Meta excluída!', 'success');
  loadAllGoals();
  loadGoalAssignmentOptions();
  loadSectorComparisonAndRanking();
}

// ==================== RANKING + COMPARATIVO ====================
async function loadSectorComparisonAndRanking() {
  const rankingContainer = document.getElementById('ranking-container');
  const compareContainer = document.getElementById('sector-compare-container');
  const adhContainer = document.getElementById('adherence-container');
  rankingContainer.innerHTML = '<div class="rank-empty">Carregando…</div>';
  compareContainer.innerHTML = '<div class="rank-empty">Carregando…</div>';
  adhContainer.innerHTML = '<div class="rank-empty">Carregando…</div>';

  const { data: people, error: pErr } = await db.from('profiles').select('id, full_name, email, role, sector, is_master').in('role', ['employee', 'colaborador', 'supervisor', 'gerente']);
  if (pErr || !people || people.length === 0) {
    rankingContainer.innerHTML = '<div class="rank-empty">Nenhum usuário cadastrado.</div>';
    compareContainer.innerHTML = ''; adhContainer.innerHTML = '';
    return;
  }
  const { data: certs, error: cErr } = await db.from('certificates').select('user_id, points_awarded, status');
  if (cErr) { rankingContainer.innerHTML = `<div class="rank-empty" style="color:#C8102E;">Erro</div>`; return; }

  const statsMap = {};
  people.forEach(p => { statsMap[p.id] = { points: 0, certCount: 0, total: 0, approved: 0, rejected: 0, pending: 0 }; });
  (certs || []).forEach(c => {
    const st = statsMap[c.user_id];
    if (!st) return;
    st.total += 1;
    if (c.status === 'approved') { st.points += (c.points_awarded || 0); st.certCount += 1; st.approved += 1; }
    else if (c.status === 'rejected') st.rejected += 1;
    else if (c.status === 'pending') st.pending += 1;
  });
  const ranking = people.map(p => {
    const st = statsMap[p.id];
    const decided = st.approved + st.rejected;
    const adherence = decided > 0 ? Math.round((st.approved / decided) * 100) : null;
    return { id: p.id, full_name: p.full_name || p.email || 'Sem nome', email: p.email || '', role: (p.role || '').toLowerCase(), isMaster: p.is_master === true, sector: p.sector || null, sectorKey: normalizeSector(p.sector), points: st.points, certCount: st.certCount, totalCerts: st.total, approved: st.approved, rejected: st.rejected, pending: st.pending, adherence };
  });
  cachedRankingData = ranking;
  renderRankingTable(ranking);
  renderSectorComparison(ranking);
  renderAdherence(ranking);
}
function adherenceBadge(a) {
  if (a === null || a === undefined) return '<span class="adherence-badge none">—</span>';
  if (a >= 80) return `<span class="adherence-badge high">${a}%</span>`;
  if (a >= 50) return `<span class="adherence-badge mid">${a}%</span>`;
  return `<span class="adherence-badge low">${a}%</span>`;
}
function renderRankingTable(ranking) {
  const container = document.getElementById('ranking-container');
  let filtered = currentSectorFilter === 'all' ? ranking : ranking.filter(r => r.sectorKey === currentSectorFilter);
  if ((isSupervisor || isGerente) && !canManageAll) filtered = filtered.filter(r => r.sectorKey === normalizeSector(currentProfile.sector));
  if (filtered.length === 0) { container.innerHTML = '<div class="rank-empty">Nenhum colaborador encontrado.</div>'; return; }
  const sorted = [...filtered].sort((a, b) => b.points - a.points || a.full_name.localeCompare(b.full_name));
  const rows = sorted.map((r, idx) => {
    const pos = idx + 1;
    let medalClass = '', medalLabel = pos;
    if (pos === 1) { medalClass = 'gold'; medalLabel = '🥇'; }
    else if (pos === 2) { medalClass = 'silver'; medalLabel = '🥈'; }
    else if (pos === 3) { medalClass = 'bronze'; medalLabel = '🥉'; }
    const isSup = r.role === 'supervisor';
    const isGer = r.role === 'gerente';
    const roleTag = isSup || isGer ? ' ' + getRoleBadge(r.role, r.isMaster) : '';
    return `<tr class="${isSup || isGer ? 'is-supervisor' : ''}">
      <td style="width:60px;"><span class="rank-pos ${medalClass}">${medalLabel}</span></td>
      <td><div class="rank-name">${escapeHtml(r.full_name)}${roleTag}</div>${r.email ? `<div class="rank-email">${escapeHtml(r.email)}</div>` : ''}</td>
      <td style="width:130px;">${getSectorBadge(r.sector)}</td>
      <td style="text-align:center; width:130px;"><span class="rank-cert-count">${r.certCount} aprovado${r.certCount === 1 ? '' : 's'}</span></td>
      <td style="text-align:center; width:110px;">${adherenceBadge(r.adherence)}</td>
      <td style="text-align:right; width:100px;"><span class="rank-points">${r.points} pts</span></td>
    </tr>`;
  }).join('');
  container.innerHTML = `<div class="ranking-table-wrapper"><table class="ranking-table"><thead><tr><th>#</th><th>Colaborador</th><th>Setor</th><th style="text-align:center;">Certificados</th><th style="text-align:center;">Aderência</th><th style="text-align:right;">Pontos</th></tr></thead><tbody>${rows}</tbody></table></div>`;
}
function applySectorFilter() { currentSectorFilter = document.getElementById('ranking-sector-filter').value; renderRankingTable(cachedRankingData); }
function renderSectorComparison(ranking) {
  const container = document.getElementById('sector-compare-container');
  const sectorData = {};
  SECTORS.forEach(s => { sectorData[s.key] = { total: 0, count: 0, topName: null, topPoints: 0 }; });
  const mySector = (isSupervisor || isGerente) ? normalizeSector(currentProfile?.sector) : null;
  ranking.forEach(r => {
    const key = r.sectorKey;
    if (!key || !sectorData[key]) return;
    if (r.role === 'supervisor' || r.role === 'gerente') { sectorData[key].count += 1; return; }
    sectorData[key].total += r.points;
    sectorData[key].count += 1;
    if (r.points > sectorData[key].topPoints) { sectorData[key].topPoints = r.points; sectorData[key].topName = r.full_name; }
  });
  const ordered = SECTORS.map(s => ({ ...s, total: sectorData[s.key].total, count: sectorData[s.key].count, avg: sectorData[s.key].count > 0 ? (sectorData[s.key].total / sectorData[s.key].count) : 0, topName: sectorData[s.key].topName, topPoints: sectorData[s.key].topPoints })).sort((a, b) => b.total - a.total);
  const maxTotal = Math.max(...ordered.map(s => s.total), 1);
  const rankLabels = ['1º', '2º', '3º'];
  const rankClasses = ['gold', 'silver', 'bronze'];
  const cards = ordered.map((s, idx) => {
    const rankLabel = rankLabels[idx] || `${idx + 1}º`;
    const rankClass = rankClasses[idx] || '';
    const barWidth = (maxTotal > 0) ? (s.total / maxTotal) * 100 : 0;
    const avgFormatted = s.avg.toFixed(1).replace('.', ',');
    const isMine = mySector && s.key === mySector;
    const topHtml = s.topName ? `<span class="top-medal">🥇</span><span class="top-name">${escapeHtml(s.topName)}</span><span class="top-points">${s.topPoints} pts</span>` : `<span>Sem pontuações</span>`;
    return `<div class="sector-compare-card ${s.cls} ${isMine ? 'mine' : ''}">
      <div class="sector-compare-header"><span class="sector-badge ${s.cls}">${s.label}</span><span class="sector-compare-rank ${rankClass}">${rankLabel}</span></div>
      <div class="sector-compare-total">${s.total}<span class="pts-suffix">pts</span></div>
      <div class="sector-compare-label">Total do setor</div>
      <div class="sector-compare-bar"><div class="sector-compare-bar-fill" style="width: ${barWidth}%"></div></div>
      <div class="sector-compare-stats"><div><span class="stat-label">Pessoas</span><span class="stat-value">${s.count}</span></div><div><span class="stat-label">Média</span><span class="stat-value">${avgFormatted}</span></div></div>
      <div class="sector-compare-top ${s.topName ? '' : 'empty'}">${topHtml}</div>
    </div>`;
  }).join('');
  container.innerHTML = `<div class="sector-compare-grid">${cards}</div>`;
}
function renderAdherence(ranking) {
  const container = document.getElementById('adherence-container');
  const totalDecided = ranking.reduce((s, r) => s + (r.approved + r.rejected), 0);
  const totalApproved = ranking.reduce((s, r) => s + r.approved, 0);
  const generalAdh = totalDecided > 0 ? Math.round((totalApproved / totalDecided) * 100) : null;
  const bySetor = {};
  SECTORS.forEach(s => { bySetor[s.key] = { approved: 0, rejected: 0 }; });
  ranking.forEach(r => {
    if (!r.sectorKey || !bySetor[r.sectorKey]) return;
    bySetor[r.sectorKey].approved += r.approved;
    bySetor[r.sectorKey].rejected += r.rejected;
  });
  const setorCards = SECTORS.map(s => {
    const d = bySetor[s.key];
    const dec = d.approved + d.rejected;
    const adh = dec > 0 ? Math.round((d.approved / dec) * 100) : null;
    const color = adh === null ? '#6D6E71' : adh >= 80 ? '#158A49' : adh >= 50 ? '#B35A00' : '#A00D24';
    const width = adh === null ? 0 : adh;
    return `<div class="adherence-card"><div class="ad-sector">${s.label}</div><div class="ad-value" style="color:${color};">${adh === null ? '—' : adh + '%'}</div><div class="ad-sub">${d.approved} aprov. / ${dec} aval.</div><div class="adherence-bar"><div class="adherence-bar-fill" style="width:${width}%; background:${color};"></div></div></div>`;
  }).join('');
  const genColor = generalAdh === null ? '#6D6E71' : generalAdh >= 80 ? '#158A49' : generalAdh >= 50 ? '#B35A00' : '#A00D24';
  container.innerHTML = `<div style="margin-bottom:18px; padding:16px; border-radius:12px; background:linear-gradient(135deg, #FFF9F3, #FFF3E6); border-left:4px solid #E87722;"><div style="font-size:0.72rem; text-transform:uppercase; letter-spacing:0.6px; color:#6D6E71; font-weight:700; margin-bottom:4px;">Aderência Geral</div><div style="font-size:2rem; font-weight:800; color:${genColor}; line-height:1;">${generalAdh === null ? '—' : generalAdh + '%'}</div><div style="font-size:0.78rem; color:#6D6E71; margin-top:4px;">${totalApproved} aprovados / ${totalDecided} avaliações</div></div><div class="adherence-grid">${setorCards}</div>`;
}

// ==================== PENDENTES / VALIDADOS ====================
async function loadPendingCertificates() {
  const { data: certs, error } = await db.from('certificates').select('*, profiles!certificates_user_id_fkey(full_name, sector, role, is_master), goals(title, deadline, max_points, goal_type)').eq('status', 'pending').order('submitted_at', { ascending: true });
  const list = document.getElementById('pending-certs-list');
  if (error) { list.innerHTML = `<p style="color:#C8102E;">Erro: ${error.message}</p>`; return; }
  if (!certs || certs.length === 0) { list.innerHTML = '<p style="color:#6D6E71;">Nenhum certificado pendente.</p>'; return; }
  
  let visible = certs;
  if ((isSupervisor || isGerente) && !canManageAll) {
    visible = certs.filter(c => normalizeSector(c.profiles?.sector) === normalizeSector(currentProfile.sector));
  }

  pendingCertsCache = {};
  for (let c of visible) {
    const { data } = await db.storage.from('certificates').createSignedUrl(c.file_url, 60 * 60);
    c.signedUrl = data?.signedUrl || '#';
    if (c.file_url_2) {
      const { data: d2 } = await db.storage.from('certificates').createSignedUrl(c.file_url_2, 60 * 60);
      c.signedUrl2 = d2?.signedUrl || '#';
    }
    pendingCertsCache[c.id] = c;
  }
  if (visible.length === 0) { list.innerHTML = '<p style="color:#6D6E71;">Nenhum pendente no seu escopo.</p>'; return; }

  list.innerHTML = visible.map(c => {
    const isSup = (c.profiles?.role || '').toLowerCase() === 'supervisor';
    const isGer = (c.profiles?.role || '').toLowerCase() === 'gerente';
    const roleTag = isSup || isGer ? ' ' + getRoleBadge(c.profiles.role, c.profiles.is_master) : '';
    
    // Se for apenas Supervisor (não for gerente nem admin), mostra apenas leitura
    const actionButtons = (isSupervisor && !isGerente && !canManageAll) 
      ? `<span class="badge pending" style="padding: 6px 12px;">👁️ Apenas Visualização</span>`
      : `<button class="small success" onclick="openApproveModal('${c.id}')">✅ Aprovar</button>
         <button class="small danger" onclick="validateCert('${c.id}', 'rejected')">❌ Rejeitar</button>`;

    return `<div class="cert-item">
      <div class="info">
        <div class="title">${escapeHtml(c.profiles?.full_name || 'Colaborador')}${roleTag} ${getSectorBadge(c.profiles?.sector)} — ${escapeHtml(c.goals?.title || 'Meta')}</div>
        <div class="meta">Enviado em ${formatDate(c.submitted_at)}</div>
        <div class="meta">
          <a href="${c.signedUrl}" target="_blank" style="color: #E87722; font-weight: bold; text-decoration: none;">📄 Ver ${escapeHtml(c.file_name || 'arquivo 1')}</a>
          ${c.signedUrl2 ? `<br><a href="${c.signedUrl2}" target="_blank" style="color: #E87722; font-weight: bold; text-decoration: none;">📄 Ver ${escapeHtml(c.file_name_2 || 'arquivo 2')}</a>` : ''}
        </div>
      </div>
      <div style="display:flex; gap:8px; align-items:center;">
        ${actionButtons}
      </div>
    </div>`;
  }).join('');
}

async function loadValidatedCertificates() {
  const { data: certs } = await db.from('certificates').select('*, profiles!certificates_user_id_fkey(full_name, sector, role, is_master), goals(title)').neq('status', 'pending').order('validated_at', { ascending: false }).limit(30);
  const list = document.getElementById('validated-certs-list');
  if (!certs || certs.length === 0) { list.innerHTML = '<p style="color:#6D6E71;">Nenhuma validação realizada.</p>'; return; }
  let visible = certs;
  if ((isSupervisor || isGerente) && !canManageAll) {
    visible = certs.filter(c => normalizeSector(c.profiles?.sector) === normalizeSector(currentProfile.sector));
  }
  if (visible.length === 0) { list.innerHTML = '<p style="color:#6D6E71;">Nenhuma no seu escopo.</p>'; return; }
  list.innerHTML = visible.map(c => {
    const isSup = (c.profiles?.role || '').toLowerCase() === 'supervisor';
    const isGer = (c.profiles?.role || '').toLowerCase() === 'gerente';
    const roleTag = isSup || isGer ? ' ' + getRoleBadge(c.profiles.role, c.profiles.is_master) : '';
    const dois = c.file_url_2 ? ' <span style="font-size:0.72rem; color:#6D6E71;">• 2 arquivos</span>' : '';
    return `<div class="cert-item">
      <div class="info">
        <div class="title">${escapeHtml(c.profiles?.full_name || '')}${roleTag} ${getSectorBadge(c.profiles?.sector)} — ${escapeHtml(c.goals?.title || '')}${dois}</div>
        <div class="meta">Validado em ${formatDate(c.validated_at)}</div>
      </div>
      <div>
        <span class="badge ${c.status}">${c.status === 'approved' ? 'Aprovado' : 'Rejeitado'}</span>
        ${c.status === 'approved' ? `<strong style="margin-left:8px; color:#158A49;">+${c.points_awarded} pts</strong>` : ''}
      </div>
    </div>`;
  }).join('');
}

// ==================== MODAL APROVAÇÃO ====================
function openApproveModal(certId) {
  if (isSupervisor && !isGerente && !canManageAll) return showMessage('Apenas Gerentes podem aprovar.', 'error');
  const cert = pendingCertsCache[certId];
  if (!cert) return showMessage('Certificado não encontrado.', 'error');
  pendingApproval = { certId };
  const maxPts = cert.goals?.max_points ?? 10;
  const sectorHtml = cert.profiles?.sector ? ` ${getSectorBadge(cert.profiles.sector)}` : '';
  document.getElementById('modal-info').innerHTML = `${escapeHtml(cert.profiles?.full_name || 'Colaborador')}${sectorHtml} — ${escapeHtml(cert.goals?.title || 'Meta')}`;
  const pointsInput = document.getElementById('modal-points');
  pointsInput.value = maxPts;
  pointsInput.max = maxPts;
  document.getElementById('modal-hint').textContent = `Nota máxima: ${maxPts} pontos (ajuste se necessário)`;
  document.getElementById('approve-modal').classList.remove('hidden');
  setTimeout(() => pointsInput.focus(), 60);
}
function closeApproveModal() { pendingApproval = null; document.getElementById('approve-modal').classList.add('hidden'); }
async function confirmApprove() {
  if (!pendingApproval) return;
  const pointsInput = document.getElementById('modal-points');
  const points = wholePoints(pointsInput.value);
  const maxPts = wholePoints(pointsInput.max);
  if (points === null) return showMessage('Informe uma pontuação válida.', 'error');
  if (maxPts !== null && points > maxPts) return showMessage(`Máximo: ${maxPts} pontos.`, 'error');
  const certId = pendingApproval.certId;
  closeApproveModal();
  await validateCert(certId, 'approved', points);
}
async function validateCert(certId, status, manualPoints = null) {
  if (isSupervisor && !isGerente && !canManageAll) return showMessage('Apenas Gerentes podem validar.', 'error');
  const { data: cert } = await db.from('certificates').select('*, goals(max_points, deadline)').eq('id', certId).single();
  if (!cert) return showMessage('Certificado não encontrado.', 'error');
  let points = 0;
  if (status === 'approved') {
    const maxPts = cert.goals?.max_points ?? 10;
    points = (manualPoints !== null && manualPoints !== undefined && !isNaN(manualPoints)) ? manualPoints : maxPts;
  }
  const { error } = await db.from('certificates').update({ status, validated_at: new Date().toISOString(), validated_by: currentUser.id, points_awarded: points }).eq('id', certId);
  if (error) return showMessage('Erro ao validar: ' + error.message, 'error');
  showMessage(status === 'approved' ? `Aprovado com ${points} ponto(s)!` : 'Rejeitado!', 'success');
  loadSectorComparisonAndRanking();
  loadPendingCertificates();
  loadValidatedCertificates();
}

// ==================== AVATAR DE PERFIL ====================
function openAvatarModal() {
  if (!currentUser || !currentProfile) return;

  selectedAvatarFile = null;
  document.getElementById('avatar-file-input').value = '';
  document.getElementById('avatar-file-name').textContent = '';
  document.getElementById('avatar-save-btn').disabled = true;

  const preview = document.getElementById('avatar-preview');
  if (currentProfile.avatar_url) {
    preview.style.backgroundImage = `url('${currentProfile.avatar_url}')`;
    preview.textContent = '';
  } else {
    preview.style.backgroundImage = '';
    preview.textContent = initials(currentProfile.full_name || currentUser.email);
  }

  document.getElementById('avatar-modal').classList.remove('hidden');
}

function closeAvatarModal() {
  document.getElementById('avatar-modal').classList.add('hidden');
  selectedAvatarFile = null;
}

function onAvatarFileSelected(event) {
  const file = event.target.files[0];
  if (!file) return;

  if (file.size > 5 * 1024 * 1024) {
    showMessage('Imagem muito grande. Máximo 5MB.', 'error');
    event.target.value = '';
    return;
  }

  const validTypes = ['image/png', 'image/jpeg', 'image/jpg', 'image/webp'];
  if (!validTypes.includes(file.type)) {
    showMessage('Formato inválido. Use JPG, PNG ou WEBP.', 'error');
    event.target.value = '';
    return;
  }

  selectedAvatarFile = file;
  document.getElementById('avatar-file-name').textContent = '✓ ' + file.name;
  document.getElementById('avatar-save-btn').disabled = false;

  const reader = new FileReader();
  reader.onload = (e) => {
    const preview = document.getElementById('avatar-preview');
    preview.style.backgroundImage = `url('${e.target.result}')`;
    preview.textContent = '';
  };
  reader.readAsDataURL(file);
}

async function saveAvatar() {
  if (!selectedAvatarFile) return;

  const btn = document.getElementById('avatar-save-btn');
  btn.disabled = true;
  btn.textContent = 'Enviando…';

  try {
    const ext = selectedAvatarFile.name.split('.').pop().toLowerCase();
    const filePath = `${currentUser.id}/avatar.${ext}`;

    const { error: upErr } = await db.storage
      .from('avatars')
      .upload(filePath, selectedAvatarFile, {
        upsert: true,
        contentType: selectedAvatarFile.type,
        cacheControl: '3600'
      });

    if (upErr) throw upErr;

    const { data: pub } = db.storage.from('avatars').getPublicUrl(filePath);
    const publicUrl = pub.publicUrl + '?t=' + Date.now();

    const { error: dbErr } = await db
      .from('profiles')
      .update({ avatar_url: publicUrl })
      .eq('id', currentUser.id);

    if (dbErr) throw dbErr;

    currentProfile.avatar_url = publicUrl;
    applyAvatarToUI(currentProfile.full_name || currentUser.email, publicUrl);

    showMessage('Foto atualizada! ✅', 'success');
    closeAvatarModal();

  } catch (e) {
    console.error('Erro ao salvar avatar:', e);
    showMessage('Erro: ' + (e.message || 'falha no upload'), 'error');
    btn.disabled = false;
    btn.textContent = 'Salvar Foto';
  }
}

function applyAvatarToUI(name, url) {
  const ini = initials(name);
  const avatars = ['emp-avatar', 'mgmt-avatar'];

  avatars.forEach(id => {
    const el = document.getElementById(id);
    if (!el) return;
    if (url) {
      el.style.backgroundImage = `url('${url}')`;
      el.textContent = '';
    } else {
      el.style.backgroundImage = '';
      el.textContent = ini;
    }
  });
}

// ==================== INIT ====================
updateAcademyFabVisibility();
document.getElementById('login-password').addEventListener('keydown', event => {
  if (event.key === 'Enter') { event.preventDefault(); login(); }
});
db.auth.onAuthStateChange((event, session) => {
  if (event === 'SIGNED_IN' && session) setTimeout(() => { loadUser(); }, 0);
  if (event === 'SIGNED_OUT') showLoginView();
});
loadUser();

window.cdePdiReady = true;

function iniciarSecoesRecolhiveis() {
  const ids = [
    'create-goal-form',       // Criar Nova Meta
    'all-goals-list',         // Metas definidas
    'ranking-container',      // Ranking de Pontuação
    'validated-certs-list',   // Histórico de Validações
    'mgmt-certs-list'         // Meus Certificados/Resultados
  ];

  ids.forEach(id => {
    const card = document.getElementById(id)?.closest('.card');

    if (!card || card.dataset.recolhivel === 'true') return;

    const titulo = card.querySelector(':scope > h2');
    if (!titulo) return;

    const secao = document.createElement('details');
    secao.className = 'pdi-section';
    secao.open = false; // Começa recolhida

    const cabecalho = document.createElement('summary');
    cabecalho.className = 'pdi-section-title';
    cabecalho.append(titulo);

    const conteudo = document.createElement('div');
    conteudo.className = 'pdi-section-body';

    // Move os elementos existentes, preservando IDs e eventos.
    while (card.firstChild) {
      conteudo.append(card.firstChild);
    }

    secao.append(cabecalho, conteudo);
    card.append(secao);

    card.classList.add('pdi-collapsible');
    card.dataset.recolhivel = 'true';
  });
}

if (document.readyState === 'loading') {
  document.addEventListener(
    'DOMContentLoaded',
    iniciarSecoesRecolhiveis,
    { once: true }
  );
} else {
  iniciarSecoesRecolhiveis();
}

function padronizarIconesCDE() {
  const desenhos = {
    grafico:
      '<path d="M4 4v16h16M8 15v-4m5 4V7m5 8v-6"/>',

    alvo:
      '<circle cx="12" cy="12" r="9"/>' +
      '<circle cx="12" cy="12" r="5"/>' +
      '<circle cx="12" cy="12" r="1"/>',

    pessoa:
      '<circle cx="12" cy="8" r="4"/>' +
      '<path d="M4 21v-2a8 8 0 0 1 16 0v2"/>',

    trofeu:
      '<path d="M8 3h8v5a4 4 0 0 1-8 0V3Z' +
      'm0 2H4v2a4 4 0 0 0 4 4' +
      'm8-6h4v2a4 4 0 0 1-4 4' +
      'm-4 1v6m-4 3h8m-6-3h4v3"/>',

    busca:
      '<circle cx="10.5" cy="10.5" r="6.5"/>' +
      '<path d="m16 16 5 5"/>',

    aprovado:
      '<circle cx="12" cy="12" r="9"/>' +
      '<path d="m8 12 3 3 5-6"/>',

    adicionar:
      '<path d="M12 4v16M4 12h16"/>',

    metas:
      '<rect x="5" y="4" width="14" height="17" rx="2"/>' +
      '<path d="M9 4V2h6v2M9 10h6m-6 5h6"/>',

    anexo:
      '<path d="m8 13 6-6a3 3 0 0 1 4 4' +
      'l-8 8a5 5 0 0 1-7-7l8-8"/>'
  };

  const mapa = {
    '📊': 'grafico',
    '🎯': 'alvo',
    '👤': 'pessoa',
    '🏆': 'trofeu',
    '🔍': 'busca',
    '✅': 'aprovado',
    '➕': 'adicionar',
    '📋': 'metas',
    '📎': 'anexo',
    '📜': 'aprovado'
  };

  document.querySelectorAll('.tab-btn, .card h2').forEach(elemento => {
    // Evita inserir o mesmo ícone duas vezes.
    if (elemento.querySelector('.cde-icon')) return;

    const texto = Array.from(elemento.childNodes).find(
      node => node.nodeType === 3 && node.textContent.trim()
    );

    if (!texto) return;

    const conteudo = texto.textContent.trimStart();
    const emoji = Object.keys(mapa).find(
      item => conteudo.startsWith(item)
    );

    if (!emoji) return;

    const svg = document.createElementNS(
      'http://www.w3.org/2000/svg',
      'svg'
    );

    svg.setAttribute('class', 'cde-icon');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('aria-hidden', 'true');
    svg.setAttribute('focusable', 'false');

    // Desenhos fixos; não utiliza conteúdo do usuário.
    svg.innerHTML = desenhos[mapa[emoji]];

    texto.textContent = conteudo
      .slice(emoji.length)
      .replace(/^[\uFE0F\s]+/, '');

    elemento.insertBefore(svg, texto);
  });
}

if (document.readyState === 'loading') {
  document.addEventListener(
    'DOMContentLoaded',
    padronizarIconesCDE,
    { once: true }
  );
} else {
  padronizarIconesCDE();
}