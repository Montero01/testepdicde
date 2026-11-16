// Carrega a mesma versão original do SDK e só inicia o PDI quando ela está disponível.
(async () => {
  const button = document.getElementById('login-submit');
  const sources = [
    'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.min.js',
    'https://unpkg.com/@supabase/supabase-js@2.45.4/dist/umd/supabase.js'
  ];
  function loadScript(src) {
    return new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = src;
      script.async = true;
      let settled = false;
      const finish = error => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        script.onload = script.onerror = null;
        if (error) { script.remove(); reject(error); } else resolve();
      };
      const timeout = setTimeout(() => finish(new Error('Tempo de carregamento excedido.')), 15000);
      script.onload = () => finish();
      script.onerror = () => finish(new Error('Falha ao carregar o arquivo.'));
      document.head.append(script);
    });
  }
  try {
    let loaded = Boolean(window.supabase?.createClient);
    for (const source of sources) {
      if (loaded) break;
      try { await loadScript(source); loaded = Boolean(window.supabase?.createClient); } catch { /* Próximo CDN. */ }
    }
    if (!loaded) throw new Error('Leitor de autenticação indisponível.');
    await loadScript('app.js');
    if (!window.cdePdiReady) throw new Error('Inicialização do aplicativo incompleta.');
    if (button) button.disabled = false;
  } catch (error) {
    if (button) button.disabled = true;
    const box = document.getElementById('message-box');
    if (box) {
      const message = document.createElement('div');
      message.className = 'msg error';
      message.textContent = 'Não foi possível carregar o PDI. Verifique sua conexão e atualize a página.';
      box.replaceChildren(message);
    }
  }
})();
