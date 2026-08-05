---
name: sssf-sandbox-orchestrator
description: Drive the six-phase sandbox mount system from the host — mount throwaway exe.dev VMs, run the Super Simple Software Factory inside them, watch from outside, harvest the commits, tear down. Use when the user says mount a sandbox, run the factory in a sandbox, spin up N sandboxes, best-of-N, check on a run, harvest a run's commits, or tear down. Keywords - sandbox, mount, exe.dev VM, run id, fan out, best-of-N, harvest, bundle, teardown, reap.
argument-hint: "[mount|execute|agent|observe|harvest|teardown] [run-id or prompt]"
---

# SSSF Sandbox Orchestrator

Drives the **out-of-sandbox** half of this repo: the `sbx` namespace under `just/sandbox/` that
take a blank exe.dev VM to a health-checked, running factory in ~10s, run work inside it, expose it
to a browser, and — only when a human says so — tear it down.

## The one governing principle: THIN SKILL, FAT RECIPES

**Every action you take should be a `just` command a human could type.** The recipes hold the
knowledge; this skill holds the judgment about which one to run and how to read the result.

- Dropping to `ssh <vm>.exe.xyz '...'` or `curl` to **inspect** is fine and expected — that is what
  `just sbx run cmd <id> '<cmd>'` exists for, and reading a log or a table needs no ceremony.
- Re-implementing what a recipe already does is not. Never hand-roll a key mint, a revoke, an
  `ssh exe.dev new`, a `share port`, or a detached `nohup` launch. Those encode measured facts
  (mint order, the revocation gate, the proxy retarget, the three detachment pieces) and a
  hand-rolled version drops one of them silently.
- If a recipe is wrong, **fix the recipe** and say so. Do not route around it.

## Dependencies

This skill **references** `/sssf` and `/sandbox-exe-dev` rather than duplicating them. `/sssf` owns
the ADW roster, the handoff contract and the trace-db schema; `/sandbox-exe-dev` owns the exe.dev
CLI surface. Both move without asking us, and a copy pasted here would be a second source of truth
that goes wrong quietly — a stale model id, a renamed flag. Read them; do not quote them.

**Preflight is one command.** Run it before the first phase; any failure means report and stop,
never work around a missing prerequisite by hand.

```bash
just sbx manage doctor
```

It checks all six in one pass: `ssh exe.dev` reachable, `OPENROUTER_PROVISIONING_KEY` set (never
printed), the run-record helper runs, the provisioner is executable,
the models template carries full four-field rate blocks, and the `adw` layer resolves. Green ends
with `sbx doctor: OK`.

Two things it does **not** cover, so check them yourself:

| Check | Command | If it fails |
|---|---|---|
| Factory skill | `test -f .claude/skills/sssf/SKILL.md` | the ADWs the sandbox runs come from `/sssf`. Without it there is nothing to mount. |
| VM skill | `test -f .claude/skills/sandbox-exe-dev/SKILL.md` | read it for exe.dev CLI detail instead of guessing flags. |

> **Listing a namespace is `just --list sbx`, not `just sbx --list`.** The latter reads `--list` as a
> recipe name and errors with ``Justfile does not contain recipe `sbx --list` ``. A bare `just sbx`
> also works — it runs the namespace's `default`, which lists.

## Two layers, one credential boundary

| | Out-sandbox (you) | In-sandbox (the VM) |
|---|---|---|
| Lives in | `just/sandbox/`, `sandbox_mount/host/` | `just/adws.just` (`mod adw`), `adws/`, `sandbox_mount/guest/` |
| Entry point | `just sbx mount`, `just sbx lifecycle execute`, `just sbx lifecycle teardown` | `just adw sdlc "..."` |
| Credential | exe.dev account + OpenRouter **provisioning** key | one disposable **runtime** key, $50 cap |

The whole repo ships to the sandbox, this skill included. **What a sandbox cannot do is USE the
out-sandbox half** — `just sbx mount` there fails on a missing exe.dev account, and `create` fails on
a missing `OPENROUTER_PROVISIONING_KEY`. Neither credential ever leaves the host, and that, not file
absence, is what stops a sandbox from mounting sandboxes. Keep the credentials on the host.

## The drive surface

Four groups under `sbx`, plus `mount` at the top because it is the entry point, not a phase:

```
just sbx
├── mount              the chain: create → fill → setup → observe
├── lifecycle          the six phases, for when you need one on its own
├── manage             preflight, readback, fleet ops — nothing here is a phase
├── run                put work in / look inside: `run cmd`, `run agent`
└── orch               boot a host-side orchestrator: `orch cc`, `orch pi`
```

`just sbx`, `just sbx lifecycle`, `just sbx manage`, `just sbx run` and `just sbx orch` each list
their own contents when run bare.

