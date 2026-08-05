const el = (id) => document.getElementById(id);
const ui = {
  list: el('post-list'), editor: el('editor'), empty: el('empty'),
  title: el('title'), content: el('content'), preview: el('preview'),
  words: el('word-count'), save: el('save-state'),
  readingTime: el('reading-time'),
  targetWords: el('target-words'),
  goalProgress: el('goal-progress'),
  goalContainer: el('goal-container'),
  panes: el('panes'),
  modeButtons: Array.from(document.querySelectorAll('.mode-btn')),
  publishBtn: el('publish'),
  deleteBtn: el('delete'), newBtn: el('new-post'),
  totalPosts: el('total-posts'), totalWords: el('total-words'),
  shortcutsToggle: el('shortcuts-toggle'),
  shortcutsModal: el('shortcuts-modal'),
  modalClose: el('modal-close'),
  focusBtn: el('focus-toggle'),
  fontIncreaseBtn: el('font-increase'),
  fontDecreaseBtn: el('font-decrease'),
  searchInput: el('search-input'),
  searchClear: el('search-clear'),
  searchCount: el('search-count'),
};

const drawer = {
  open: false,
  toggle: el('posts-toggle'),
  closeBtn: el('drawer-close'),
  scrim: el('scrim'),
  search: el('search-input'),
};

const menu = {
  open: false,
  toggle: el('menu-toggle'),
  panel: el('menu-panel'),
};

let posts = [];        // sidebar summaries, newest first
let current = null;    // full post being edited
let saveTimer = null;
let pendingSave = null;
let focusMode = false;
let fontSize = 19;

