# Fan Out to N

Best-of-N means **N separate sandboxes**. One run, one VM, one runtime key, one working tree, one
git state, one set of ports.

## The rule, and why it is not negotiable

The problem this system exists to solve is that five agents on one machine fight over one working
directory, one dev-server port, and one git state. Running N agents inside a single sandbox
**reintroduces exactly that collision** — you have paid for a VM and bought nothing.

Isolation is not the only thing you would lose:

- **Spend attribution.** One runtime key per sandbox is what makes "same prompt, N models, cost beside
  result" a table you can rank. N agents sharing one key produce one number nobody can decompose.
- **Blast radius.** `--limit` caps a single arm at its own budget. One key for N arms means one
  runaway arm can spend all of it.
- **The commit graph.** SSSF commits plan, code and docs separately. Two agents committing into one
  repo interleave their history and the `git bundle` at teardown is unreadable.
- **The gate.** A/B/C/D/E describe *one* sandbox's health. There is no per-agent version of it.

Getting one sandbox right is what makes N free. N is a loop over the same six phases.

## The loop

Mint the run id yourself and pass it through the phases. **Do not use `just sbx mount` for fan-out**:
`mount` recovers the generated id by reading the newest record out of `run_record.py list`, which is
correct for one run and a race under concurrency.

`just sbx lifecycle create` only generates a new id when the argument does not already end in `-<6 hex>`, so an id
from `new-id` is used verbatim.

```bash
#!/usr/bin/env bash
set -euo pipefail
RR=sandbox_mount/host/run_record.py

PROMPT="add a word-count badge to the editor footer"
PIN=$(git rev-parse HEAD)          # one commit for every arm — this is the control variable
ARMS=(sssf.config.yaml sssf.frontier.config.yaml)

for i in "${!ARMS[@]}"; do
  ID=$("$RR" new-id "bestof-$i")
  just sbx lifecycle create "$ID" --limit 10     # per-arm ceiling, not the $50 default
  just sbx lifecycle fill   "$ID" "$PIN"         # pin every arm to the same sha or the comparison is noise
  just sbx lifecycle setup  "$ID"                # gate; on failure it STOPS and leaves this arm's VM alive
  just sbx lifecycle observe "$ID"
  echo "$ID ${ARMS[$i]}" >> /tmp/fanout.map
done
```

Phases are ~12s cold per arm and mostly network wait, so backgrounding each arm's chain is fine. Two
things to know before you do: `just sbx lifecycle create` is the only phase that mints, so id generation must stay
outside the parallel section (it already is), and a gate failure in one arm must not abort the others
— run each chain in its own subshell and collect exit codes.

**A failed arm stays up.** `just sbx lifecycle setup` never destroys. Read `debug_a_failed_gate.md`, fix, re-run
`just sbx lifecycle setup <id>` for that arm only.

## Then execute

```bash
while read -r ID CFG; do
  just sbx lifecycle execute "$ID" "$PROMPT"      # detached; returns a pid, recorded
done < /tmp/fanout.map
```

`just sbx lifecycle execute` returns immediately. Watch any arm with `just sbx run cmd <id> 'tail -f run.log'`, or open its
observability UI (`just sbx lifecycle observe <id>` printed both URLs).

## Where per-run variance lives

Three places, and nowhere else. Everything else stays inside the codebase — that is what keeps this
orchestrator a set of recipes instead of an agent system.

### 1. The prompt

`just sbx lifecycle execute <id> "<prompt>"`. The obvious axis, and the one worth varying least: if the prompts
differ, you are not comparing models, you are comparing prompts.

### 2. `SSSF_CONFIG` — the roster

The repo ships two rosters: `adws/adw_sssf_config/sssf.config.yaml` (starter) and
`sssf.frontier.config.yaml`. A roster names an agent's coding agent, model, thinking level, tools and
prompts — it is the single richest per-run knob.

**`just sbx lifecycle execute` does not take a config argument.** It runs `adw sdlc <prompt>` with the module's
default, and `--env`-style delivery is useless here (`ssh vm "cmd"` reads no profile). **The right
fix is to teach `execute` a config flag rather than route around it.** Until that lands, the interim
is a direct ssh — `just sbx run cmd` would need two layers of quoting for a prompt with spaces plus a remote
`$!`, which is one layer too many:

```bash
ssh "$VM".exe.xyz "cd app && ( SSSF_CONFIG=adws/adw_sssf_config/sssf.frontier.config.yaml nohup just --shell bash --shell-arg -c adw sdlc 'add a word-count badge' > run.log 2>&1 < /dev/null & echo \$! )"
```

Four things in that line are load-bearing:

- `SSSF_CONFIG=...` goes **before** `nohup`, not after. `nohup VAR=x cmd` makes nohup try to exec a
  program literally named `VAR=x`.
- `--shell bash --shell-arg -c` — the root justfile sets `shell := ["zsh", "-ic"]` and zsh is not in
  the exeuntu image.
- All three detachment pieces (`nohup`, the redirect, `< /dev/null`) or ssh never returns.
- `\$!` — the pid must be expanded by the **remote** shell.

The pid is not recorded in the run record when you go around `just sbx lifecycle execute` — write it yourself
(`sandbox_mount/host/run_record.py set <id> pid=<n>`) if you want `just obs kill` semantics.

A cleaner alternative that needs no new flag: the module recipe is
`uv run adws/adw_plan_build_test.py --config {{config}} "$@"`, and argparse takes the **last**
`--config`, so a trailing `--config <path>` in the args wins. `just sbx lifecycle execute` passes only the prompt,
so that too waits on the recipe change.

