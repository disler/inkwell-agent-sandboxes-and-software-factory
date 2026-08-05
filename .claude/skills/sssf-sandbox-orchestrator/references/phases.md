# The six-phase contract

Two layers, one repo. Which layer a file belongs to is decided by one question:
**what credential does it need?**

| | OUT-sandbox (orchestration) | IN-sandbox (execution) |
| --- | --- | --- |
| Lives in | `just/sandbox/`, `sandbox_mount/host/` | `just/adws.just` (`mod adw`), `adws/`, `sandbox_mount/guest/` |
| Runs on | your machine | the VM |
| Credential | exe.dev account + `OPENROUTER_PROVISIONING_KEY` | the disposable runtime key only |
| Entry point | `just sbx mount` / `lifecycle execute` / `lifecycle teardown` | `just adw sdlc "..."` |

The entire repo ships to the sandbox — orchestration recipes, host scripts and skills included.
The boundary is enforced by **credentials, not by deletion**: the exe.dev account and
`OPENROUTER_PROVISIONING_KEY` never leave the host, so a sandbox that tries `just sbx mount` gets
an auth failure rather than a nested VM. Nothing is stripped, which is why the sandbox's working
tree stays clean and a harvested branch carries only the run's own work.

---

## The contract

| Phase | Runs where | Needs | Gate | Writes to the run record |
| --- | --- | --- | --- | --- |
| **create** `RUN_ID [--limit N]` | host only — exe.dev control plane + OpenRouter mint API. Nothing lands on the VM. | `ssh`, `curl`, `python3` on PATH; `OPENROUTER_PROVISIONING_KEY` in `.env`; hostname-safe run id (≤63 chars) | ssh answers on `<vm>.exe.xyz` within 60s | `run_id`, `created_at`, `vm_name`, `https_url`, `key_hash`, `limit`, `session_id` |
| **fill** `RUN_ID [SHA]` | host-triggered, the clone runs inside the VM | `vm_name` in the record; `.sandbox/runs/<id>.key` non-empty | checked-out HEAD == the resolved pin (when a SHA/tag/branch was given). Unpinned: HEAD is reported and recorded, not gated | `commit_sha` |
| ↳ *the run branch* | inside, at the end of the clone step | — | none — `git switch -c sbx/<run-id>` at existing HEAD adds no commit and changes no file, so assertion **A** still compares the same sha | *nothing* |
| **setup** `RUN_ID` | inside — `ssh <vm> 'bash app/sandbox_mount/guest/provision.sh'`, then the gate | `vm_name` **and** `commit_sha` in the record | five assertions **A–E**, all must pass | *nothing* |
| **execute** `RUN_ID "PROMPT"` | host-triggered, `just adw sdlc` runs inside, detached | `vm_name` in the record; a passed SETUP | the remote shell returns a numeric PID (non-numeric = the remote printed an error where the PID should be) | `pid` |
| **observe** `RUN_ID` | host + VM — starts both servers, retargets the proxy | `vm_name`; `adws/adw_data/sssf.db` present on the VM (the visualizer exits without it) | app returns **200 anonymously**; obs port is reachable (anything that is not `000` and not `5xx`) | `ports` |
| **teardown** `RUN_ID` | host only, and only when we decide | the record (hard prerequisite — it is the only handle on the key); `OPENROUTER_PROVISIONING_KEY` if `key_hash` is set | `key_hash` is **absent from `GET /api/v1/keys`** — the LIST, never `/api/v1/key` | `spend`, `closed_at` |

Three recipes sit outside the phase list and write nothing to the record:

