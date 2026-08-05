Redesign Inkwell around one idea: the app is a quiet room where writing happens. Everything that
is not the current draft should feel like it has left the room until called for.

The problem: today's Inkwell is a cluttered room. Buttons and readouts crowd the footer, the
sidebar is always present whether or not it is wanted, and the text itself is hard to read and
see — font scaling is limited and the type never gets to breathe. The footer and sidebar are
unintuitive; tools sit where they landed, not where a writer would look. The result is a very
average writing experience. The solution is this redesign: uplevel the experience while staying
focused and minimal — the quiet room below.

The vibe: opening Inkwell should feel like sitting down at a cleared desk. Generous whitespace,
one beautiful column of text, calm neutral surfaces, no competing chrome. The writer's words are
the interface; the app recedes.

Product direction:
- Keep every existing feature — posts list, search, publish, delete, themes, view modes, focus
  mode, font sizing, word goals, reading time, shortcuts. Nothing is removed. Nothing new either.
- Simplify how they are reached: collapse today's always-visible button rows and footer strips
  into a small number of unobtrusive menus. A writer who wants a tool opens a menu; a writer who
  is writing sees almost nothing.
- The default state is the writing state. Lists, settings, and metadata are visitors, not
  residents — they appear on intent and get out of the way after.
- Transitions should feel soft and immediate. Nothing should jump, flash, or demand attention
  while someone is mid-sentence.

PM framing: the target user writes daily and opens the app to continue a draft, not to manage a
library. Optimize for the second session of the day — muscle-memory entry straight into the text.
Judge every visible element by one question: does this help the next sentence get written?

Constraints: same stack (Bun server, vanilla JS, single stylesheet), no new dependencies, all
existing behavior and keyboard shortcuts keep working, and the existing test suite stays green.
You own the visual language, layout, menu structure, and interaction details.
