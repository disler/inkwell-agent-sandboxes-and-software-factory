---
description: Prime context for Inkwell — the app, the Super Simple Software Factory that builds it, and the sandbox mount system that runs both on throwaway VMs.
---

# Purpose

Orient yourself in a three-layer system: **Inkwell** (a small blog-writing app), the **Super Simple Software Factory** (deterministic Python owns the graph, coding agents are bounded phases inside it), and the **sandbox mount system** (six host-side phases that stand the whole thing up on a disposable exe.dev VM, run it, and watch it from outside). The app is the payload; the point is the loop that ships it without a human in the middle.

## Workflow

1. Map the surface first, because it is the fastest way to see the shape: `just` (four namespaces, nothing else), then `just --list sbx`, `just --list adw`, `just --list obs`, `just --list local`. The namespace answers *where the work happens*: `sbx` orchestrates VMs from the host, `adw` runs the workflows, `local` boots an orchestrator agent on this machine, `obs` reads the trace db. Then `git ls-files | head -60` and `ls sandbox_mount/host sandbox_mount/guest just/sandbox`.

2. Read `TREE.md` — every file that matters and why it exists, grouped by layer, ending with the
   five things that will bite you. It is the map; the rest of this workflow is the territory. Then
   `README.md` for the three layers, then `specs/sandbox-mount-system.html` — **the plan is the working checklist**, with live checkboxes recording what has actually been verified on hardware versus what is still theory. Open it in a browser or read the `data-ck="... checked"` attributes. Treat an unchecked box as "not proven", not "not written".

3. Read `ai_docs/exedev_sandbox_mounting.md` — every number in it was measured on live VMs, and several "obvious" designs were killed by those measurements (a custom Docker image buys ~1s; `--setup-script` cannot see `--env`; an unsynced `ssh exe.dev cp` silently produced 5,641 zero-byte files). Do not re-derive these; do not contradict them without a new measurement.

4. Read `justfile` and `just/sandbox/mod.just`. This is the load-bearing idea: `just/sandbox/` and `sandbox_mount/host/` are **host-only** — not because they are removed from the mounted copy (the whole repo ships intact) but because they need the exe.dev account and `OPENROUTER_PROVISIONING_KEY`, and neither credential ever leaves the host. A sandbox that runs `just sbx mount` gets an auth failure, not a nested VM.

5. Walk one phase end to end: `just/sandbox/create.just` (strict order — record, then VM, then key, so a crash always leaves teardown a handle) and `sandbox_mount/host/run_record.py` (the only state shared across the six phases, since each is a separate process). Then skim `sandbox_mount/guest/provision.sh`, which runs *inside* the VM and installs bun, just and the trace db.

6. Read `.claude/skills/sssf-sandbox-orchestrator/SKILL.md` and its `references/gotchas.md`. The governing rule is **thin skill, fat recipes**: every action should be a `just` command a human could type. Dropping to `ssh`/`curl` to *inspect* is fine; re-implementing mint, revoke, or port logic is not. `cookbooks/just_command_model.md` explains why modules inherit nothing and what each missing `set` line silently breaks.

7. Read `.claude/skills/sssf/SKILL.md` and `adws/adw_sssf_config/sssf.config.yaml` for the factory itself and its roster. Every model is `openrouter/<id>`; the roster runs entirely through OpenRouter on a disposable per-sandbox key (`$50` default, revoked at teardown). Models carry a **four-field** `cost` block — a partial one fails schema validation and pi silently drops the entire roster, and with no rates pi reports `$0.0000` forever while genuinely spending.

8. Check live state before acting: `just sbx manage doctor` (host prerequisites), `just sbx manage list` (sandboxes and whether their VMs are alive), and `ssh exe.dev ls --json` (ground truth). A sandbox hosts **many** ADW runs — `just sbx manage list` counts sandboxes, `just obs sessions` counts runs inside one. Never run `just sbx lifecycle teardown` unless asked: it is always an explicit human decision, and it is the one phase not yet exercised.

9. Summarize your understanding: the three layers, the four namespaces, what the credential boundary protects, what is verified versus outstanding, and the entry points you would use next. Then stop and wait for a request rather than surveying further.
