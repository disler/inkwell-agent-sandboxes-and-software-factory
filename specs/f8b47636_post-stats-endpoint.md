# Implementation Plan - Single Post Stats Endpoint (`GET /api/posts/:id/stats`)

Add a `GET /api/posts/:id/stats` endpoint to `apps/inkwell/server.ts` returning `{ word_count, reading_minutes, status }` for a single post, returning 404 `{ error: 'not found' }` for unknown IDs, and add automated test coverage in `apps/inkwell/server.test.ts`.

## User Request

Add a GET /api/posts/:id/stats endpoint to apps/inkwell/server.ts returning JSON {word_count, reading_minutes, status} for a single post, using the word-count and reading-time logic already in the file, and 404 {error: 'not found'} for an unknown id. Add a test for it in apps/inkwell/server.test.ts.

## Proposed Changes

### `apps/inkwell/server.ts`

- In `handleApi(req, pathname)`:
  - Handle 4-segment `/api/posts/:id/stats` route (`segments[1] === "posts" && segments.length === 4 && segments[3] === "stats"`).
  - Validate HTTP method is `GET` (return 405 `{ error: "method not allowed" }` otherwise).
  - Retrieve post via `getPost(id)`.
  - Return `notFound()` (404 `{ error: "not found" }`) if post does not exist.
  - Compute word count using existing `wordCount(post.content ?? "")`.
  - Compute reading minutes: `wc === 0 ? 0 : Math.ceil(wc / 200)`.
  - Return 200 JSON `{ word_count: wc, reading_minutes: readingMinutes, status: post.status }`.

### `apps/inkwell/server.test.ts`

- Add a test `GET /api/posts/:id/stats returns post stats and 404 for unknown id`:
  - Create a post with content and verify `word_count`, `reading_minutes`, and `status`.
  - Verify reading minutes for posts with 0 words, <= 200 words, and > 200 words.
  - Verify published post status in stats after publishing.
  - Verify 404 `{ error: "not found" }` response for non-existent post ID.
  - Verify 405 `{ error: "method not allowed" }` for non-GET HTTP methods.

## Verification

Run test suite:
```bash
bun test apps/inkwell/server.test.ts
```
Verify all tests pass with zero failures.
