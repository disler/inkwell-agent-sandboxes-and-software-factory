# Total Words Field in GET /api/stats

## Summary of Changes
The `GET /api/stats` endpoint in the Inkwell server (`apps/inkwell/server.ts`) has been extended to include a `total_words` field in its JSON response. This field aggregates the word count across all posts stored in the database (both drafts and published) using the server's existing `wordCount` helper function.

## Changed Files
- **`apps/inkwell/server.ts`**:
  - Updated `GET /api/stats` handler to query `content` from all posts in the database (`SELECT content FROM posts`).
  - Computed total word count by aggregating `wordCount(p.content ?? "")` across all posts.
  - Added `total_words` to the returned JSON payload alongside `total`, `published`, and `drafts`.
- **`apps/inkwell/server.test.ts`**:
  - Updated the `GET /api/stats` integration test to check that `total_words` is returned as a number.
  - Added post creation with content ("hello world" and "one two three") to verify that `total_words` correctly increments by 5.
- **`specs/306a0046_inkwell-stats-total-words.md`**:
  - Specification tracking file for the `total_words` stats endpoint extension.

## Usage & Verification

### Endpoint Response
Calling `GET /api/stats` returns an updated response schema:

```json
{
  "total": 2,
  "published": 1,
  "drafts": 1,
  "total_words": 5
}
```

### Running Tests
Verify the implementation by running the test suite with Bun:

```bash
bun test apps/inkwell/server.test.ts
```
