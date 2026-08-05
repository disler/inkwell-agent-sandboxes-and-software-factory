# Mounting exe.dev Sandboxes — Research

> Research only. Nothing here is built. Sources are the **live exe.dev CLI** (`ssh exe.dev help <cmd>`),
> the **official docs served over SSH** (`ssh exe.dev doc <slug>`), and the **open-source exeuntu
> Dockerfile** (`github.com/boldsoftware/exeuntu`). The web docs at `exe.dev/docs` render client-side
> and return nothing to a fetcher — `ssh exe.dev doc` is the fetchable form of the same pages.
>
> Date verified: 2026-08-04.
>
> **Everything in §11 was measured on real VMs on 2026-08-04**, not inferred. Where a measurement
> contradicted an inference, the inference has been corrected in place.

---

## 0. The one-sentence model

**The exe.dev API *is* SSH.** There are two planes:

| Plane | Address | What it does |
| --- | --- | --- |
| Control | `ssh exe.dev <verb>` | create / list / delete / resize / share / integrations |
| Data | `ssh <vm>.exe.xyz "<cmd>"` | anything inside the VM — it's just a Linux box |

`--json` on any control-plane verb makes it scriptable. `POST https://exe.dev/exec` is the same API
with the SSH command in the body (bearer token via `ssh exe.dev ssh-key generate-api-key --exp=30d`),
but it caps at 30s/64KB — **SSH is the right transport for mounts**.

Docs (`doc api`): *"The exe.dev API is SSH. Run commands like `ssh exe.dev ls --json` or `ssh exe.dev new --json` directly from scripts and automation."*

---

## 1. Verified `new` surface

From `ssh exe.dev help new` (authoritative — note there is **no** `--command` flag despite what
third-party write-ups suggest):

```
new [--name] [--image] [--cpu] [--memory] [--disk] [--env] [--tag]
    [--setup-script] [--prompt] [--integration] [--registry-auth]
    [--comment] [--pool] [--no-email] [--json]
```

