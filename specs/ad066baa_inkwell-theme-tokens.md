# Plan: Themeable design tokens + light mode for inkwell

## Goal

Add a light theme alongside the default dark theme in `apps/inkwell`, built on named
design tokens so a third theme later requires **only** declaring a new named token set in
`style.css` — zero changes to `app.js` or `index.html`.

Done means:
- User can switch dark ⇄ light from the UI.
- Choice persists across reloads (localStorage).
- Dark is the default on first load.
- Third theme = one new `[data-theme="..."]` block + one word added to a theme registry
  custom property, both in `style.css`.

Out of scope: server/db changes, API endpoints, per-post theming, layout redesign.

## Files to touch

1. `apps/inkwell/public/style.css` — full token set, theme blocks, replace hardcoded colors.
2. `apps/inkwell/public/index.html` — theme toggle button + tiny inline early-boot script.
3. `apps/inkwell/public/app.js` — generic theme cycling + persistence.

## Step 1 — `style.css`: promote every color to a token

### 1a. Expand the `:root` block (this remains the DARK theme / default)

Keep all existing tokens and add tokens for every color currently hardcoded in rules,
so no rule below references a raw hex/rgba value. Suggested additions (dark values taken
from the current stylesheet):

```css
:root {
  /* existing */
  --bg: #0d1117;
  --bg-sidebar: #090c11;
  --border: #303846;
  --text: #c9d1d9;
  --text-dim: #a3b0c2;
  --text-faint: #8b949e;
  --accent: #6ee7b7;
  --danger: #d97583;
  --serif: ...; --sans: ...; --mono: ...;   /* unchanged */

  /* new surface/strong tokens (currently hardcoded) */
  --surface-1: #11161e;            /* search input, new-btn, goal-input, post hover */
  --surface-2: #151b25;            /* hover/active states, new-btn hover */
  --surface-3: #161b22;            /* inline code bg, kbd bg */
  --surface-inset: #0b0f15;        /* pre/code block bg */
  --text-strong: #e6edf3;          /* preview strong */
  --border-strong: #3d4652;        /* kbd border */
  --scrollbar-thumb: #343d4d;
  --scrollbar-thumb-hover: #455062;
  --overlay: rgba(0, 0, 0, 0.65);  /* modal backdrop */
  --shadow-modal: 0 12px 32px rgba(0, 0, 0, 0.6);

  /* theme registry — JS reads this. Add a name here when adding a theme. */
  --themes: dark light;
}
```

### 1b. Declare the light theme as a named token set

```css
[data-theme="light"] {
  --bg: #f6f4ef;              /* warm paper — builder may adjust for taste */
  --bg-sidebar: #efede6;
  --border: #d8d3c8;
  --text: #2c2a26;
  --text-dim: #4f4b44;
  --text-faint: #8a847a;
  --accent: #0f7b56;          /* darker green for contrast on light bg */
  --danger: #b3353f;
  --surface-1: #ffffff;
  --surface-2: #e9e5db;
  --surface-3: #ece8df;
  --surface-inset: #e7e3d9;
  --text-strong: #1a1815;
  --border-strong: #c4beb1;
  --scrollbar-thumb: #c8c2b4;
  --scrollbar-thumb-hover: #a89f8e;
  --overlay: rgba(60, 55, 45, 0.35);
  --shadow-modal: 0 12px 32px rgba(60, 55, 45, 0.25);
}
```

Light values are a starting point — the builder should eyeball contrast in the browser
and tune. Font tokens are intentionally NOT overridden per theme (shared).

### 1c. Replace every hardcoded color in the rules with `var(--...)`

Sweep the file and substitute:
- `.search-input` background `#11161e` → `var(--surface-1)`
- `.new-btn` background `#11161e` → `var(--surface-1)`; hover bg `#151b25` → `var(--surface-2)`
- `.post-item:hover` bg `#11161e` → `var(--surface-1)`; `.post-item.active` bg `#151b25` → `var(--surface-2)`
- `.preview strong` color `#e6edf3` → `var(--text-strong)`
- `.preview code` background `#161b22` → `var(--surface-3)`
- `.preview pre` background `#0b0f15` → `var(--surface-inset)`
- `.goal-input` background `#11161e` → `var(--surface-1)`
- `.btn:hover` background `#151b25` → `var(--surface-2)`
- `kbd, .key-hint` background `#161b22` → `var(--surface-3)`; border `#3d4652` → `var(--border-strong)`
- `.modal-backdrop` background `rgba(0,0,0,0.65)` → `var(--overlay)`
- `.modal-content` box-shadow → `var(--shadow-modal)`
- `.close-btn:hover` background `#151b25` → `var(--surface-2)`
- Scrollbar rules: `#343d4d` → `var(--scrollbar-thumb)`, `#455062` → `var(--scrollbar-thumb-hover)`
- `.brand-icon` SVG rect uses a `fill="#11161e"` attribute in index.html (see Step 2) — add
  `.brand-icon rect { fill: var(--surface-1); }` so CSS overrides the attribute.

