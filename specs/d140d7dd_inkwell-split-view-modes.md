# Plan: Inkwell side-by-side markdown view + three view modes (edit / split / preview)

## Goal

Give the Inkwell editor three view modes — **edit**, **split**, **preview** — driven by one
piece of state, one hot key, and three CSS layouts.

Done means:
- **split** shows the textarea on the left and a live-updating rendered preview on the right.
- The hot key (`Cmd/Ctrl + Enter`) cycles edit → split → preview → edit.
- Every mode is reachable (hot key *and* a click target) and visibly distinct.
- `bun test` covers the mode cycling and the preview rendering, and all existing tests stay green.

Out of scope (do not touch):
- `apps/inkwell/server.ts`, the sqlite schema, any API route or response shape.
- Any new markdown parser or dependency — reuse the existing `renderMarkdown` in `app.js`.
- The theme system from the previous run (`--themes`, `[data-theme="light"]`, `applyTheme`,
  `inkwell-theme` localStorage) — it must keep working untouched.
- Scroll-position syncing between the two split panes (explicitly not required).

## Files to touch

1. `apps/inkwell/public/index.html` — pane wrapper markup, 3-way mode switch, shortcuts-modal copy.
2. `apps/inkwell/public/app.js` — `viewMode` state, pure mode helpers, hot key, live preview render.
3. `apps/inkwell/public/style.css` — the three layouts, split divider, pane labels, responsive fallback.
4. `apps/inkwell/server.test.ts` — new tests; update the two legacy assertions listed in Step 4.
5. `apps/inkwell/README.md` — *small doc touch-up only* (shortcut list + a "View Modes" bullet). Allowed, not optional-blocking.

## Current state (read before editing)

- `index.html`: `<main class="editor" id="editor">` contains `#title`, `<textarea id="content">`,
  `<div id="preview" class="preview" hidden>`, then `<footer class="footer">` with the
  `#preview-toggle` button.
- `app.js`: `let previewing = false;` plus `showPreview(on)` which toggles `hidden` on
  `#preview`/`#content` and rewrites the button label. `Cmd/Ctrl+Enter` calls
  `showPreview(!previewing)`. `renderEditor()` and `selectPost()` also call into it.
- `style.css`: `.title, .content, .preview { max-width: 720px; margin: 0 auto; padding: 0 40px; }`
  and `.content`/`.preview` are both `flex: 1` children of the column-flex `.editor`.
- `server.test.ts`: front-end tests fetch `/index.html`, `/app.js`, `/style.css` from a real
  `Bun.serve` and assert on the source text. One test (`"app.js contains keydown listener for
  Cmd+Enter toggling preview mode"`) asserts `showPreview(!previewing)` — that string goes away.

## Step 1 — `index.html`: pane wrapper + 3-way mode switch

### 1a. Wrap the editing surfaces in a panes container

Replace the current `#content` / `#preview` pair inside `<main class="editor">` with:

```html
  <div id="panes" class="panes">
    <section class="pane editor-pane">
      <span class="pane-label">markdown</span>
      <textarea id="content" class="content" placeholder="Start writing…" spellcheck="true"></textarea>
    </section>
    <section class="pane preview-pane">
      <span class="pane-label">preview</span>
      <div id="preview" class="preview" aria-live="polite"></div>
    </section>
  </div>
```

Rules:
- Keep the ids `content` and `preview` and the classes `content` / `preview` exactly — `app.js`,
  `setFontSize()`, and existing preview typography CSS all key off them.
- Drop the `hidden` attribute from `#preview`; visibility is now CSS-driven off
  `body[data-view-mode]` (see Step 3). Do **not** re-introduce `hidden` toggling for the panes —
  the global `[hidden] { display: none !important; }` rule would fight the layout.
- `#title` stays a direct child of `.editor`, above `#panes`.

### 1b. Replace `#preview-toggle` with a segmented mode switch

In `<footer class="footer">`, replace the single `preview` button with:

```html
    <div class="mode-switch" role="group" aria-label="View mode">
      <button id="mode-edit" class="btn mode-btn" type="button" data-mode="edit" aria-pressed="true" title="Edit only">edit</button>
      <button id="mode-split" class="btn mode-btn" type="button" data-mode="split" aria-pressed="false" title="Editor + live preview">split</button>
      <button id="mode-preview" class="btn mode-btn" type="button" data-mode="preview" aria-pressed="false" title="Preview only">preview</button>
      <kbd class="key-hint">⌘↵</kbd>
    </div>
```

Keep it in the same footer slot the old button occupied (before `#publish`) so the footer order
stays familiar: font buttons, focus, shortcuts, **mode switch**, publish, delete.

