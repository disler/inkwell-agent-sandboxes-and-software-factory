# inkwell
Minimalist blog-writing app — drafts, an editor, one-click publish. Bun + `bun:sqlite`, zero dependencies.

Drafts autosave as you type.

- **Tech stack:** Bun, SQLite (`bun:sqlite`), vanilla JS
```bash
bun run server.ts   # http://localhost:4501 — PORT and INKWELL_DB env overrides
bun test            # end-to-end API suite against a temp db
```
| Method | Route | Does |
| --- | --- | --- |
| GET | `/api/posts` | List `{id, title, status, updated_at, word_count, target_word_count}`, newest updated first (supports `?q=term` / `?search=term`) |
| POST | `/api/posts` | Create a draft from `{title?, content?, target_word_count?}` |
| GET | `/api/posts/:id` | Full post |
| PUT | `/api/posts/:id` | Update `{title?, content?, target_word_count?}` |
| POST | `/api/posts/:id/publish` | Toggle draft ⇄ published |
| DELETE | `/api/posts/:id` | Delete → `{ok: true}` |

## Keyboard Shortcuts

- `Cmd+N` / `Ctrl+N`: Create new post
- `Cmd+S` / `Ctrl+S`: Save current post
- `Cmd+Enter` / `Ctrl+Enter`: Cycle view mode (edit → split → preview)
- `Cmd+Shift+F` / `Ctrl+Shift+F`: Toggle focus mode
- `Cmd++` / `Ctrl++`: Increase editor font size
- `Cmd+-` / `Ctrl+-`: Decrease editor font size
- `?` or `Cmd+/` / `Ctrl+/`: Open/toggle keyboard shortcuts help modal
- `Esc`: Close keyboard shortcuts help modal / exit focus mode

Action buttons feature visual key shortcut hints (`<kbd>`) for quick reference, and an interactive keyboard shortcuts modal is accessible via the `shortcuts ?` footer button or `?` / `Cmd+/` shortcut.

## Sidebar UI

- **Search Filter**: Includes a search text input (`#search-input`) above the post list to filter posts by title and content as you type, displaying a live result count (`#search-count`) and a clear button (`#search-clear`) to restore the full list.
- **Sidebar Footer**: Displays total post count and aggregate word count across all posts.
- **Editor Footer**: Displays active post word count, estimated reading time, writing target goal input, live progress percentage indicator, and auto-save status (`saved`/`saving`), alongside post controls (font size adjusters, focus mode toggle, keyboard shortcuts help, view-mode switch, publish/unpublish toggle, and delete post action).

## View Modes

- **edit**: textarea only.
- **split**: editor on the left, live-rendered markdown preview on the right, with a divider and `MARKDOWN` / `PREVIEW` pane labels; the preview updates on every keystroke.
- **preview**: rendered output only.

Cycle with `Cmd+Enter` / `Ctrl+Enter` or click the footer `mode-switch` buttons. The chosen mode persists while switching posts. Below ~860px viewport width, split mode stacks the panes vertically.

