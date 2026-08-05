# Inkwell: three view modes (edit / split / preview) with a live side-by-side markdown preview

## What changed and why

Inkwell's editor previously had a binary preview toggle (`showPreview(on)` flipping a `hidden`
attribute between the textarea and a preview div). This run replaces that with a three-mode
view system — **edit**, **split**, **preview** — driven by a single piece of state
(`viewMode`), one hot key, and CSS layouts keyed off `body[data-view-mode]`. Split mode puts
the textarea on the left and a live-rendered markdown preview on the right (divider plus
`MARKDOWN` / `PREVIEW` pane labels), and the preview re-renders on every keystroke. The old
`showPreview` / `previewing` machinery is gone entirely. No server, database, or API changes,
and the existing `renderMarkdown` parser and theme-token system are untouched.

## Files that carry it

- `apps/inkwell/public/index.html` — `#content` and `#preview` now live inside a `#panes`
  flex wrapper as two `.pane` sections (`.editor-pane`, `.preview-pane`, each with a
  `.pane-label`). `#preview` no longer ships the `hidden` attribute; visibility is CSS-driven.
  The footer's `#preview-toggle` button is replaced by a `.mode-switch` segmented control
  (`#mode-edit` / `#mode-split` / `#mode-preview`, each with `data-mode` and `aria-pressed`).
  The shortcuts modal row now reads "Cycle view mode (edit → split → preview)".
- `apps/inkwell/public/app.js` — two new sections after `// --- markdown ---`:
  - `// --- view mode (pure) ---`: `VIEW_MODES`, `normalizeViewMode`, `nextViewMode`
    (wraps edit → split → preview → edit; unknown input normalizes to `edit` first),
    `viewModeShowsPreview`. Side-effect free so tests can eval it in isolation.
  - `// --- view mode (dom) ---`: `viewMode` state, `refreshPreview()` (early-returns in edit
    mode), `setViewMode()` (writes `document.body.dataset.viewMode`, toggles `.mode-btn`
    `active`/`aria-pressed`, re-renders), `cycleViewMode()`.
  - The content `input` handler now calls `refreshPreview()` on every keystroke;
    `Cmd/Ctrl+Enter` calls `cycleViewMode()`; each `.mode-btn` calls `setViewMode` on click;
    `start()` seeds `setViewMode('edit')`. Mode persists across post switches — `selectPost()`
    and the new-post handler just call `refreshPreview()` instead of snapping back to edit.
- `apps/inkwell/public/style.css` — a new `--- view modes ---` block: `.panes` flex row with
  `min-height: 0` so each pane scrolls independently; `body[data-view-mode="edit"]` hides the
  preview pane, `="preview"` hides the editor pane, `="split"` shows both with a `border-left`
  divider, pane labels, and relaxed `max-width` centering. Below 860px split stacks vertically
  (divider moves to `border-top`). All colors use existing theme tokens — no new hex/rgba
  literals. `.mode-switch` is styled as one segmented control; the active button reuses the
  existing `.btn.active` accent.
- `apps/inkwell/server.test.ts` — the legacy Cmd+Enter assertion now expects `cycleViewMode()`.
  New `section()` / `loadSection()` helpers slice a `// --- <name> ---` block out of the served
  `app.js` and eval it via `new Function`, enabling behavioral tests of the pure logic.
  New tests cover: the panes/mode-button markup (including that `#preview` has no `hidden` and
  content precedes preview), the three CSS layouts plus token discipline in the new block, the
  app.js wiring (mode state, buttons, live-preview handler; `showPreview`/`previewing` absent),
  behavioral mode cycling (including wrap-around and unknown-mode normalization), and behavioral
  markdown rendering (headings, bold, inline code, lists, fenced code, HTML escaping).
- `apps/inkwell/README.md` — shortcut list updated to "Cycle view mode" and a new **View Modes**
  section describing the three modes and the <860px stacking.
- `requests/split-view-editor.md` — the original request.
- `specs/d140d7dd_inkwell-split-view-modes.md` — the implementation plan this run followed.

## How to use / verify

1. `cd apps/inkwell && bun test` — full suite green, including the new mode/markup/layout tests.
2. `bun run server.ts`, open http://localhost:4501, open a post:
   - Press `Cmd/Ctrl+Enter` (or click the footer `mode-switch` buttons) to move
     edit → split → preview → edit. The active button highlights and `aria-pressed` tracks it.
   - In split, type markdown — the right pane updates on every keystroke.
   - Switch posts while in split: the mode persists and the preview shows the new post.
   - Shrink the window below ~860px: split stacks the panes vertically.

## Notes

- The chosen mode is in-memory only for the session; the spec listed `localStorage` persistence
  as optional and it was not implemented.
- Scroll-position syncing between the two split panes was explicitly out of scope — each pane
  scrolls independently.
- Keep the `// --- view mode (pure)` / `// --- view mode (dom)` / `// --- markdown` section
  headers in `app.js` intact: the tests slice the source on those exact markers.