### 1c. Shortcuts modal copy

Change the `Toggle preview mode` row to:

```html
      <li class="shortcuts-item">
        <span class="shortcuts-desc">Cycle view mode (edit → split → preview)</span>
        <span class="shortcuts-keys"><kbd>⌘ ↵</kbd> / <kbd>Ctrl ↵</kbd></span>
      </li>
```

## Step 2 — `app.js`: state, pure helpers, hot key, live preview

### 2a. `ui` map

Remove `previewBtn: el('preview-toggle')` and add:

```js
  panes: el('panes'),
  modeButtons: Array.from(document.querySelectorAll('.mode-btn')),
```

(Query it lazily inside the wiring block if you prefer — `app.js` is a module loaded at the end
of `<body>`, so the nodes exist.)

### 2b. Pure view-mode helpers — **these two sections must stay side-effect free**

The tests evaluate this block in isolation (no `document`), so it must contain no DOM access.
Add it immediately after the existing `// --- markdown ---` section, using exactly these headers:

```js
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
```

Notes:
- Section header text matters: the tests slice `app.js` between `// --- view mode (pure)` and the
  next `\n// --- ` header, and between `// --- markdown` and the next `\n// --- ` header.
  Do not rename, merge, or reorder those markers, and keep `// --- view mode (dom)` right after
  the pure block.
- `renderMarkdown`, `inline`, `escapeHtml` stay exactly where they are inside the
  `// --- markdown ---` section and stay pure.

### 2c. Delete `showPreview()` and re-point its callers

- Remove `let previewing = false;` and the whole `showPreview(on)` function.
- `renderEditor()`: replace the trailing `if (previewing) ui.preview.innerHTML = ...` with
  `refreshPreview();`.
- `selectPost()`: replace `showPreview(false)` with `refreshPreview()` — the writer's chosen mode
  **persists across post switches** (do not snap back to edit).
- The `ui.newBtn` click handler: same swap — `showPreview(false)` → `refreshPreview()`.
- Remove `ui.previewBtn.addEventListener('click', ...)` and add:

```js
for (const btn of document.querySelectorAll('.mode-btn')) {
  btn.addEventListener('click', () => setViewMode(btn.dataset.mode));
}
```

### 2d. Live preview on every keystroke

In the existing `ui.content` input handler:

```js
ui.content.addEventListener('input', () => {
  updateWordCount();
  refreshPreview();   // live preview — no-op in edit mode
  scheduleSave();
});
```

`refreshPreview()` early-returns in edit mode, so edit-only typing costs nothing. No debounce
needed — `renderMarkdown` is a single pass over the text.

### 2e. Hot key

In the `document.addEventListener('keydown', ...)` chain, replace the Cmd/Ctrl+Enter branch:

```js
  } else if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
    e.preventDefault();
    if (current) cycleViewMode();
  }
```

Leave every other shortcut branch (focus mode, font size, `⌘N`, `⌘S`, `?`, `Esc`) untouched.

### 2f. Boot

Call `setViewMode('edit')` once during startup (e.g. at the end of the module, or the first line of
`start()`), so `document.body.dataset.viewMode` is always set and the `edit` button starts `active`.

Optional (only if it costs nothing): persist the mode under `localStorage['inkwell-view-mode']` and
seed `setViewMode(localStorage.getItem('inkwell-view-mode') || 'edit')`, writing inside
`setViewMode`. Skip it if it complicates the tests — it is not part of "done".

## Step 3 — `style.css`: the three layouts

Add a `--- view modes ---` block after the existing editor section. Keep the existing
`.title, .content, .preview` typography rule but move the `max-width: 720px; margin: 0 auto`
centering so it can be relaxed in split mode.

```css
/* --- view modes --------------------------------------------------------- */

.panes {
  display: flex;
  flex: 1;
  min-height: 0;          /* lets children scroll instead of overflowing .editor */
  width: 100%;
}

.pane {
  display: flex;
  flex-direction: column;
  flex: 1 1 50%;
  min-width: 0;
  min-height: 0;
  position: relative;
}

.pane-label {
  display: none;          /* split mode only */
  padding: 4px 40px 6px;
  font-size: 10.5px;
  letter-spacing: 0.09em;
  text-transform: uppercase;
  color: var(--text-faint);
}

/* edit: textarea only */
body[data-view-mode="edit"] .preview-pane { display: none; }

/* preview: rendered output only */
body[data-view-mode="preview"] .editor-pane { display: none; }

/* split: both, side by side, divider between them */
body[data-view-mode="split"] .pane-label { display: block; }

body[data-view-mode="split"] .preview-pane {
  border-left: 1px solid var(--border);
  background: var(--surface-1);
}

body[data-view-mode="split"] .content,
body[data-view-mode="split"] .preview {
  max-width: none;
  margin: 0;
  padding-left: 28px;
  padding-right: 28px;
}

body[data-view-mode="split"] .title {
  max-width: none;
  padding-left: 40px;
  padding-right: 40px;
}

/* narrow viewports: split stacks vertically instead of squeezing */
@media (max-width: 860px) {
  body[data-view-mode="split"] .panes { flex-direction: column; }
  body[data-view-mode="split"] .preview-pane {
    border-left: 0;
    border-top: 1px solid var(--border);
  }
}
```

