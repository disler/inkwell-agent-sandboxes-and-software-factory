# Inkwell `GET /api/tags` Endpoint

This update adds a `GET /api/tags` HTTP endpoint to the Inkwell server (`apps/inkwell/server.ts`), enabling client applications to inspect distinct tags used across all posts along with their frequency counts.

---

## What Changed and Why It Matters

Inkwell now provides a centralized endpoint for retrieving tag metadata across all blog posts. The endpoint dynamically supports both explicit `tags` column data and title-embedded hashtags (`#tag`), allowing tag discovery regardless of database schema evolution.

### Key Features
1. **Schema-Aware Tag Extraction**:
   - Queries `PRAGMA table_info(posts)` to detect whether a `tags` column exists in the database.
   - **Explicit Tags**: If the `tags` column exists and contains non-empty comma-separated tags (e.g., `"tech, bun"`), tags are parsed and trimmed.
   - **Hashtag Fallback**: If no `tags` column exists (or a post's `tags` field is null/empty), hashtags are extracted from the post's `title` using `#([^\s#]+)` with trailing punctuation removed.
2. **Frequency Aggregation & Deduplication**:
   - Each post contributes at most a count of `1` to any distinct tag it carries (using a per-post `Set<string>`).
3. **Deterministic Sorting**:
   - Returns array of `{ tag: string, count: number }` sorted primarily by `count` descending, then alphabetically by `tag` ascending for ties.
4. **HTTP Status Code Compliance**:
   - Returns HTTP 200 `{ tags: [...] }` on success or when no posts/tags exist (`{ tags: [] }`).
   - Returns HTTP 405 `{"error": "method not allowed"}` for non-`GET` HTTP methods to `/api/tags`.
   - Returns HTTP 404 `{"error": "not found"}` for subpaths such as `/api/tags/foo`.

---

## Files Changed

| File | Changes |
| --- | --- |
| `apps/inkwell/server.ts` | Added `/api/tags` handler in `handleApi`, including `PRAGMA` schema check, hashtag title parsing, tag count aggregation, sorting logic, 405 method guard, and 404 subpath guard. |
| `apps/inkwell/server.test.ts` | Added tests verifying `GET /api/tags` behavior across empty tables, title hashtags, explicit `tags` column schema modifications, and 405/404 error responses. |
| `specs/c564e391_inkwell-tags-endpoint.md` | Created engineering specification and step-by-step plan for the feature. |

---

## How to Use and Verify

### Running Tests
Execute the Inkwell test suite using Bun:

```bash
bun test apps/inkwell/server.test.ts
```

### Example Usage

#### Endpoint Request
```bash
curl -X GET http://localhost:3000/api/tags
```

#### Example Response JSON
```json
{
  "tags": [
    { "tag": "tech", "count": 3 },
    { "tag": "bun", "count": 2 },
    { "tag": "javascript", "count": 2 },
    { "tag": "sqlite", "count": 1 }
  ]
}
```