Note the gate does **not** see `SSSF_CONFIG`: assertion C reads it from the sandbox's environment, and
`ssh vm "cmd"` carries no environment at all. C pings the default roster regardless. If an arm uses a
different roster, its models were never gated — ping them by hand or accept the risk.

### 3. The model

Edit a copy of the roster file: `defaults.model` for the whole roster, or `agents[].model` for one
agent. Ids are `provider/id` — pi splits on the **first** slash, so `openrouter/google/gemini-3.6-flash`
means provider `openrouter`, model `google/gemini-3.6-flash`.

**Any new model must also land in `sandbox_mount/guest/models.json.tmpl` with all four cost fields**
(`input`, `output`, `cacheRead`, `cacheWrite`; use `0.0` where a provider publishes no cache-write
rate). A partial cost block fails pi's schema validation and pi drops **the entire roster** — the
sandbox then reports "No models available" and gate B fails. Rates are per-million-token dollars,
pulled live 2026-08-04; they go stale.

### And the control: the commit pin

`just sbx lifecycle fill <id> <sha>` pins the arm. Hold it constant across arms or the comparison has two variables.
`commit_sha` is recorded from what actually got checked out, never from what was asked for, and FILL
gates that they match.

## Ranking the arms

`just sbx manage list` gives you state, VM liveness and spend for every run. There is no single
ranked table beyond that — `just sbx manage harvest <id>` each arm and diff the refs against each
other with plain git, which is the honest comparison anyway: the code is the artifact, not a score.

Where each column comes from:

| Column | Source |
|---|---|
| run id, vm, limit, spend, closed | `.sandbox/runs/<id>.json` via `run_record.py list` |
| commit | run record `commit_sha` (the input), plus the run's own commits in the teardown bundle (the output) |
| model (per agent) | trace db `agent_sessions.model` |
| tokens, cost, status, request | trace db `sessions.total_tokens`, `total_cost`, `status`, `request` |

Today:

```bash
# every run, newest first — run_id, vm_name, commit_sha, limit, spend, closed_at
sandbox_mount/host/run_record.py list

# per-arm result, read live off the VM
just sbx run cmd <id> "sqlite3 adws/adw_data/sssf.db 'select adw_id, status, total_tokens, round(total_cost,4) from sessions order by started_at desc limit 5;'"
just sbx run cmd <id> "sqlite3 adws/adw_data/sssf.db 'select agent, model, context_tokens from agent_sessions;'"

# live spend on an arm's key, before teardown writes it into the record
curl -sS https://openrouter.ai/api/v1/key -H "Authorization: Bearer $(cat .sandbox/runs/<id>.key)" | jq '.data.usage'
```

`spend` in the run record is written by **teardown**, from the key's own usage read before revocation.
That is the authoritative per-arm number — and it is unrecoverable once the key is deleted, which is
why teardown reads it first.

## The golden-VM path (N >= 3) — not yet exercised

A cold mount is ~12s (1.9s boot + 2.6s clone + toolchain + deps). A `cp` of a warm VM is **0.37s
server-side, ~1s wall**. At N=2 that is noise; at N>=3 it starts to matter.

**`sync` THEN `cp`. Always.**

```bash
ssh <golden>.exe.xyz 'sync'                  # MANDATORY
ssh exe.dev cp <golden> <run-id> --json
```

An unsynced `cp` produced **5,641 zero-byte files and reported no error**. The clone looked complete:
files existed, `just --list` exited 0, and thousands of them were empty. That is precisely why gate A
checks `git status --porcelain` rather than that files exist.

`exedev vm snapshot` (in `/sandbox-exe-dev`) is a thin wrapper over `ssh exe.dev cp` and **does not
sync** — the patch to add it is listed in the spec's modified files and has not landed. Call `sync`
yourself, or use the raw control-plane command.

What still runs after a `cp`:

- **FILL still runs.** A clone's code is stale by definition, and each arm needs its own runtime key
  in `.env`. FILL handles both: it detects an existing `app/.git` and fetches instead of cloning, and
  it fast-forwards with `--ff-only` so it can never reset over commits an earlier run produced.
- **SETUP still runs.** In principle it degrades to verify-only; as built, provision.sh is idempotent
  (skip-if-present installs, `CREATE TABLE IF NOT EXISTS`), so run it unchanged and
  let the gate do its job. The gate matters *more* here, not less — the zero-byte failure mode is
  unique to this path.
- **CREATE is different.** `cp` creates the VM, so the `ssh exe.dev new` in `create.just` is not what
  you want. There is no golden-VM variant of `just sbx lifecycle create` today; wiring one is the work this path
  needs.

Costs: a golden VM bills continuously while it sits idle — exe.dev VMs are persistent and never
expire. And it drifts: the toolchain it carries is the toolchain of the day you built it.

**This whole path is unexercised.** Five phases were verified end to end on a live VM by cold mount.
The golden-VM route is designed, measured (0.37s, 5,641 files) and written down — but no run has been
mounted through it. Treat the first one as an experiment, not an optimization.

## Cleanup

N sandboxes means N live VMs and N live keys, all billing until someone decides otherwise. Nothing
expires and nothing auto-destroys. Tear each arm down explicitly when you have its artifacts — see
`teardown_and_reap.md` — and use `just sbx manage reap` (dry run by default) as the backstop for arms whose
teardown never ran.
