# Debug a Failed Gate

The SETUP gate (`just/sandbox/setup.just`, step 3/3) runs five assertions against a mounted sandbox.
When one fails it **reports, stops, and leaves the VM running**. That is deliberate: the evidence you
need is on the box, and a gate that auto-destroys throws it away. Nothing in the six phases destroys a
VM except `just sbx lifecycle teardown`, and teardown is always a separate human decision.

So the first rule of debugging a gate failure is: **do not tear down.** Read the box.

## What the failure hands you

`gate_fail()` prints the assertion that failed and three starting commands:

```
[setup] FAILED: assertion B — pi --list-models empty or 'No models available'
[setup] the VM is still running on purpose — the evidence is on the box:
[setup]   ssh <vm>.exe.xyz
[setup]   ssh <vm>.exe.xyz 'cd app && git status --porcelain'
[setup]   ssh <vm>.exe.xyz 'pi --list-models'
[setup] tear it down only when you are done: just sbx lifecycle teardown <run-id>
```

A/B run as their own remote scripts and fail on their own. C/D/E run as **one** remote script, so the
exit code names which one:

| Remote exit | Assertion | setup.just says |
|---|---|---|
| 2 | C | at least one roster model did not answer |
| 3 | D | no cost reported and/or no rate table in models.json |
| anything else | C/D/E prologue | the remote gate script exited N (see output above) — usually a missing `.env` key, missing `jq`, or a dead `/api/v1/key` read |

## The two handles

Everything below uses one of these. There is no third source of truth.

```bash
RR=sandbox_mount/host/run_record.py
$RR get <run-id>                    # the whole record
VM=$($RR get <run-id> vm_name)      # the ssh target is $VM.exe.xyz
just sbx run cmd <run-id> '<cmd>'           # synchronous, already cd'd into app/
```

**Quoting rule for `just sbx run cmd`, verified:** `{{CMD}}` is interpolated verbatim into a double-quoted
ssh string, so any quoting that must survive to the VM has to be **single** quotes, and any `$` the
VM should expand has to be `\$`. `just sbx run cmd id "sqlite3 db 'select 1'"` reaches the VM intact;
`just sbx run cmd id 'sqlite3 db "select 1"'` arrives as `sqlite3 db select 1`. When a command needs both
nested quotes and remote `$` expansion, drop to `ssh $VM.exe.xyz '<single-quoted script>'` — one
layer of quoting instead of two.

---

## A — git integrity

**What it proves.** The clone landed *intact* and is the commit the run record says it is. Existence
is not the check — content is. An unsynced golden-VM `cp` once produced 5,641 zero-byte files and
reported success; truncation shows up in git as ` M path`, which is why this is `git status`, not a
file count or a hash manifest.

Two conditions:

1. `git rev-parse HEAD` prefix-matches the recorded `commit_sha` (prefix, so a short sha in the
   record still matches a full HEAD).
2. `git status --porcelain` is **completely empty**. Nothing legitimately dirties the tree — the
   sandbox clones the repo and provisions around it — so any porcelain line at all means something
   wrote where it should not have.

**Failure looks like** one of:

```
   no ~/app on this VM — FILL never ran
   git rev-parse failed — .git is damaged
   HEAD does not match the recorded commit_sha
   unexpected working-tree changes (the tree must be clean):
      M justfile
      M README.md
```

**Diagnose:**

```bash
$RR get <run-id> commit_sha
just sbx run cmd <run-id> 'git rev-parse HEAD'
just sbx run cmd <run-id> 'git status --porcelain'
just sbx run cmd <run-id> 'git diff --stat'
# the zero-byte signature of an unsynced clone
just sbx run cmd <run-id> "find . -type f -empty -not -path './.git/*' | wc -l"
```

**Read it:**

- ` M` on tracked files, plus a non-trivial empty-file count → corrupt copy. Re-run `just sbx lifecycle fill
  <run-id> [sha]` or mount a fresh run. If it came from `cp`, you skipped `ssh <golden> sync`.
- HEAD mismatch with a clean tree → FILL checked out something else, or an ADW already ran in this
  box and committed. A run that has executed will fail A by design; A is a pre-execute check.