| Flag | Notes that matter for mounting |
| --- | --- |
| `--name` | Auto-generated if omitted. **Becomes the public URL** `https://<name>.exe.xyz`. |
| `--image` | Any container image. Default `exeuntu`. |
| `--cpu` / `--memory` / `--disk` | `--cpu=4 --memory=16GB --disk=50GB`. Sized at create; live-resizable later. |
| `--env` | `KEY=VALUE`, repeatable. |
| `--tag` | Repeatable/comma-separated. **Tags are how integrations auto-attach.** |
| `--setup-script` | Runs on **first boot, once**. **Max 10KiB.** Supports `\n`. `/dev/stdin` to pipe. |
| `--prompt` | Initial prompt to **Shelley** (exe.dev's built-in agent) after creation. `/dev/stdin` supported. |
| `--integration` | Attach integrations at create time (GitHub repos, LLM gateway, HTTP proxies). |
| `--registry-auth` | `USERNAME:PASSWORD` for private registries. |

Boot is ~0.6–2s: the docs describe it as attaching a block device carrying the container image.

---

## 2. What is already inside the default image

This is the single biggest lever on mount speed. From the **exeuntu Dockerfile**:

```
FROM ubuntu:24.04
LABEL "exe.dev/login-user"="exedev"
LABEL "exe.dev/install-shelley"="true"
EXPOSE 8000 9999
```

**Preinstalled — do not waste mount time reinstalling:**

| Category | Present |
| --- | --- |
| Coding agents | **`claude` → `/usr/local/bin/claude`**, **`codex`**, **`pi` → `/usr/local/bin/pi`** (installed to `/home/exedev/.local/bin/pi`, symlinked) |
| Python | `python3`, `python3-pip`, `pipx`, **`uv` → `/usr/local/bin/uv`** |
| VCS | `git`, **`gh`** (GitHub CLI) |
| Data | `sqlite3`, `jq` |
| Transfer | `rsync`, `scp`, `openssh-client`, `netcat`, `socat` |
| Containers | `docker.io`, `docker-buildx`, `docker-compose-v2` |
| Search/build | `ripgrep`, `fd`, `make`, `build-essential`, Go |
| Browser | headless Chrome (`/headless-shell`) |
| Media | `ffmpeg`, `imagemagick` |

**NOT present — this repo must install these:**

- **`bun`** — required by `apps/inkwell` *and* by the SSSF visualizer.
- **`node` / `npm`** — absent entirely.
- **`just`** — the factory's entry point (or bypass it and call `uv run adws/adw_*.py` directly).

So the gap for this codebase is small and fixed: **bun + just**. Everything the *agents* need
(`claude`, `pi`, `uv`, `git`) is already there.

> **Implication for `EXPOSE 8000 9999`:** the proxy auto-picks the smallest exposed TCP port ≥1024,
> so a default exeuntu VM proxies **port 8000**. Inkwell serves 4501 and the visualizer serves its
> own port — both need an explicit `share port`, see §7.

---

## 3. Six ways to mount

Ordered slowest-and-most-flexible → fastest.

### A. Blank VM

```bash
ssh exe.dev new --name inkwell-scratch --json
```

Two seconds, nothing configured. Useful as a control, or when the setup is exploratory.

### B. Create + push files (create, then data plane)

The docs' own recommendation: *"The simplest and most common approach is to create a VM, and then use ssh, scp, rsync, etc."*

```bash
# scp — simple, no excludes
scp -r . inkwell-01.exe.xyz:~/app

# rsync — incremental, exclude-aware, best for re-pushes
rsync -avz --exclude .git --exclude node_modules --exclude .venv \
  ./ inkwell-01.exe.xyz:~/app/

# tar pipe — fastest single cold copy, one SSH round trip
tar cf - . | ssh inkwell-01.exe.xyz 'mkdir -p ~/app && tar xf - -C ~/app'
```

Or through the wrapper CLI already vendored at `.claude/skills/sandbox-exe-dev/`:

```bash
uv run exedev files upload-dir inkwell-01 ./ /home/exedev/app
```

> ⚠️ **The wrapper's `upload-dir` excludes `.git` by default** (`DEFAULT_RSYNC_EXCLUDES` in
> `exedev_cli/src/modules/ssh_runner.py`). SSSF workflows like `adw_simple_sdlc` **commit** their
> plan, code, and docs separately — a mounted copy with no `.git` will fail at the commit step.
> Either push `.git` deliberately, or `git init` + initial commit on the VM as part of setup.

### C. `--setup-script` at create (one call, self-configuring)

The exeuntu image runs `/exe.dev/setup` at first boot, once. `--setup-script` populates it.

```bash
cat mount/setup.sh | ssh exe.dev new --name inkwell-01 --setup-script=/dev/stdin --json
```

Also supported inline (`--setup-script '"touch /tmp/x"'`) and multi-line via `\n`, and it can be set
**account-wide** as a default:

```bash
cat setup.sh | ssh exe.dev defaults write dev.exe new.setup-script   # applies to every new VM
ssh exe.dev defaults delete dev.exe new.setup-script                 # clear it
```

> ⚠️ **10KiB cap.** The docs say plainly: *"Setup scripts have a maximum size. Use indirection."*
> The durable pattern is a ~15-line bootstrap that fetches the real provisioning script
> (`curl … | bash`, or `git clone` then run `mount/provision.sh` from inside the repo).
>
> Scripts run as a **systemd oneshot** (`exe-setup.service`), i.e. asynchronously at first boot —
> so `new` returning does **not** mean setup finished. This is exactly why the debrief's
> **health-check gate** is load-bearing: poll for a sentinel (`/exe.dev/READY`) before executing.

### D. Git clone via the GitHub integration (no tokens on the VM)

```bash
ssh exe.dev integrations add github --name inkwell \
  --repository ghuser/inkwell --attach vm:inkwell-01
```

Then, from inside the VM — no credentials present:

```bash
git clone https://github.int.exe.xyz/ghuser/inkwell.git
export GH_HOST=github.int.exe.xyz && gh repo view ghuser/inkwell
```

Supports `--readonly` and `--act-as-user` (otherwise pushes appear as
`exe-dev-github-integration[bot]`). Attach by `vm:`, `tag:`, or `auto:all` — **`tag:` is the clean
fan-out primitive**: create N VMs with `--tag inkwell` and every one gets the repo.

