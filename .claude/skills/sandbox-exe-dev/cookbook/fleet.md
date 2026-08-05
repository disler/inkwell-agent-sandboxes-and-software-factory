# Fleet Operations — download-all / restore

exe.dev VMs cannot be paused and bill continuously until `vm kill`. The fleet
scripts give you the practical equivalent of pause/resume: **archive everything
locally, kill the VMs, restore any of them later byte-for-byte** — same VM
name, same `https://<vm>.exe.xyz/` URL, no agent/model tokens spent.

| Script | Purpose |
|---|---|
| [`scripts/fleet-download-all.sh`](../scripts/fleet-download-all.sh) | Archive every live VM's app dir + runtime manifest + sha256 checksums |
| [`scripts/fleet-restore.sh`](../scripts/fleet-restore.sh) | Recreate one VM from its archive, checksum-verified, server relaunched, URL public |

## Download all

```bash
.claude/skills/sandbox-exe-dev/scripts/fleet-download-all.sh ./archives /home/exedev/app 5
#                                                  dest-dir       remote app dir  concurrency
```

Per VM it produces `archives/<vm>/`:

- `app/` — the app directory via `files download-dir` (rsync). Default excludes
  skip ONLY rebuildables (`.venv`, `__pycache__`, `node_modules`, `.git`,
  caches, `dist`, `build`). Dotfiles like `.env`, SQLite DBs, and data dirs
  ARE included.
- `MANIFEST.json` — the exact running server command (captured from `ps`),
  python/node/pi versions, port, app size, URL. The restore script replays
  `start_cmd` verbatim, so restores don't guess how to boot the app.
- `CHECKSUMS.sha256` / `REMOTE_CHECKSUMS.sha256` — sha256 of every archived
  file, computed locally AND on the VM pre-download.
- `DOWNLOAD_VERIFIED` — created only when local == remote checksums. **No
  marker file = do not trust that archive.**

Gotchas:

- **Live SQLite**: DBs are copied while the server runs. Fine for read-mostly
  apps; for transactional consistency stop the server first
  (`exec <vm> "pkill -f uvicorn"`), archive, restart.
- **Built frontends**: `dist`/`build` are in the exclude list. If an app
  serves a compiled bundle, re-run its build after restore or pass
  `--include-all` to `files download-dir` manually.
- **Validate on a COPY, never in the archive**: booting an archived app mutates
  its SQLite files (WAL checkpoints, re-ingest timestamps) and breaks the
  checksum match. `cp -R archives/<vm>/app /tmp/probe && cd /tmp/probe` first.
- **Secrets travel**: `.env` lands in the archive on purpose (restores need
  it). Keep archive dirs out of version control.

## Restore one VM

```bash
.claude/skills/sandbox-exe-dev/scripts/fleet-restore.sh <vm-name> ./archives [--force]
```

What it does, in order:

1. Refuses if a VM with that name exists (`--force` kills it first)
2. `exedev init --name <vm>` → same name, therefore the SAME public URL
3. Installs `uv`; if the manifest recorded a pi binary, installs Node 20 +
   `@earendil-works/pi-coding-agent` (apps that shell out to pi need it)
4. `files upload-dir` the archive, `chmod 600 .env`
5. **`sha256sum -c` on the VM against the archive's checksum file — the
   restore fails unless every file is byte-identical**
6. Relaunches the manifest's `start_cmd` with `--background`, cwd = app dir,
   `.env` sourced
7. `share port` + `share set-public`, then polls until the public URL
   returns 200

Exit code 0 means both proofs passed: perfect file match AND live URL.

## Verifying a restore beyond 200

Checksums prove the files; for behavioral proof, capture API fixtures before
killing and diff after restoring:

```bash
curl -s https://<vm>.exe.xyz/api/meta > before-meta.json     # before kill
# ... kill, restore ...
curl -s https://<vm>.exe.xyz/api/meta | diff before-meta.json -   # empty diff = identical
```

Because the DB is part of the archive, ingest timestamps/counts inside the app
survive the round-trip — a restored app is the same app, not a rebuilt one.

## The full pause/resume cycle

```bash
fleet-download-all.sh ./archives          # 1. archive everything (verify ALL VERIFIED)
exedev vm kill <vm> ...                   # 2. kill fleet -> billing stops
fleet-restore.sh <vm> ./archives          # 3. later: restore any VM in ~2-4 min
```
