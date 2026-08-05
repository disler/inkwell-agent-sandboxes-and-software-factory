# Browser Automation Cookbook (exe.dev)

Visual validation tools for VM-hosted applications using **Playwright's isolated Chromium**, lifted verbatim from `/agent-sandboxes` — same code, same flags, same semantics. Browser commands run on **your local machine**, not inside the VM.

## Quick Start

```bash
cd .claude/skills/sandbox-exe-dev/exedev_cli

# 1. Initialize (first time only — installs Playwright + Chromium locally)
uv run exedev browser init

# 2. Start browser
uv run exedev browser start

# 3. Navigate to your VM's URL
uv run exedev browser nav https://my-vm.exe.xyz/

# 4. Validate
uv run exedev browser eval "document.title"
uv run exedev browser screenshot --path validation.png

# 5. Close
uv run exedev browser close
```

## Commands Reference

```text
exedev browser <subcommand> [options]

  init                Install Playwright + Chromium locally (run once per machine)
  start               Start Chromium with remote debugging (CDP)
  status              Check connection status
  nav URL             Navigate to a URL
  screenshot          Take a screenshot of the active page
  eval CODE           Execute JavaScript in the page
  click SELECTOR      Click an element
  type SELECTOR TEXT  Type text into an input field
  press KEY           Press a keyboard key
  scroll DIRECTION    Scroll up/down/top/bottom
  a11y                Get accessibility tree snapshot
  dom [--full]        Get DOM (simplified default; `--full` = raw HTML)
  pick MESSAGE        Interactive element picker
  cookies             Get all cookies as JSON
  close               Close the browser process
```

## Headless vs Headed

```bash
uv run exedev browser start            # headless, no window (default)
uv run exedev browser start --headed   # show window (debug-friendly)
```

## Multi-agent parallel execution

Use unique `--port` per concurrent agent (default 9222):

```bash
# Agent 1
uv run exedev browser start
uv run exedev browser nav https://app1.exe.xyz/

# Agent 2
uv run exedev browser start --port 9223
uv run exedev browser nav https://app2.exe.xyz/ --port 9223
```

Pass `--port <p>` to **all** browser subcommands consistently.

## Validating an exe.dev-hosted app

```bash
# 1. Get the URL (deterministic; no API call needed).
uv run exedev share get-host my-vm
# https://my-vm.exe.xyz/

# 2. (Important) Make sure it's actually reachable.
#    For E2B-style anonymous access:
uv run exedev share set-public my-vm

#    Or, to keep it private and authenticate the browser session,
#    you'll need an exe.dev session cookie — run `exedev browser nav`
#    against an exe.dev login page first, then nav to the VM URL.

# 3. Drive Playwright.
uv run exedev browser start
uv run exedev browser nav https://my-vm.exe.xyz/
uv run exedev browser eval "document.readyState"
uv run exedev browser screenshot --path validation.png --full

# 4. Close.
uv run exedev browser close
```

## Common patterns

### Verify the page loaded
```bash
uv run exedev browser eval "document.readyState"
uv run exedev browser eval "document.title"
```

### Inspect UI structure
```bash
uv run exedev browser eval "document.querySelectorAll('button').length"
uv run exedev browser eval "Array.from(document.querySelectorAll('a')).map(a => a.href)"
```

### Form interactions
```bash
uv run exedev browser type "#username" "testuser"
uv run exedev browser type "#password" "testpass"
uv run exedev browser click "#submit"
```

### Accessibility tree (best for LLM-driven validation)
```bash
uv run exedev browser a11y
```

### Full-page screenshot
```bash
uv run exedev browser screenshot --full --path full-page.png
```

## Troubleshooting

### "Browser environment not initialized"
```bash
uv run exedev browser init
```

### "Could not connect to Chromium on port 9222"
```bash
uv run exedev browser start
```

### "Port already in use"
```bash
# Use a different port
uv run exedev browser start --port 9223

# Or close the existing browser
uv run exedev browser close --port 9222

# Or check what's using the port
lsof -i :9222
```

### Browser won't start at all
```bash
uv run exedev browser init                                    # re-run init
pkill -f "chromium.*remote-debugging"                         # kill stale processes
uv run exedev browser start --port 9223                       # try a different port
```

## Important notes

- Browser commands run on **your local machine**, not inside the exe.dev VM.
- Uses **Playwright's isolated Chromium** — does NOT touch your everyday Chrome profile.
- **Headless by default** — no visible window unless `--headed`.
- The browser persists across commands until `close`.
- This implementation is **identical** to `/agent-sandboxes`'s `sbx browser`. If you find a bug here, it's a bug there too — fix in both places.

## See also

- `../SKILL.md` — workflow and `share` family for getting URLs.
- `/agent-sandboxes/cookbook/browser.md` — the canonical version of this doc; we re-target the URL examples but the implementation is byte-identical.
