Redesign Inkwell as a typography-first editorial instrument — the feeling of drafting in a
beautifully set book rather than operating a web app.

The problem: the current app reads like a tool, not a text. The screen is cluttered — a footer
full of buttons, an ever-present sidebar — and the words themselves are hard to read and see:
font size scaling is limited, and the typography is serviceable rather than set. The footer and
sidebar are unintuitive homes for the features they hold. Altogether it is a very average
writing experience for an app whose whole job is writing. The solution is the redesign below:
uplevel it into something typographically excellent while staying focused and minimal.

The vibe: confident, modern, restrained. Type does the work: a considered scale, real hierarchy,
comfortable measure and line height, text that looks publishable while it is being written. The
chrome that remains should feel engineered — precise, quiet, almost invisible — like the hardware
of a good pen.

Product direction:
- All current features survive — search, post management, publish/delete, view modes, focus mode,
  themes, font controls, goals, reading time, shortcuts — but their controls consolidate into
  clean menus instead of persistent toolbars. Fewer things on screen, nothing lost.
- Treat the editor page as the product. The draft list, actions, and settings become secondary
  surfaces the writer summons, in whatever menu structure you judge best.
- Light and dark themes should both feel deliberately art-directed, not inverted.
- Details carry the feel: cursor comfort, spacing rhythm, how the preview mirrors the editor,
  how state (saving, word count, goal progress) whispers instead of announces.

PM framing: the pitch is "the most beautiful place to write on your own machine." A returning
user should feel the difference in the first five seconds — before touching a single menu — and a
screenshot of the editor alone should sell the app.

Constraints: same stack (Bun server, vanilla JS, single stylesheet), no new dependencies, every
existing behavior and shortcut still works, existing tests stay green. Layout, type system, menu
design, and interaction polish are yours to decide.
