# Plan: Inkwell header icon + New button relocation

## Goal

1. Improve the Inkwell application icon so it is clearly legible (today the only icon is the favicon — an emoji glyph `✎` inside a data-URI SVG in `index.html`, which renders inconsistently across platforms).
2. Place that icon immediately to the left of the "inkwell" title in the sidebar header.
3. Move the `+ new` button out of `.sidebar-head` and into the top of the document/post list, where it stays easy to find and use.

All existing behavior must be preserved: the `⌘N`/`Ctrl+N` shortcut (which calls `ui.newBtn.click()`), the new-post click handler, the focus-visible outline, and the current layout.

## Files to touch

- `apps/inkwell/public/index.html` — icon + markup move
- `apps/inkwell/public/style.css` — icon/list-header styles, `.sidebar-head` cleanup
- `apps/inkwell/server.test.ts` — new/updated content-assertion tests
- `apps/inkwell/public/app.js` — **no changes required** (see "Why app.js is untouched")

## Context the builder needs (verified against the code)

- `apps/inkwell` is a Bun + `bun:sqlite` zero-dependency app: `server.ts` serves statics from `public/` and a JSON API under `/api`. Run tests with `bun test server.test.ts` from `apps/inkwell/`.
- Current sidebar header (`index.html` lines ~12–15):
  ```html
  <header class="sidebar-head">
    <h1 class="brand">inkwell</h1>
    <button id="new-post" class="new-btn" type="button">+ new <kbd class="key-hint">⌘N</kbd></button>
  </header>
  ```
- The favicon is the only existing icon: `<link rel="icon" href="data:image/svg+xml,<svg ...><text y='13' font-size='13'>&#9998;</text></svg>">`.
- `app.js` references the button only by id (`ui.newBtn = el('new-post')`) and the keyboard shortcut does `ui.newBtn.click()`. **Keeping `id="new-post"` means zero JS changes.**
- **Critical:** `renderList()` calls `ui.list.replaceChildren(...)` on `#post-list`, wiping all children. Therefore the New button must NOT be a child of `#post-list`; put it in a wrapper element directly above the `<nav id="post-list">`. It still visually heads the list, which is what the task asks for.
- Existing tests include content-assertion tests that fetch `/index.html`, `/app.js`, `/style.css` from the running test server and assert on substrings. No existing test references `new-post`, `sidebar-head`, `brand`, or the favicon, so nothing existing breaks from the markup move.

## Changes

### 1. `apps/inkwell/public/index.html`

**a. New legible icon.** Replace the emoji-glyph favicon with a hand-drawn inline SVG (quill/pen-nib in an inkwell or a simple nib), built from real vector shapes (paths/circles), using the app's accent color (`#6ee7b7`) and a dark rounded-square background (`#11161e` or `--bg-sidebar` tone `#090c11`) so it reads at 16×16. Keep it small and URL-encoded in the `data:image/svg+xml,` href. Design at a `viewBox="0 0 32 32"` with bold strokes (≥2.5px at that scale) so it stays legible at favicon size. Example concept: a fountain-pen nib (pointed pentagon path with a center slit line and a dot) over a rounded dark tile.

**b. Header icon.** In `.sidebar-head`, insert the same SVG inline (not a data URI — inline so it inherits CSS sizing) immediately before the `<h1 class="brand">`:

```html
<header class="sidebar-head">
  <svg class="brand-icon" viewBox="0 0 32 32" aria-hidden="true" focusable="false">…same shapes as favicon…</svg>
  <h1 class="brand">inkwell</h1>
</header>
```

`aria-hidden="true"` because it is decorative; the text title already names the app. Keep the SVG markup identical in shape to the favicon so the brand mark is consistent.

**c. Move the New button.** Remove the `<button id="new-post">` from `.sidebar-head` and place it in a new wrapper between the `.search-box` div and the `<nav id="post-list">`:

```html
<div class="list-head">
  <button id="new-post" class="new-btn" type="button">+ new <kbd class="key-hint">⌘N</kbd></button>
</div>
<nav id="post-list" class="post-list" aria-label="Posts"></nav>
```

