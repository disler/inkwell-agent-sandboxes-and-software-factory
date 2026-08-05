# Inkwell "quiet room" redesign

## What changed and why it matters

Inkwell was a cluttered room: an always-present sidebar, a footer crowded with buttons and
readouts, and cramped type. This change redesigns the app around one idea — the default state is
the writing state. On load the writer lands straight in the text: one serif column on a calm,
cleared surface, with a hairline topbar and a whisper of a footer. Everything that is not the
current draft (posts list, search, theme, view modes, focus, font size, word goal, reading time,
publish, delete, shortcuts) is now a visitor: it appears on intent and leaves afterward.

No features were removed and none were added. The same stack stays (Bun server, vanilla JS, one
stylesheet), no new dependencies, all keyboard shortcuts keep working, and the existing 30-test
suite (`bun test apps/inkwell/server.test.ts`) passes unmodified. `server.ts` was not touched.

## The new shell (three surfaces)

- **Topbar** — one thin, transparent row (`padding: 12px 22px`, no border). Left: the brand mark
  plus a text-labeled **Posts** button (`#posts-toggle`). Right: a single **⋯** button
  (`#menu-toggle`). In focus mode the topbar fades to 15% opacity and ignores clicks; hover
  restores it.
- **Posts drawer** — the old `.sidebar` became a left slide-in drawer: fixed, `300px` wide,
  `translateX(-100%)` by default, sliding in under `body.drawer-open` (260ms ease). A `.scrim`
  overlay covers the editor; clicking the scrim, the new `#drawer-close` button, or pressing Esc
  closes it. Drawer content and order are unchanged: brand header, search box (with
  clear/count), `+ new`, the post list, and the posts/words totals footer.
- **Editor menu** — a small popover card (`#menu-panel`) anchored under the ⋯ button, shown by
  `body.menu-open` with a 160ms fade/rise. Everything a writer reaches for mid-draft lives here,
  grouped into sections: View (edit/split/preview switch, focus), Type (A−/A+, theme), Progress
  (word goal input + progress, reading time), Actions (shortcuts, publish, delete). Outside-click
  or Esc closes it.
- **Footer (whisper)** — one quiet centered line under the column: word count and save state,
  dim and tiny. The old button rows and strips (font, focus, shortcuts, view switch, publish,
  delete, goal, reading time) are gone from the footer; word goal and reading time moved into the
  menu.

Opening the drawer closes the menu and vice versa — only one visitor at a time. Focus moves only
between the toggle buttons and the drawer's search box; the draft textarea is never blurred.

## Typography and visual language

- The editor is a single centered column: `max-width: 760px` (`--column-w`), ~48px side padding,
  serif at a new base of **19px** (was 18), `line-height: calc(1.65 + 0.004 * size)`,
  `letter-spacing: 0.01em`, `text-rendering: optimizeLegibility`. The title gets 72px of top
  padding ("sky") at 34px.
- Font size range widened from 12–36 to **12–48px** (steps stay ±2). The chosen size now
  persists in `localStorage` under `inkwell-fontsize` and is restored on boot; the title follows
  at `size + 12px`, and the line-height scales gently via the `--content-fs` CSS variable.
- New tokens for the quiet surfaces: `--topbar-bg`, `--menu-bg`, `--menu-border`, `--shadow-menu`,
  `--drawer-shadow`, `--scrim`, plus motion tokens (`--ease`, `--t-fast/med/drawer`). All
  translucency uses `color-mix()`, never `rgba()`, and the CSS after the `/* --- view modes */`
  comment is token/`color-mix()`-only (a test-enforced constraint).
- Transitions share one curve (`cubic-bezier(0.32, 0.72, 0.25, 1)`) at 150–260ms; nothing
  animates while typing. `prefers-reduced-motion` disables all transitions. Focus-visible rings
  remain in accent for every interactive element; toggles carry `aria-expanded`.

## Files that carry it

- `apps/inkwell/public/index.html` — restructured chrome: drawer-close button in the sidebar,
  new `.scrim`, new `.topbar` with `#posts-toggle` and `#menu-toggle`/`#menu-panel`, footer
  slimmed to word count + save state, goal/reading-time moved into the menu. The frozen
  selectors the tests grep (panes, mode buttons, search box, modal, brand SVG, etc.) are all kept.
- `apps/inkwell/public/style.css` — new shell CSS (topbar, menu panel, scrim, drawer), quiet-room
  tokens, editor column typography, responsive/reduced-motion rules; the view-mode block was
  moved to the end of the file to satisfy the hex-discipline test rule.
- `apps/inkwell/public/app.js` — additive shell state: `drawer`/`menu` objects, open/close/
  toggle helpers, outside-click and Escape handling (priority: modal → menu → drawer → focus),
  menu close after publish/delete, font-size persistence, and default size 19.
- `specs/889ae961_quiet-room-redesign.md` — the plan: design, frozen-contract checklist,
  feature-to-destination map, verification steps.

## How to use and verify

1. **Gate:** `bun test apps/inkwell/server.test.ts` from the repo root — 30 pass, unchanged.
2. **Boot:** `bun run apps/inkwell/server.ts` → http://localhost:4501. You land on a cleared
   desk: no drawer, no menu, one column of text.
   - **Posts:** click the Posts button — drawer slides in over a scrim; search filters the list;
     select a post (drawer closes); Esc, the × button, or clicking the scrim closes it.
   - **Menu:** click ⋯ — switch edit/split/preview (⌘↵ still cycles), toggle focus (topbar and
     footer recede; hover restores), A−/A+ (range 12–48, persisted across reload), theme,
     goal input updates the progress %, reading time shows, shortcuts opens with `?`,
     publish toggles, delete confirms.
   - Opening the drawer closes the menu and vice versa; typing never loses focus to a menu.
3. **Spot-check:** no `#hex` literals or `rgba(` after the `/* --- view modes */` comment in
   `style.css`.
