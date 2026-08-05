Make Inkwell's posts portable: export one post as a markdown file with front matter, export every
post as a single bundle, and import either one back.

Why it matters: the writing lives in one sqlite file with no way out. A writer who wants to move a
draft into another tool, keep a copy in a git repo, or move machines has to select-all-copy post by
post — and an app you cannot leave is an app you hesitate to commit to.

Where: apps/inkwell/server.ts (export routes, import route, front-matter parse and serialize),
apps/inkwell/public/app.js + index.html + style.css (export buttons, file input),
apps/inkwell/server.test.ts (new tests).

Done means:
1. GET /api/posts/:id/export returns 200 text/markdown: a --- delimited front-matter block holding
   title, status, created_at, updated_at and target_word_count, one blank line, then the content
   verbatim. Content-Disposition names a slugified .md file. Unknown id is 404 {error: "not found"}.
2. GET /api/export returns 200 application/json: {version: 1, exported_at, posts: [...]} with the
   full row for every post.
3. POST /api/import with content-type text/markdown parses one document and returns 201
   {imported: 1, ids: [id]}.
4. POST /api/import with content-type application/json accepts a bundle and returns 201
   {imported: n, ids: [...]} in bundle order.
5. Import ALWAYS creates new rows with new ids. It never overwrites, never matches on id or title,
   and importing the same file twice yields two independent posts.
6. The round-trip law holds: export a post, import those exact bytes, and the new post's title,
   content, target_word_count and status equal the original's. Prove it on content that contains a
   bare --- line, a fenced code block, a colon in the title, non-ASCII characters, and a trailing
   newline.
7. Malformed input is 400 {error}: a markdown body with no front-matter block, an unterminated one,
   a bundle with the wrong version, and a bundle whose posts is not an array.
8. Fields missing from front matter fall back to the same defaults POST /api/posts uses — title
   "Untitled", status draft, target_word_count 0.
9. UI: an export button in the editor footer downloads the current post as .md, an export-all
   control in the sidebar footer downloads the bundle, and an import file input accepts .md and
   .json, posts it, and refreshes the list to show what arrived.

Constraints:
- Bun + bun:sqlite, no new dependencies, vanilla JS. Downloads go through Blob and
  URL.createObjectURL; no shell-outs, no filesystem writes outside the db.
- Write the front-matter parser by hand and keep it flat key: value only — no YAML library, no
  nesting, lists, anchors or multi-line scalars. Values containing a colon must survive intact.
- Only the FIRST --- block at byte zero is front matter; a --- later in the body is content.
- bun test apps/inkwell/server.test.ts stays green and gains tests for every numbered item.

Out of scope: zip archives, images or media, importing Jekyll/Hugo/WordPress/Notion formats,
update-in-place or merge-on-conflict import, scheduled or automatic backups, drag-and-drop upload,
and any change to how posts are stored.
