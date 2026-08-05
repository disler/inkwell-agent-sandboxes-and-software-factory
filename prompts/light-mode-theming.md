Add a light mode to contrast the default dark mode, and build the design system so that
additional themes can be added later. Themes should be defined as named sets of design tokens
rather than hardcoded colors, with the dark theme remaining the default.
Where: apps/inkwell/public/style.css (tokens + themes), apps/inkwell/public/app.js (theme
toggle + persistence), apps/inkwell/public/index.html (control markup).
Done means: the user can switch between dark and light from the UI, the choice persists across
reloads, dark remains the default on first load, and adding a third theme requires only
declaring one new named token set — no other file changes.
Out of scope: server or database changes, new API endpoints, per-post theming, and any
redesign of the existing layout beyond the color/token work.
