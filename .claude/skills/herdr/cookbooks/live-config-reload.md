# Cookbook: Live Config Reload Loop

## Purpose

Use this workflow while iterating on `~/.config/herdr/config.toml`. It runs
`herdr server reload-config` every two seconds in a dedicated shell pane, so
saved theme, spacing, sidebar, notification, and keymap changes appear without
restarting Herdr or dropping agents.

Use when the user asks to:

- live-reload Herdr configuration while editing it
- build or tune a Herdr theme interactively
- run a config watcher in a particular workspace, tab, or pane
- stop or inspect an existing reload loop

## Safety rules

1. Run `herdr --help` and `herdr pane --help` first; trust the installed CLI.
2. Resolve workspace, tab, and pane IDs from fresh list responses. Never turn
   human ordinals such as "space 1, tab 1, pane 2" directly into guessed IDs.
3. Inspect the target with `pane process-info` and `pane read` before typing.
4. Only reuse a pane whose foreground process is an idle shell. If it contains
   an agent, editor, server, or other task, create a utility pane with
   `pane split --no-focus` instead of interrupting it.
5. Do not steal focus. The reload loop does not require the target tab to be
   visible.
6. Report the resolved public IDs and explain that `Ctrl+C` stops the loop.

## Workflow

### 1. Confirm the server and CLI

```bash
herdr --help
herdr pane --help
herdr status server
```

If the server is not running, ask whether the user wants a headless server or
an attached TUI before starting one.

### 2. Resolve the requested target

List the live hierarchy:

```bash
herdr workspace list
herdr tab list --workspace <workspace-id>
herdr pane list
```

For a request such as "space 1, tab 1, pane 2":

1. Select the workspace whose response has `number: 1`.
2. List that workspace's tabs and select the requested tab number/label.
3. Filter `pane list` to that tab and select the requested visual/list position.
4. Capture the returned `pane_id`; do not infer it from the ordinal.

Example parsing pattern:

```bash
W=$(herdr workspace list \
  | jq -r '.result.workspaces[] | select(.number == 1) | .workspace_id')

T=$(herdr tab list --workspace "$W" \
  | jq -r '.result.tabs[] | select(.number == 1) | .tab_id')

P=$(herdr pane list \
  | jq -r --arg tab "$T" '[.result.panes[] | select(.tab_id == $tab)][1].pane_id')

test -n "$P" && test "$P" != "null"
```

Because panes can move or close between calls, use the freshly returned ID
immediately. If ordering is ambiguous, inspect `herdr pane layout --pane <id>`
and ask the user rather than guessing.

### 3. Verify that the target is safe

```bash
herdr pane process-info --pane "$P"
herdr pane read "$P" --source visible --lines 20
```

Proceed only when the foreground process is an idle shell. Otherwise, create a
utility pane without focus:

```bash
P=$(herdr pane split <safe-source-pane> --direction down --no-focus \
  | jq -r '.result.pane.pane_id')
```

### 4. Start the two-second reload loop

```bash
herdr pane run "$P" \
  'while true; do printf "[%s] " "$(date +%H:%M:%S)"; herdr server reload-config; sleep 2; done'
```

This intentionally prints every reload response. Successful cycles contain:

```text
"status":"applied","type":"config_reload"
```

Invalid or half-written TOML is reported as diagnostics; the loop continues and
applies the next valid save.

### 5. Verify that it is running

Prefer a blocking wait instead of sleeping and polling:

```bash
herdr wait output "$P" --match 'config_reload' --timeout 10000
herdr pane read "$P" --source visible --lines 12
```

`config_reload` does not appear in the typed loop command, so this wait matches
a real response rather than the shell's echoed command line.

### 6. Iterate on configuration

Edit the canonical active file:

```text
~/.config/herdr/config.toml
```

A persistent Herdr server owns the live configuration. Setting
`HERDR_CONFIG_PATH` only on a newly attached client does not reconfigure a
server that is already running. Activate/copy a profile to the canonical path
before relying on this loop, or start a fresh named session under the alternate
config path.

### 7. Stop and verify cleanup

From the Herdr UI, focus the reload pane and press `Ctrl+C`. From orchestration:

```bash
herdr pane send-keys "$P" ctrl+c
herdr pane process-info --pane "$P"
herdr pane read "$P" --source visible --lines 12
```

Confirm that the foreground process returned to the shell. Do not close the pane
unless the user asks; it may be their designated utility pane.

## Compact recipe

Use only after resolving and validating `$P`:

```bash
herdr pane run "$P" \
  'while true; do printf "[%s] " "$(date +%H:%M:%S)"; herdr server reload-config; sleep 2; done'
herdr wait output "$P" --match 'config_reload' --timeout 10000
herdr pane read "$P" --source visible --lines 12
```

Stop:

```bash
herdr pane send-keys "$P" ctrl+c
```

## Report format

Report concisely:

```text
Live config reload is running every 2 seconds in workspace <n>, tab <n>,
pane <n> (<pane-id>). The first config_reload response was applied successfully.
Stop it with Ctrl+C in that pane.
```