async function api(method, path, body) {
  const res = await fetch(path, {
    method,
    headers: body === undefined ? undefined : { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`${method} ${path} failed: ${res.status}`);
  return res.status === 204 ? null : res.json();
}

// --- markdown -------------------------------------------------------------

function escapeHtml(s) {
  return s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}

function inline(s) {
  const spans = [];
  s = s.replace(/`([^`]+)`/g, (_, code) => `\u0000${spans.push(code) - 1}\u0000`);
  s = s
    .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (m, text, href) =>
      /^(https?:|mailto:|[/#])/i.test(href) ? `<a href="${href}" target="_blank" rel="noopener">${text}</a>` : m)
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/\*([^*]+)\*/g, '<em>$1</em>');
  return s.replace(/\u0000(\d+)\u0000/g, (_, i) => `<code>${spans[i]}</code>`);
}

function renderMarkdown(src) {
  const lines = escapeHtml(src).split('\n');
  const isBreak = (l) => !l.trim() || /^```/.test(l) || /^#{1,3}\s/.test(l) || /^\s*[-*]\s+/.test(l);
  const out = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (/^```/.test(line)) {
      const buf = [];
      for (i++; i < lines.length && !/^```/.test(lines[i]); i++) buf.push(lines[i]);
      i++; // closing fence
      out.push(`<pre><code>${buf.join('\n')}</code></pre>`);
    } else if (/^(#{1,3})\s+(.*)$/.test(line)) {
      const [, hashes, text] = line.match(/^(#{1,3})\s+(.*)$/);
      out.push(`<h${hashes.length}>${inline(text)}</h${hashes.length}>`);
      i++;
    } else if (/^\s*[-*]\s+/.test(line)) {
      const items = [];
      while (i < lines.length && /^\s*[-*]\s+/.test(lines[i])) {
        items.push(`<li>${inline(lines[i].replace(/^\s*[-*]\s+/, ''))}</li>`);
        i++;
      }
      out.push(`<ul>${items.join('')}</ul>`);
    } else if (!line.trim()) {
      i++;
    } else {
      const para = [];
      while (i < lines.length && !isBreak(lines[i])) para.push(lines[i++]);
      out.push(`<p>${inline(para.join('\n'))}</p>`);
    }
  }
  return out.join('\n');
}

// --- view mode (pure) -----------------------------------------------------

const VIEW_MODES = ['edit', 'split', 'preview'];

function normalizeViewMode(mode) {
  return VIEW_MODES.includes(mode) ? mode : VIEW_MODES[0];
}

function nextViewMode(mode) {
  const i = VIEW_MODES.indexOf(normalizeViewMode(mode));
  return VIEW_MODES[(i + 1) % VIEW_MODES.length];
}

function viewModeShowsPreview(mode) {
  return normalizeViewMode(mode) !== 'edit';
}

// --- view mode (dom) ------------------------------------------------------

let viewMode = 'edit';

function refreshPreview() {
  if (!viewModeShowsPreview(viewMode)) return;
  ui.preview.innerHTML = renderMarkdown(ui.content.value);
}

function setViewMode(mode) {
  viewMode = normalizeViewMode(mode);
  document.body.dataset.viewMode = viewMode;
  for (const btn of document.querySelectorAll('.mode-btn')) {
    const on = btn.dataset.mode === viewMode;
    btn.classList.toggle('active', on);
    btn.setAttribute('aria-pressed', String(on));
  }
  refreshPreview();
}

function cycleViewMode() {
  setViewMode(nextViewMode(viewMode));
}

// --- formatting -----------------------------------------------------------

function toMillis(ts) {
  if (typeof ts === 'number') return ts < 1e12 ? ts * 1000 : ts;
  if (typeof ts !== 'string') return NaN;
  // SQLite CURRENT_TIMESTAMP ("2026-07-28 10:36:00") is UTC but not ISO-parseable everywhere.
  const sqlite = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(ts) ? ts.replace(' ', 'T') + 'Z' : ts;
  return Date.parse(sqlite);
}

function relTime(ts) {
  const ms = toMillis(ts);
  if (Number.isNaN(ms)) return '';
  const secs = Math.max(0, (Date.now() - ms) / 1000);
  if (secs < 60) return 'just now';
  if (secs < 3600) return `${Math.floor(secs / 60)}m ago`;
  if (secs < 86400) return `${Math.floor(secs / 3600)}h ago`;
  if (secs < 604800) return `${Math.floor(secs / 86400)}d ago`;
  return new Date(ms).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

const countWords = (text) => (text.trim() ? text.trim().split(/\s+/).length : 0);

function calcReadingTime(wordCount) {
  if (!wordCount || wordCount <= 0) return '0 min read';
  const mins = Math.max(1, Math.ceil(wordCount / 200));
  return `${mins} min read`;
}

// --- rendering ------------------------------------------------------------

function renderList() {
  ui.list.replaceChildren(...posts.map((p) => {
    const item = document.createElement('button');
    item.type = 'button';
    item.className = 'post-item' + (current && p.id === current.id ? ' active' : '');
    item.dataset.id = p.id;

    const dot = document.createElement('span');
    dot.className = 'dot ' + (p.status === 'published' ? 'published' : 'draft');
    dot.title = p.status;

    const title = document.createElement('span');
    title.className = 'post-title';
    title.textContent = p.title || 'Untitled';

    const when = document.createElement('span');
    when.className = 'post-time';
    when.textContent = relTime(p.updated_at);

    item.append(dot, title, when);
    item.addEventListener('click', () => {
      selectPost(p.id);
      closeDrawer();
    });
    return item;
  }));
  ui.empty.hidden = posts.length > 0;
  if (posts.length === 0 && ui.searchInput && ui.searchInput.value.trim()) {
    ui.empty.textContent = 'No matching posts.';
  } else if (posts.length === 0) {
    ui.empty.textContent = 'No posts yet.';
  }
  updateTotals();
}

function renderEditor() {
  ui.editor.hidden = !current;
  if (!current) return;
  ui.title.value = current.title || '';
  ui.content.value = current.content || '';
  if (ui.targetWords) {
    ui.targetWords.value = current.target_word_count || '';
  }
  ui.publishBtn.textContent = current.status === 'published' ? 'unpublish' : 'publish';
  ui.publishBtn.classList.toggle('is-published', current.status === 'published');
  updateWordCount();
  refreshPreview();
}

function updateWordCount() {
  const n = countWords(ui.content.value);
  ui.words.textContent = `${n} ${n === 1 ? 'word' : 'words'}`;
  if (ui.readingTime) {
    ui.readingTime.textContent = calcReadingTime(n);
  }
  const target = parseInt(ui.targetWords?.value, 10) || 0;
  if (target > 0) {
    const pct = Math.round((n / target) * 100);
    if (ui.goalProgress) {
      ui.goalProgress.textContent = `${pct}%`;
      ui.goalProgress.title = `${n} / ${target} words`;
    }
    ui.goalContainer?.classList.toggle('goal-met', n >= target);
  } else {
    if (ui.goalProgress) {
      ui.goalProgress.textContent = '';
      ui.goalProgress.title = '';
    }
    ui.goalContainer?.classList.remove('goal-met');
  }
  updateTotals();
}

function updateTotals() {
  const count = posts.length;
  let totalWords = 0;
  for (const p of posts) {
    if (current && p.id === current.id) {
      totalWords += countWords(ui.content.value);
    } else {
      totalWords += p.word_count || 0;
    }
  }
  ui.totalPosts.textContent = `${count} ${count === 1 ? 'post' : 'posts'}`;
  ui.totalWords.textContent = `${totalWords} ${totalWords === 1 ? 'word' : 'words'}`;
}

function setSaveState(state) {
  ui.save.textContent = state;
  ui.save.classList.toggle('busy', state !== 'saved');
}

// --- data flow ------------------------------------------------------------

function mergeSummary(post) {
  const summary = {
    id: post.id, title: post.title, status: post.status,
    updated_at: post.updated_at, word_count: countWords(post.content || ''),
    target_word_count: post.target_word_count ?? 0,
  };
  posts = [summary, ...posts.filter((p) => p.id !== post.id)]
    .sort((a, b) => (toMillis(b.updated_at) || 0) - (toMillis(a.updated_at) || 0));
  renderList();
}

async function save() {
  if (!current) return;
  clearTimeout(saveTimer);
  saveTimer = null;
  setSaveState('saving…');
  const targetVal = ui.targetWords ? parseInt(ui.targetWords.value, 10) : 0;
  const target_word_count = Number.isInteger(targetVal) && targetVal >= 0 ? targetVal : 0;
  pendingSave = api('PUT', `/api/posts/${current.id}`, {
    title: ui.title.value,
    content: ui.content.value,
    target_word_count,
  })
    .then((post) => {
      if (current && current.id === post.id) current = post;
      mergeSummary(post);
      setSaveState('saved');
    })
    .catch((err) => {
      console.warn(err);
      setSaveState('save failed');
    })
    .finally(() => { pendingSave = null; });
  return pendingSave;
}

function scheduleSave() {
  setSaveState('saving…');
  clearTimeout(saveTimer);
  saveTimer = setTimeout(save, 800);
}

async function flushSave() {
  if (saveTimer) await save();
  if (pendingSave) await pendingSave;
}

async function selectPost(id) {
  if (current && current.id === id) return;
  await flushSave();
  current = await api('GET', `/api/posts/${id}`);
  setSaveState('saved');
  renderEditor();
  renderList();
}

function toggleShortcutsModal(show) {
  if (typeof show === 'boolean') {
    ui.shortcutsModal.hidden = !show;
  } else {
    ui.shortcutsModal.hidden = !ui.shortcutsModal.hidden;
  }
}

function toggleFocusMode(on) {
  focusMode = typeof on === 'boolean' ? on : !focusMode;
  document.body.classList.toggle('focus-mode', focusMode);
  ui.focusBtn?.classList.toggle('active', focusMode);
}

// --- shell: posts drawer & editor menu ------------------------------------

function openDrawer() {
  drawer.open = true;
  document.body.classList.add('drawer-open');
  document.body.classList.remove('menu-open');
  menu.open = false;
  drawer.toggle?.setAttribute('aria-expanded', 'true');
  if (drawer.search) drawer.search.focus();
}

function closeDrawer() {
  if (!drawer.open) return;
  drawer.open = false;
  document.body.classList.remove('drawer-open');
  drawer.toggle?.setAttribute('aria-expanded', 'false');
  drawer.toggle?.focus();
}

function toggleDrawer() {
  if (drawer.open) closeDrawer();
  else openDrawer();
}

function toggleMenu(show) {
  const next = typeof show === 'boolean' ? show : !menu.open;
  if (next) {
    // only one visitor at a time: pull the drawer away without stealing focus
    drawer.open = false;
    document.body.classList.remove('drawer-open');
    drawer.toggle?.setAttribute('aria-expanded', 'false');
  }
  menu.open = next;
  document.body.classList.toggle('menu-open', next);
  menu.toggle?.setAttribute('aria-expanded', String(next));
  if (!next) menu.toggle?.focus();
}

function setFontSize(size) {
  fontSize = Math.min(48, Math.max(12, size));
  if (ui.content) ui.content.style.fontSize = `${fontSize}px`;
  if (ui.preview) ui.preview.style.fontSize = `${fontSize}px`;
  if (ui.title) ui.title.style.fontSize = `${fontSize + 12}px`;
  document.documentElement.style.setProperty('--content-fs', String(fontSize));
  try { localStorage.setItem('inkwell-fontsize', String(fontSize)); } catch { /* private mode */ }
}

// --- search ---------------------------------------------------------------

let currentSearchQuery = '';

async function performSearch(query) {
  const trimmed = (query || '').trim();
  currentSearchQuery = trimmed;
  if (trimmed) {
    if (ui.searchClear) ui.searchClear.hidden = false;
    const res = await api('GET', `/api/posts?q=${encodeURIComponent(trimmed)}`);
    if (currentSearchQuery !== trimmed) return;
    posts = res;
    if (ui.searchCount) {
      ui.searchCount.hidden = false;
      const count = posts.length;
      ui.searchCount.textContent = `${count} ${count === 1 ? 'match' : 'matches'}`;
    }
  } else {
    if (ui.searchClear) ui.searchClear.hidden = true;
    if (ui.searchCount) ui.searchCount.hidden = true;
    const res = await api('GET', '/api/posts');
    if (currentSearchQuery !== '') return;
    posts = res;
  }
  renderList();
}

drawer.toggle?.addEventListener('click', toggleDrawer);
drawer.closeBtn?.addEventListener('click', closeDrawer);
drawer.scrim?.addEventListener('click', closeDrawer);
menu.toggle?.addEventListener('click', () => toggleMenu());

document.addEventListener('click', (e) => {
  if (menu.open && menu.panel && !menu.panel.contains(e.target) && e.target !== menu.toggle) {
    toggleMenu(false);
  }
});

ui.searchInput?.addEventListener('input', (e) => performSearch(e.target.value));
ui.searchInput?.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && ui.searchInput.value) {
    e.preventDefault();
    e.stopPropagation();
    ui.searchInput.value = '';
    performSearch('');
  }
});
ui.searchClear?.addEventListener('click', () => {
  if (ui.searchInput) {
    ui.searchInput.value = '';
    performSearch('');
    ui.searchInput.focus();
  }
});

