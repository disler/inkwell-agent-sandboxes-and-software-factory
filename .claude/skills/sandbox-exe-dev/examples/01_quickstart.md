# Example 01 — Quickstart end-to-end

A 5-minute walkthrough that exercises every command group at least once. Use this the first time you run the skill to verify everything connects.

## Prerequisites

```bash
cd .claude/skills/sandbox-exe-dev/exedev_cli
uv sync --quiet
uv run exedev doctor          # must end with `doctor: OK`
```

## 1. Create a VM

Pick a name. The name becomes the public URL.

```bash
WORKFLOW_ID="quickstart-$(date +%Y%m%d)-$(openssl rand -hex 2)"   # e.g. quickstart-20260508-7f3a
uv run exedev init --name "$WORKFLOW_ID" --cpu 2 --memory 4GB --tag demo
```

You should see `✓ VM created`. Capture `$WORKFLOW_ID` in your context.

## 2. Inspect

```bash
uv run exedev vm list
uv run exedev vm info "$WORKFLOW_ID"
```

## 3. Run a command

```bash
uv run exedev exec "$WORKFLOW_ID" "uname -a"
uv run exedev exec "$WORKFLOW_ID" "whoami"        # → exedev
uv run exedev exec "$WORKFLOW_ID" "ls /home" --cwd /
```

## 4. Write and read a file

```bash
echo 'print("hello from exe.dev")' \
  | uv run exedev files write "$WORKFLOW_ID" /home/exedev/hello.py --stdin

uv run exedev files read "$WORKFLOW_ID" /home/exedev/hello.py
uv run exedev exec "$WORKFLOW_ID" "python3 /home/exedev/hello.py"
```

## 5. Edit (literal-string find/replace, matches `sbx files edit`)

```bash
uv run exedev files edit "$WORKFLOW_ID" /home/exedev/hello.py \
  --old "hello from exe.dev" --new "hello, world"

uv run exedev files read "$WORKFLOW_ID" /home/exedev/hello.py
```

## 6. Host a frontend and expose it

```bash
# Tiny static server (no `--timeout 0` needed — we detach with nohup).
uv run exedev exec "$WORKFLOW_ID" \
  "echo '<h1>hello</h1>' > /home/exedev/index.html && python3 -m http.server 5173 --bind 0.0.0.0" \
  --cwd /home/exedev --background --shell

# Tell the proxy which port to forward to.
uv run exedev share port "$WORKFLOW_ID" 5173

# Make it anonymously reachable (E2B-equivalent default).
uv run exedev share set-public "$WORKFLOW_ID"

# Get the URL (deterministic).
uv run exedev share get-host "$WORKFLOW_ID"
# → https://quickstart-20260508-7f3a.exe.xyz/

curl "https://${WORKFLOW_ID}.exe.xyz/"
# → <h1>hello</h1>
```

## 7. Validate visually with the browser

```bash
uv run exedev browser init       # one-time
uv run exedev browser start
uv run exedev browser nav "https://${WORKFLOW_ID}.exe.xyz/"
uv run exedev browser eval "document.querySelector('h1').textContent"
uv run exedev browser screenshot --path /tmp/quickstart.png
uv run exedev browser close
```

## 8. Snapshot before destruction (unique-to-exe.dev)

```bash
uv run exedev vm snapshot "$WORKFLOW_ID" "${WORKFLOW_ID}-archive"
uv run exedev vm list
```

## 9. Tear down

```bash
uv run exedev vm kill "$WORKFLOW_ID"
uv run exedev vm kill "${WORKFLOW_ID}-archive"
```

## What just happened

You exercised every command group:

| Group     | Verb(s) used                           |
|-----------|----------------------------------------|
| top       | `init`, `doctor`                       |
| `vm`      | `list`, `info`, `snapshot`, `kill`     |
| `exec`    | basic, `--cwd`, `--background --shell` |
| `files`   | `write --stdin`, `read`, `edit`        |
| `share`   | `port`, `set-public`, `get-host`       |
| `browser` | `init`, `start`, `nav`, `eval`, `screenshot`, `close` |

Compare with `/agent-sandboxes/examples/05_host_frontend.md` — the verbs line up almost one-for-one; the differences (named VM, no `--timeout`, `share set-public` step) are exactly the parity-table-documented divergences.
