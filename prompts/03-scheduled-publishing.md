Add scheduled publishing: a third post status, 'scheduled', with a publish_at timestamp that turns
a draft into a published post the moment it comes due.

Why it matters: a writer finishes at midnight and wants the post to land Tuesday at 9am. Today the
only lever is a manual toggle, so the choice is publish now or remember later — and the whole
finished queue sits in the same undifferentiated draft pile as the unfinished work.

Where: apps/inkwell/server.ts (publish_at column, the status machine, schedule + sweep routes),
apps/inkwell/public/app.js + index.html + style.css (schedule control, scheduled state in the list),
apps/inkwell/server.test.ts (new tests).

Done means:
1. status is exactly one of draft, scheduled, published. A publish_at column (ISO-8601 UTC, null
   when not scheduled) is added by an in-place migration that leaves existing rows valid.
2. POST /api/posts/:id/schedule with {publish_at} sets status 'scheduled' and stores the timestamp
   normalized to UTC ISO. Missing or unparseable publish_at is 400 {error}; unknown id is 404.
3. DELETE /api/posts/:id/schedule returns the post to draft and nulls publish_at. Calling it on a
   post that is not scheduled is 409 {error}.
4. POST /api/scheduled/run sweeps: every scheduled post whose publish_at is at or before now
   becomes published, keeping publish_at as the record of when. It returns {published: [ids]} and is
   idempotent — a second call immediately after returns {published: []}.
5. The same sweep runs before GET /api/posts and GET /api/posts/:id, so the list is never stale
   without anything scheduled outside the process.
6. The existing toggle still flips draft and published. Publishing a scheduled post cancels its
   schedule; unpublishing a published post clears publish_at.
7. GET /api/posts summary shape is unchanged — status already carries the new state — and the
   existing exact-key assertion must still pass untouched. GET /api/posts/:id includes publish_at.
8. Tests are deterministic by choosing timestamps, not by waiting: schedule in the past then sweep
   and assert published; schedule far in the future then sweep twice and assert it stays scheduled
   and nothing else moved.
9. UI: the post list marks scheduled posts distinctly from drafts and published; the editor footer
   has a datetime-local input plus a schedule button that becomes cancel schedule once set, showing
   the writer's local time while sending UTC.

Constraints:
- Bun + bun:sqlite, no new dependencies, vanilla JS.
- No setInterval, no timers, no background worker, no cron. Due-ness is decided by comparing
  timestamps at request time — that is what makes it testable and what makes it survive a restart.
- Store UTC only. Never store a local-zone string in the db.
- bun test apps/inkwell/server.test.ts stays green and gains tests for every numbered item.

Out of scope: recurring or repeating schedules, a timezone picker, scheduled unpublishing, email or
webhook notification on publish, a calendar or queue view, editing publish_at through PUT
/api/posts/:id, and any external scheduler (cron, systemd, launchd).
