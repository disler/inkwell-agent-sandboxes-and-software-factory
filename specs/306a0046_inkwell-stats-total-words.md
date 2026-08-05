# Implementation Plan - Extend GET /api/stats with total_words

Extend the `GET /api/stats` endpoint in Inkwell (`apps/inkwell/server.ts`) to return a `total_words` field containing the sum of word counts across all posts in the database, calculated using the existing `wordCount` logic. Add test assertions in `apps/inkwell/server.test.ts`.

## Target Files

- `apps/inkwell/server.ts`
- `apps/inkwell/server.test.ts`

## Proposed Changes

### 1. `apps/inkwell/server.ts`

- In `handleApi` when handling `segments[1] === "stats"` and `method === "GET"`:
  - Query post contents from the SQLite database:
    ```ts
    const posts = db().query("SELECT content FROM posts").all() as { content: string | null }[];
    const total_words = posts.reduce((sum, p) => sum + wordCount(p.content ?? ""), 0);
    ```
  - Include `total_words` in the returned JSON object alongside `total`, `published`, and `drafts`:
    ```ts
    return json({
      total: row.total,
      published: row.published,
      drafts: row.drafts,
      total_words,
    });
    ```

### 2. `apps/inkwell/server.test.ts`

- Update the existing `GET /api/stats` test or add a new test case to verify `total_words`:
  - Assert `typeof initialStats.total_words === "number"`.
  - Create new posts with known content (e.g. `"one two three"` [3 words] and `"four five"` [2 words]).
  - Fetch `GET /api/stats` and verify that `total_words` increases by the sum of words added (5 words).

## Verification

Run test suite:

```bash
bun test apps/inkwell/server.test.ts
```
