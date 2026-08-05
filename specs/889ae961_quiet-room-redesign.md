# Plan: Inkwell quiet-room redesign

## Goal

Turn Inkwell into a quiet room: the default state is the writing state — one beautiful column of
text on a calm, cleared surface — and everything else (posts list, search, theme, view modes,
focus, font size, word goals, reading time, publish, delete, shortcuts) is a visitor that appears
on intent inside a small number of unobtrusive menus and leaves afterward.

No features are removed, no features are added, no dependencies, same stack (Bun server, vanilla
JS, single stylesheet). All existing behavior and keyboard shortcuts keep working. The existing
test suite (`bun test apps/inkwell/server.test.ts`, 30 tests) stays green, unmodified.

## Files to touch

Only these three — everything else (including `server.ts` and `server.test.ts`) is untouched:

1. `apps/inkwell/public/index.html` — restructure chrome into a topbar, drawer, and popover menu.
2. `apps/inkwell/public/style.css` — new visual language, surfaces, transitions.
3. `apps/inkwell/public/app.js` — shell state (drawer/menu open-close, Esc, persistence).

`server.ts` stays byte-for-byte identical; all `/api` behavior and the 30 tests are untouched.

## The design

### Surfaces (what the writer sees)

```
┌────────────────────────────────────────────────────────┐
│  ◈ inkwell    [Posts ▾]                    [⋯]         │  ← .topbar (quiet, minimal)
│                                                        │
│                                                        │
│                  Untitled                               │  ← #title  (part of the draft)
│                                                        │
│     one beautiful column of text. the writer's         │  ← #content / #preview
│     words are the interface; the app recedes.          │
│     62–74ch measure, serif, generous line height       │
│                                                        │
│                                         1,204 words   saved │  ← .footer (whisper: words · save)
└────────────────────────────────────────────────────────┘
```

- **Default state = writing state.** On load, no sidebar, no menus. The most recent draft is open
  (same data flow as today) and the only visible chrome is a hairline top row and a whisper of a
  footer. The user lands in the text.
- **Topbar (persistent but quiet).** One thin row, no background, no border, padded. Left: inline
  brand mark (reuse the existing `brand-icon` SVG, small) plus a text-labeled "Posts" button
  (`#posts-toggle`). Right: a single "⋯" button (`#menu-toggle`, `aria-haspopup`, `aria-expanded`).
  In focus mode the topbar fades to near-invisible (hover restores).
- **Posts drawer (the library).** The existing `.sidebar` *becomes* a left slide-in drawer:
  `position: fixed; left:0; top:0; bottom:0; width: 300px; transform: translateX(-100%)` by
  default; opening adds `body.drawer-open` -> `translateX(0)` with a 260ms ease-out. A `.scrim`
  (fixed full-screen overlay, faded in) covers the editor; clicking it or pressing Esc closes the
  drawer. Drawer content is today's sidebar content, in today's order (see frozen contract).
- **Editor menu (the toolkit).** A small popover card anchored under `#menu-toggle`
  (`.menu-panel`, `position:absolute; right:0; top:calc(100% + 8px)` inside a `position:relative`
  wrapper). Hidden by default (`opacity:0; visibility:hidden; transform:translateY(4px)`), shown
  by `body.menu-open` with a 160ms fade/rise. Everything a writer might want *while writing* lives
  here: view modes, focus, font size, theme, goal, reading time, shortcuts, publish, delete.
- **Footer (whisper).** One quiet centered line under the column: `#word-count` and
  `#save-state`, tiny and dim — readouts that help the next sentence. No buttons. Reading time and
  the goal live in the menu. Focus mode fades the footer further (rule stays, behavior matches).

### Visual language

- **Calm neutral surfaces.** Warm paper in light (`--bg: #f7f5f1`-family), soft ink in dark
  (keep the current near-black neutrals, shift slightly warmer). Surfaces are differentiated by
  tone, not by borders. Hairlines only where two live surfaces meet (panes divider, drawer edge).
