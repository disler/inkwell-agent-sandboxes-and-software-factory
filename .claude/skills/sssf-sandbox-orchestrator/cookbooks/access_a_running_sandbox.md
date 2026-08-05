# Access a running sandbox

Trigger: **the user wants to access the running sandbox** — "get me into the box", "give me a
terminal in there", "let me talk to the agent inside", "attach me to the run".

Two flows, chosen by what the user wants to touch:

| Flow | The user wants | Mechanism |
|---|---|---|
| **A — shell access** | a terminal inside the box | a herdr pane running `ssh <vm>.exe.xyz` |
| **B — join the agent** | to talk to the in-box orchestrator agent | `ssh -t` + `claude --resume` on the recorded session |

Both start the same way: resolve the VM from the run record, because the run id is the handle and
the record is the only truth about which box it names.

```bash
VM=$(sandbox_mount/host/run_record.py get <run-id> vm_name)
[ -n "$VM" ] || echo "not mounted — no vm_name in the record"
```

Neither flow is destructive, neither touches a key, and neither needs a new credential: the host's
exe.dev SSH access is the whole mechanism. What these flows hand the user is a **live interior** —
remind them the box is disposable, the repo clone in `app/` is the run branch, and anything worth
keeping leaves via `just sbx manage harvest`, not via copy-paste from a pane.

## Flow A — a herdr pane with SSH into the box

Follow the local `/herdr` skill (`.claude/skills/herdr/SKILL.md`) — it owns the herdr surface;
this cookbook only says what to build with it. The shape:

1. **Server up:** `herdr status server` → if not running, `herdr server &`.
2. **A labeled workspace for the run**, so panes group by sandbox and the label answers "which
   box is this":

   ```bash
   herdr workspace create --cwd "$PWD" --label sbx-<run-id>
   # capture .result.workspace.workspace_id AND .result.root_pane.pane_id
   ```

3. **SSH in the root pane.** `pane run` types the command and presses Enter; the pane is now a
   real interactive shell inside the box:

   ```bash
   herdr pane run <pane-id> "ssh $VM.exe.xyz"
   herdr pane run <pane-id> "cd app"
   ```

4. **Confirm before declaring victory** — read the pane, don't assume:

   ```bash
   herdr pane read <pane-id> --source visible --lines 10
   ```

5. **Hand the user the address:** report the workspace label and pane id. This is their pane
   now — do not keep typing into it once they have it. More eyes on the same box = more panes
   (`herdr pane split <pane-id> --direction right --no-focus`), one ssh each.

Do NOT `--no-focus` the pane the user asked for — they asked to be taken there. `--no-focus` is
for extra panes you add around them.

When the box dies (teardown), the ssh session ends and the pane shows a dead shell; close the
workspace (`herdr workspace close <id>`) as part of reporting the teardown, never before.

## Flow B — connect to the orchestrator agent inside the box

The box's steering agent is a **resumable Claude Code session**: its `session_id` was minted at
CREATE and lives in the run record; `just sbx run agent` has been the host's way of talking to
it one turn at a time. This flow joins that same session interactively.

1. **Resolve both handles:**

   ```bash
   VM=$(sandbox_mount/host/run_record.py get <run-id> vm_name)
   SID=$(sandbox_mount/host/run_record.py get <run-id> session_id)
   ```

2. **Check the session has started.** `--resume` on a session that never had a first turn fails.
   The bit lives beside the run record:

   ```bash
   test -e .sandbox/runs/<run-id>.agent-started
   ```

   If it does not exist, send the first turn through the recipe — never hand-roll
   `--session-id`, the recipe owns the sentinel:

   ```bash
   just sbx run agent <run-id> "status check — reply READY"
   ```

3. **Attach interactively.** Env verbatim from the verified `run agent` lane — the key-free
   exe.dev gateway, not OpenRouter, and never the engineer's personal keys (`okey` and its
   exports stay on the host; only the boot *flags* cross). The boot style is the engineer's
   `cldyo` shape — `--dangerously-skip-permissions --model "opus[1m]"`:

   ```bash
   ssh -t $VM.exe.xyz "cd app && ANTHROPIC_API_KEY=implicit \
     ANTHROPIC_BASE_URL=https://llm.int.exe.xyz \
     claude --resume $SID --dangerously-skip-permissions --model \"opus[1m]\""
   ```

   `-t` is mandatory: claude's interactive UI needs a TTY, and `ssh vm "cmd"` does not allocate
   one. Run this inside a herdr pane (flow A step 2, then `pane run` this command) when the user
   wants the conversation to persist beyond their terminal; run it bare when they just want in.

4. **On exit,** the session remains resumable — from the terminal again, or from the host via
   `just sbx run agent <run-id> "..."`. Same session, same memory, two doors.

**What this flow is NOT:** the detached SDLC (`just sbx lifecycle execute`) is not an agent you
can join — it is a pid and a `run.log`. "Attach me to the build" means
`just sbx run cmd <run-id> 'tail -f run.log'`, and that belongs to
[observe_and_report.md](observe_and_report.md).

## Which flow, when

| The user says | Flow |
|---|---|
| "ssh me in", "give me a shell", "let me poke around" | A |
| "let me talk to the agent", "connect me to claude in there" | B |
| "how is the run going" | neither — [observe_and_report.md](observe_and_report.md) |
| "run this command in there for me" | neither — `just sbx run cmd`, [execute_work.md](execute_work.md) |
