# Single Post Stats Endpoint (`GET /api/posts/:id/stats`)

## Overview
Added a new API endpoint `GET /api/posts/:id/stats` to the Inkwell server (`apps/inkwell/server.ts`). The endpoint returns reading statistics and post status in JSON format (`{ word_count, reading_minutes, status }`) for an individual post specified by ID. Unknown post IDs return a 404 error response (`{ error: "not found" }`).

## What Changed

### 1. Server Route Implementation (`apps/inkwell/server.ts`)
- Added route handling inside `handleApi` for paths matching 4 URL segments ending in `stats` (`/api/posts/:id/stats`).
- Enforces `GET` method; returns 405 (`{ error: "method not allowed" }`) for other HTTP methods.
- Fetches post by ID using `getPost(id)`; returns 404 (`{ error: "not found" }`) if missing.
- Computes statistics using existing helper functions:
  - `word_count`: derived from `wordCount(post.content ?? "")`.
  - `reading_minutes`: `0` if `word_count` is 0, otherwise `Math.ceil(word_count / 200)`.
  - `status`: post status string (`draft` or `published`).

### 2. Test Coverage (`apps/inkwell/server.test.ts`)
- Added `/posts/${missing}/stats` to the unknown route 404 validation test array.
- Added a dedicated test `GET /api/posts/:id/stats returns post stats and 404 for unknown id` covering:
  - Empty posts (0 words, 0 reading minutes).
  - Short posts (150 words, 1 reading minute).
  - Longer posts (250 words, 2 reading minutes).
  - Status updates reflecting post publication.
  - 404 responses for non-existent post IDs.
  - 405 responses for non-GET requests.

### 3. Specification Document (`specs/f8b47636_post-stats-endpoint.md`)
- Created implementation specification outlining user requirement, planned server/test edits, and verification commands.

## How to Verify
Run the Inkwell server test suite using `bun`:
```bash
bun test apps/inkwell/server.test.ts
```