Requirements this block must satisfy:
- Each pane scrolls independently: `.content` and `.preview` keep `overflow-y: auto` and their
  parent `.pane` has `min-height: 0`.
- Use only existing theme tokens (`var(--border)`, `var(--surface-1)`, `var(--text-faint)`, …).
  **No new hex/rgba literals outside `:root` / `[data-theme="light"]`** — the WCAG/contrast test
  and the token discipline from the previous run depend on it.
- `.mode-switch` styling: `display: inline-flex; align-items: center; gap: 2px;` and
  `.mode-btn` reuses `.btn` (the existing `.btn.active { color: var(--accent); }` gives the active
  mode its highlight). Optionally give `.mode-switch` a `border: 1px solid var(--border);
  border-radius: 6px; padding: 2px;` so it reads as one segmented control.
- Focus mode (`body.focus-mode`) keeps working: it only hides `.sidebar` and dims `.footer`, so no
  extra rules are needed — verify split still looks right in focus mode.

## Step 4 — `server.test.ts`: tests

### 4a. Fix the two legacy assertions

- `"app.js contains keydown listener for Cmd+Enter toggling preview mode"` — rename to
  `"app.js cycles view mode on Cmd+Enter"` and swap `expect(text).toContain("showPreview(!previewing)")`
  for `expect(text).toContain("cycleViewMode()")` (keep the `e.key === 'Enter'` assertion).
- `"index.html contains shortcuts modal elements and visual key hints"` — unaffected, but if any
  assertion still references the string `Toggle preview mode`, update it to the new copy.
- Run the full suite and fix any other assertion that referenced `preview-toggle` / `previewing`.

### 4b. Add a source-extraction helper (top of the front-end test group)

```ts
// Pulls one `// --- <name> ---` section out of app.js so pure logic can be exercised directly.
function section(src: string, name: string): string {
  const start = src.indexOf(`// --- ${name}`);
  if (start === -1) throw new Error(`section "${name}" not found in app.js`);
  const rest = src.slice(start);
  const end = rest.indexOf("\n// --- ", 1);
  return end === -1 ? rest : rest.slice(0, end);
}

function loadSection<T>(src: string, name: string, exports: string[]): T {
  return new Function(`${section(src, name)}\nreturn { ${exports.join(", ")} };`)() as T;
}
```

### 4c. New tests

1. **`index.html` exposes the panes and the three mode buttons`**
   - contains `id="panes"`, `class="editor-pane"`, `class="preview-pane"`, `class="mode-switch"`.
   - contains `id="mode-edit"`, `id="mode-split"`, `id="mode-preview"` and
     `data-mode="edit"`, `data-mode="split"`, `data-mode="preview"`.
   - still contains `id="content"` and `id="preview"`.
   - `#preview` no longer ships `hidden`: assert the substring `<div id="preview" class="preview"`
     is present and that the `#preview` tag text (slice from `id="preview"` to the next `>`)
     does not contain `hidden`.
   - order: `indexOf('id="content"') < indexOf('id="preview"')`, both inside the `#panes` block
     (`indexOf('id="panes"') < indexOf('id="content"')`).
   - shortcuts modal advertises the cycle: contains `Cycle view mode`.

2. **`style.css` defines all three layouts**
   - contains `.panes`, `.editor-pane`, `.preview-pane`, `.pane-label`, `.mode-switch`.
   - contains `body[data-view-mode="edit"]`, `body[data-view-mode="split"]`,
     `body[data-view-mode="preview"]`.
   - split adds a divider: the `body[data-view-mode="split"] .preview-pane` rule contains
     `border-left`.
   - guard the token discipline: every `#hex`/`rgba(` match in the file still falls inside the
     `:root` or `[data-theme="light"]` blocks (reuse the approach of the existing contrast test, or
     assert `css.slice(css.indexOf('/* --- view modes'))` has no `#` hex literal).

