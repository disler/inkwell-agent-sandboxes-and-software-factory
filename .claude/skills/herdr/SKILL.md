---
name: herdr
description: Drive herdr — the terminal-native agent multiplexer (herdr.dev) — from natural language. Use whenever a prompt asks you to open, inspect, prompt, read, wait on, or tear down herdr sessions, workspaces, tabs, panes, or the agents running inside them, or to launch/orchestrate coding agents (claude, codex, pi, opencode, cursor) inside herdr. Prefix orchestration prompts with /herdr. Fully self-contained — all references and cookbooks are bundled in this skill directory.
argument-hint: [what to do in herdr]
---

# herdr

## Purpose

You are driving **herdr**, a CLI + NDJSON socket for controlling a persistent
fleet of terminal panes (and the agents running inside them). Every workspace,
tab, and pane is a real, addressable object you can spawn, prompt, read, wait
on, and close from the command line — locally, in named sessions, or over SSH.
Unlike a plain multiplexer, herdr also tracks **semantic agent state**
(`idle · working · blocked · done`), so you can block on *"the agent finished"*
instead of scraping screens.

## Instructions

### Discover commands first (`--help`)

Before doing anything, run:

```bash
herdr --help
herdr <command> --help     # e.g. herdr pane --help, herdr wait --help
```

herdr evolves fast (validated here against `0.7.1`); **trust `--help` over
memory**. Never guess flags — confirm them.

When you need the full surface at once — every command's flags, the socket
API's method families, event types, environment variables, or config keys —
read [`references/command-reference.md`](references/command-reference.md)
instead of running many `--help` calls. It's the validated lookup table
(including all reproduced gotchas); still confirm against `--help` if the
installed version differs from `0.7.1`.

### Make sure a server is running

The CLI talks to a server over `~/.config/herdr/herdr.sock`. Check and start:

```bash
herdr status server            # "status: running" or "not running"
herdr server &                 # headless server — no TUI needed to orchestrate
```

Anyone on the box can drive the socket — **you do not need to run inside a
herdr pane** to orchestrate (no permission mode to raise). Inside a pane,
`HERDR_ENV=1` plus `HERDR_PANE_ID` / `HERDR_TAB_ID` / `HERDR_WORKSPACE_ID`
tell you where you are; use them to avoid touching your own pane.

### Understand the hierarchy

Everything nests in one tree. Learn the boxes and the verbs fall out:

- **Session** → a persistent server (default, or named via `--session <name>`).
- **Workspace** → a project-level container. ID: `w1`.
- **Tab** → a page of panes inside a workspace. ID: `w1:t1`.
- **Pane** → one real PTY (a shell or an agent). ID: `w1:p1`.

Every command returns **JSON on stdout** — parse IDs from the result, never
guess them. IDs compact as things close; refresh with `list` before acting.

```bash
herdr workspace list                 # all workspaces
herdr tab list --workspace w1        # tabs in a workspace
herdr pane list                      # every pane + its agent_status
herdr agent list                     # only panes with a detected/reported agent
```

### Create the topology

```bash
# Workspace: capture workspace_id AND the root pane_id from one call.
herdr workspace create --cwd "$PWD" --label fleet --no-focus
#   → .result.workspace.workspace_id  (w1)
#   → .result.root_pane.pane_id       (w1:p1)

# Splits: each returns the new pane's id.
P2=$(herdr pane split w1:p1 --direction right --no-focus | jq -r .result.pane.pane_id)
P3=$(herdr pane split w1:p1 --direction down  --no-focus | jq -r .result.pane.pane_id)

# Tabs and env injection:
herdr tab create --workspace w1 --label logs --no-focus
herdr pane split w1:p1 --direction right --env OPENROUTER_API_KEY="$OPENROUTER_API_KEY" --no-focus
```

- **Always pass `--no-focus`** when scripting so you don't steal the human's focus.
- Env injection is per-flag (`--env KEY=VALUE`, repeatable) on `workspace create`,
  `tab create`, `pane split`, and `agent start` — there is no `--env-file`; expand
  from your own shell (`--env KEY="$KEY"`) and never echo the values.
- **Closing the last pane deletes the workspace (verified).** Never `pane close`
  the sole/root pane of a workspace you want to keep — the workspace goes with
  it, and a pending `agent start --workspace <id>` against it fails silently. To
  swap what's in a workspace, split the NEW pane in FIRST, then close the old
  one; to reuse the root pane, `pane run`/`agent start --split` off it rather
  than closing it.
