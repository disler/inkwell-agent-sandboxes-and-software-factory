# herdr Command Reference (validated against 0.7.1)

Complete CLI surface + socket methods. `SKILL.md` teaches the loop; this is the lookup table.
Everything returns NDJSON on stdout: `{"id":"cli:…","result":{…}}` or `{"id":…,"error":{"code":…,"message":…}}`.

## Launch, sessions & server

```bash
herdr                                  # launch/attach default session (TUI)
herdr --session <name>                 # named session (own server + socket)
herdr --remote <ssh-target>            # attach to a herdr server over SSH
herdr --remote <t> --remote-keybindings server
herdr --no-session                     # single-process escape hatch
herdr status [server|client]           # health check
herdr server                           # run headless server (orchestration without TUI)
herdr server stop                      # stop via socket
herdr server reload-config             # re-read config.toml live
herdr session list [--json]
herdr session attach <name>
herdr session stop <name>              # 'default' targets the default session
herdr session delete <name>
herdr update [--handoff]               # upgrade (handoff = live, no fleet restart)
herdr channel show | set stable|preview
```

## Workspaces

```bash
herdr workspace list
herdr workspace create [--cwd PATH] [--label TEXT] [--env K=V]... [--focus|--no-focus]
#  → result.workspace.workspace_id (w1), result.tab.tab_id (w1:t1), result.root_pane.pane_id (w1:p1)
herdr workspace get|focus|close <id>
herdr workspace rename <id> <label>
```

## Tabs

```bash
herdr tab list [--workspace <id>]
herdr tab create [--workspace <id>] [--cwd PATH] [--label TEXT] [--env K=V]... [--focus|--no-focus]
herdr tab get|focus|close <tab_id>
herdr tab rename <tab_id> <label>
```

## Panes

```bash
herdr pane list [--workspace <id>]          # every pane + agent_status
herdr pane current                          # the focused pane
herdr pane get <id> · layout · process-info · edges · neighbor --direction <dir>
herdr pane split [<id>] --direction right|down [--ratio F] [--cwd PATH] [--env K=V]... [--no-focus]
#  → result.pane.pane_id
herdr pane focus  --direction left|right|up|down [--pane ID]
herdr pane resize --direction <dir> [--amount FLOAT]
herdr pane zoom [<id>] [--toggle|--on|--off]
herdr pane swap --direction <dir> | --source-pane A --target-pane B
herdr pane move <id> --tab <tab_id> --split right|down [--target-pane ID] [--ratio F]
herdr pane move <id> --new-tab [--workspace ID] [--label TEXT]
herdr pane move <id> --new-workspace [--label TEXT] [--tab-label TEXT]
herdr pane rename <id> <label>|--clear
herdr pane close <id>

# I/O
herdr pane run       <id> "<command>"        # text + Enter
herdr pane send-text <id> "<text>"           # text only
herdr pane send-keys <id> <key> [key...]     # enter esc tab backspace up down ctrl+c alt+x shift+tab f1 minus plus backtick
herdr pane read <id> [--source visible|recent|recent-unwrapped] [--lines N] [--format text|ansi]

# Agent state / metadata (self-reporting)
herdr pane report-agent <id> --source ID --agent LABEL --state idle|working|blocked|unknown \
     [--message TEXT] [--custom-status TEXT] [--seq N] [--agent-session-id ID] [--agent-session-path PATH]
herdr pane report-agent-session <id> --source ID --agent LABEL [--agent-session-id ID] [--agent-session-path PATH]
herdr pane release-agent <id> --source ID --agent LABEL
herdr pane report-metadata <id> --source ID [--title T|--clear-title] [--display-agent T] \
     [--custom-status T] [--state-label STATUS=TEXT] [--ttl-ms N]
```

## Agents (target = agent name · terminal id · pane id)

```bash
herdr agent list
herdr agent get <target>
herdr agent read <target> [--source ...] [--lines N] [--ansi]
herdr agent send <target> "<text>"           # literal text, NO Enter (use pane run for cmd+Enter)
herdr agent rename <target> <name>|--clear
herdr agent focus <target>
herdr agent wait <target> --status idle|working|blocked|unknown [--timeout MS]
herdr agent attach <target> [--takeover]     # your terminal becomes that pane
herdr agent start <name> [--cwd PATH] [--workspace ID] [--tab ID] [--split right|down] \
     [--env K=V]... [--no-focus] -- <argv...>    # argv recorded in layout
herdr agent explain <target> [--json]        # why herdr thinks this pane is in this state
```

## Waits (blocking)

```bash
herdr wait output <pane_id> --match <text> [--regex] [--raw] \
     [--source visible|recent|recent-unwrapped] [--lines N] [--timeout MS]
#  → result.matched_line + result.read.text (a full read payload)
herdr wait agent-status <pane_id> --status idle|working|blocked|done|unknown [--timeout MS]
#  → {"event":"pane.agent_status_changed","data":{...}}
```

## Worktrees

```bash
herdr worktree list [--workspace ID | --cwd PATH] [--json]
herdr worktree create [--workspace ID | --cwd PATH] [--branch NAME] [--base REF] \
     [--path PATH] [--label TEXT] [--no-focus] [--json]
herdr worktree open (--path PATH | --branch NAME) [--label TEXT] [--json]
herdr worktree remove --workspace ID [--force] [--json]
# default checkout dir: ~/.herdr/worktrees ([worktrees] directory in config.toml)
```

