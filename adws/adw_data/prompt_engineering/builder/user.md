# Build Task

## Variables

### prompt

{{prompt}}

### previous_envelope

{{previous_envelope}}

### context_handoff_dir

{{context_handoff_dir}}

## Task

Implement the work described in `prompt`, guided by `previous_envelope` if present, then emit your `Report` JSON.

## Report

Respond with ONLY valid JSON matching `BuildOutput` — no prose before or after:

```json
{
  "status": "success",
  "summary": "<one sentence describing what you built>",
  "changed_files": ["src/server.ts"],
  "artifacts": [],
  "commit_message": "<imperative one-line git subject for the code you changed — this is what the commit of your work will say>",
  "notes_for_next_agent": "<how to verify this work>"
}
```
