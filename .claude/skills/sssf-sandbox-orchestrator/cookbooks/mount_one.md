# Mount one sandbox

One command takes a blank exe.dev VM to a health-checked, running factory and stops:

```bash
just sbx mount <task-or-run-id> [--limit 200]
```

`mount` chains **create → fill → setup → observe**. It never tears down. Teardown is always a
separate, explicit decision, and nothing on the success path destroys anything.

The four phases are also individually callable, and that is the debugging path: if `mount` stops,
re-run the phase that stopped rather than starting over. Every phase except `create` is idempotent.

## What you type

```bash
just sbx mount inkwell-e2e            # default $50 runtime key
just sbx mount inkwell-e2e --limit 200 # bigger cap for a long run
```

The argument is a **task name**, not the final run id. `create` appends a date and six hex
characters (`inkwell-e2e` → `inkwell-e2e-20260804-e08747`) unless you pass something that already
ends in `-<6 hex>`. The suffix is not optional: the run id becomes the VM name and the VM name
becomes a public hostname, so a collision is two runs fighting over one URL.

Everything after `create` takes the **full run id**. `mount` echoes it, and prints it again at the
end.

## Timing

| Step | Measured |
|---|---|
| `ssh exe.dev new` → ssh answering | 1.9s |
| public `git clone` of the repo | 2.61s |
| bun + just from their CDNs | ~1s combined |
| `bun install` (both apps) | 0.4s |
| cold `uv` PEP-723 resolve, warmed once | 3s |

That is ~10s of mechanical work. The health gate then spends **real model round trips** on top —
one ping per roster model plus one live `pi` call — so wall clock is longer than the sum above and
varies with the roster. Never `apt` anything into this path: measured ~148 kB/s and ~35s per
package from the dal region.

## Phase by phase

### 1. create — host only, control plane, no code and no secrets on the box

Order is the design: **record → VM → key.**

- record first, so a crash anywhere after it leaves teardown a handle to work from;
- VM before key, because a failed mint orphans a VM (cheap, and visible in `ssh exe.dev ls`) while
  a failed VM after a mint orphans a key that spends money invisibly.

```
run id:  inkwell-e2e-20260804-e08747
record:  .sandbox/runs/inkwell-e2e-20260804-e08747.json
vm:      creating inkwell-e2e-20260804-e08747 (ssh exe.dev new --tag inkwell) ...
vm:      inkwell-e2e-20260804-e08747  ->  https://inkwell-e2e-20260804-e08747.exe.xyz
key:     sbx-inkwell-e2e-20260804-e08747  limit $50.00  hash <64 hex>
key:     secret written to .sandbox/runs/<run-id>.key (0600) — FILL injects it
ssh:     waiting for <run-id>.exe.xyz (up to 60s) ...
ssh:     up after 4s
session: 8941a9f0-ac02-4678-be96-d578ac224c3b

created  <run-id>  (no code and no secrets on the box yet)
next     just sbx lifecycle fill <run-id>
```

The `sbx-` key-name prefix is load-bearing: it is how `just sbx manage reap` tells managed keys from your
personal ones. The secret itself never reaches stdout — python writes it straight to a 0600 file
and prints only the hash.