// --- events ---------------------------------------------------------------

ui.newBtn.addEventListener('click', async () => {
  await flushSave();
  const post = await api('POST', '/api/posts', { title: '', content: '' });
  current = post;
  mergeSummary(post);
  setSaveState('saved');
  renderEditor();
  renderList();
  closeDrawer();
  ui.title.focus();
});

ui.title.addEventListener('input', scheduleSave);
ui.content.addEventListener('input', () => {
  updateWordCount();
  refreshPreview(); // live preview — no-op in edit mode
  scheduleSave();
});
ui.targetWords?.addEventListener('input', () => {
  if (current) {
    current.target_word_count = parseInt(ui.targetWords.value, 10) || 0;
    updateWordCount();
    scheduleSave();
  }
});

for (const btn of document.querySelectorAll('.mode-btn')) {
  btn.addEventListener('click', () => setViewMode(btn.dataset.mode));
}

ui.publishBtn.addEventListener('click', async () => {
  if (!current) return;
  await flushSave();
  current = await api('POST', `/api/posts/${current.id}/publish`);
  mergeSummary(current);
  renderEditor();
  toggleMenu(false);
});

ui.deleteBtn.addEventListener('click', async () => {
  if (!current || !confirm(`Delete “${current.title || 'Untitled'}”?`)) return;
  clearTimeout(saveTimer);
  saveTimer = null;
  const index = posts.findIndex((p) => p.id === current.id);
  await api('DELETE', `/api/posts/${current.id}`);
  posts = posts.filter((p) => p.id !== current.id);
  current = null;
  const next = posts[index] || posts[posts.length - 1];
  if (next) await selectPost(next.id);
  else {
    renderEditor();
    renderList();
  }
  toggleMenu(false);
});

