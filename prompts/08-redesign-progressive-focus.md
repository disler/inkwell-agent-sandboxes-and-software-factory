Redesign Inkwell around progressive disclosure: full power, revealed in layers, with the writing
surface as layer zero.

The problem: right now every layer is on screen at once. The app is cluttered — sidebar always
open, a footer strip of buttons always visible — which makes the draft itself hard to read and
see. Font size scaling is limited, and the footer and sidebar are unintuitive: features live
where they were bolted on, not where intent would find them. The net effect is a very average
writing experience. The solution is the layered redesign below: uplevel the experience while
staying focused and minimal, disclosure by disclosure.

The vibe: modern, minimal, intentional — an app that feels smaller than it is. Calm by default,
capable on demand. The writer should sense that everything is one gesture away and nothing is in
their face.

Product direction:
- Inventory today's UI honestly: the sidebar, the footer strip of buttons, the mode switch, the
  goal inputs, the theme toggle, the shortcuts modal. Keep every capability; rehouse them.
- Organize the features into a small, coherent menu system by writer intent — roughly: finding
  and managing drafts, shaping the current draft, tuning the environment, shipping the work. The
  exact grouping and mechanism (menus, palette, panels) is your call; the bar is that a first-time
  user can guess where anything lives.
- Layer zero — what is visible while typing — should be radically spare: the text and the barest
  trace of status. Each layer up may show more, and each dismisses cleanly back to zero.
- Keyboard-first users are the loyal core: every existing shortcut keeps working, and the menu
  system should teach the shortcuts as it is used.

PM framing: this is a focus play, not a feature cut. Success is a writer saying "it does less" as
a compliment while nothing was actually removed. Measure the redesign by how little is on screen
during a writing session and how few steps any feature takes from a cold start.

Constraints: same stack (Bun server, vanilla JS, single stylesheet), no new dependencies, all
behavior preserved, existing tests stay green. Menu architecture, visual style, and interaction
model are the implementer's decisions to make and defend.