This is the cleanest path for a *public* Inkwell repo and the best answer to "no secrets in the sandbox."

### E. Custom Docker image (bake the gap)

```bash
ssh exe.dev new --image=myorg/inkwell-base:latest
```

Base it on the open-source exeuntu Dockerfile and add only `bun` + `just` (+ warmed `~/.pi`). Private
registries work two ways: `--registry-auth=USER:TOKEN` (ghcr.io needs a classic PAT with
`read:packages`), or self-host `registry:2` on an exe.dev VM and reference
`<vm>.exe.xyz/my-image:v1`.

Useful image labels: `exe.dev/login-user=…`, `exe.dev/install-shelley=true`, and `EXPOSE` to control
the default proxy port (i.e. `EXPOSE 4501` makes Inkwell the auto-proxied port).

### F. `cp` — clone a golden VM ⭐ fastest

```bash
ssh exe.dev cp inkwell-golden inkwell-run-01 --cpu=4 --memory=16GB --json
```

Whole-VM clone: disk **and** config. Provision once (bun, just, deps warmed, `~/.pi/agent/models.json`
in place, `uv` cache primed, `node_modules`/`bun.lock` resolved), then every run is a copy. This is
the debrief's *"build-once, mount-many"* snapshot extension, and it is natively supported — it needs
no infrastructure of ours.

Trade-off: a golden VM bills while it sits idle (exe.dev VMs are persistent and never expire), and
the clone carries stale code, so a `git pull`/rsync of just the delta still runs after `cp`.

---

## 4. Mount-strategy comparison

| # | Strategy | Cold time (measured) | Code freshness | Secrets on VM | Best for |
| --- | --- | --- | --- | --- | --- |
| A | Blank | **1.9s** | none | none | control/debug |
| B | Create + rsync/tar | **1.9s + 5.1s** | exact working tree (incl. uncommitted) | must be written post-boot | local iteration, dirty trees |
| C | `--setup-script` | 1.9s + async provision | whatever the script fetches | **cannot** — script sees no `--env` | reproducible one-call mounts |
| D | GitHub integration | 1.9s + clone | last push | **none** ✅ | clean-repo runs, fan-out by tag |
| E | Custom image | 1.9s (deps baked) | code still needs pushing | none | pinning a toolchain you don't want drifting |
| F | `cp` golden VM | **1.0s, everything warm** | stale, needs delta | inherited | fan-out where 10s matters |

**CORRECTION (measured 2026-08-04):** the original draft assumed dependency install was the expensive
part and therefore that E/F were necessary. They are not. A complete cold mount of this repo is
**~12s** (1.9 boot + 5.1 push + 1 toolchain + 4 deps). The golden clone is ~1s. Both are fast enough
that **the choice is about reproducibility, not speed** — and a golden VM bills continuously while
idle, because exe.dev VMs never expire.

**Actual shape for this repo:** **B for code + a post-boot provision step**, with **F reserved for
fan-out** where paying 12s × N is annoying. See §12.

---

## 5. What a full Inkwell + SSSF mount has to accomplish

Derived from `.env.sample`, `justfile`, `adws/adw_sssf_config/sssf.config.yaml`, and
`.claude/skills/sssf/cookbooks/install.md`:

1. **Toolchain gap** — install `bun` (`curl -fsSL https://bun.sh/install | bash`) and `just`.
   `uv`, `git`, `python3`, `sqlite3`, `claude`, `pi` are already in the image.
2. **Code** — repo at `/home/exedev/app`, **with a working `.git`** (SSSF commits).
3. **App deps** — `cd apps/inkwell && bun install`; visualizer deps under
   `.claude/skills/sssf/apps/visualizer/`.
4. **Python deps** — none to preinstall: every `adws/adw_*.py` is a `uv run` script with inline
   PEP-723 dependencies (`pydantic`, `python-dotenv`, `pyyaml`, `rich`). First run resolves them —
   **pre-warming the uv cache is exactly the kind of thing a golden VM (F) makes free.**
