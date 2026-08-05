# exedev CLI

A streamlined command-line interface for managing **exe.dev persistent VMs**, mirroring the shape of the [`sbx`](../../agent-sandboxes/sandbox_cli/README.md) CLI from `/agent-sandboxes` so users feel at home.

## Install

```bash
cd .claude/skills/sandbox-exe-dev/exedev_cli
uv sync
uv run exedev --help
```

Prerequisites:
- An exe.dev account with an SSH public key registered (`ssh exe.dev whoami` works).
- `ssh`, `scp`, `rsync` on your `$PATH` (every Linux/macOS host).
- Optional: `playwright` for the `browser` group (installed via `uv sync` dev deps).

## Smoke-test

```bash
uv run exedev doctor
```

If `doctor` is green, every other command should work.

## Quick reference

```text
exedev init     --name <vm>                       # create a VM
exedev exec     <vm> "<cmd>" [--cwd] [--env] [--root] [--shell] [--background] [--timeout]
exedev files    ls|read|write|edit|upload|download|upload-dir|download-dir|exists|info|mkdir|mv|rm
exedev vm       list|info|stat|kill|restart|rename|resize|tag|comment|snapshot
exedev share    show|port|set-public|set-private|add|remove|add-link|remove-link|get-host
exedev browser  init|start|status|nav|eval|screenshot|click|type|press|scroll|a11y|dom|cookies|pick|close
exedev whoami
exedev doctor
```

## Mapping from `sbx` (E2B)

| `sbx` (E2B)                    | `exedev` equivalent              | Notes                                                    |
|--------------------------------|----------------------------------|----------------------------------------------------------|
| `sbx init`                     | `exedev init --name X`           | name required; no auto-IDs                               |
| `sbx exec <id> "<cmd>"`        | `exedev exec <vm> "<cmd>"`       | one-for-one flag mapping (`--cwd`/`--env`/`--root`/`--shell`/`--stdin`/`--background`) |
| `sbx files <verb>`             | `exedev files <verb>`            | identical verbs; SSH/SCP/RSYNC under the hood            |
| `sbx sandbox list`             | `exedev vm list`                 | `--json` works on exe.dev                                |
| `sbx sandbox info <id>`        | `exedev vm info <name>`          | composes `ls --json` + `stat`                            |
| `sbx sandbox kill <id>`        | `exedev vm kill <name>`          | destructive; deletes persistent disk too                 |
| `sbx sandbox get-host <id>`    | `exedev share get-host <vm>`     | URL is deterministic; reachability depends on `share` state |
| `sbx sandbox extend-lifetime`  | **N/A**                          | exe.dev VMs are persistent — no expiry                   |
| `sbx sandbox pause` / `connect`| **N/A**                          | no analog                                                |
| `sbx browser <verb>`           | `exedev browser <verb>`          | same code (lifted verbatim; local Playwright + CDP)      |
| —                              | `exedev vm snapshot <src>`       | clone an entire VM (unique-to-exe.dev)                   |
| —                              | `exedev vm resize`               | live CPU/RAM/disk grow (unique-to-exe.dev)               |
| —                              | `exedev share set-public/private`| anonymise / re-gate the URL (unique-to-exe.dev)          |
| —                              | `exedev share add/add-link`      | per-user / per-link auth grants (unique-to-exe.dev)      |

The full parity table lives at `/tmp/sandbox-parity/AGENT_SANDBOXES_FEATURE_PARITY.md` (or whichever path the parity exercise output it to).

## Architecture

Every command resolves to one of three SSH idioms:

1. **Control plane** — `ssh exe.dev <verb> [--json]` → handled by `modules.ssh_runner.control_plane`.
2. **Data plane** — `ssh <vm>.exe.xyz "<cmd>"` → `modules.ssh_runner.vm_exec` (with `--cwd`, `--env`, `sudo`, `bash -c`, `nohup`, `--stdin` translation).
3. **File transfer** — `scp` (single file) or `rsync -avz --exclude=...` (directory) → `vm_scp` / `vm_rsync`.

We deliberately **never** use the HTTPS API (`POST https://exe.dev/exec`) — it has a 30s ceiling and a 64KB body cap. SSH has neither.

## Multi-agent safety

Unlike E2B, where the sandbox ID is the only identifier and is opaque, exe.dev VMs are named. Pick names like `<workflow-id>-<short-uuid>` (e.g. `todo-app-20260508-7f3a`) so concurrent agents don't collide. Capture the name in *your* context, not in shell variables.

## See also

- `../SKILL.md` — the parent skill with workflow/troubleshooting/cookbook pointers.
- `../cookbook/browser.md` — browser automation usage.
- `ai_docs/exedev/all.md` (in the project that drove the parity exercise) — the full exe.dev docs.