ui.shortcutsToggle?.addEventListener('click', () => toggleShortcutsModal(true));
ui.modalClose?.addEventListener('click', () => toggleShortcutsModal(false));
ui.shortcutsModal?.addEventListener('click', (e) => {
  if (e.target === ui.shortcutsModal) toggleShortcutsModal(false);
});

ui.focusBtn?.addEventListener('click', () => toggleFocusMode());
ui.fontIncreaseBtn?.addEventListener('click', () => setFontSize(fontSize + 2));
ui.fontDecreaseBtn?.addEventListener('click', () => setFontSize(fontSize - 2));

document.addEventListener('keydown', (e) => {
  const isInput = ['INPUT', 'TEXTAREA'].includes(e.target?.tagName);
  if ((e.metaKey || e.ctrlKey) && e.shiftKey && e.key.toLowerCase() === 'f') {
    e.preventDefault();
    toggleFocusMode();
  } else if ((e.metaKey || e.ctrlKey) && (e.key === '=' || e.key === '+')) {
    e.preventDefault();
    setFontSize(fontSize + 2);
  } else if ((e.metaKey || e.ctrlKey) && (e.key === '-' || e.key === '_')) {
    e.preventDefault();
    setFontSize(fontSize - 2);
  } else if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'n') {
    e.preventDefault();
    ui.newBtn.click();
  } else if ((e.metaKey || e.ctrlKey) && e.key === 's') {
    e.preventDefault();
    save();
  } else if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
    e.preventDefault();
    if (current) cycleViewMode();
  } else if ((e.key === '?' && !isInput) || ((e.metaKey || e.ctrlKey) && e.key === '/')) {
    e.preventDefault();
    toggleShortcutsModal();
  } else if (e.key === 'Escape') {
    if (!ui.shortcutsModal.hidden) {
      e.preventDefault();
      toggleShortcutsModal(false);
    } else if (menu.open) {
      e.preventDefault();
      toggleMenu(false);
    } else if (drawer.open) {
      e.preventDefault();
      closeDrawer();
    } else if (focusMode) {
      e.preventDefault();
      toggleFocusMode(false);
    }
  }
});

