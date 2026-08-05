# Teardown and Reap

`just sbx lifecycle teardown <run-id>` is the only thing in this repo that destroys a VM. It is **always an explicit
human decision** — never chained, never automatic, never suggested casually.

> **Status, honestly: teardown and reap are written but have NOT been run.** Five of the six phases
> were verified end to end on a live VM on 2026-08-04. Teardown is the sixth and is unexercised.
> Watch the first one; do not background it.

## Why it is never chained

`just sbx mount` stops at `observe`. Every failure path in create / fill / setup / execute / observe
prints the teardown command and **leaves the box alive** — that is an offer, not a recommendation.
The reasons compound:

- **The VM is the evidence.** A gate that auto-destroys throws away the only copy of what went wrong.
- **`ssh exe.dev rm` has no confirmation and no undo.** It deletes the persistent disk.
- **A VM sitting for an hour is cheap. A run destroyed early is gone.** The asymmetry is not close.

So: propose it, wait for a yes, then run it. Never fold it into a script that also did something
else.

## The order, and why each step is where it is

```
1. capture spend   2. pull artifacts   3. git bundle   4. revoke key
5. destroy VM      6. close record + shred key file    7. gate: key absent from the LIST
```

**1 — spend before revoke.** `GET /api/v1/key` with the runtime key reports that key's own usage.
After `DELETE` the number is **unrecoverable**. It is written into the run record as `spend`, and it
is what makes best-of-N comparable: same prompt, N models, cost beside result. (If the `.key` file is
already gone, teardown falls back to the provisioning `GET /api/v1/keys` list, which still carries
`usage` per hash.)

**2 — artifacts before destroy.** One tar over one ssh round trip: `specs/`, `app_docs/`,
`adws/adw_data/sssf.db`, `run.log`, filtered by `ls -d` so a run that died before writing `app_docs/`
is not an error. Lands in `.sandbox/runs/<run-id>-artifacts/`.

**3 — the bundle, because file copies LOSE history.** SSSF commits the plan, the code and the docs as
**separate commits**. The shape of the run is in the commit graph, not in the files. `git bundle
create /tmp/run.bundle --all` on the VM, `scp` it down to `.sandbox/runs/<run-id>.bundle`. Read it
back locally without touching your branches:

```bash
git fetch .sandbox/runs/<run-id>.bundle 'refs/heads/*:refs/heads/sandbox/<run-id>/*'
git log --oneline --graph sandbox/<run-id>/main
```

**4 before 5 — revoke before destroy.** A crash between them leaves a dead key and a live VM: visible
in `ssh exe.dev ls`, cheap, obvious. The reverse leaves a live key nobody can find — invisible, and it
spends. Order the failure modes, not the happy path.

**6 — close the record, shred the key file.** `closed_at` non-null is what `reap` reads as "this run
is over." The key file gets `shred -u` where available, `rm -P` on macOS.

**7 — the gate.** See below.

## Verify revocation against the key LIST

**Measured:** immediately after a successful `DELETE`, `GET /api/v1/key` still returned **200** for
the dead key while the authoritative list already showed it gone.

So the gate asserts the hash is **absent from `GET /api/v1/keys`** — the list, read with the
provisioning key. Never gate on `/api/v1/key`. If the list read itself fails, teardown reports
"revocation UNVERIFIED" and exits non-zero rather than claiming success.

From the outside, after the fact, the runtime key should 401:

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://openrouter.ai/api/v1/auth/key \
  -H "Authorization: Bearer $DEAD_RUNTIME_KEY"      # expect 401
```

## It is idempotent, and partial states are normal

A run can die anywhere: VM but no key, key but no VM, a record with neither. Every step is
individually guarded, so re-running teardown is the normal recovery path, not a risk.

The one hard prerequisite is **the run record** — it is the only handle on the key. No record, no
teardown; fall through to `reap`.

Two places it stops on purpose:

| Condition | Behavior | Why |
|---|---|---|
| `key_hash` is set but `OPENROUTER_PROVISIONING_KEY` is unset | reports and exits 1, **VM left alone** | a live key keeps spending; that is the bigger problem, and destroying the VM would not fix it |
| `DELETE` returns anything but 2xx or 404 | reports and exits 1, **VM left alone** | the key may still be live. Do not compound an unknown state by destroying the evidence |

`404` on the DELETE is treated as success — it means a previous run already revoked it.

## reap

The fleet-wide backstop. No RUN_ID, because it is not a per-run step. OpenRouter keys have **no native
TTL**, so a teardown that never ran leaves a key spending forever.

```bash
just sbx manage reap          # dry run: prints the plan, deletes nothing
just sbx manage reap --yes    # actually revoke
```

**Dry run is the default and that is not decoration.** Read the table before you pass `--yes`.

### The `sbx-` prefix is the entire safety model

`create` mints every managed key as `sbx-<run-id>`. Your personal keys carry **no prefix** — verified
on this account: `mac-mini-agent`, `OAuth: localhost`, `m4 global`, `benchy`. Deleting one is
**unrecoverable**: OpenRouter shows a key's secret once, at mint, and never again.

Nothing without that prefix is ever considered — not deleted, not even printed as a candidate. The
prefix is asserted **twice**: once at selection, and again immediately before each `DELETE`, so a bug
upstream still cannot reach a personal key.

### What it selects

A three-way join of the key list, `ssh exe.dev ls --json`, and the run records in `.sandbox/runs/`. An
`sbx-` key is orphaned when either:

- its run record has a non-null `closed_at`, or
- its VM no longer exists in the live VM list.

A **live run — VM up, record open — is left alone.** With no record at all, `reap` falls back to
`vm_name == run_id`, which holds because `create` passes the run id as `--name`.

An **unreadable** run record is a hard error, not a skip: a record quietly dropped for being malformed
is a key that quietly keeps spending.

After deleting, `reap` re-reads the list and asserts every reaped hash is gone — the same gate as
teardown, for the same measured reason.

**Unverified:** whether `GET /keys` paginates past some page size. Four keys came back in one response
with no pagination envelope. A large fleet may need an offset loop.

## What is actually unproven

Be specific about this rather than hand-waving. Written, reviewed, never executed:

- the artifacts tar when `app/` is missing or empty (guarded with `exit 0`, untested)
- `git bundle create --all` + the `scp` back
- the `DELETE` → list-gate sequence on a real key
- `reap`'s three-way join against a real key list and VM list

Everything upstream of it — create, fill, setup, execute/run/agent, observe — ran end to end on a real
VM. When you run teardown for the first time, run it in the foreground, read every line, and check
`.sandbox/runs/` for the artifacts and the bundle before you believe it.
