# Cookbook: Setup — Disable Herdr's Background Network Checks

## Purpose

Herdr's core binary is local-first — **no account, no telemetry, no hosted
control plane** — but out of the box it makes **two background, download-only
HTTP requests to `herdr.dev`**:

| Config key             | Default | What it does                                                        |
| ---------------------- | ------- | ------------------------------------------------------------------- |
| `update.version_check` | on      | Background poll of `herdr.dev` for a newer Herdr release.           |
| `update.manifest_check`| on      | Background download of updated agent-detection rules from `herdr.dev`. |

Neither uploads your code, prompts, keystrokes, or session data — they **pull**
data down. But any request to `herdr.dev` still exposes standard connection
metadata (your IP, request timing, your installed Herdr version) to that server
and its CDN. For a strict "nothing leaves this device" posture, both must be
`false` in `config.toml`.

Use this workflow when the user asks to:

- make Herdr fully offline / local-only / air-gapped
- stop Herdr from "phoning home" or contacting `herdr.dev`
- disable Herdr's version and/or agent-manifest update checks
- audit and lock down Herdr's outbound network behavior in `config.toml`

This is a **setup/config** cookbook — it edits `config.toml` and reloads the
running server. It does **not** touch panes or agents.

## What this does and does NOT cover

- ✅ Stops the two background checks above.
- ✅ Idempotent — safe to re-run; reports "already correct" when nothing changes.
- ✅ Preserves any existing `[update]` keys (e.g. `channel = "stable"`).
- ⚠️ Manual, on-demand fetches are **not** background checks and still reach the
  network when *you* invoke them: `herdr update` (self-update) and
  `herdr server update-agent-manifests` (force manifest pull). For a strict
  posture, simply don't run those.
- ⚠️ **Plugins are third-party code** and can make their own network calls
  regardless of these flags. Audit any plugin you install; this cookbook does
  not sandbox them.
- ⚠️ **Remote attach** (`herdr --remote <host>`) intentionally connects over
  SSH to hosts *you* name — that is expected egress, not a background check.
- 🔒 To *guarantee* silence beyond config, firewall `herdr.dev` at the host and
  build from the AGPL-3.0 source (`github.com/ogulcancelik/herdr`).

## Safety rules

1. Run `herdr --help` and `herdr server --help` first; trust the installed CLI
   over memory (validated here against `0.7.x`).
2. Resolve the **canonical active config path** before editing (below). A
   running server owns the live config; editing a file it isn't reading, or
   setting `HERDR_CONFIG_PATH` only on a new client, changes nothing on the
   live server.
3. **Back up** `config.toml` before writing, and preserve every other setting.
4. Never rewrite the whole file blind — set only the two keys, keep the rest.
5. Apply with `herdr server reload-config` and **verify the response** and the
   file contents; don't assume the write took effect.

## Workflow

### 1. Confirm the CLI and locate the active config

```bash
herdr --help
herdr server --help
herdr status server
```

The canonical config path is `HERDR_CONFIG_PATH` if set, otherwise
`~/.config/herdr/config.toml`:

```bash
CFG="${HERDR_CONFIG_PATH:-$HOME/.config/herdr/config.toml}"
echo "active config: $CFG"
mkdir -p "$(dirname "$CFG")"
```

> A persistent server reads the config it was started with. If the user runs a
> named session or a non-default path, confirm which file that server loaded
> and edit **that** file — otherwise `reload-config` re-reads a file you didn't
> change. When in doubt, ask.

### 2. Show the current state

```bash
grep -nE '^\s*\[update\]|version_check|manifest_check' "$CFG" 2>/dev/null \
  || echo "(no [update] settings yet — background checks are ON by default)"
```

Both keys default to on, so **absence means the checks are active**.

### 3. Set both keys to `false`

**Preferred (agent-native):** open `$CFG` with your file tools, ensure an
`[update]` table exists, and set both keys — leaving `channel` and every other
table untouched. The desired end state is:

```toml
[update]
version_check  = false   # no background version poll to herdr.dev
manifest_check = false   # no background agent-manifest download from herdr.dev
# channel = "stable"     # keep any existing keys as-is
```

**Scripted fallback (idempotent, stdlib-only, preserves other keys):**

```bash
CFG="${HERDR_CONFIG_PATH:-$HOME/.config/herdr/config.toml}" python3 - <<'PY'
import os, re, pathlib
cfg = pathlib.Path(os.environ["CFG"])
cfg.parent.mkdir(parents=True, exist_ok=True)
src = cfg.read_text() if cfg.exists() else ""
lines = src.splitlines()
want = {"version_check": "false", "manifest_check": "false"}

hdr = re.compile(r'^\s*\[([^\[\]]+)\]\s*(#.*)?$')          # a table header line
def key_re(k): return re.compile(r'^\s*' + re.escape(k) + r'\s*=')

start = None
for i, ln in enumerate(lines):
    m = hdr.match(ln)
    if m and m.group(1).strip() == "update":
        start = i
        end = len(lines)
        for j in range(i + 1, len(lines)):
            if hdr.match(lines[j]):
                end = j; break
        break

if start is None:                                          # no [update] table — append one
    block = ["[update]"] + [f"{k} = {v}" for k, v in want.items()]
    if src and not src.endswith("\n"): block = [""] + block
    else: block = (["", *block] if src.strip() else block)
    lines += block
else:                                                      # update existing table in place
    body = lines[start + 1:end]
    for k, v in want.items():
        for idx, b in enumerate(body):
            if key_re(k).match(b):
                body[idx] = f"{k} = {v}"; break
        else:
            body.append(f"{k} = {v}")
    lines = lines[:start + 1] + body + lines[end:]

out = "\n".join(lines).rstrip("\n") + "\n"
if out == src:
    print("already correct:", cfg)
else:
    if cfg.exists():
        cfg.with_name(cfg.name + ".bak").write_text(src)
        print("backup written:", cfg.name + ".bak")
    cfg.write_text(out)
    print("updated:", cfg)
PY
```

The script only ever touches those two keys, backs the file up before writing,
and is safe to run repeatedly.

### 4. Apply to the running server

```bash
herdr server reload-config
```

A successful reload response contains:

```text
"status":"applied","type":"config_reload"
```

If the server was not running, no reload is needed — the next `herdr` start
reads the updated file. Invalid TOML is reported as diagnostics and the old
config stays live; fix the file and reload again.

### 5. Verify

```bash
grep -nE 'version_check|manifest_check' "$CFG"
```

Expect exactly:

```text
version_check  = false
manifest_check = false
```

For extra assurance that no live check fires, watch outbound connections to
`herdr.dev` for a bit (nothing new should appear from the `herdr` process):

```bash
# macOS
nettop -p "$(pgrep -x herdr | head -1)" -l 1 2>/dev/null | grep -i herdr.dev || echo "no herdr.dev connections observed"
# Linux
lsof -nPi 2>/dev/null | grep -iE 'herdr.*(:443|:80)' || echo "no herdr.dev connections observed"
```

## Compact recipe

```bash
CFG="${HERDR_CONFIG_PATH:-$HOME/.config/herdr/config.toml}"
# ... run the python block from step 3 (CFG is exported into it) ...
herdr server reload-config
grep -nE 'version_check|manifest_check' "$CFG"
```

## Report format

Report concisely:

```text
Herdr background network checks are now disabled in <config path>:
  update.version_check  = false
  update.manifest_check = false
Applied live (config_reload: applied). A backup was saved as config.toml.bak.
Note: `herdr update`, `herdr server update-agent-manifests`, remote SSH attach,
and any installed plugins can still use the network by design.
```