- ` D` lines on tracked paths → something deleted files in the clone. Nothing in provisioning
  removes anything, so treat it as damage and re-run `just sbx lifecycle fill <run-id>`.

---

## B — `pi --list-models` is non-empty

**What it proves.** The pi model registry loaded. `~/.pi/agent/models.json` does not exist on a fresh
VM, and without it **pi prints "No models available" and EXITS 0**. Never trust `$?` here. The gate
also runs `command -v pi` first, because a missing binary prints one line of "command not found" and
a bare non-empty check calls that a pass.

**Failure looks like:**

```
   pi is not on PATH
   pi --list-models printed nothing
   pi says: No models available — ~/.pi/agent/models.json did not load
```

**Diagnose:**

```bash
just sbx run cmd <run-id> 'pi --list-models; echo "exit=$?"'
just sbx run cmd <run-id> 'ls -l ~/.pi/agent/models.json'
just sbx run cmd <run-id> 'jq . ~/.pi/agent/models.json >/dev/null && echo JSON_OK'
just sbx run cmd <run-id> "jq -r '.providers.openrouter.models[].id' ~/.pi/agent/models.json"
# did provision fail to find a key and leave the placeholder behind?
just sbx run cmd <run-id> "grep -c 'env:OPENROUTER_API_KEY' ~/.pi/agent/models.json"
```

**Read it:**

- **"No models available" with a file present is almost always a cost-block problem, not a model
  problem.** pi's schema requires **all four** of `input`/`output`/`cacheRead`/`cacheWrite`. A partial
  block fails validation and pi drops **the entire roster** — not just that model. The error is
  `must have required properties cacheRead, cacheWrite`. Find the offender:

  ```bash
  just sbx run cmd <run-id> "jq -r '.providers[].models[] | select(.cost.input==null or .cost.output==null or .cost.cacheRead==null or .cost.cacheWrite==null) | .id' ~/.pi/agent/models.json"
  ```

  Any id printed there is holding the whole roster hostage. Use `0.0` where a provider publishes no
  cache-write rate — the field must be present, not non-zero. Fix
  `sandbox_mount/guest/models.json.tmpl`, then re-run SETUP.
- Placeholder count `1` → provision.sh found no `OPENROUTER_API_KEY` in `app/.env`, so it left
  `"apiKey": "env:OPENROUTER_API_KEY"` in place. A bare `ssh vm 'pi ...'` exports nothing, so pi has
  no key. Re-run `just sbx lifecycle fill <run-id>` (which writes `.env`), then `just sbx lifecycle setup <run-id>`.
- `pi is not on PATH` on a stock exeuntu VM means something clobbered the image — pi ships at
  `/usr/local/bin/pi`. Suspect a bad `rm` before suspecting the image.

---

## C — every roster model answers a ping

**What it proves.** The runtime key works, the sandbox's own egress works, and every model id in the
**active** config actually resolves at OpenRouter. Ids rot; this catches a retired or typo'd id before
an agent burns a phase on it.