- **Capture BOTH ids from `workspace create`** —
  `.result.workspace.workspace_id` AND `.result.root_pane.pane_id` — and thread
  them through; never rely on focus to place a pane.

### The control loop

You operate panes the way a person would, but over the CLI:

```bash
herdr pane run       w1:p2 "just test"       # type a command AND press Enter
herdr pane send-text w1:p2 "some text"       # type only — does NOT submit
herdr pane send-keys w1:p2 enter             # press a key (esc, tab, ctrl+c, up…)
herdr pane read      w1:p2 --source visible --lines 40    # your eyes
herdr pane close     w1:p2                   # end a pane cleanly
```

- **`pane run` = text + Enter. `send-text` types only.** For shell commands use
  `run`; for driving an interactive TUI agent use `send-text` then
  `send-keys enter` as two steps.
- **`send-keys` accepts real chords** (`ctrl+c`, `alt+x`, `shift+tab`) — you can
  interrupt a running process without killing the pane.
- Read sources: **`visible`** (current screen — the reliable default),
  `recent` / `recent-unwrapped` (scrollback; `-unwrapped` undoes pane-width
  line wrapping). **Scrollback reads can come back empty** until output has
  actually scrolled — if `recent` returns nothing, fall back to `visible`.
- **Fresh panes buffer input.** Text sent before the shell finishes starting is
  queued, not lost — but reads will look empty for a beat. Give a new pane a
  moment (or `wait output --match '\$|%' --regex`) before judging silence.

### Wait, don't poll

herdr's killer verbs are **blocking waits** — prefer them over `sleep`+read loops:

```bash
# Block until a pane prints something (returns the matched line + a read payload):
herdr wait output w1:p3 --match "Server running" --timeout 60000
herdr wait output w1:p3 --match "PASS|FAIL" --regex --timeout 120000

# Block until an agent's semantic state changes (the agent-finished signal):
herdr wait agent-status w1:p2 --status idle --timeout 300000
```

- **Sentinel pitfall (verified):** `wait output` also matches the *echoed
  command line*. If you run `echo DONE_TOKEN`, the wait fires on the typed
  command, not the output. Split the sentinel in the command —
  `sh -c 'make test && echo DONE_"TOKEN"'` — so only real output matches.
- **Stale-scrollback pitfall (verified 0.7.1):** `wait output` can also fire on
  matching text ALREADY in the pane from earlier runs — it is not
  "new output only." For TUI agents that print the same marker format every
  turn (e.g. a per-run `artifacts:` line), a repeated-marker wait false-fires
  instantly on the previous turn's output. For driving multi-turn TUI sessions,
  poll the app's state line instead (e.g. read the last footer rows every
  10-15s until no `working` appears for several consecutive polls), or match
  text unique to the NEW turn.
- `wait agent-status` needs the pane to *have* an agent state: launch through an
  installed integration (`herdr integration install claude codex …` — one per
  call) or via `herdr agent start`, or self-report (below). A bare shell pane
  stays `unknown` forever and the wait just times out.
- For fan-in across many panes, run several `wait`s in parallel shell jobs and
  `wait` on them, or subscribe to events on the socket (see Socket API).

### Semantic agent state — the beyond-tmux feature

Every pane carries `agent_status`: `idle · working · blocked · done · unknown`.
Integrated agents report it automatically; your own scripts can too:

```bash
herdr pane report-agent w1:p4 --source custom:build --agent worker-1 \
  --state working --message "compiling"          # …later: --state idle
herdr agent list                                  # fleet dashboard in one call
herdr agent read worker-1 --source visible --lines 30   # target agents BY NAME
herdr agent send worker-1 "continue"              # literal text (no Enter — send-keys after)
```

`agent <verb>` targets accept **agent names**, terminal ids, or pane ids —
name your agents and stop threading pane ids everywhere.

### Launching agents

```bash
# Named, tracked, declarative — prefer agent start over run "claude":
herdr agent start reviewer --workspace w1 --split right --no-focus -- \
  claude --dangerously-skip-permissions "review this repo"

# Codex unattended:  codex -m gpt-5.5 --dangerously-bypass-approvals-and-sandbox "<task>"
# pi:                pi --model <model> "<task>"

# Claude Code + the user's real Chrome (browser-driving agent):
herdr agent start creds-runner --tab w1:t1 --split down --cwd <repo> --no-focus -- \
  claude --dangerously-skip-permissions --chrome "<task that browses>"
```