| Recipe | Shape | Notes |
| --- | --- | --- |
| `just sbx run cmd RUN_ID '<cmd>'` | synchronous, prints output, `cd app &&` first | generic escape hatch. `{{CMD}}` is interpolated verbatim so your pipes/globs/quotes reach the remote shell intact |
| `just sbx manage harvest RUN_ID` | synchronous, reads the box, writes `refs/sandbox/<run-id>` | bundles `<commit_sha>..sbx/<run-id>` on the VM, copies it to `.sandbox/runs/<id>.bundle`, verifies, fetches. **Non-destructive and idempotent** — run it the moment a run commits, don't wait for teardown. Writes nothing to the record: the bundle's existence *is* the record, same as `.agent-started`. A run filled before run branches existed gets `sbx/<run-id>` created at HEAD, which touches no files |
| `just sbx run agent RUN_ID "PROMPT"` | synchronous Claude Code turn inside the box | reads `session_id`; first call uses `--session-id`, every later one `--resume`. "Has it started" is a **host sentinel** `.sandbox/runs/<id>.agent-started`, touched only after a successful turn — the record schema is closed and has nowhere to put a boolean, and probing the VM's session layout would depend on an unverified implementation detail. Runs on exe.dev's key-free gateway (`ANTHROPIC_BASE_URL=https://llm.int.exe.xyz`, `ANTHROPIC_API_KEY=implicit`), **not** OpenRouter |

And the fleet-wide backstop, which takes no run id:

`just sbx manage reap [--yes]` — dry run by default. Joins the OpenRouter key list × `ssh exe.dev ls --json`
× `.sandbox/runs/*.json` and revokes every `sbx-*` key whose record is closed or whose VM no
longer exists. **The `sbx-` prefix is the entire safety model**: personal keys carry no prefix,
and the prefix is re-asserted at the point of deletion, not just at selection.

---

## Readback: `just/sandbox/manage/list.just`

Launching N sandboxes is the easy half of best-of-N; the decision needs the results side by side.
This is a pure read over the run records plus one control-plane call.

| Recipe | Columns | Sources |
| --- | --- | --- |
| `just sbx manage list` | RUN, STATE (`open`/`closed` from `closed_at`), VM (`up`/`gone`/`?`), SPEND, CREATED | `run_record.py list` + **one** `ssh exe.dev ls --json` call for the whole table. `?` is deliberately distinct from `gone` — a failed control-plane lookup must never render as "every VM is destroyed" |

Formatting happens in `sandbox_mount/host/runs_table.py`, not a shell read-loop, for two reasons:
an unindented line inside a just recipe body terminates the recipe, so embedded python is a parse
error waiting to happen; and the record has legitimately-empty fields (`spend` is null until
teardown) which a tab-delimited read-loop mis-assigns — that showed up as the vm name landing in
the SPEND column.

---

## Booting an agent: `just/sandbox/orch/mod.just`

There are two levels, and booting the wrong one is the classic mistake.

| Level | Recipes | Reads | Belongs |
| --- | --- | --- | --- |
| **Factory** | `just local cc` / `pi` / `ipi` | `.claude/skills/sssf/SKILL.md` | **inside** a sandbox. Running it on the host runs the factory on your laptop, which is the one thing this system exists to prevent |
| **Orchestration** | `just sbx orch cc` / `just sbx orch pi` | `.claude/skills/sssf-sandbox-orchestrator/SKILL.md` | the **host**, and only the host — it needs the exe.dev account and the provisioning key, neither of which reaches a sandbox |

`just sbx run agent RUN_ID "<prompt>"` talks to the factory orchestrator already running *inside* a
mounted sandbox, over ssh, in a resumable session — so you can keep steering without ssh-ing in
yourself.

---

## The five gate assertions (SETUP)

