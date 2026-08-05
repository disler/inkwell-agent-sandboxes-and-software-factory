Give every published post a public read-only permalink at /p/:slug — a standalone server-rendered
page with no editor on it.

Why it matters: publish is currently a flag with nowhere to point. There is no URL a writer can
send to a reader, and the only way to see the finished piece is inside the editor chrome that
produced it. A permalink is what makes the publish button mean something.

Where: apps/inkwell/server.ts (slug column, the /p/ route, the page template),
apps/inkwell/public/markdown.js (extracted renderer), apps/inkwell/public/app.js + index.html +
style.css (permalink link, read-view styles), apps/inkwell/server.test.ts (new tests).

Done means:
1. A slug TEXT UNIQUE column derived from the title on create and on title change: lowercased,
   runs of non-alphanumerics collapsed to a single dash, trimmed of leading and trailing dashes,
   capped at 80 characters, empty result becomes "post". Collisions append -2, -3, and so on.
   Existing rows are backfilled by an in-place migration.
2. GET /p/:slug returns 200 text/html for a PUBLISHED post: title, the rendered markdown body,
   word count, reading time, and the published date. No editor markup, no app.js.
3. A draft, a scheduled post, or an unknown slug returns 404 with an HTML body — never JSON, never
   any fragment of the unpublished content.
4. The page is rendered server-side through THE SAME markdown code path as the editor preview.
   Move the renderer out of public/app.js into public/markdown.js as an ES module and import it
   from both; app.js is already loaded as type="module". This is the one existing test you may
   touch: "preview rendering: markdown section renders headings, inline marks, lists, code" loads
   that section out of app.js, so repoint it at markdown.js. Change nothing else in the existing
   tests.
5. Content is escaped: a post whose body contains <script>alert(1)</script> serves &lt;script&gt;,
   asserted against the bytes the route actually returns.
6. The page links style.css and honors the same theme tokens, including the inline localStorage
   theme bootstrap, so a dark-mode reader is not flashed white.
7. GET /api/posts/:id includes slug, and the editor shows a permalink that is live only while the
   post is published and opens in a new tab.
8. Unpublishing makes the URL 404 again; republishing serves it again at the same slug.

Constraints:
- Bun + bun:sqlite, no new dependencies, no template engine — build the HTML with a template
  literal in server.ts and escape every interpolated value.
- /p/ resolves before the static file handler and must not become a path traversal: a slug
  containing .. or / is a 404, not a file read.
- /api/* behavior and static serving are otherwise untouched.
- bun test apps/inkwell/server.test.ts stays green and gains tests for every numbered item.

Out of scope: RSS or Atom feeds, a sitemap, an index page listing all published posts, comments,
OpenGraph or Twitter meta tags, custom domains, hand-editing a slug from the UI, caching headers or
ETags, and analytics of any kind.