- **`agent start --split` / `pane split` with no explicit target splits the
  FOCUSED pane** — which may be in another workspace entirely, landing your
  agent in the wrong place. ALWAYS target explicitly: `--tab <ws>:t1` (or
  `--workspace <ws>`), or split the captured `root_pane.pane_id`.
- **Always pass `--cwd "$PWD"` on `agent start`** — it otherwise defaults to
  `~/Desktop`, so a repo-relative brief pointer ("Read prompts/x.md") fails.
- Safe pattern — launch an agent into a FRESH workspace (capture both ids,
  target explicitly, never close the root pane):
  ```bash
  read WS ROOT < <(herdr workspace create --cwd "$PWD" --label <topic> --no-focus \
    | jq -r '.result | "\(.workspace.workspace_id) \(.root_pane.pane_id)"')
  herdr agent start <name> --tab "${WS}:t1" --split right --cwd "$PWD" --no-focus -- \
    claude --dangerously-skip-permissions --model <model> "Read prompts/<brief>.md and execute end-to-end."
  # do NOT close $ROOT — closing the last pane deletes $WS
  ```
- **`claude --chrome`** attaches the agent to the user's actual Chrome (logged-in
  sessions and all) — the right tool for signups, dashboards, key retrieval, and
  any flow where the human must take over mid-stream (logins, payments, captchas).
  Prompt the agent to print a clear `WAITING ON <human>: <what to do>` line in its
  pane and poll the page rather than failing, so the human can complete the step
  in the browser and the agent resumes on its own.

- `agent start` records the **argv in the layout** (so `layout.export` can
  rebuild the fleet) and registers the name for `agent read/send/wait`.
- **Claude Code panes: also name the agent inside the session.** After the
  task prompt has been sent, follow up with the `/name` slash command so the
  Claude Code session itself carries the same name as its herdr registration
  (shows in the CC UI/session, not just the herdr fleet):
  ```bash
  herdr agent send reviewer "/name reviewer"   # literal text, no Enter
  herdr pane send-keys <pane_id> enter         # submit (send-keys is pane-level only;
                                               # get the pane_id from `herdr agent get reviewer`)
  ```
  Safe to send while the agent is mid-turn — Claude Code queues the message.
- Launch Claude Code with `--dangerously-skip-permissions` and Codex with
  `--dangerously-bypass-approvals-and-sandbox` for hands-off fleet runs —
  per-launch flags only; never edit the user's global agent config.
- An agent turning `idle` does **not** mean it succeeded — a declined turn also
  goes idle. Always `read` the pane (or check artifacts) after the wait fires.

### Worktrees, sessions & remote (parity-and-beyond surface)

```bash
# Git worktree per agent — parallel agents without file collisions:
herdr worktree create --workspace w1 --branch feat-auth --label auth --json

# Named sessions — one fleet per project, each with its own socket:
herdr --session api            # create/attach
herdr session list --json      # HERDR_SESSION=api herdr pane list  → script it
herdr session stop api

# Remote: the same verbs against a server on another box:
herdr --remote workbox         # SSH attach; panes survive your disconnect
```

Detach (`prefix+q`) or close the terminal — **agents keep running**; `herdr`
reattaches. That persistence is the core difference from an app-bound fleet.

### Layouts as code & the socket API

The CLI is sugar over newline-delimited JSON on a Unix socket
(`~/.config/herdr/herdr.sock`; named sessions under
`~/.config/herdr/sessions/<name>/`). Anything the CLI does, one JSON line does:

```bash
printf '{"id":"1","method":"ping","params":{}}\n' | nc -U ~/.config/herdr/herdr.sock -w 2
printf '{"id":"2","method":"layout.export","params":{"tab_id":"w1:t1"}}\n' | nc -U ~/.config/herdr/herdr.sock -w 2 > fleet.layout.json
# layout.apply rebuilds the BSP tree — including each agent pane's argv.
```

Subscribe to push events (`pane.agent_status_changed`, `pane.created`,
`pane.output_matched`, `workspace.*`, `worktree.*`) with `events.subscribe`;
note it **replays a snapshot of existing state first**, then streams. Stream to
a file and grep the file — piping through `jq` in a one-liner can stall on
buffering.

### Notifications

```bash
herdr notification show "fleet done" --body "3/3 green" --sound done
```