Mechanically: parse every `model:` line out of the config, strip the leading `openrouter/` (that
segment is pi's *provider* name, not part of the OpenRouter id), and send each a 256-token completion
with `provider.zdr=true` and `data_collection=deny`. A reply counts if either `.content` **or**
`.reasoning` is non-empty — reasoning models answer with `content: null`, and accepting only
`.content` produces false failures on them.

**Failure looks like:**

```
   pass  deepseek/deepseek-v4-flash-0731
   FAIL  z-ai/glm-5.2: No endpoints found matching your data policy
```

**Diagnose.** First, see exactly which ids the gate pinged:

```bash
just sbx run cmd <run-id> "grep -hE '^[[:space:]]*model:[[:space:]]' adws/adw_sssf_config/sssf.config.yaml | sed -E 's/^[[:space:]]*model:[[:space:]]*//; s/[[:space:]]+#.*//; s|^openrouter/||' | sort -u"
```

Then reproduce one model by hand. Do this **in an interactive session on the box** — a JSON body does
not survive two layers of shell quoting:

```bash
ssh $VM.exe.xyz
cd app && set -a && . ./.env && set +a
curl -sS https://openrouter.ai/api/v1/chat/completions \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" -H 'Content-Type: application/json' \
  -d '{"model":"z-ai/glm-5.2","max_tokens":64,"provider":{"zdr":true,"data_collection":"deny"},"messages":[{"role":"user","content":"ping"}]}' | jq .
```

**Read the error field:**

| Error | Cause | Fix |
|---|---|---|
| `... is not a valid model ID` | id retired or mistyped | fix the config, and `models.json.tmpl` if it lists it too |
| `No endpoints found matching your data policy` | no ZDR endpoint for that model | different model, or relax the provider block (a deliberate policy change, not a gate bug) |
| HTTP 402 / `credits` | the $50 cap is already spent | `just sbx lifecycle create` a fresh run with `--limit`, or raise the key's limit |
| `User not found` | you are calling with the **provisioning** key | the provisioning key cannot do inference. It mints and revokes only. The gate uses the runtime key from `app/.env` on purpose |

**Note on config selection:** the gate reads `${SSSF_CONFIG:-adws/adw_sssf_config/sssf.config.yaml}`
inside the sandbox, and `ssh vm "cmd"` carries no environment — `--env` lands in
`/etc/profile.d/exe-env.sh`, which a non-interactive ssh never reads. In practice the gate always
pings the **default** roster. If a run uses a different roster, C did not check it.

---

## D — pi reports NON-ZERO cost

**What it proves.** The rate table is loaded. This is the assertion people delete because it "looks
redundant with B," and it is the one that caught the most expensive bug in the system.

`adw_modules/agent_pi.py` reads `usage.cost.total` straight out of pi, and **pi defaults every rate to
zero when models.json carries no `cost` block**. A factory in that state runs perfectly and reports
`$0.0000` forever while genuinely spending money. Measured: a **463.6k-token run logged $0.0000**.
With rates loaded, a 1,797-token run reported `$0.0081`.

Two halves:

1. A live pi call on the cheapest roster model, cost pulled out of pi's own JSON. One sentence reports
   about `4.3e-05` — small, unambiguously `> 0`.
2. The registry itself: every model in `~/.pi/agent/models.json` has a non-zero `cost.input`. This
   catches a partial rate table the single call happened not to touch.

**Failure looks like:**

```
   FAIL  pi reported cost 0 — models.json has no rate table, so every
         run will log $0.0000 while really spending money
   FAIL  models.json is missing rates — pi will report $0.0000 on every run
```

**Diagnose:**

```bash
# the same call the gate makes, raw
just sbx run cmd <run-id> "timeout 180 pi -p --mode json --provider openrouter --model deepseek/deepseek-v4-flash-0731 'Write one sentence about sandboxes.' | tail -n 3"
# the rate table as pi sees it
just sbx run cmd <run-id> "jq '.providers.openrouter.models[] | {id, cost}' ~/.pi/agent/models.json"
```

**Read it:**

- pi errors instead of answering → this is really a B or C failure wearing D's clothes. Fix those first.
- pi answers but `cost.total` is `0` → the rate table. Rates live in
  `sandbox_mount/guest/models.json.tmpl` as **per-million-token** dollars, pulled live from OpenRouter
  on 2026-08-04. They go stale when pricing moves; regenerate, then re-run SETUP to rewrite the file
  on the box.
- A new model added to a config **must** also be added to the template with all four cost fields, or
  B fails and takes the whole roster with it. D and B are the same bug seen from two sides.

**jq, not python.** An unindented line inside a `just` recipe body TERMINATES the recipe, so a
multi-line python heredoc cannot survive there. `jq` ships in the exeuntu image; use it.

---

## E — remaining credit is reported

**What it proves.** The key is alive and the sandbox can read its own budget. This is the one
assertion with no pass/fail threshold — it prints, so you know what is left before you spend it:

```
   limit     $50.0
   used      $0.0081
   remaining $49.9919
```

`remaining` is **computed** from `limit - usage` rather than read from a `limit_remaining` field, so
it cannot break on a field name nobody verified. A `null` limit prints `uncapped`.

**Failure looks like** `could not read /api/v1/key`, and the remote script exits 1 → setup reports
"assertions C/D/E — the remote gate script exited 1".

**Diagnose:**

```bash
ssh $VM.exe.xyz 'cd app && set -a && . ./.env && set +a && curl -sS -o /dev/null -w "%{http_code}\n" https://openrouter.ai/api/v1/key -H "Authorization: Bearer $OPENROUTER_API_KEY"'
```

- `401` → the key is dead. Teardown already revoked it, or `reap` did. That run is over; mount a new one.
- `000` / timeout → the sandbox has no egress. Check the VM is actually up (`ssh exe.dev ls`) before
  blaming OpenRouter.
- Empty `.env` → FILL never injected the key. `just sbx lifecycle fill <run-id>` then `just sbx lifecycle setup <run-id>`.

---

## Two false failures already paid for

Both of these were healthy sandboxes that the system called broken. They are here because the shape
repeats.

### 1. Gate D diffed the wrong instrument

The first version of D read `GET /api/v1/key` usage before and after the C pings and asserted the
delta was non-zero. On the first live mount it failed — on a **correctly configured** sandbox. Four
250-token pings on cheap models round to `$0` at that endpoint's precision, so a working box looked
broken.

The thing being guarded is whether **pi** reports cost, not whether OpenRouter recorded it. D now
makes a real pi call and asserts pi's own reported number. (The `usage_before` / `usage_after` reads
survive in the script as leftovers from that version; D no longer asserts on them.)

