# Inkwell header and list controls

## What changed

Inkwell now uses a legible vector brand mark instead of the previous emoji-glyph favicon. The same dark rounded-square / mint pen-nib SVG is rendered inline immediately before the `inkwell` title in the sidebar header and is retained as the data-URI favicon. The inline mark is decorative (`aria-hidden="true"`).

The `+ new` button was removed from the sidebar header and placed in a `.list-head` wrapper between search and the `#post-list` navigation. It remains the same `#new-post` button with its `⌘N` hint, but is now full-width and visually positioned at the top of the post list. Keeping it outside `#post-list` avoids its being removed when list rendering calls `replaceChildren`.

The existing JavaScript behavior is preserved by retaining the button ID; no `app.js` change was needed. The CSS updates align the icon and title, style the list control, and add hover/background treatment while retaining focus-visible behavior.

## Files carrying the change

- `apps/inkwell/public/index.html` — favicon, inline brand SVG, and button relocation.
- `apps/inkwell/public/style.css` — header/icon and `.list-head`/button layout and visual styles.
- `apps/inkwell/server.test.ts` — content assertions for the vector icon, favicon replacement, button placement, and related CSS; an existing tag test also now initializes the posts table before direct database cleanup.
- `apps/inkwell/package.json` — adds the private ESM package metadata for Inkwell.
- `justfile` — changes `cc`, `pi`, and `ipi` orchestrator recipes to launch through an interactive zsh shell, preserving the operator’s shell environment; shared `boot` and `ask` variables hold the invocation strings.
- `specs/e2688070_inkwell-header-icon-controls.md` — records the implementation plan, preserved behavior, constraints, and verification checklist.

## Verification and use

Run the Inkwell server tests from the app directory:

```sh
cd apps/inkwell && bun test server.test.ts
```

For a manual check, run `bun run server.ts` from `apps/inkwell/` and open `http://localhost:4501`. Confirm the icon appears beside the title and as the favicon, the full-width New control appears below search and above the post list, clicking it still creates a post, `⌘N` still invokes it, and keyboard focus shows the accent outline. The added tests fetch `/index.html` and `/style.css` and assert the relevant structure and styles directly.