Keep the exact `id`, `class="new-btn"`, inner content, and `type="button"` so the click handler, `⌘N` shortcut, and key-hint styling all keep working. Optionally add `title="New post (⌘N)"` for discoverability — do not remove the `<kbd>` hint.

### 2. `apps/inkwell/public/style.css`

- `.sidebar-head`: change `justify-content: space-between` to `justify-content: flex-start` and add `gap: 10px` (icon + title only now). Keep padding.
- Add `.brand-icon`: `width: 22px; height: 22px; flex-shrink: 0; display: block; border-radius: 6px;` (radius applies to the background tile in the SVG or via CSS background if the SVG uses a rect — pick one approach and keep it consistent with the favicon).
- Add `.list-head`: `padding: 0 12px 8px;` (aligns with `.search-box` horizontal padding). Make the button full-width inside it: `.list-head .new-btn { width: 100%; display: block; }`. Keep the existing `.new-btn` hover and `.new-btn:focus-visible` rules unchanged — focus outline accessibility is preserved automatically.
- No `@media` queries exist in the stylesheet; the sidebar is a fixed 240px flex column, so there is no responsive behavior to regress — just do not change `.sidebar`, `.post-list`, or the body flex layout.

### 3. `apps/inkwell/server.test.ts`

Follow the established fetch-and-assert-substring pattern. Add tests near the other UI content tests:

1. **Icon test** — fetch `/index.html`:
   - `expect(html).toContain('class="brand-icon"')`
   - Assert the icon precedes the title: `html.indexOf('class="brand-icon"')` is greater than `indexOf('sidebar-head')` and less than `indexOf('class="brand"')`.
   - Assert the favicon no longer uses the emoji glyph: `expect(html).not.toContain('&#9998;')`.
   - `expect(html).toContain('aria-hidden="true"')` (icon accessibility).
2. **Button relocation test** — fetch `/index.html`:
   - `expect(html).toContain('id="new-post"')` still present exactly once (split on the string, expect length 2).
   - Assert ordering: `indexOf('id="new-post"')` is **after** `indexOf('search-box')` (or after the close of `.sidebar-head`) and **before** `indexOf('id="post-list"')` — i.e., it sits at the top of the list, outside the header.
   - Assert `.sidebar-head` block no longer contains it: slice from `indexOf('sidebar-head')` to `indexOf('search-box')` and expect the slice not to contain `new-post`.
   - Assert the key hint survives: the button markup still contains `⌘N` and `class="key-hint"`.
3. **CSS test** — fetch `/style.css`:
   - `expect(css).toContain('.brand-icon')` and `.toContain('.list-head')`.
4. **Shortcut regression test** — fetch `/app.js` (already covered in spirit by an existing test, but add or extend): assert `ui.newBtn.click()` and `el('new-post')` still appear, proving the `⌘N` path is intact.

Do not modify any existing API tests; they are unaffected.

## Why `app.js` is untouched

The button keeps `id="new-post"`; `ui.newBtn` resolves identically; the `⌘N`/`Ctrl+N` keydown handler calls `ui.newBtn.click()`, which works regardless of DOM location. `renderList()`'s `replaceChildren` on `#post-list` is safe because the button lives in the sibling `.list-head` wrapper, not inside the nav.

## Verification

1. `cd apps/inkwell && bun test server.test.ts` — all tests (existing + new) pass.
2. Manual smoke: `cd apps/inkwell && bun run server.ts`, open `http://localhost:4501`:
   - Icon renders left of "inkwell", legible at sidebar size and as the tab favicon.
   - `+ new ⌘N` button appears full-width at the top of the post list, below search.
   - Clicking it creates a post and focuses the title input; `⌘N` does the same.
   - Tab-focus the button — accent focus outline appears.
   - Search, selection, publish, focus mode, and footer stats all still work.

## Out of scope

- No API/server changes.
- No responsive redesign (none exists today).
- No changes to the shortcuts modal content (the `⌘N` entry remains accurate).
