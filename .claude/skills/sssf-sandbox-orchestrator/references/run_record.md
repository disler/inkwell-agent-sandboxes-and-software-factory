# The run record

`.sandbox/runs/<run-id>.json` — the only state shared across the six phases.

Each phase is a separate process, so nothing survives between them except what is on disk.
Teardown has no other way to learn which OpenRouter key to revoke: **lose the record and the key
is unrevokable and keeps burning credit.** `.sandbox/` is gitignored.

Implementation: `sandbox_mount/host/run_record.py`. Stdlib only, on purpose — it runs on the host
before any toolchain exists and must never be the reason a teardown cannot start.

---

## The twelve fields

The schema is **closed**. Every field is referenced by name somewhere in the six phases, so a
typo in a `set` would be silent data loss — unknown keys are rejected rather than written.

| # | Field | Written by | Read by | Type / coercion | Why it must persist |
| --- | --- | --- | --- | --- | --- |
| 1 | `run_id` | create (at `create`) | everything | str, **immutable** | It is also the filename. Rewriting it would leave the record answering to a name that is not its own |
| 2 | `vm_name` | create | fill, setup, execute, run, agent, observe, teardown, reap | str | Every ssh target: `<vm_name>.exe.xyz` |
| 3 | `https_url` | create | operator | str | The public URL. Derived as `https://<vm_name>.exe.xyz` if `new --json` does not return it |
| 4 | `key_hash` | create | teardown, reap | str | Without it the key is **unrevokable**. This is the revocation handle — not the key |
| 5 | `limit` | create | operator, teardown math | float | Dollars on the OpenRouter key. Default `50.00`, per-run via `just sbx lifecycle create <id> --limit N` |
| 6 | `spend` | teardown | compare | float | What the key actually cost, read back from OpenRouter **before** revoking. This is what makes best-of-N comparable: same prompt, N models, cost beside result |
| 7 | `session_id` | create | agent | str (UUID) | `claude --session-id` demands a UUID and `--resume` needs the same one on every later turn, so it is minted once at create |
| 8 | `commit_sha` | fill | setup gate A, compare | str | Pins the run. Always the sha **actually checked out**, never the one that was asked for. Not coerced — `5734129` is a string that happens to parse as a number |
| 9 | `ports` | observe | operator | JSON (`{"app":4501,"obs":4600}`) | Which surface is on which port |
| 10 | `pid` | execute | operator | int | The detached SDLC's remote pid |
| 11 | `created_at` | create | list ordering | str, **immutable** | Identity, not state |
| 12 | `closed_at` | teardown (`close`) | reap | str or null | **Non-null means the key is revoked.** This is what distinguishes a live run from an orphan |

`run_id` and `created_at` are immutable: `set` refuses them.

Coercion is per-field, not "try JSON first": `ports` → JSON, `pid` → int, `limit`/`spend` →
float, everything else stays a string. The literal `null` sets a field back to `None`.

---

## The secret is NOT in the JSON

The runtime key lives in a **separate file**:

```
.sandbox/runs/<run-id>.key      mode 600, bare key + newline
```

The JSON record is greppable and gets shown in reports; the key never goes near it. CREATE writes
the key straight to that path from a python heredoc at `0o600` and prints only the hash, so the
secret never reaches stdout, a log, or a shell variable. FILL reads it back, strips an optional
`OPENROUTER_API_KEY=` prefix, and pipes it over ssh via `printf` into `umask 077 && cat >
app/.env` — the key never appears in `argv` on either side, so it never shows up in `ps`.
TEARDOWN shreds it.

The record itself is created with `O_EXCL` at mode `0600` — overwriting a live record orphans
that run's key, and the check-then-write window is exactly when a retrying phase would land.
Updates are atomic (`tmp` + `os.replace`), so a crash mid-write leaves the old record, not half
of one.

`OPENROUTER_PROVISIONING_KEY` appears in exactly two files, `create.just` and `teardown.just`,
and never leaves the host.

---

## CLI

```
run_record.py create  <run-id>          # seed run_id + created_at; refuses to clobber; prints the path
run_record.py get     <run-id> [field]  # whole record as JSON, or one field
run_record.py set     <run-id> k=v ...  # merge; rejects unknown and immutable keys
run_record.py close   <run-id>          # stamp closed_at; idempotent, first close wins
run_record.py list                      # every record, newest first, as a JSON array
run_record.py path    <run-id>          # where the record lives; creates nothing
run_record.py new-id  <task>            # <slug>-<YYYYMMDD>-<6 hex>
```

**`get <run-id> <field>` prints the BARE value** so shell can capture it:

```bash
RUN_VM=$(sandbox_mount/host/run_record.py get my-run vm_name)
```

An unset field prints an **empty line**, so emptiness — not exit status — is the real check.
Every phase does `[ -n "$VM" ] || { echo "... run 'just sbx lifecycle create' first"; exit 1; }`. Only `dict`
and `list` values (i.e. `ports`) come back as JSON; booleans print `true`/`false`.

`new-id` slugifies because the run id becomes the VM name and the VM name becomes a public
hostname — a collision is not a local annoyance, it is two runs fighting over one URL. CREATE
additionally rejects anything that is not a valid DNS label or is over 63 chars.

`list` raises loudly on a malformed record instead of skipping it: `reap` walks that list to find
keys nobody revoked, and a record quietly dropped for being unreadable is a key that quietly
keeps spending.

---

## A real record

```json
{
  "run_id": "inkwell-e2e-20260804-e08747",
  "vm_name": "inkwell-e2e-20260804-e08747",
  "https_url": "https://inkwell-e2e-20260804-e08747.exe.xyz",
  "key_hash": "18ed7070caa5016ec5e325653a35f6fba2b13cb4239ff34b426de9cbe131ea2f",
  "limit": 50.0,
  "spend": null,
  "session_id": "8941a9f0-ac02-4678-be96-d578ac224c3b",
  "commit_sha": "30c962bcd4fe37dd451dc529043920317f6a5db4",
  "ports": { "app": 4501, "obs": 4600 },
  "pid": 1542,
  "created_at": "2026-08-04T16:57:16Z",
  "closed_at": null
}
```

---

## Sidecar files

Two things live beside the record and are **not** part of the schema:

| Path | Written by | Purpose |
| --- | --- | --- |
| `<run-id>.key` | create (600) | the runtime secret; read by fill and teardown, shredded at teardown |
| `<run-id>.agent-started` | `just sbx run agent`, after a **successful** turn | the "has this session started" bit that decides `--session-id` vs `--resume`. It is a host sentinel because the schema is closed and has nowhere to put a boolean, and probing the VM for Claude Code's on-disk session layout would make an unverified implementation detail the source of truth. Touched only after success — a first call that died never created a session, and `--resume` on a session that does not exist would fail forever |

Teardown also drops `<run-id>-artifacts/` and `<run-id>.bundle` into the same directory.