| | Assertion | Why it exists |
| --- | --- | --- |
| **A** | `git status --porcelain` clean **and** `HEAD` matches the recorded `commit_sha` (prefix match, so a short sha still matches) | Integrity is git, not a hash — nothing to precompute, and if corruption destroys `.git`, git fails loudly. The tree must be **completely clean**: nothing legitimately dirties it, so any porcelain line at all means something wrote where it should not have. |
| **B** | `pi --list-models` output is non-empty **and** does not say "No models available" | `pi --list-models` **exits 0 while empty**. Never trust `$?`. `command -v pi` runs first, because a missing `pi` prints one line of "command not found" that a bare non-empty check calls a pass. |
| **C** | every model in the **active** config answers a ping | Catches model-id drift. Models are parsed out of `$SSSF_CONFIG` (default `adws/adw_sssf_config/sssf.config.yaml`) and the `openrouter/` provider prefix is stripped. Reasoning models answer with `content: null` and the text under `.reasoning`, so the check accepts either. |
| **D** | `pi` reports **non-zero** cost on a live call, **and** every model in `models.json` has a non-zero `cost.input` | Without a rate table pi reports `$0.0000` forever while really spending. Ask **pi**, not OpenRouter: an earlier version diffed `/api/v1/key` usage before/after the pings and false-failed a healthy sandbox, because four 250-token pings round to $0 in that endpoint. |
| **E** | remaining credit on the runtime key | Exhaustion mid-run reads as a 402. Computed as `limit - usage` rather than read from a `limit_remaining` field, so it cannot break on a field name nobody verified. `limit: null` means uncapped. |

C, D and E run as **one** script inside the sandbox. They all need the runtime key, which
already lives in `app/.env` on the VM — keeping them there means the key never crosses the wire
and the gate proves the *sandbox's* egress works, not the host's.

**A gate failure REPORTS AND STOPS and LEAVES THE VM ALIVE.** It prints the ssh commands to
inspect the box, exits non-zero, and says `just sbx lifecycle teardown <run-id>` is your call. An earlier draft
destroyed the VM on failure; that throws away the evidence you need to diagnose it. Only teardown
destroys.

---

## CREATE ordering: record → VM → key

Strict, and the order is the whole design. A crash between any two steps must leave something
teardown can find.

1. **Run record first.** It is the only state shared across the six phases. Written before any
   resource exists, so a crash anywhere after leaves teardown a handle to work from. Lose the
   record and the key is unrevokable and keeps burning credit.
2. **VM before key.** A failed mint orphans a VM — cheap, and visible in `ssh exe.dev ls`. A
   failed VM after a successful mint orphans a **key**, which spends money invisibly. Trade the
   visible failure for the invisible one, every time.
3. **Key last**, named `sbx-<run-id>`, `limit` default `50.00`. The secret is written straight to
   `.sandbox/runs/<id>.key` at mode 600 by a python heredoc that prints only the hash — the key
   never reaches stdout, a log, a shell variable, or the JSON record.

Nothing in CREATE ever destroys a VM. Every failure path prints the teardown command and leaves
the box up. The mint response tempfile holds the secret and is shredded on every exit path via
an `EXIT` trap.

`$50` is the default because a real SDLC run will blow through a tight cap and die mid-workflow,
which looks like a bug rather than a budget.

---

## TEARDOWN must be idempotent on a half-created run

A run can die anywhere: VM but no key, key but no VM, a record with neither. **A missing piece is
the normal path, not an error.** Every step in `teardown.just` is individually guarded.

Order is load-bearing — **spend → artifacts → harvest → revoke → destroy**. Everything that READS
the box runs before anything that destroys it:

| Step | Guard |
| --- | --- |
| VM liveness | asked of the control plane (`ssh exe.dev ls --json`), not probed over ssh. Authoritative, and it is the same answer `reap` uses |
| 1. spend | read **before** the key dies — after `DELETE` the number is unrecoverable. Prefers the runtime key's own `GET /api/v1/key`; on a re-run where the `.key` file was already shredded it falls back to the provisioning **LIST**, which still carries `usage` per hash |
| 2. artifacts | skipped if no VM. `ls -d` filters to what exists, so a run that died before writing `app_docs/` is not an error. Empty result removes the dir rather than implying something was pulled |
| 3. harvest | delegates to `just sbx manage harvest`, **default on**, so nobody loses a run's commits by forgetting. Skipped if no VM, or deliberately with `--no-harvest` when you already harvested. A failure **ABORTS the teardown before revoke and destroy** — destroying a VM whose commits were never pulled is the one irreversible mistake this file can make |
| 4. revoke | no `key_hash` → nothing to revoke. `2xx` → revoked. `404` → already gone (the idempotent re-run path). Anything else → stop, leave the VM alone. A live `key_hash` with no provisioning key in `.env` is a hard stop, not a warning |
| 5. destroy | only if the VM is actually alive |
| 6. close | `close()` is idempotent and **first close wins** — the moment that matters is when the key actually died. Key file shredded (`shred -u`, `rm -P` on macOS), `-f` last so a re-run never fails on an already-removed file |
| 7. gate | short-circuits to success when no key was ever minted |

