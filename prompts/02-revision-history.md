Give Inkwell a revision history: snapshot a post's prior state on every meaningful save, let the
writer browse those snapshots, diff any one against the current text, and restore it.

Why it matters: the editor autosaves as you type, so a bad paragraph, a bad paste, or a delete-key
accident is written to disk within a second and the previous wording is gone forever. Writers cut
hard when they can get it back, and hedge when they cannot.

Where: apps/inkwell/server.ts (revisions table, snapshot points, the four routes),
apps/inkwell/public/app.js + index.html + style.css (history panel, diff view, restore),
apps/inkwell/server.test.ts (new tests).

Done means:
1. A revisions table (id, post_id, title, content, word_count, reason, created_at), created on db
   open by an in-place migration that leaves existing posts intact.
2. PUT /api/posts/:id snapshots the PRE-EDIT row, and only when title or content actually changed —
   a PUT that changes nothing, or only target_word_count, adds no revision.
3. Autosave coalescing: if the post's newest revision has reason 'edit' and is younger than 60
   seconds, overwrite it instead of appending. Twenty keystroke-saves in a row leave one revision.
4. reason is 'edit', 'publish', 'unpublish', or 'restore'; the publish toggle snapshots too.
5. GET /api/posts/:id/revisions returns newest first as {id, created_at, word_count, reason};
   404 for an unknown post.
6. GET /api/posts/:id/revisions/:rev returns the full snapshot, and 404s when that revision belongs
   to a different post.
7. GET /api/posts/:id/revisions/:rev/diff returns an ordered array of {op, text} against the post's
   current content, op being "+", "-", or " ". Identical text yields all " ".
8. POST /api/posts/:id/revisions/:rev/restore snapshots the pre-restore state FIRST, then writes the
   revision's title and content onto the post, bumps updated_at, and returns the updated post — so a
   restore is itself undoable.
9. At most 50 revisions per post; the oldest are pruned. Deleting a post deletes its revisions
   (assert the count is 0 afterwards).
10. UI: a history control in the editor footer opens a panel of revisions with relative time, word
    count and reason; selecting one shows the diff with added and removed lines visually distinct;
    a restore button applies it and refreshes the editor in place.

Constraints:
- Bun + bun:sqlite, no new dependencies, vanilla JS. Write the line diff by hand and make it
  deterministic — same inputs, same array, every run.
- Do not change the GET /api/posts summary shape; the existing exact-key assertion must still pass.
- bun test apps/inkwell/server.test.ts stays green and gains tests for every numbered item.

Out of scope: word-level or character-level inline diffs, three-way merge, branching or named
versions, per-revision authorship or comments, textarea-level undo/redo, changing the autosave
debounce, and diffing two arbitrary revisions against each other.