- **The draft is set, not styled.** Editor column: `max-width: 760px, margin: 0 auto`,
  horizontal padding ~48px. Base serif 19px, `line-height: 1.85`, `letter-spacing: 0.01em`,
  `text-rendering: optimizeLegibility`. Title 34px/1.3. Generous top padding (title gets ~80px
  of sky). Placeholder text is faint, not gray-on-gray.
- **Type scale.** Font size range widens: clamp 12–48px (today 12–36). Steps stay ±2px. The
  chosen size persists in `localStorage` (`inkwell-fontsize`). `#title` follows at +12px, and
  line-height scales gently with size (`calc(1.65 + 0.004 * size)`).
- **Quiet controls.** Topbar and menu buttons are borderless text/icon buttons until hover;
  hover is a subtle surface tint, never a flash. Danger (delete) only acquires its red on hover.
- **Transitions.** One consistent curve (`cubic-bezier(.32,.72,.25,1)`), short durations (150–
  260ms); drawer 260ms, scrim 200ms, popover 160ms, focus fade 160ms. Nothing animates while
  typing — only the menus/drawer/scrim move. Respect `prefers-reduced-motion` (all transitions
  `none`).
- **Focus.** All interactive elements keep a visible `:focus-visible` ring in accent, never
  removed. Every icon/toggle gets `aria-label`; toggles carry `aria-expanded`.

### Interaction model

- Click `#posts-toggle` (or anywhere on the brand) -> open drawer; same click while open closes.
- Click `#menu-toggle` -> open/close menu; clicking outside the menu or pressing Esc closes.
- Opening the drawer closes the menu and vice versa (only one visitor at a time).
- Selecting view/font/theme/focus/shortcuts keeps the menu open (instant, self-contained
  feedback). Publish/unpublish and delete close the menu after the action.
- Typing never moves: opening a menu takes/returns focus only from/to the toggle button; the
  draft textarea keeps its lifecycle untouched.
- Basic focus management: opening the drawer moves focus to `#search-input`; closing restores it
  to `#posts-toggle`.

---

## index.html — restructure

New body shape (order matters — see Frozen contract):

```html
<body>
  <aside class="sidebar" aria-label="Posts library">      <!-- the drawer -->
    <header class="sidebar-head">brand (svg class="brand-icon" viewBox="0 0 32 32"
      stroke-width="2.5" + <span>inkwell</span>) + button#drawer-close ("×")
    </header>
    <div class="search-box">#search-input, #search-clear, #search-count</div>
    <div class="list-head"><button id="new-post" class="new-btn">+ new <kbd class="key-hint">⌘N</kbd></button></div>
    <nav id="post-list" class="post-list"></nav>
    <footer class="sidebar-footer">#total-posts, #total-words</footer>
  </aside>
  <div class="scrim" id="scrim"></div>

  <header class="topbar">
    <div class="topbar-left">
      button#posts-toggle (inline brand-icon + "Posts")
    </div>
    <div class="topbar-right">
      button#menu-toggle ("⋯", aria-haspopup="true" aria-expanded="false")
      <div id="menu-panel" class="menu-panel">
        <div class="menu-section" aria-label="View">
          <div class="mode-switch">  <!-- the segmented view switcher -->
            <button id="mode-edit" class="btn mode-btn" data-mode="edit" aria-pressed="true">edit</button>
            <button id="mode-split" class="btn mode-btn" data-mode="split" aria-pressed="false">split</button>
            <button id="mode-preview" class="btn mode-btn" data-mode="preview" aria-pressed="false">preview</button>
          </div>
          <button id="focus-toggle">focus <kbd class="key-hint">⌘⇧F</kbd></button>
        </div>
        <div class="menu-section">
          <span>Type size</span> <button id="font-decrease">A-</button> <button id="font-increase">A+</button>
          <button id="theme-toggle">light</button>
        </div>
        <div class="menu-section">
          <div class="goal-container" id="goal-container">
            <label for="target-words">Goal:</label>
            <input id="target-words" …>
            <span id="goal-progress"></span>
          </div>
          <span id="reading-time">0 min read</span>
        </div>
        <button id="shortcuts-toggle">keyboard shortcuts <kbd class="key-hint">?</kbd></button>
        <button id="publish">publish</button>
        <button id="delete" class="btn btn-danger">delete</button>
      </div>
    </div>
  </header>

  <main class="editor" id="editor" hidden>
    <input id="title" …>
    <div id="panes" class="panes">
      <section class="pane editor-pane"><span class="pane-label">markdown</span><textarea id="content" …></textarea></section>
      <section class="pane preview-pane"><span class="pane-label">preview</span><div id="preview" class="preview" aria-live="polite"></div></section>
    </div>
    <footer class="footer"><span id="word-count" class="meta">0 words</span><span class="spacer"></span><span id="save-state" class="meta save-state">saved</span></footer>
  </main>

  <p id="empty" class="empty" hidden>No posts yet.</p>
  <div id="shortcuts-modal" class="modal-backdrop" hidden>…unchanged…</div>
  <script>…existing theme early-boot script (inkwell-theme) unchanged…</script>
  <script type="module" src="app.js"></script>
</body>
```