## Integrations, plugins, notifications

```bash
herdr integration install|uninstall pi|omp|claude|codex|copilot|devin|droid|kimi|opencode|kilo|hermes|qodercli|cursor
herdr integration status [--outdated-only]

herdr plugin install <owner>/<repo>[/subdir] [--ref REF] [--yes]
herdr plugin list [--json] · uninstall · link <path> · unlink · enable · disable

herdr notification show <title> [--body TEXT] [--position top-left|top-right|bottom-left|bottom-right] [--sound none|done|request]
# returns shown:false reason:"disabled" until config.toml sets [ui.toast] delivery = "herdr"|"terminal"|"system"
```

## Socket API (NDJSON over Unix socket)

Socket: `~/.config/herdr/herdr.sock` · named: `~/.config/herdr/sessions/<name>/herdr.sock`
Override: `HERDR_SOCKET_PATH` · select session: `HERDR_SESSION=<name>`

```bash
printf '{"id":"1","method":"ping","params":{}}\n' | nc -U ~/.config/herdr/herdr.sock -w 2
```

Method families: `ping` · `server.*` · `notification.show` · `client.window_title.*` ·
`workspace.*` · `worktree.*` · `tab.*` · `pane.*` (35 methods incl. `pane.send_text`,
`pane.send_keys`, `pane.read`, `pane.report_agent`, `pane.wait_for_output`) ·
`layout.export` / `layout.apply` · `agent.*` · `events.subscribe` / `events.wait` ·
`integration.*` · `plugin.*`

```bash
# Layout as code — the BSP tree includes each agent pane's label + argv:
printf '{"id":"2","method":"layout.export","params":{"tab_id":"w1:t1"}}\n' | nc -U ~/.config/herdr/herdr.sock -w 2

# Push events (snapshot-replay of existing state first, then live stream):
printf '{"id":"3","method":"events.subscribe","params":{"subscriptions":[{"type":"pane.agent_status_changed"}]}}\n' \
  | nc -U ~/.config/herdr/herdr.sock > /tmp/herdr.ev &
```

Event types: `workspace.created/updated/renamed/closed/focused` ·
`pane.created/closed/focused/moved/exited/agent_detected/output_matched/agent_status_changed` ·
`worktree.created/opened/removed`

## Environment variables

| Var | Meaning |
|---|---|
| `HERDR_ENV=1` | you are inside a herdr-managed pane |
| `HERDR_PANE_ID` / `HERDR_TAB_ID` / `HERDR_WORKSPACE_ID` | where you are |
| `HERDR_SESSION` | select a named session for CLI calls |
| `HERDR_SOCKET_PATH` | socket override |
| `HERDR_CONFIG_PATH` | config override (`~/.config/herdr/config.toml`) |
| `HERDR_LOG` | log filter, e.g. `herdr=debug` |
| `HERDR_DISABLE_SOUND` | mute audio |

## Config quick hits (`~/.config/herdr/config.toml`)

```toml
[ui.toast]      delivery = "herdr"          # enable notification toasts (default off)
[session]       resume_agents_on_restore = true
[worktrees]     directory = "~/.herdr/worktrees"
[terminal]      default_shell = "zsh"       # new_cwd = "follow"|"home"|fixed
[theme]         name = "tokyo-night"        # 18 built-ins; [theme.custom] for colors
[keys]          prefix = "ctrl+b"           # full rebinding + [[keys.command]] custom verbs
[update]        channel = "stable"          # or "preview"
[update]        version_check = false       # off = no background version poll to herdr.dev (default on)
[update]        manifest_check = false      # off = no background agent-manifest download (default on)
```

Apply live: `herdr server reload-config`.

**Background egress note:** `version_check`/`manifest_check` are the only two
"phone-home" behaviors and are **on by default** (download-only, but they reveal
IP/version to herdr.dev). Set both `false` for offline/air-gapped installs — see
[`cookbooks/setup-disable-network-checks.md`](../cookbooks/setup-disable-network-checks.md).
Manual `herdr update`, `herdr server update-agent-manifests`, remote SSH attach,
and plugins can still use the network by design.

## Validated gotchas (all reproduced on 0.7.1)

1. **Sentinel echo-match**: `wait output` matches the typed command line too. Split the token: `echo DONE_"TOKEN"`.
2. **Empty scrollback reads**: `--source recent`/`recent-unwrapped` return empty until output scrolls; `visible` always works.
3. **Wrapped reads**: `recent` wraps at pane width; use `recent-unwrapped` for greppable lines.
4. **Fresh-pane buffering**: input sent before the shell is up is queued and runs later — reads look empty meanwhile.
5. **`agent send` ≠ submit**: it writes literal text; follow with `send-keys enter`, or use `pane run` for shell commands.
6. **Toasts disabled by default**: `notification show` → `shown:false` until `[ui.toast] delivery` is set.
7. **`wait agent-status` on a bare shell never fires** — the pane must have an integration-launched, `agent start`-launched, or self-reported agent.
8. **`events.subscribe` replays existing state** before streaming — dedupe if you only want *new* events.
9. **Idle ≠ success**: an agent that declined the task also goes idle; read the pane after the wait.
