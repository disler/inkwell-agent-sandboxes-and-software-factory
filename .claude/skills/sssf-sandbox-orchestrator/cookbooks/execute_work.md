# Execute work in a mounted sandbox

Three recipes drive a mounted sandbox. They are not interchangeable — pick by **how long the work
takes and whether you intend to stay**.

| Recipe | Shape | Runs | Pick it when |
|---|---|---|---|
| `just sbx run cmd <id> '<cmd>'` | synchronous, prints stdout | any command, in `app/` | inspecting, debugging, one-off shell work |
| `just sbx lifecycle execute <id> "<prompt>"` | **detached**, returns a pid | `adw sdlc` — plan → build → test | the default: real work, we walk away |
| `just sbx run agent <id> "<prompt>"` | synchronous, **resumable session** | Claude Code inside the box | steering, asking, iterating without ssh-ing in |

`execute` and `run agent` are the two **kickoff paths** — direct (a command) versus
agent-mediated (a delegation to the in-box orchestrator). When the choice between them is the
question, read [references/kickoff_paths.md](../references/kickoff_paths.md). When delegating
work through `run agent`, every work turn opens with
`If you have not already: READ and EXECUTE .claude/skills/sssf/SKILL.md. Then: <the work>` —
equip the delegate before commanding it (the delegation contract, same reference).

All three read `vm_name` from the run record, so the run must be mounted. None of them ever
destroys a VM: a failure reports, exits non-zero, and leaves the box up because the evidence is on
it. None of them reads `OPENROUTER_PROVISIONING_KEY` — only mint and revoke touch that, and it
never leaves the host.

## `just sbx run cmd` — the escape hatch

```bash
just sbx run cmd <run-id> uname -a
just sbx run cmd <run-id> 'tail -30 run.log'
just sbx run cmd <run-id> 'git log --oneline -5'
just sbx run cmd <run-id> 'sqlite3 adws/adw_data/sssf.db "select adw_id,status from sessions;"'
```

It runs `ssh <vm>.exe.xyz "cd app && <cmd>"`. Two consequences:

- **`cd app` is implicit** — every path is relative to the repo on the VM.
- **`{{CMD}}` is interpolated verbatim**, not rebuilt from `"$@"`. That is the point: pipes, globs
  and quotes you typed are meant to reach the remote shell intact. It also means you own the
  quoting. Single-quote anything containing `$`, `*` or `"` that the *remote* shell should see.

Synchronous, so `tail -f` blocks until you Ctrl-C. That is fine and often what you want.

## `just sbx lifecycle execute` — the default

```bash
just sbx lifecycle execute <run-id> "add a word-count badge to the editor footer"
```

```
→ execute <run-id> on <vm> (detached): add a word-count badge to the editor footer
→ pid 1542 recorded; SDLC is running detached
→ watch it:  just sbx run cmd <run-id> 'tail -f run.log'
```

Returns immediately. What it actually runs on the VM:

```bash
cd app && ( nohup just --shell bash --shell-arg -c adw sdlc <prompt> > run.log 2>&1 < /dev/null & echo $! )
```

Every piece is mandatory:

- **`nohup`** survives the ssh session ending, **`> run.log 2>&1`** releases stdout/stderr,
  **`< /dev/null`** releases stdin. Drop any one and ssh never returns.
- **`--shell bash --shell-arg -c`** — the root justfile sets `shell := ["zsh", "-ic"]` and zsh is
  not in the exeuntu image. The sandbox's default `sh` is dash, which also cannot parse the module's
  `${@:2}`.
- **`echo $!`** inside the subshell is the only way to get the pid back; `| tail -n 1` on the host
  side protects the capture from any stray remote stdout.
- The prompt makes two hops (just → host bash → remote login shell), so it is quoted twice:
  `{{ quote(PROMPT) }}` then `printf '%q'`. Apostrophes in a prompt survive.

The pid is written to the run record. A non-numeric answer is rejected on the spot rather than
recorded as garbage.

Two things to know:

- **`run.log` is truncated on every `execute`.** One detached SDLC per sandbox at a time is the
  intended shape. Pull the old log first if you care about it.