**Not idempotent.** The record is created with `O_EXCL`, so a second `just sbx lifecycle create` on the same full
run id fails rather than clobbering a live record (clobbering would orphan that run's key).

### 2. fill — public clone, pinned sha, runtime key

```bash
just sbx lifecycle fill <run-id> [SHA]
```

Plain `git clone https://github.com/disler/inkwell-agent-sandboxes-and-software-factory.git app` —
public repo, no auth, no GitHub integration, and `.git` comes with it because SSSF commits its own
plan, code and docs. Optional `SHA` (a sha, tag or branch) pins the run; the pin is resolved
**inside the clone**, so a short sha or a branch name works.

```
==> fill: <vm> — cloning app/
==> fill: no pin — HEAD 30c962bcd4fe37dd451dc529043920317f6a5db4 (recorded)
==> fill: app/.env written (mode/size: 600 <bytes>) — provisioning key never left the host
```

`.env` is written here, not at create: it lives inside `app/`, which does not exist until the clone
lands. `ssh exe.dev new --env` cannot carry it either — that writes `/etc/profile.d/exe-env.sh`,
which `ssh vm "cmd"` never reads.

**Gate:** checked-out HEAD equals the intended sha. Failure leaves the VM up.

**Idempotent**, including on a golden-VM `cp` where `app/` arrives stale: an existing `app/.git` is
fetched and fast-forwarded, never reset, because a sandbox that already ran an ADW carries commits
that *are* the run's output.

### 3. setup — provision inside, then the five-assertion gate

```bash
just sbx lifecycle setup <run-id>
```

Runs `bash app/sandbox_mount/guest/provision.sh` over ssh with its output streaming, then polls for
`/tmp/PROVISION_READY` (the script's literal last line — there is no other reliable completion
signal), then gates.

provision does, in order: bun → just → write
`~/.pi/agent/models.json` → `bun install` → `bunx vite build` the visualizer → initialize the trace
db → warm the uv cache → touch the sentinel.

The five assertions:

| | Asserts | Why it exists |
|---|---|---|
| **A** | `git status --porcelain` **completely** clean and HEAD matches the recorded sha | an unsynced golden clone produced 5,641 zero-byte files and reported success; truncation shows up as ` M path` |
| **B** | `pi --list-models` non-empty and not "No models available" | `~/.pi/agent/models.json` is absent on a fresh VM and pi **exits 0** while printing "No models available" |
| **C** | every model in the active roster answers a ping | a roster id that 404s fails the first agent call, 80s into a run |
| **D** | a live `pi` call reports **non-zero cost**, and every model in `models.json` has a non-zero input rate | without a rate table pi reports `$0.0000` forever while really spending — a 463.6k-token run logged `$0.0000` |
| **E** | remaining credit on the runtime key | you should know the budget before you spend it |

C, D and E run as one script **inside** the sandbox, because they need the runtime key that is
already in `app/.env`. The key never crosses the wire and the gate proves the sandbox's own egress.

```
[gate] A PASS  git integrity
[gate] B PASS  pi model registry loaded
[gate] C PASS  every roster model answered
[gate] D PASS  non-zero cost and a loaded rate table
[gate] E PASS  credit reported above

[setup] GATE PASSED — <run-id> is healthy on <vm>.exe.xyz
[setup] next: just sbx lifecycle observe <run-id>
```

**A gate failure reports and STOPS, and leaves the VM alive.** That is deliberate: the evidence is
on the box. The failure message hands you the three commands that matter:

```
ssh <vm>.exe.xyz
ssh <vm>.exe.xyz 'cd app && git status --porcelain'
ssh <vm>.exe.xyz 'pi --list-models'
```

Only `just sbx lifecycle teardown` destroys.

**Idempotent.** The sentinel is deleted before provisioning, so a re-run cannot find the previous
run's sentinel and declare victory early.

### 4. observe — start both servers, expose 4501, print URLs

See [observe_and_report.md](observe_and_report.md). In one line: app on 4501 anonymous (200), trace
UI on 4600 owner-gated (307 anonymously, which is correct), both recorded into the run record.

## What each phase writes to the run record

The record (`.sandbox/runs/<run-id>.json`, gitignored, 0600) is the **only** state shared across
phases — each phase is a separate process. Its schema is closed: `run_record.py` rejects unknown
keys, so a typo in a `set` fails loudly instead of silently losing data.

| Phase | Writes |
|---|---|
| create | `run_id`, `created_at`, `vm_name`, `https_url`, `key_hash`, `limit`, `session_id` — plus the secret to `.sandbox/runs/<run-id>.key` (0600) |
| fill | `commit_sha` (the sha actually checked out, never the one asked for) — plus `app/.env` on the VM |
| setup | **nothing** — it only reads `vm_name` and `commit_sha` |
| execute | `pid` |
| observe | `ports` (`{"app":4501,"obs":4600}`) |
| agent | nothing in the record; a sibling sentinel file `<run-id>.agent-started` |
| teardown | `spend`, `closed_at` — and shreds the `.key` file |

Read it directly whenever you need a field:

```bash
sandbox_mount/host/run_record.py get <run-id>            # whole record as JSON
sandbox_mount/host/run_record.py get <run-id> vm_name    # bare value, for shell capture
sandbox_mount/host/run_record.py list                    # every record, newest first
```

> `just sbx manage list` is the run table. `run_record.py list` is the same data unformatted, for
> when you want to pipe it.

## After mount

```
mounted: inkwell-e2e-20260804-e08747
  execute: just sbx lifecycle execute inkwell-e2e-20260804-e08747 "<prompt>"
  agent:   just sbx run agent inkwell-e2e-20260804-e08747 "<prompt>"
  destroy: just sbx lifecycle teardown inkwell-e2e-20260804-e08747
```

## Two things that bite

- **Do not run two `just sbx mount`s concurrently from this repo.** `mount` learns the generated run id
  by reading the **newest** record (`run_record.py list | … [0]["run_id"]`), so two overlapping
  mounts will hand the second run's id to the first run's `fill`. For parallel fan-out, call
  `create` yourself, capture the printed run id, and drive the phases per id.
- **`mount` stops at observe on purpose.** Nothing in create/fill/setup/execute/observe ever calls
  `ssh exe.dev rm`. Only `teardown.just` is allowed to, and exe.dev VMs never expire — a run you
  forget bills until you tear it down, and its OpenRouter key spends until `just sbx manage reap` catches it.