window.addEventListener('beforeunload', () => {
  if (saveTimer) save();
});

// --- theme ----------------------------------------------------------------

const THEME_KEY = 'inkwell-theme';
const themeBtn = el('theme-toggle');

function availableThemes() {
  const raw = getComputedStyle(document.documentElement).getPropertyValue('--themes');
  const names = raw.trim().split(/\s+/).filter(Boolean);
  return names.length ? names : ['dark'];
}

function currentTheme(themes) {
  const t = document.documentElement.getAttribute('data-theme');
  return t && themes.includes(t) ? t : themes[0];
}

function applyTheme(name, themes) {
  if (name === themes[0]) {
    document.documentElement.removeAttribute('data-theme');
  } else {
    document.documentElement.setAttribute('data-theme', name);
  }
  localStorage.setItem(THEME_KEY, name);
  if (themeBtn) {
    const next = themes[(themes.indexOf(name) + 1) % themes.length];
    themeBtn.textContent = next;
    themeBtn.title = `Switch to ${next} theme`;
  }
}

(function initTheme() {
  const themes = availableThemes();
  const stored = localStorage.getItem(THEME_KEY);
  const startTheme = stored && themes.includes(stored) ? stored : themes[0];
  applyTheme(startTheme, themes);
  themeBtn?.addEventListener('click', () => {
    const cur = currentTheme(themes);
    const next = themes[(themes.indexOf(cur) + 1) % themes.length];
    applyTheme(next, themes);
  });
})();

// --- boot -----------------------------------------------------------------

async function start() {
  setViewMode('edit');
  const savedSize = Number(localStorage.getItem('inkwell-fontsize'));
  if (savedSize >= 12 && savedSize <= 48) setFontSize(savedSize);
  posts = await api('GET', '/api/posts');
  if (!posts.length) {
    const post = await api('POST', '/api/posts', { title: '', content: '' });
    current = post;
    mergeSummary(post);
    renderEditor();
  } else {
    await selectPost(posts[0].id);
  }
  renderList();
}

start().catch((err) => {
  console.error(err);
  ui.empty.hidden = false;
  ui.empty.textContent = 'Could not reach the server.';
});