Notes:
- Keep the `<head>` exactly as today (`rel="icon"` SVG favicon, the inline early theme script,
  stylesheet link).
- `#menu-panel` is a plain `div` (no `hidden` attribute) so CSS can animate it; it starts
  `visibility:hidden; opacity:0`.
- The drawer starts closed via CSS (`transform`), not `hidden`, so focus mode rules still match.
- Move `#reading-time`, `#goal-progress`, `#target-words`, `#goal-container` and their labels
  into the menu sections. Exactly the sample above shows them.
- `confirm()` and all existing text labels stay.

## style.css — changes

- **Token layer.** Keep every existing variable name and its current value except where a new
  neutral palette says otherwise — but the eight contrast-tested variables must stay in their
  current passing range: `--bg`, `--bg-sidebar`, `--border`, `--text-faint`, `--text-dim`
  (see Frozen contract). Add surface tokens for the new UI: `--topbar-bg`, `--menu-bg`,
  `--menu-border`, `--shadow-menu`, `--drawer-shadow`, `--scrim`, fade opacity constants, and a
  `--type-scale-slack` if wanted. All new rules reference `var(--…)`/`color-mix()` only.
- **New sections** (place before the `/* --- view modes */` comment, see Frozen contract):
  `.topbar`, `.topbar-left/-right`, `.posts-toggle`, `.menu-panel` (+ `.menu-section`, rows),
  `.scrim`, `body.drawer-open .sidebar` (open state), `body.menu-open .menu-panel`, quiet
  `.footer` (one-line, dim, centered), editor typography upgrades (`body .editor-column` rules),
  drawer polish (shadow on the right edge), responsive (`@media (max-width: 860px)` drawer full
  width; `@media (prefers-reduced-motion: reduce)` disable transitions).
  - `.editor-column` typography: `.title { padding-top: 80px; font-size: 34px; }`,
    `.content, .preview { padding: 0 48px; font-size: 19px; line-height: 1.85; max-width: 760px; }`
    (split mode keeps its current behavior; panes already become borderless rows inside the
    column).
- **Keep every rule/selector the tests grep** (Frozen contract below), at minimum by selector
  name; `body.focus-mode .sidebar` and `body.focus-mode .footer` keep working as the fade rules.
- **Focus mode** extends: `body.focus-mode .topbar { opacity: .15; }` (hover `opacity:1`), keep
  `body.focus-mode .sidebar` hidden and `.footer` fade.

### Frozen contract — things the 30 tests grep for (do not rename/remove)

These are substring/selector checks, not semantics — keep them present:

- HTML: `id="panes"`, `class="pane editor-pane"`, `class="pane preview-pane"`, `class="mode-switch"`,
  `id="mode-edit"|"mode-split"|"mode-preview"` with `data-mode="edit|split|preview"`,
  `id="content"`, `<div id="preview" class="preview"` (no `hidden` attr on preview),
  order `panes` < `content` < `preview`; modal: `id="shortcuts-modal"`, `id="shortcuts-toggle"`,
  `id="modal-close"`, `class="key-hint"`, the string "Cycle view mode" in the modal; focus/font:
  `id="focus-toggle"`, `id="font-increase"`, `id="font-decrease"`, the strings "Toggle focus mode",
  "Increase font size", "Decrease font size"; search: `id="search-input"`, `id="search-clear"`,
  `id="search-count"`, `class="search-box"`; goal/reading: `id="target-words"`, `id="reading-time"`,
  `id="goal-progress"`, `id="goal-container"`; theme: `id="theme-toggle"` and the string
  `inkwell-theme`; brand/new: `class="brand-icon"`, `<svg class="brand-icon"`, `viewBox="0 0 32 32"`,
  `stroke-width="2.5"`, `<rect width="32" height="32"`, `<span>inkwell</span>`, `rel="icon"`,
  `image/svg+xml`, NOT `&#9998;`, `class="list-head"`, `id="new-post"`, `class="new-btn"`; ordering
  in the drawer: `search-box` index < `list-head` index < `id="post-list"` index, and `id="new-post"`
  index sits between `list-head` and `post-list`.
