# Scout Task

## Variables

### prompt

{{prompt}}

### previous_envelope

{{previous_envelope}}

### context_handoff_dir

{{context_handoff_dir}}

## Task

Find what `prompt` asks about. Write findings into `context_handoff_dir`, then emit your `Report` JSON.

## Report

Respond with ONLY valid JSON matching `ScoutOutput` — no prose before or after:

```json
{
  "status": "success",
  "summary": "<one sentence on what you found>",
  "findings": [
    { "file": "src/server.ts", "note": "<why this file matters>" }
  ],
  "artifacts": ["<context_handoff_dir>/scout_findings.md"]
}
```