Toast delivery is **off by default** — the call returns
`"shown": false, "reason": "disabled"` until the user sets
`[ui.toast] delivery = "herdr"` (or `terminal`/`system`) in
`~/.config/herdr/config.toml`, then `herdr server reload-config`. Check the
response; don't assume the human saw it.

### Cookbook workflows

Load cookbook files only when their workflow matches the request:

- **Live config/theme iteration:** read
  [`cookbooks/live-config-reload.md`](cookbooks/live-config-reload.md) when the
  user wants Herdr to reload `config.toml` continuously, asks for a live theme
  development loop, names a pane for config watching, or wants to stop that
  loop. The cookbook resolves human ordinals to fresh IDs, checks that the pane
  is an idle shell, runs `server reload-config` every two seconds, verifies the
  first applied response, and documents safe shutdown.
- **Lock down outbound network / go offline:** read
  [`cookbooks/setup-disable-network-checks.md`](cookbooks/setup-disable-network-checks.md)
  when the user wants Herdr fully local-only, air-gapped, or to stop it
  contacting `herdr.dev` — i.e. disabling the two background checks
  (`update.version_check`, `update.manifest_check`) that are **on by default**.
  Run this as a setup step when provisioning Herdr into sandboxes, VMs, or new
  devices. The cookbook locates the active `config.toml`, sets both keys to
  `false` idempotently (preserving other keys), applies via
  `server reload-config`, and verifies.

### Best practices

1. **`--help` before every unfamiliar verb**; confirm flags exist on this version.
2. **Look before you leap** — `pane list` / `agent list` before sending or closing.
3. **Parse IDs from JSON results; never guess.** IDs compact when things close.
4. **`--no-focus` everywhere** when scripting; you are a guest in the user's terminal.
5. **Prefer `wait` over polling** — `wait output` for text, `wait agent-status` for turn-done.
6. **Read back to verify** after the wait fires; an idle agent may have declined.
7. **Close scoped, never broad** — close only panes you created; never loop-close `pane list`.
8. **Never print secrets** — inject with `--env KEY="$KEY"`; don't `read` a pane right after it echoed a key.
9. **Inside a pane, don't drive your own pane** — check `HERDR_PANE_ID` and act on siblings.
10. **Target workspace/tab explicitly on split/start; never close a workspace's last pane.** Focus-relative splits and last-pane closes are the two ways agents land in the wrong workspace or vanish.

## Workflow

The default loop for any orchestration task:

1. `herdr status server` (start `herdr server &` if needed) → `herdr --help` to confirm verbs.
2. Inspect current state: `workspace list` / `pane list` / `agent list`.
3. Build topology: `workspace create` → `pane split` / `agent start`, capturing every ID from JSON.
4. Drive: `pane run` (or `send-text` + `send-keys enter` for TUIs).
5. Block: `wait output` / `wait agent-status` with a timeout.
6. Verify: `pane read --source visible`, then act on what it says.
7. Teardown what you created: `pane close` → `workspace close`.

## Examples

**"Stand up two agents on the same question and compare"** → workspace create;
split right; `agent start` claude + codex with the prompt in argv; two parallel
`wait agent-status --status idle`; `agent read` both; synthesize; teardown.

**"Run the tests and tell me when they're done"** → `pane split --no-focus`;
`pane run` with a split sentinel (`&& echo TESTS_"OK" || echo TESTS_"FAIL"`);
`wait output --match 'TESTS_(OK|FAIL)' --regex`; read; report; close the pane.

**"Save this fleet so I can boot it tomorrow"** → `layout.export` per tab to
JSON files; later `layout.apply` — agent panes relaunch from recorded argv.

**"Live-reload config every two seconds in space 1, tab 1, pane 2"** → read
`cookbooks/live-config-reload.md`; resolve each ordinal from current list JSON;
verify the target is an idle shell; start the loop; wait for `config_reload`;
report the resolved pane ID and `Ctrl+C` shutdown path.

**"Make sure Herdr never phones home before we ship it to the sandboxes"** →
read `cookbooks/setup-disable-network-checks.md`; locate the active
`config.toml`; set `[update] version_check = false` and `manifest_check = false`
idempotently; `herdr server reload-config`; grep the file to confirm; report the
two keys and the remaining by-design egress paths (`herdr update`, remote SSH,
plugins).

## Report Format

Report concisely in plain English: what you did, the workspaces/panes/agents
involved (cite ids like `w1:p3` or agent names), what the wait returned, and
what `pane read` confirmed. Never echo secret values or full env dumps.