- CSS: `.panes`, `.editor-pane`, `.preview-pane`, `.pane-label`, `.mode-switch`,
  `body[data-view-mode="edit"]`, `body[data-view-mode="split"]`, `body[data-view-mode="preview"]`,
  a rule `body[data-view-mode="split"] .preview-pane` that contains `border-left`, `body.focus-mode .sidebar`,
  `body.focus-mode .footer`, `--themes: dark light`, `[data-theme="light"]`, `.brand-icon`, `.list-head`,
  `.brand` with `display: inline-flex` and `align-items: center`, `.search-box`, `.search-input`,
  `.search-clear`, `.search-count`, `:focus-visible`, and the token definitions
  `--bg`, `--bg-sidebar`, `--border`, `--text-faint`, `--text-dim`.
  - **Hex discipline:** the test slices CSS from the `/* --- view modes */` comment to EOF and
    asserts no `#hex` literals and no `rgba(`. Keep the `view-modes` block at the end of the file
    and put all new sections before it, or guarantee everything after it is
    `var(--…)`/`color-mix()` only. Use `color-mix(...)` for any translucency; the scrim overlay
    uses a token too (e.g. `--scrim`), never `rgba(...)` inside/after that block.
- JS/app.js (strings and pure sections must survive verbatim or in compatible form):
  - Keep the `// --- view mode (pure)` section with `VIEW_MODES`, `nextViewMode`,
    `normalizeViewMode`, `viewModeShowsPreview`; keep the `// --- markdown` section with
    `renderMarkdown`.
  - Keep identifiers: `VIEW_MODES`, `nextViewMode`, `setViewMode`, `refreshPreview`,
    `document.body.dataset.viewMode`, `.mode-btn`, `cycleViewMode()`, `e.key === 'Enter'`,
    `toggleShortcutsModal`, `toggleFocusMode`, `setFontSize`, `ui.title.style.fontSize`,
    `e.key === '?'`, `e.key === 'Escape'`, `e.key.toLowerCase() === 'n'`,
    `e.shiftKey && e.key.toLowerCase() === 'f'`, `e.key === '=' || e.key === '+'`,
    `e.key === '-' || e.key === '_'`, `searchInput`, `searchClear`, `searchCount`, `performSearch`,
    `/api/posts?q=`, `calcReadingTime`, `target_word_count`, `goalProgress`, `goal-met`,
    `"inkwell-theme"`, `availableThemes`, `applyTheme`.
  - Keep the content input handler block (`ui.content.addEventListener('input', …)` containing
    `refreshPreview()` before `});`) intact.
  - `ui` map keys for everything that is dereferenced without `?.` must resolve to elements that
    exist in the new HTML: `title`, `content`, `preview`, `words`, `save`, `readingTime`,
    `targetWords`, `goalProgress`, `goalContainer`, `publishBtn`, `deleteBtn`, `newBtn`,
    `totalPosts`, `totalWords`, `shortcutsToggle`, `shortcutsModal`, `modalClose`, `focusBtn`,
    `fontIncreaseBtn`, `fontDecreaseBtn`, `searchInput`, `searchClear`, `searchCount`.

## app.js — changes (all additive)

1. **Drawer state.** Add `const drawer = { open:false … }` + `openDrawer()/closeDrawer()/toggleDrawer()`
   toggling `document.body.classList` (`body.drawer-open`) and `aria-expanded` on `#posts-toggle`.
   Close on `.scrim` click, on `#drawer-close`, and on Escape. Focus `#search-input` on open.