5. **Secrets** — `.env` needs `OPENROUTER_API_KEY` / `FIREWORKS_API_KEY` / `OPENAI_API_KEY` for the
   starter roster. Three routes, see §6.
6. **Pi model registry** — `~/.pi/agent/models.json` must contain the config's model ids
   (`google/gemini-3.6-flash`, `fireworks/…/kimi-k3`, `openai/gpt-5.6-terra`). The install cookbook
   calls this out: *"the config's default `gemini-3.6-flash` must be a registered id."* **This file
   is not in the repo and not in the image — it is the most likely silent mount failure.**
7. **`just` shell assumption** — the justfile sets `shell := ["zsh", "-ic"]` (interactive zsh, to pick
   up the engineer's profile). A headless VM may not have zsh or a profile. Either install zsh, or
   call `uv run adws/adw_*.py` directly and treat `just` as host-only ergonomics.
8. **De-nest** — keep the orchestration credentials (the exe.dev account, any provisioning key)
   off the VM. A sandbox that cannot authenticate cannot mount sandboxes, whether or not it has
   the code. Enforcing by credential beats deleting files: the tree stays clean and commits made
   inside the box carry only the run's own work.
9. **Health check** — assert before executing: `bun --version`, `uv --version`, `pi --version`,
   `claude --version`, `git -C ~/app status`, model id resolves, `.env` non-empty.
10. **Kick off** — §7.

---

## 6. Three ways to get model access into the sandbox

| Route | Mechanism | Key on VM? |
| --- | --- | --- |
| Env vars | `new --env OPENROUTER_API_KEY=… ` or write `.env` post-mount | **yes** — readable by anything on the box |
| **LLM integration** | `https://llm.int.exe.xyz` proxies Anthropic/OpenAI/Fireworks; attach by `vm:`/`tag:`/`auto:all` | **no** ✅ |
| exe.dev gateway | Same hostname, exe.dev-managed credentials + token allocation | **no** |

The integration route is documented for both agents this factory can drive:

```bash
# Claude Code — needs a placeholder key value, then redirect the base URL
ANTHROPIC_API_KEY=implicit ANTHROPIC_BASE_URL=https://llm.int.exe.xyz claude --model opus
```
```json
// or ~/.claude/settings.json
{ "apiKeyHelper": "printf exe-gateway",
  "env": { "ANTHROPIC_BASE_URL": "https://llm.int.exe.xyz" } }
```

BYOK per provider, key never lands on the VM:

```bash
printf '%s' "$OPENROUTER_API_KEY" | ssh exe.dev integrations add llm \
  --name inkwell-llm --openai=byok --openai-key=- --attach tag:inkwell
```

This maps directly onto the debrief's IP-hygiene beat: cheap non-IP models get their own
integration + tag, frontier work gets another, and **no sandbox ever holds a raw key**.

> ⚠️ Open question: `pi` resolves providers through `~/.pi/agent/models.json`, not through
> `ANTHROPIC_BASE_URL`. Pointing pi at `llm.int.exe.xyz` means authoring custom model entries with
> that base URL. Unverified — this is the first thing to test.

---

## 7. Exposing and kicking off

**Ports** (`doc proxy`):

- Default target = smallest `EXPOSE`d TCP port ≥1024 → **8000** on exeuntu, preferring 80.
- `ssh exe.dev share port <vm> <port>` retargets the proxy.
- **The proxy transparently forwards 3000–9999**: `https://<vm>.exe.xyz:4501/` reaches port 4501
  with no configuration.
- **Only one port can be made public.** `share set-public` applies to the primary port; alternate
  ports stay auth-gated to users with VM access.
- Servers **must bind `0.0.0.0`**, not `127.0.0.1`, or the proxy can't reach them.
- `X-Forwarded-Proto` / `-Host` / `-For` are set.

This resolves the debrief's two-port question cleanly: the **app** (4501) is the public primary port;
the **observability UI** rides an alternate port in 3000–9999, auth-gated to you — which is arguably
the correct security posture anyway.

**Long-running processes** need full detachment or SSH never returns. The vendored wrapper already
encodes the working incantation:

```bash
( nohup <cmd> > /tmp/exedev-bg.log 2>&1 < /dev/null & echo $! )
```

All three parts are required: `nohup` (survive session end), redirect (release stdout/stderr),
`< /dev/null` (release stdin).

**Kickoff options:**

```bash
# 1. Run the factory directly (deterministic — preferred)
ssh inkwell-01.exe.xyz 'cd ~/app && ( nohup uv run adws/adw_sdlc.py "<prompt>" > ~/run.log 2>&1 < /dev/null & )'

# 2. Hand the prompt to Shelley at create time (exe.dev's own agent, no factory involved)
echo 'build me a web app' | ssh exe.dev new --prompt=/dev/stdin
```

Shelley is auto-installed by the `exe.dev/install-shelley=true` label. Since this repo brings its own
factory, Shelley is mostly noise — `shelley` subcommands manage it, and the wrapper's `--no-shelley`
disables the service post-boot.

---

## 8. Fan-out to N (best-of-N)

Every piece already exists:

```bash
ssh exe.dev cp inkwell-golden inkwell-run-$i --cpu=4      # F: warm clone
ssh exe.dev tag inkwell-run-$i inkwell                    # integrations auto-attach by tag
ssh exe.dev integrations attach inkwell-llm tag:inkwell   # per-tier model access, no keys
```

Per-run variation lives in three places and nowhere else: **the prompt**, **the model config**
(`SSSF_CONFIG=…` selects `sssf.config.yaml` vs `sssf.frontier.config.yaml` — the repo already ships
both), and **env**. Everything else stays inside the code base, which is what keeps the orchestrator
two scripts instead of an agent system.

Teardown is `ssh exe.dev rm <name>` — **destructive, deletes the persistent disk, no confirmation,
no undo.** VMs never expire, so anything not killed bills indefinitely. `cp` to an archive VM first
if the state matters; the vendored `scripts/fleet-download-all.sh` / `fleet-restore.sh` do the
local-archive version of the same idea.

---

## 9. Open questions — RESOLVED 2026-08-04

All six were tested on live VMs. Answers below; raw measurements in §11.

1. **Where does `--env` land?** → **`/etc/profile.d/exe-env.sh`**, as `export VAR='value'`.
   Consequence: visible to **interactive login shells only**. It is **NOT** visible to
   `ssh vm "cmd"` (how the orchestrator runs everything) and **NOT** visible to the setup script.
   **This is a trap.** Do not rely on `--env` for anything the mount script needs.
2. **`pi` + the exe.dev gateway?** → **Works, key-free.** A 12-line `models.json` pointing at
   `https://llm.int.exe.xyz/v1` (api `openai-completions`, dummy `apiKey`) makes `pi --list-models`
   resolve, and `pi -p --model exe/fireworks/kimi-k3` returns real inference. Roster strings become
   `exe/<gateway-id>`, e.g. `exe/fireworks/kimi-k3`, **not** the long `fireworks/accounts/...` form.
3. **Setup-script completion signal?** → The unit is `exe-setup.service`, runs **as `exedev`**, and
   ends `ActiveState=inactive` + `Result=success` + `ExecMainStatus=0`. Since "inactive" is also the
   pre-run state, **poll a sentinel file the script itself touches**, not the unit. Confirmed working.
4. **Cold dependency cost?** → **Negligible.** `bun install` 0.4s (54 pkgs), `uv` PEP-723 cold
   resolve 3s (11 pkgs), `bun` install 1s, `just` install <1s. **This invalidates the earlier
   assumption that a golden VM is needed for speed** (see §4, corrected).
5. **Region pinning** — still unexamined. `set-region` exists; only matters at large N.
6. **`just` under a headless shell** — `just` installs fine, but the justfile's
   `set shell := ["zsh", "-ic"]` still assumes an interactive zsh that does **not** exist on a fresh
   VM (`zsh` is not in the image, and `/etc/profile.d` is a bash convention zsh ignores). **Bypass
   `just` in the sandbox**; call `uv run adws/adw_*.py` directly.

### Two findings nobody asked for, both load-bearing

- **Every `*.exe.xyz` VM shares ONE host key**, fingerprint `SHA256:JJOP/lwiBGOMilfONPWZCXUrfK154cnJFXcqlsi6lPo`,
  identical to `exe.dev` itself. Trust it once with a wildcard `known_hosts` entry; otherwise every
  new sandbox fails with `Host key verification failed` before the mount script does anything.
- **exe.dev ships a broken pi extension.** `~/.pi/agent/extensions/exe-dev/` is meant to auto-wire
  models from their integrations and errors on every `pi` invocation with
  `reflection fetch failed: ... unrecognized reflection shape`, because the reflection integration is
  not attached to the account. Harmless (exit 0) but it pollutes every agent's stderr, which matters
  when the factory parses agent output. Attaching `reflection` may fix it and remove the need for
  `models.json` entirely; untested.

---

## 10. Command reference (verified live, 2026-08-04)

```
ssh exe.dev help                    # 27 verbs
ssh exe.dev doc <slug>              # the official docs, fetchable
ssh exe.dev new     --name --image --cpu --memory --disk --env --tag
                    --setup-script --prompt --integration --registry-auth
                    --comment --pool --no-email --json
ssh exe.dev ls [-a] [pattern] --json
ssh exe.dev cp <src> [new-name] [--cpu --memory --disk --copy-tags=false]
ssh exe.dev rm | restart | rename | tag | comment | stat <vm>
ssh exe.dev resize <vm> [--cpu --memory --disk]
ssh exe.dev share show|port|set-public|set-private|add|remove|add-link|remove-link <vm>
ssh exe.dev integrations add|edit|attach|detach|setup  (github | llm | http-proxy | reflection | …)
ssh exe.dev defaults write dev.exe new.setup-script    # account-wide default (stdin)
ssh exe.dev ssh-key generate-api-key --exp=30d         # bearer token for POST /exec
ssh exe.dev whoami | billing | set-region | domain | shelley | grant-support-root
```

Docs worth reading in full: `doc customization`, `doc proxy`, `doc faq/copy-files`,
`doc integrations-github`, `doc integrations-llm`, `doc private-image`, `doc api`, `doc https-api`.

---

## 11. Measured on hardware (2026-08-04)

VMs `inkwell-probe-0804`, `inkwell-probe-env`, `inkwell-clone-test`. Every number below is observed.

### Timings

| Operation | Measured |
| --- | --- |
| `exedev init` (blank VM, boot to SSH-ready) | **1.88s** |
| `rsync -az` push of this repo, `.git` included, 25 MB landed | **5.1s** |
| `bun` install (curl installer) | **1s** |
| `just` install (prebuilt binary) | **<1s** |
| `bun install` (sssf visualizer, 54 pkgs, cold) | **0.40s** |
| `uv` PEP-723 cold resolve of an `adw_*.py` (11 pkgs) | **3s** |
| **Total cold mount, blank VM to runnable factory** | **~12s** |
| `exedev vm snapshot` (golden clone, fully provisioned) | **0.37s server-side, ~1s wall** |

### Toolchain in the default `exeuntu` image — verified by `command -v`

**Present:** `pi` 0.83.0 (`/usr/local/bin/pi`), `claude` 2.1.220 (`/usr/local/bin/claude`), `codex`,
`uv` 0.12.0, `python3` 3.12.3, `git`, `gh`, `sqlite3`, `docker`, `rg`, `jq`.

**Absent:** `bun`, `just`, `node`, `npm`. (Total cost to close the gap: ~1s. Not worth a custom image.)

### Agents run with ZERO credentials in the sandbox

`https://llm.int.exe.xyz/v1/models` answers from inside a VM with **74 models and no API key**,
including every model in the SSSF starter roster (`fireworks/kimi-k3`, `openai/gpt-5.6-terra`,
`openai/gpt-5.6-luna`) plus `fireworks/deepseek-v4-flash`.

Both agents verified by real inference, not version strings:

```bash
# Claude Code — no key
ANTHROPIC_API_KEY=implicit ANTHROPIC_BASE_URL=https://llm.int.exe.xyz \
  claude -p "Reply with exactly: SANDBOX AGENT ONLINE"     # -> SANDBOX AGENT ONLINE

# Pi — no key, after writing ~/.pi/agent/models.json
pi -p --model exe/fireworks/kimi-k3 "Reply with exactly: PI ONLINE IN SANDBOX"   # -> PI ONLINE IN SANDBOX
```

The `models.json` that makes pi work (this is the whole file):

```json
{ "providers": { "exe": {
  "baseUrl": "https://llm.int.exe.xyz/v1",
  "api": "openai-completions",
  "apiKey": "implicit",
  "models": [ { "id": "fireworks/kimi-k3" }, { "id": "fireworks/deepseek-v4-flash" },
              { "id": "openai/gpt-5.6-terra" }, { "id": "openai/gpt-5.6-luna" } ]
} } }
```

`~/.pi/agent/models.json` does **not** exist on a fresh VM. Without it `pi --list-models` prints
*"No models available"* and exits **0** — a naive health check passes and the first agent call fails.
Assert on `pi --list-models` output, not its exit code.

### `--env` behaviour (the trap)

`--env KEY=VAL` writes `/etc/profile.d/exe-env.sh` containing `export KEY='VAL'`.

| Context | Sees `--env`? |
| --- | --- |
| Interactive login shell (`bash -lic`) | ✅ yes |
| `ssh vm "cmd"` (what the orchestrator uses) | ❌ **no** |
| The `--setup-script` itself | ❌ **no** |
| `/etc/environment` | ❌ not written there |

Consequences: a minted runtime key **cannot** be delivered via `--env` + setup-script, because the
setup script runs before/outside that file and never sees it. Deliver credentials **post-boot**, by
writing `.env` into the repo (SSSF reads it via `set dotenv-load`) or by passing them inline on the
exec that needs them.

### Setup script semantics

Runs as **`exedev`** (not root), once, via systemd unit `exe-setup.service`. On success:
`ActiveState=inactive`, `Result=success`, `ExecMainStatus=0`. Because `inactive` is also the pre-run
state, **poll a sentinel file the script touches as its last line** rather than the unit state.

### Host key

All `*.exe.xyz` VMs present the **same** RSA host key as `exe.dev`:
`SHA256:JJOP/lwiBGOMilfONPWZCXUrfK154cnJFXcqlsi6lPo`. Add one wildcard `known_hosts` line and every
future sandbox connects non-interactively. Without it, the first exec on every new VM dies with
`Host key verification failed`.

### Proxy

A fresh VM reports `"proxy_port": 8000` (matches `EXPOSE 8000 9999` in the exeuntu Dockerfile).
Inkwell serves 4501, so the proxy needs retargeting or the alternate-port path (3000-9999) is used.

---

## 12. API keys: what they do and do not replace

`ssh exe.dev ssh-key generate-api-key [--label=NAME] [--vm=VMNAME] [--cmds=A,B] [--exp=30d]`

There are **two different tokens** behind one command, and conflating them wastes time.

### Account token (no `--vm`) — replaces SSH for the CONTROL plane

```bash
ssh exe.dev ssh-key generate-api-key --label=orchestrator --cmds=ls,new,rm,cp,share --exp=30d
curl -X POST https://exe.dev/exec -H "Authorization: Bearer exe1.AAA" -d 'new --name foo --json'
```

Runs any lobby command (`new`, `ls`, `rm`, `cp`, `share`, …) over HTTPS with **no SSH key present**.
`--cmds` scopes it, `--exp` expires it. This is strictly better than an SSH key for an unattended
orchestrator: an SSH key can do everything *including shell into every VM*, a scoped token cannot.

**Limits:** `POST /exec` caps at **30s and 64KB**. Fine for create/list/destroy. Useless for anything
long-running.

### VM token (`--vm=NAME`) — authenticates to the VM's HTTPS PROXY, not to a shell

```bash
ssh exe.dev ssh-key generate-api-key --vm=inkwell-01 --label=observability
curl -H "X-Exedev-Authorization: Bearer <token>" https://inkwell-01.exe.xyz/
```

This gates the **web server** on the VM, not command execution. The proxy strips the header and
forwards `X-ExeDev-UserID`, `X-ExeDev-Email`, and `X-ExeDev-Token-Ctx` to your app. Basic-auth form
also works, which is what makes `git push` over HTTPS possible.

**This solves a real problem in our design:** the observability UI can stay **private** (no
`share set-public`) and still be reachable programmatically by a token instead of a browser login.
Anonymous public exposure stops being the only option for "watch it from outside."

### What it does NOT replace

Running commands inside a VM, `scp`, and `rsync` all still require **SSH**. There is no HTTPS shell.
So the mount itself is SSH either way, and for a laptop-run orchestrator an API key adds nothing that
SSH does not already do.

**Verdict:** not needed for V1 on the laptop. Generate one the moment the orchestrator runs anywhere
that is not Dan's machine (CI, a cron box, or another sandbox), because the alternative is copying a
personal SSH private key into that environment, which the credential rules in the debrief forbid.

---

## 13. Model access: DECIDED 2026-08-04

**One mechanism: OpenRouter.** Provisioning key on the host, one disposable runtime key per sandbox
(`sbx-<run-id>`, default `limit: 50.00`, adjustable per run), revoked at teardown by hash.

### Why not exe.dev's BYOK LLM integration

exe.dev integrations can hold OpenAI / Anthropic / Fireworks / xAI keys and serve them from
`llm.int.exe.xyz` with **no key on the VM**. Verified working; flags confirmed live
(`integrations edit llm --openai=byok --openai-key=-`). Rejected anyway:

| Criterion | OpenRouter | exe.dev BYOK |
| --- | --- | --- |
| Portability | laptop, exe.dev, E2B, CI | **exe.dev only** |
| Blast radius | $50/sandbox, revocable | account-wide, shared |
| Coverage | 338 models | 4 providers |
| `deepseek-v4-flash-0731` | yes, $0.09/$0.18 per M | **no** (serves April preview) |

Portability is the disqualifier: a credential layer bound to one provider's hostname is not a
transferable asset, and transferability is the point.

### The managed gateway stays as-is

`llm.int.exe.xyz` is attached `auto:all` by default on new accounts and serves **74 models with zero
keys configured**. Nothing is built on it, but it means anyone cloning this public repo onto an
exe.dev VM gets working agents with no credentials at all. Both `claude` and `pi` verified.

Catalog observed: openai 31, fireworks 11, xai 1 (43 prefixed + 31 bare aliases). **Anthropic lists
zero models but `POST /v1/messages` works** — you must know the model id, you cannot discover it.

### DeepSeek: the gateway serves the wrong build

`fireworks/deepseek-v4-flash` on the gateway reports `createTime: 2026-04-24` — the April **preview**
weights. The official 0731 build shipped 2026-07-31 with identical architecture and all gains from
post-training, i.e. different weights. OpenRouter prices confirm two distinct models:

```
deepseek/deepseek-v4-flash         $0.140/M in  $0.280/M out   <- April preview
deepseek/deepseek-v4-flash-0731    $0.090/M in  $0.180/M out   <- the A-tier build, 36% cheaper
~deepseek/deepseek-v4-flash-latest $0.090/M in  $0.180/M out   <- alias of 0731
```

Use `deepseek/deepseek-v4-flash-0731` via OpenRouter. Note these are **open-weight MIT models on a
Western host** — the "Chinese labs train on your data" caution applies to DeepSeek's own API, not to
DeepSeek weights served by Fireworks or OpenRouter.

### Roster (all ids verified live on OpenRouter)

| Agent | Model | In/Out per M |
| --- | --- | --- |
| scout, documenter | `openrouter/deepseek/deepseek-v4-flash-0731` | $0.09 / $0.18 |
| builder | `openrouter/moonshotai/kimi-k2.6` | $0.59 / $2.48 |
| reviewer | `openrouter/z-ai/glm-5.2` | $0.76 / $2.42 |
| planner | `openrouter/google/gemini-3.6-flash` | $1.50 / $7.50 |

pi resolves `provider/id` by splitting on the first slash, so `openrouter/google/gemini-3.6-flash`
means provider `openrouter`, model `google/gemini-3.6-flash`. Verified with the same shape
(`exe/fireworks/kimi-k3`) on a live VM.

Claude Code stays on its own Anthropic key with a workspace spend cap — it speaks the Messages API
and does not route through OpenRouter cleanly.
