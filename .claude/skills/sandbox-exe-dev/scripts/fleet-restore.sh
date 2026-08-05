#!/usr/bin/env bash
# fleet-restore.sh — recreate an archived exe.dev sandbox PERFECTLY:
# fresh VM (same name -> same URL), exact files (sha256-verified against the
# archive), runtime reinstalled per manifest, original server command relaunched,
# URL re-exposed publicly.
#
# Usage:
#   fleet-restore.sh <vm-name> [archive-root] [--force]
#     archive-root default: ./archives   (expects <root>/<vm>/ from fleet-download-all.sh)
#     --force: kill an existing VM with that name first
#
# Exit 0 only when: files on VM == archive checksums AND the public URL serves 200.

set -uo pipefail

CLI="$(cd "$(dirname "${BASH_SOURCE[0]}")/../exedev_cli" && pwd)"
VM="${1:?usage: fleet-restore.sh <vm-name> [archive-root] [--force]}"
ROOT="${2:-./archives}"
FORCE="${3:-}"
ARC="$(cd "$ROOT" && pwd)/$VM"
APP="$ARC/app"
MAN="$ARC/MANIFEST.json"

[ -d "$APP" ] || { echo "no archive at $APP" >&2; exit 1; }
[ -f "$MAN" ] || { echo "no manifest at $MAN" >&2; exit 1; }

REMOTE=$(python3 -c "import json;print(json.load(open('$MAN'))['remote_app_dir'])")
START=$(python3 -c "import json;print(json.load(open('$MAN'))['start_cmd'])")
NEEDS_PI=$(python3 -c "import json;print(str(json.load(open('$MAN'))['needs_node_pi']).lower())")
PORT=$(python3 -c "import json;print(json.load(open('$MAN')).get('port',5173))")
[ -n "$START" ] || { echo "manifest has no start_cmd" >&2; exit 1; }

cd "$CLI"
step(){ echo; echo "── $*"; }

# 0) existing VM?
if uv run exedev vm list --json | python3 -c "import json,sys;sys.exit(0 if '$VM' in [v['vm_name'] for v in json.load(sys.stdin)['vms']] else 1)"; then
  if [ "$FORCE" = "--force" ]; then
    step "killing existing VM $VM (--force)"
    uv run exedev vm kill "$VM"
  else
    echo "VM $VM already exists — pass --force to kill and restore over it" >&2; exit 1
  fi
fi

step "creating VM $VM"
uv run exedev init --name "$VM"
for i in $(seq 1 15); do
  ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "$VM.exe.xyz" "echo READY" 2>/dev/null && break
  sleep 2
done

step "installing uv on VM"
uv run exedev exec "$VM" "command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh" --timeout 180

if [ "$NEEDS_PI" = "true" ]; then
  step "installing node 20 + pi coding agent (manifest says the app shells out to pi)"
  uv run exedev exec "$VM" "node --version 2>/dev/null | grep -qE 'v(2[0-9]|[3-9][0-9])' || (curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y nodejs)" --root --timeout 300
  uv run exedev exec "$VM" "npm install -g @earendil-works/pi-coding-agent && pi --version" --root --timeout 300
fi

step "uploading archive -> $REMOTE"
uv run exedev exec "$VM" "mkdir -p $REMOTE"
uv run exedev files upload-dir "$VM" "$APP" "$REMOTE"
uv run exedev exec "$VM" "[ -f $REMOTE/.env ] && chmod 600 $REMOTE/.env; true"

step "verifying checksums on VM against archive"
uv run exedev files upload "$VM" "$ARC/CHECKSUMS.sha256" "/tmp/CHECKSUMS.sha256"
if uv run exedev exec "$VM" "cd $REMOTE && sha256sum -c /tmp/CHECKSUMS.sha256 --quiet && echo CHECKSUMS_OK" --timeout 300 | grep -q CHECKSUMS_OK; then
  echo "files on VM are byte-identical to the archive"
else
  echo "CHECKSUM VERIFICATION FAILED" >&2; exit 1
fi

step "starting server: $START"
uv run exedev exec "$VM" "export PATH=\$HOME/.local/bin:\$PATH; cd $REMOTE && set -a && [ -f .env ] && . ./.env; set +a; $START" --background

step "exposing https://$VM.exe.xyz/ (port $PORT, public)"
uv run exedev share port "$VM" "$PORT"
uv run exedev share set-public "$VM"

step "waiting for HTTP 200"
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w "%{http_code}" "https://$VM.exe.xyz/" || true)
  [ "$code" = "200" ] && { echo "LIVE: https://$VM.exe.xyz/ (200)"; echo; echo "RESTORE COMPLETE — perfect file match + live URL"; exit 0; }
  sleep 3
done
echo "server did not reach 200 in time — check: uv run exedev exec $VM 'tail -50 /tmp/exedev-bg.log'" >&2
exit 1