3. **`app.js` wires mode state, buttons, and live preview**
   - contains `VIEW_MODES`, `nextViewMode`, `setViewMode`, `refreshPreview`,
     `document.body.dataset.viewMode`, `.mode-btn`.
   - no longer contains `showPreview` or `previewing`.
   - the content input handler calls the live render: assert the source slice from
     `ui.content.addEventListener('input'` to the next `});` contains `refreshPreview()`.

4. **view-mode cycling (behavioral, pure section eval)**
   ```ts
   const js = await (await fetch(`${base}/app.js`)).text();
   const { VIEW_MODES, nextViewMode, normalizeViewMode, viewModeShowsPreview } =
     loadSection<any>(js, "view mode (pure)", ["VIEW_MODES", "nextViewMode", "normalizeViewMode", "viewModeShowsPreview"]);

   expect(VIEW_MODES).toEqual(["edit", "split", "preview"]);
   expect(nextViewMode("edit")).toBe("split");
   expect(nextViewMode("split")).toBe("preview");
   expect(nextViewMode("preview")).toBe("edit");          // wraps
   expect(nextViewMode("bogus")).toBe("split");            // unknown normalizes to edit, then advances
   expect(normalizeViewMode(undefined)).toBe("edit");
   expect(viewModeShowsPreview("edit")).toBe(false);
   expect(viewModeShowsPreview("split")).toBe(true);
   expect(viewModeShowsPreview("preview")).toBe(true);
   ```
   Also assert three cycles from `edit` return to `edit`, i.e. every mode is reachable by the hot key.

5. **preview rendering (behavioral, markdown section eval)**
   ```ts
   const { renderMarkdown } = loadSection<any>(js, "markdown", ["renderMarkdown"]);

   const html = renderMarkdown("# Title\n\nsome **bold** and `code`\n\n- one\n- two");
   expect(html).toContain("<h1>Title</h1>");
   expect(html).toContain("<strong>bold</strong>");
   expect(html).toContain("<code>code</code>");
   expect(html).toContain("<li>one</li>");
   expect(html).toContain("<ul>");
   expect(renderMarkdown("```\nlet x = 1;\n```")).toContain("<pre><code>let x = 1;</code></pre>");
   expect(renderMarkdown("<script>alert(1)</script>")).toContain("&lt;script&gt;");
   // live-updating: successive keystroke states render different output
   expect(renderMarkdown("# a")).not.toBe(renderMarkdown("# ab"));
   ```

Keep every new test in the existing style: `fetch` the asset off `base`, `expect(res.status).toBe(200)`,
plain `expect(...)` assertions, no new dependencies.

## Step 5 — `README.md` touch-up

- Shortcut list: replace `Cmd+Enter … Toggle preview mode` with
  `` `Cmd+Enter` / `Ctrl+Enter`: Cycle view mode (edit → split → preview) ``.
- Add a short **View Modes** section: edit (textarea only), split (editor left, live preview right,
  divider + pane labels), preview (rendered only); reachable by hot key or the footer `mode-switch`
  buttons; the chosen mode persists while switching posts.

## Step 6 — Verify

1. `cd apps/inkwell && bun test` — whole suite green (exit status 0), including the new tests.
2. `cd apps/inkwell && bun run server.ts`, open http://localhost:4501:
   - Type markdown. Press `⌘↵` → **split**: textarea left, rendered output right, divider visible,
     `MARKDOWN` / `PREVIEW` labels showing, `split` button highlighted.
   - Keep typing in split → the right pane updates on every keystroke (headings, bold, lists, code).
   - `⌘↵` again → **preview** only. `⌘↵` again → back to **edit**. Buttons track the active mode.
   - Click each of the three buttons directly — each mode is reachable by click too.
   - Scroll each split pane independently; `A+` / `A-` still resize both panes.
   - Switch posts while in split → still split, preview shows the newly loaded post.
   - Toggle focus mode (`⌘⇧F`) in split → sidebar hides, split layout intact.
   - Toggle the theme (sidebar footer) in split → divider/pane background/labels read correctly in
     both dark and light.
   - Shrink the window below ~860px in split → panes stack vertically.
3. Optional visual record: capture a screenshot of split mode (the app already keeps
   `apps/inkwell/validation.png` from a prior run — overwrite or add alongside, your call).

## Constraints recap

- No changes to `server.ts`, the db, or any API contract.
- No new dependencies, no build step, no new markdown parser.
- Theme tokens and the `--themes` registry stay exactly as shipped; new CSS uses tokens only.
- Keep `app.js` section headers (`// --- markdown`, `// --- view mode (pure)`,
  `// --- view mode (dom)`) intact — the behavioral tests slice on them.
- All pre-existing tests must pass; only the two assertions named in Step 4a may be rewritten.