- **A recorded pid means "spawned", not "working".** `nohup … & echo $!` prints a pid even for a
  process that dies a millisecond later — a justfile parse error, for instance. Always confirm
  against `run.log` before telling anyone the run is underway.

### Watching a detached run

```bash
just sbx run cmd <run-id> 'tail -f run.log'            # live, blocks until Ctrl-C
just sbx run cmd <run-id> 'tail -40 run.log'           # a snapshot, non-blocking

# still alive? ask about the pid the record holds
PID=$(sandbox_mount/host/run_record.py get <run-id> pid)
just sbx run cmd <run-id> "ps -o pid,etime,command -p $PID"
```

`run.log` is the SSSF console transcript. Real output from the verified e2e run:

```
▶ 02 plan  agent · planner  Turn the request into an implementable plan
  ▸ planner openrouter/google/gemini-3.6-flash  session sssf-84b6551f-planner-dee5
  ✓ gate artifacts_exist 2 checked
  └ planner used 685,426 tokens · $0.5172
  ✓ plan 82.6s
▶ 03 build  agent · builder  Implement the plan exactly
  ▸ builder openrouter/deepseek/deepseek-v4-flash-0731  session sssf-84b6551f-builder-457b
  └ builder used 217,405 tokens · $0.0108
  ✓ build 110.2s
▶ 04 test_1  code · quality  Run the suite
  · quality tests: passed (exit 0, 0.3s)
▶ 05 commit  code · git
  · sha: bcfc678, message: Add word-count target progress bar under editor footer
╭───────── ADW complete ──────────╮
│  status   ✓ success             │
│  phases   5/5 passed            │
│  tokens   902,831               │
│  cost     $0.5280               │
│  adw_id   84b6551f              │
╰─────────────────────────────────╯
```

The `adw_id` printed near the top of the log is the handle for every trace query — see
[observe_and_report.md](observe_and_report.md) for reading progress out of the db instead of the
log.

### Running a different ADW

`execute` hardcodes `adw sdlc`. For any other chain, go through `run`:

```bash
just sbx run cmd <run-id> 'just --shell bash --shell-arg -c adw scout "where does auth live"'
just sbx run cmd <run-id> '( nohup just --shell bash --shell-arg -c adw simple-sdlc "..." > run.log 2>&1 < /dev/null & echo $! )'
```

Keep all three detachment pieces if you want it detached.

## `just sbx run agent` — Claude Code, resumable

```bash
just sbx run agent <run-id> "remember the number 42, reply STORED"
just sbx run agent <run-id> "what number did I ask you to remember?"     # -> 42
```

Verified working across **separate ssh invocations**: the second call is a new connection, a new
shell and a new `claude` process, and it still has the first turn's context.

What it runs:

```bash
cd app && ANTHROPIC_API_KEY=implicit ANTHROPIC_BASE_URL=https://llm.int.exe.xyz \
  claude -p (--session-id <uuid> | --resume <uuid>) --dangerously-skip-permissions <prompt>
```

- **The base URL is exe.dev's gateway, not OpenRouter.** OpenRouter does not serve the Anthropic
  Messages API cleanly. This lane needs **no key at all** — `ANTHROPIC_API_KEY=implicit` is a
  placeholder the client insists on. Claude Code work in a sandbox therefore does not draw down the
  run's OpenRouter budget.
- **The session uuid is minted once, at `create`**, and lives in the run record. `claude
  --session-id` demands a uuid and `--resume` needs the same one on every later turn.
- **First call vs later call** is decided by a host sentinel next to the run record,
  `.sandbox/runs/<run-id>.agent-started`. It is touched **only after a turn succeeds**, because a
  first call that died never created a session and `--resume` on a missing session would fail
  forever. The run record's schema is closed, which is why this is a file and not a field.
- **Synchronous by design.** The whole point is to read the reply and send the next turn.

Use it when you want to *steer* — inspect a failed build, ask what a file does, make a small fix —
without ssh-ing in and losing the thread between commands.

## Choosing, in one paragraph

Start with `execute`: it is the factory, it is detached, and walking away is the entire premise of
the system. Reach for `agent` when the next step needs judgment and you want a conversation that
survives between commands. Reach for `run` when you want to *look* at something — a log, a git
state, a port, a table — and nothing more.