2. **Menu state.** `toggleMenu(show)` toggles `body.menu-open`, flips `#menu-toggle`'s
   `aria-expanded`; outside-click closes; Escape closes. Opening the drawer closes the menu.
3. **Escape priority** in the existing keydown branch: modal → menu → drawer → focus. Keep
   `e.key === 'Escape'` and the existing strings.
4. **Publish/delete close the menu** after their existing handlers run (wrap or `.then` —
   do not alter the API calls or `confirm()` flow).
5. **Font size persistence.** `setFontSize` additionally writes `localStorage['inkwell-fontsize']`;
   on `start()`, read it and apply (`if (saved) setFontSize(saved)`), default `19`. Keep the
   12px–48px clamp and the ±2 steps; keep `ui.title.style.fontSize` and the CSS-variable
   line-height toggling.
6. **No other behavior changes** — boot, autoselect, save, search, publish, delete, theme cycling,
   view-mode cycling, focus toggle, shortcuts modal all remain wired as today.

---

## Feature-to-destination map (nothing removed)

| Feature | Where now, unchanged handlers |
| --- | --- |
| Posts list / selection | Drawer (`#post-list`, `renderList`, click-to-select unchanged) |
| New post (`⌘N`) | Drawer, `.list-head` `#new-post` |
| Search | Drawer, `.search-box` (only entry point; still opens with drawer) |
| Totals (posts/words) | Drawer footer (`#total-posts`, `#total-words`) |
| View modes (edit/split/preview + `⌘↵`) | Editor menu `.mode-switch`; `body[data-view-mode]` CSS kept |
| Focus mode (`⌘⇧F`, Esc) | Editor menu `#focus-toggle`; `body.focus-mode` rules kept + topbar fade |
| Font size (`⌘+`/`⌘-`) | Editor menu A-/A+; range 12–48; persisted; title tracks |
| Themes | Editor menu `#theme-toggle`; cycling/persistence code untouched |
| Word goal | Editor menu: `#target-words` input + `#goal-progress`; goal-met styling kept |
| Reading time | Editor menu readout `#reading-time` |
| Save state | Footer `#save-state` |
| Word count | Footer `#word-count` (also drives totals) |
| Publish/unpublish | Editor menu `#publish` |
| Delete | Editor menu `#delete` (danger, confirm() unchanged) |
| Shortcuts modal (`?`/`⌘/`) | Modal unchanged; trigger moved into menu `#shortcuts-toggle` |

## Verification

1. **The gate:** `bun test apps/inkwell/server.test.ts` (from repo root) — all 30 pass.
2. **Boot**: `bun run apps/inkwell/server.ts` → http://localhost:4501:
   - Default view: cleared desk — no drawer, no clusters; one column; type starts immediately.
   - Open Posts: drawer slides in with scrim; search filters; select a post; Esc/backdrop closes.
   - Menu: view-mode switch with live preview (`⌘↵` cycles), focus (topbar+footer recede),
     font size persists after reload, theme switches + persists, goal input updates %,
     reading time shows, shortcut modal opens (with `?`), publish toggles label, delete confirms.
   - No element jumps while typing; reduced-motion preference respected.
3. Spot-read `styles.css` to double-check no hex/`rgba(` sits after the `/* --- view modes */` comment.

## Out of scope

- No server/API/database changes; no new endpoints; `server.test.ts` untouched.
- No new features (no tags/stats UI, no import/export, nothing new); only repackaging + polish.
- No build step; no new dependencies; stays one `style.css`, one `app.js`, one `index.html`.

## Risks

- **Reorder**: moving elements must never break the substring/order assertions (Frozen contract);
  when unsure, run the suite — it is authoritative.
- **View-modes hex rule** — keep every `/* --- view modes */`-onward style token-only.
- **Focus stealing**: opening menus must not blur the draft mid-sentence; only the drawer sets
  focus to its search box, and returning restores.
- **Contrast**: keep the eight critical variables in the current range; the suite double-checks
  `--text-dim` against hard-coded dark surfaces and `--text-faint` against the two bgs.