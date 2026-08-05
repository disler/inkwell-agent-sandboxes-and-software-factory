# Document Task

## Variables

### prompt

{{prompt}}

### previous_envelope

{{previous_envelope}}

### context_handoff_dir

{{context_handoff_dir}}

## Task

Document the completed work described by `previous_envelope`, using `prompt` for what was originally asked.

1. Read the full diff at `previous_envelope.diff_path`, plus any changed file that needs context.
2. Write the write-up to `<context_handoff_dir>/document.md`. Cover: what changed and why it matters, the files that carry it, and how to use or verify it.
3. Copy that file into the repo under `app_docs/`:
   - **List `app_docs/` before you pick the name.** A session that documents more than once reuses its `<adw_id>`, so the obvious name may already be taken.
   - Base name: `app_docs/<adw_id>_<slug>.md`, where `<adw_id>` is the session directory name inside `context_handoff_dir` (`.../sessions/<adw_id>/context_handoff`) and `<slug>` is two to four kebab-case words naming the work.
   - If a file with that name already exists, use `app_docs/<adw_id>_<slug>_v2.md`, then `_v3`, and so on until the name is free. **Never overwrite an existing write-up** — it describes a change that already shipped.
   - **Copy it, do not retype it.** One bash call does the whole step:
     `mkdir -p app_docs && cp "<context_handoff_dir>/document.md" "app_docs/<adw_id>_<slug>.md"`
     Writing the document a second time through `write` re-emits every line you already wrote, which costs the whole write-up again in output tokens and lets the two copies drift.
4. Emit your `Report` JSON, declaring BOTH paths in `artifacts`.

## Report

Respond with ONLY valid JSON matching `DocumentOutput` — no prose before or after:

```json
{
  "status": "success",
  "summary": "<one sentence describing what you documented>",
  "document_path": "app_docs/<adw_id>_<slug>.md",
  "documented_files": ["src/server.ts"],
  "artifacts": ["<context_handoff_dir>/document.md", "app_docs/<adw_id>_<slug>.md"],
  "commit_message": "<imperative one-line git subject for committing THIS WRITE-UP, not the change it describes — e.g. 'Document the /health endpoint'>",
  "notes_for_next_agent": "<anything the diff left unexplained>"
}
```

`document_path` and the `app_docs/` entry in `artifacts` are the path you ACTUALLY wrote, `_v2` suffix and all. Gates open these files — a name you meant to use fails them.
