Replace Inkwell's naive LIKE post filter with a real SQLite FTS5 full-text index that ranks
results by relevance and returns a highlighted snippet of the matching text.

Why it matters: a writer with two hundred drafts searches for a half-remembered phrase, not a
substring. LIKE '%term%' scans every row, cannot rank, matches inside words, and hands back only a
title — so the writer still opens four posts to find the line they meant.

Where: apps/inkwell/server.ts (schema, triggers, the GET /api/posts query path),
apps/inkwell/public/app.js + index.html + style.css (render the snippet under each hit),
apps/inkwell/server.test.ts (new tests).

Done means:
1. A posts_fts FTS5 virtual table over title and content is created on db open, backfilled once
   from existing rows, and kept current by INSERT/UPDATE/DELETE triggers — create a post, search a
   word in it, and it comes back with no explicit reindex step anywhere.
2. GET /api/posts?q=term (and the ?search= alias) is served by FTS5 and ordered best-match first,
   not updated_at first.
3. Each row of a SEARCH response gains exactly two keys, snippet and rank. snippet is drawn from
   the content around the hit (title when the hit is there) and wraps each matched term in
   <mark>...</mark>.
4. The UNFILTERED list response shape is unchanged. server.test.ts already asserts the exact key
   set of a summary row — id, status, title, updated_at, word_count, target_word_count — and that
   assertion must still pass untouched.
5. Multi-word queries are AND, matching is case-insensitive, and a trailing * prefix-matches.
6. Hostile input returns 200 and an array, never a 500. Test at least: a lone double quote, AND,
   foo NEAR bar), a lone *, and an empty q (empty means the full unfiltered list, unchanged).
7. A query matching nothing returns [].

Constraints:
- Bun + bun:sqlite only. No new dependencies, no package.json edits, vanilla JS on the client.
- If FTS5 is not available in the sqlite Bun links, detect that at db-open time and fall back to
  the current LIKE path while still producing snippet and rank. The contract is identical either
  way and the tests must pass under both.
- Migrate in place: an inkwell.db written before this change must keep working without being
  deleted, and its existing posts must be searchable.
- bun test apps/inkwell/server.test.ts stays green and gains a test for every numbered item above.

Out of scope: searching revisions or deleted posts, status/tag facets or filter chips, fuzzy or
typo-tolerant matching, stemming beyond what FTS5 gives for free, pagination or infinite scroll, a
search endpoint separate from /api/posts, and any change to the editor, view modes, or themes.