A crash between revoke and destroy leaves a dead key and a live VM: visible, cheap. The reverse
leaves a live key nobody can find: invisible, spending. That is why the order is what it is.

---

## Getting commits out: branch at fill, bundle at harvest

The sandbox is filled by a **public, unauthenticated `git clone`** and holds one disposable
OpenRouter runtime key — no PAT, no deploy key, no ssh identity, nothing that could push. That is
the point: the box runs an autonomous agent under `--dangerously-skip-permissions`, and a push
credential would hand that agent write access to the repo it was cloned from. A `git bundle` moves
commits across the gap with no credential at all.

| Decision | Why |
| --- | --- |
| Branch at **fill**, not at execute | `git switch -c sbx/<run-id>` at existing HEAD adds no commit and changes no file, so it lands before the gate without disturbing assertion **A**. The ADW needs no change at all — its commit phase already commits to HEAD, which is now the run branch |
| Bundle a **range**, not `--all` | `<commit_sha>..sbx/<run-id>` packs only what the run introduced — 4 commits measured at **7.6 KB**. `--all` packs the whole history. The range also records a prerequisite, so `git fetch` REFUSES a bundle whose base this host does not have, instead of importing detached history |
| Fetch into `refs/sandbox/<run-id>` | not a branch. Nothing collides with your branches, nothing touches your working tree or index, and `git log`/`git diff` read it like any other ref. On fan-out, N runs of one prompt land as N refs in one repo and diff against each other with plain git |
| Harvest is its own recipe | teardown is the human's call, so a harvest that only ran inside teardown would leave commits hostage to a decision nobody has made yet. Standalone and idempotent, the exposure window is seconds instead of days |
| Bundle over push | a push is durable the instant the ADW commits, which a bundle is not — but the gap closes once you harvest on completion. Not worth a GitHub App, a private key, JWT signing and a ruleset. The branch naming is the only expensive-to-change decision and `sbx/<run-id>` is correct under both, so this does not foreclose pushing later |

If a run's commits are missing after a harvest, check the ADW committed at all (`NOCOMMITS` means
the branch tip still equals `commit_sha`) before suspecting the bundle.

## The mount chain

```
just sbx mount RUN_ID [--limit N]    # create -> fill -> setup -> observe
```

Stops at observe **by design**. Teardown is never chained. `mount` re-reads the generated run id
back out of `run_record.py list` (newest first) because `create` slugifies and suffixes whatever
you passed.

`just sbx lifecycle create` accepts either a task description (it gets slugified and suffixed with
`-YYYYMMDD-<6 hex>`) or an already-minted run id (recognised by the `-<6 hex>` tail, passed
through untouched). Every later phase takes the full run id.

---

## Status

Five phases verified end to end on a real VM (`inkwell-e2e-20260804-e08747`): create → fill →
setup (all five assertions) → execute → observe, with both surfaces served and the gate proven by
deliberate failure. Teardown has since been exercised against a live sandbox: spend → artifacts → harvest →
revoke → destroy → close, with the revocation gate confirming the key was gone from the
OpenRouter list.

Everything host-only lives under `just/sandbox/` or `sandbox_mount/host/` — the readback recipes,
`runs_table.py`, the orchestrator boot recipes, and this skill. Those paths ship to the sandbox
along with everything else; keeping them in one place is about legibility, not enforcement. The
enforcement is that neither credential they need ever leaves the host.