**The lesson generalizes: assert on the component you are guarding, at the precision it operates.**
A proxy metric that rounds to zero is a gate that fails randomly and gets deleted for being flaky.

### 2. `bun: No such file or directory` in OBSERVE

OBSERVE tried to start the app and got `bun: No such file or directory` — **minutes after provision.sh
had used bun successfully** on the same VM.

Cause: **each `ssh vm cmd` is a fresh non-interactive shell that reads no rc file.** The bun installer
only edits shell rc files; provision.sh worked because it did `export PATH="$HOME/.bun/bin:$PATH"`
inside its own process, and that died with the script. `just` was never affected because its installer
writes to `/usr/local/bin`.

Fix, now in `sandbox_mount/guest/provision.sh` (step 3/10): symlink `bun` and `bunx` into
`/usr/local/bin`.

**Detect it in one command** — compare the non-interactive answer (the truth for everything the
orchestrator does) with the login-shell answer:

```bash
ssh $VM.exe.xyz 'command -v bun'                    # what the recipes see
ssh $VM.exe.xyz 'bash -lic "command -v bun"'        # what a human sees
```

If the first is empty and the second is not, you have this bug. It applies to **anything** installed
into a home directory: put it on `/usr/local/bin` or it does not exist as far as the orchestrator is
concerned. The same fact is why `--env` is useless for secrets (it lands in `/etc/profile.d/`) and why
`just` in the sandbox needs `just --shell bash --shell-arg -c` (the root justfile sets `zsh -ic`, and
zsh is not in the image; installing it is ~35s of apt for no benefit).

---

## Re-running the gate

`just sbx lifecycle setup <run-id>` is safe to re-run and is the normal fix loop. It removes `/tmp/PROVISION_READY`
first — otherwise a re-run would find the *previous* run's sentinel and declare victory before
provision.sh had done anything — then re-runs provision.sh, which is idempotent by construction
(skip-if-present installs, `CREATE TABLE IF NOT EXISTS` DDL).

For a fix that lives in the repo (a config model, a rate in `models.json.tmpl`), push it, then:

```bash
just sbx lifecycle fill  <run-id>          # fast-forwards app/ to origin/main; never resets over the run's own commits
just sbx lifecycle setup <run-id>
```

If provision.sh itself fails, its last `── step ──` line names the stage — the ERR trap prints
`[provision] FAILED during: <step>`.

## When to actually tear down

Only when you have what you need, and only because a human said so. The VM costs money while it
sits, but a destroyed VM costs the whole debugging session. If the box is unsalvageable, `just
teardown <run-id>` still pulls artifacts and the git bundle **before** it destroys anything — see
`teardown_and_reap.md`.