Also add a small style for the new toggle button — reuse the existing `.btn` class so no
new CSS is strictly needed; if an icon/emoji is used, no extra rules required.

Verification for this step: after editing, `grep -nE '#[0-9a-fA-F]{3,6}|rgba\(' apps/inkwell/public/style.css`
should return matches ONLY inside the `:root` and `[data-theme="light"]` blocks.

## Step 2 — `index.html`: toggle control + flash-free boot

1. **Early theme boot (prevents flash of wrong theme):** add a tiny inline script in
   `<head>` BEFORE the `<link rel="stylesheet">`... actually it must run before first paint;
   placing it in `<head>` after the stylesheet link is fine since it sets an attribute, not
   styles:

```html
<script>
  (function () {
    var t = localStorage.getItem('inkwell-theme');
    if (t) document.documentElement.setAttribute('data-theme', t);
  })();
</script>
```

   No `data-theme` attribute on `<html>` by default → `:root` dark tokens apply → dark
   remains the default on first load.

2. **Toggle button:** add to the sidebar footer (`<footer class="sidebar-footer">`), after
   the word-count span — it is visible even when the editor is empty and in focus mode
   (footer stays at 0.3 opacity but hoverable), unlike the editor footer which is hidden
   with no post:

```html
<button id="theme-toggle" class="btn" type="button" title="Switch theme">light</button>
```

   The button label is set by JS to the name of the theme it will switch TO (or current
   theme — builder's choice; label = next theme reads best for a cycle button).

3. Optionally swap the favicon/brand-icon hardcoded hexes — NOT required; the
   `.brand-icon rect` CSS rule from Step 1c handles the in-page icon. Leave the favicon
   data-URI as-is (always dark, acceptable).

## Step 3 — `app.js`: generic theme cycling + persistence

Add near the other UI wiring (keep it self-contained, ~25 lines):

```js
// --- theme ----------------------------------------------------------------

const THEME_KEY = 'inkwell-theme';
const themeBtn = el('theme-toggle');

function availableThemes() {
  // Registry lives in CSS (--themes on :root) so new themes need no JS changes.
  const raw = getComputedStyle(document.documentElement).getPropertyValue('--themes');
  const names = raw.trim().split(/\s+/).filter(Boolean);
  return names.length ? names : ['dark'];
}

function currentTheme(themes) {
  const t = document.documentElement.getAttribute('data-theme');
  return t && themes.includes(t) ? t : themes[0];   // first name = default (dark)
}

function applyTheme(name, themes) {
  if (name === themes[0]) document.documentElement.removeAttribute('data-theme');
  else document.documentElement.setAttribute('data-theme', name);
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
  const start = stored && themes.includes(stored) ? stored : themes[0];
  applyTheme(start, themes);
  themeBtn?.addEventListener('click', () => {
    const cur = currentTheme(themes);
    applyTheme(themes[(themes.indexOf(cur) + 1) % themes.length], themes);
  });
})();
```

Key properties:
- The theme list comes from the `--themes` custom property in `style.css`, so theme
  **registration** lives entirely in CSS. Adding `[data-theme="sepia"] { ... }` and
  changing `--themes: dark light;` to `--themes: dark light sepia;` is the complete
  third-theme workflow — no other file changes.
- The first name in `--themes` is the default and maps to NO attribute (falls through to
  `:root`), keeping dark as the default on first load.
- Unknown/stale stored values fall back to the default.
- The inline boot script in index.html applies the stored attribute before app.js (a
  module) executes, so there is no flash; app.js then validates it against the registry
  and fixes the button label.

## Step 4 — Verify

1. `cd apps/inkwell && bun test` — API suite must still pass (no server changes, sanity check).
2. `grep -nE '#[0-9a-fA-F]{3,6}|rgba\(' public/style.css` — matches only inside `:root` and `[data-theme="light"]`.
3. `bun run server.ts`, open http://localhost:4501:
   - First load (fresh browser profile / cleared localStorage) renders DARK.
   - Click the sidebar-footer theme button → UI switches to light; all surfaces
     (sidebar, editor, inputs, preview code blocks, kbd hints, modal, scrollbars) change.
   - Reload → light persists.
   - Click again → back to dark; reload → dark persists.
   - Open the shortcuts modal and preview mode in light theme to confirm overlay/code
     tokens look right.
4. Third-theme drill (temporary, then revert): add `[data-theme="sepia"] { --bg: #f4ecd8; ... }`
   and `sepia` to `--themes` — button cycles dark → light → sepia with no other edits.
   Revert the drill before committing (or keep it out of the working tree entirely).

## Constraints / notes

- Do NOT touch `server.ts`, `server.test.ts`, or the db.
- No new dependencies, no build step.
- Keep the existing layout and component structure pixel-identical; only colors move.
- `--themes` order matters: index 0 is the default and MUST stay `dark`.
- `color-mix()` usages already reference tokens — they work in both themes unchanged.
