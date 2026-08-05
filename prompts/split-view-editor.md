Give the Inkwell editor a side-by-side markdown view — edit on the left, live preview on the
right — and let the writer switch between three modes: edit, split, and preview. A hot key
cycles between the modes.
Where: apps/inkwell/public/index.html (mode markup), apps/inkwell/public/app.js (mode state,
hot key, live preview rendering), apps/inkwell/public/style.css (the three layouts),
apps/inkwell/server.test.ts (tests).
Done means: split mode shows the editor and a live-updating rendered preview side by side; the
hot key moves the writer between edit, split, and preview; each mode is reachable and visibly
distinct; and tests cover the mode switching and the preview rendering.
Out of scope: server, database, or API changes; a new markdown parser (use the existing one);
and any change to the theme system shipped in the previous run.
