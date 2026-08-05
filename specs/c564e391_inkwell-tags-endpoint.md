# Plan: Add GET /api/tags Endpoint to Inkwell Server

## Summary
Implement a new `GET /api/tags` endpoint in `apps/inkwell/server.ts` that returns a JSON object `{ tags: [{ tag: string, count: number }] }`. The tags are aggregated across all posts in the database:
- If posts have a `tags` column, comma-separated tags are extracted and counted.
- If posts do not have a `tags` column (or a post's `tags` value is missing/empty), tags are derived from hashtags in the post's `title` (e.g. `#tech` -> `tech`).
- Each post contributes at most 1 count to any distinct tag it carries.
- The results are sorted by `count` descending, then by `tag` ascending (alphabetical).
- Unhandled HTTP methods on `/api/tags` return 405 `{"error": "method not allowed"}`.
- Sub-paths under `/api/tags/...` return 404 `{"error": "not found"}`.

## Files to Touch
1. `apps/inkwell/server.ts`
2. `apps/inkwell/server.test.ts`

## Step-by-Step Implementation Instructions

### 1. Update `apps/inkwell/server.ts`
In `handleApi(req, pathname)`:
- Add a handler block for `segments[1] === "tags"` before checking `segments[1] !== "posts"`:
  ```ts
  if (segments[1] === "tags") {
    if (segments.length === 2) {
      if (method === "GET") {
        const tableInfo = db().query("PRAGMA table_info(posts)").all() as { name: string }[];
        const hasTagsColumn = tableInfo.some((col) => col.name === "tags");

        const posts = hasTagsColumn
          ? (db().query("SELECT title, tags FROM posts").all() as { title: string | null; tags?: string | null }[])
          : (db().query("SELECT title FROM posts").all() as { title: string | null });

        const tagCounts: Record<string, number> = {};

        for (const post of posts) {
          const postTags = new Set<string>();

          if (
            hasTagsColumn &&
            typeof (post as { tags?: string | null }).tags === "string" &&
            (post as { tags: string }).tags.trim() !== ""
          ) {
            const rawTags = (post as { tags: string }).tags.split(",");
            for (const rawTag of rawTags) {
              const trimmed = rawTag.trim();
              if (trimmed) {
                postTags.add(trimmed);
              }
            }
          } else {
            const title = post.title ?? "";
            const hashtagMatches = title.match(/#([^\s#]+)/g) || [];
            for (const match of hashtagMatches) {
              const tag = match.slice(1).replace(/[.,!?:;'"()\[\]{}]+$/, "").trim();
              if (tag) {
                postTags.add(tag);
              }
            }
          }

          for (const tag of postTags) {
            tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
          }
        }

        const tags = Object.entries(tagCounts)
          .map(([tag, count]) => ({ tag, count }))
          .sort((a, b) => {
            if (b.count !== a.count) {
              return b.count - a.count;
            }
            return a.tag.localeCompare(b.tag);
          });

        return json({ tags });
      }
      return json({ error: "method not allowed" }, 405);
    }
    return notFound();
  }
  ```

### 2. Update `apps/inkwell/server.test.ts`
Add test cases testing `/api/tags`:
- `GET /api/tags` returns tags derived from title hashtags when no `tags` column is used.
  - Verify exact sorting: higher count first, ties sorted alphabetically.
  - Verify formatting `{ tags: [{ tag: "bun", count: 2 }, ...] }`.
- `GET /api/tags` when `tags` column exists in table (add `tags` column via `ALTER TABLE posts ADD COLUMN tags TEXT` in a test or test post with tags column if present).
- `GET /api/tags` returns `{ tags: [] }` when no posts or no tags exist.
- Non-GET methods (e.g. `POST /api/tags`) return status 405.

### 3. Verification
Run test suite:
```bash
bun test
```
Confirm all tests pass cleanly.

## Notes for Next Agent
- Ensure `bun test` is executed to validate tests pass.
- Do not alter existing API endpoints or static server functionality in `apps/inkwell/server.ts`.