| Command | What it does |
|---|---|
| `just sbx mount RUN_ID [--limit N]` | create → fill → setup → observe. **Never teardown.** Prints the resolved run id and both URLs. |
| `just sbx lifecycle create RUN_ID [--limit N]` | mint `sbx-<run-id>` (\$50 default) + boot the VM, in record → VM → key order |
| `just sbx lifecycle fill RUN_ID [SHA]` | public `git clone` (2.61s, no auth), optional SHA pin, write `.env` with the runtime key |
| `just sbx lifecycle setup RUN_ID` | `provision.sh` + the five-assertion gate |
| `just sbx lifecycle execute RUN_ID "PROMPT"` | full SDLC detached inside the box; returns a pid, records it |
| `just sbx run cmd RUN_ID '<cmd>'` | generic escape hatch, synchronous, runs in `app/`. Your inspection tool. |
| `just sbx run agent RUN_ID "PROMPT"` | Claude Code inside the box, resumable session — hand off, then keep talking |
| `just sbx lifecycle observe RUN_ID` | start both servers, expose 4501, print URLs. Idempotent. |
| `just sbx manage list` | every run record: state, VM alive, spend |
| `just sbx manage harvest RUN_ID` | pull the run's commits home as a git bundle, fetched into `refs/sandbox/<run-id>`. Non-destructive, idempotent, run it any time. |
| `just sbx lifecycle teardown RUN_ID [--no-harvest]` | spend → artifacts → **harvest** → revoke → destroy → close. **The only destructive recipe.** |
| `just sbx manage reap [--yes]` | delete orphaned `sbx-*` keys. Dry run by default. Run it at the start of a session. |

The run id is the handle for every phase. `create` appends `-<date>-<6 hex>` if you did not, and
prints what it settled on — use that string, not the one you typed.

**The five gate assertions** (`setup`): **A** git integrity (`status --porcelain` clean, HEAD
matches the recorded sha) · **B** `pi --list-models` non-empty — *it exits 0
while empty* · **C** every roster model answers a ping · **D** pi reports **non-zero** cost, which
proves the rate table loaded · **E** remaining credit. A failure **reports, stops, and leaves the VM
alive**.

## Cookbooks (lazy-load the one the request calls for)

| Activity | When to read | File |
|---|---|---|
| Understand the recipes before running any | first time, or when a recipe surprises you | [cookbooks/just_command_model.md](cookbooks/just_command_model.md) |
| Stand up one sandbox end to end | "mount a sandbox", "run this in a sandbox" | [cookbooks/mount_one.md](cookbooks/mount_one.md) |
| Put work into a mounted box | "build X in there", "ask the agent", picking `run cmd` vs `lifecycle execute` vs `run agent` | [cookbooks/execute_work.md](cookbooks/execute_work.md) |
| Watch a run and report it back | "check on the run", "is it done", "show me the URLs" | [cookbooks/observe_and_report.md](cookbooks/observe_and_report.md) |
| Give the user access to a running box | "get me into the sandbox", a shell in there, talk to the in-box agent | [cookbooks/access_a_running_sandbox.md](cookbooks/access_a_running_sandbox.md) |
| A gate assertion failed | `setup` exited non-zero, or the box looks wrong | [cookbooks/debug_a_failed_gate.md](cookbooks/debug_a_failed_gate.md) |
| Spin up N and pick a winner | "best-of-N", "three variants", "diff the runs" | [cookbooks/fan_out_n.md](cookbooks/fan_out_n.md) |
| Shut a run down, clean up keys | the human decided to tear down; orphaned `sbx-` keys | [cookbooks/teardown_and_reap.md](cookbooks/teardown_and_reap.md) |

## References (deep specs, read on demand)

| Reference | Covers |
|---|---|
| [references/phases.md](references/phases.md) | what each of the six phases does, in order, and why the order is that order |
| [references/kickoff_paths.md](references/kickoff_paths.md) | the two ways work enters a box: direct (`lifecycle execute`, a command) vs agent-mediated (`run agent`, a delegation) |
| [references/run_record.md](references/run_record.md) | `.sandbox/runs/<id>.json` — the closed schema, who writes each field, who reads it |
| [references/models.md](references/models.md) | the roster, per-million rates, the mandatory four-field `cost` block, ZDR |
| [references/gotchas.md](references/gotchas.md) | every trap that cost a debugging cycle, with the symptom it produces |

## Hard rules

1. **Never decide teardown.** Report what the run produced, what it cost, and recommend — the human
   decides. `mount` stops at `observe` on purpose and nothing chains into `teardown`. A VM left
   running is a bill; a VM destroyed early is the evidence and the artifacts, gone. **`harvest` is
   the exception you may run freely** — it only reads the box and only writes `refs/sandbox/`, so
   run it as soon as a run commits rather than letting the commits wait on a teardown decision.
2. **Never run ADWs on the host.** `just adw sdlc "..."` here runs the factory on the engineer's
   laptop — the exact collision this system exists to remove. Work goes in through
   `just sbx lifecycle execute` / `just sbx run agent`, always.
3. **A gate failure means STOP and diagnose, never destroy.** The VM is left alive deliberately.
   Read the failing assertion, `just sbx run cmd <id> '...'` your way to the cause, fix it, re-run
   `just sbx lifecycle setup`. Re-running setup is safe.
4. **Never touch a key.** The runtime key lives at `.sandbox/runs/<id>.key` (0600) and inside the
   VM's `app/.env`. Never print it, never copy it, never pass it over ssh — `setup`'s gate spends it
   from inside the box for exactly that reason. The provisioning key never leaves the host.
5. **Never mint outside `create`.** The `sbx-` prefix is the entire safety model for `reap`; the
   engineer's personal keys carry no prefix and deleting one is unrecoverable.
6. **Report the run id every time.** It is the only handle the next phase, the next session, and
   `teardown` have.
