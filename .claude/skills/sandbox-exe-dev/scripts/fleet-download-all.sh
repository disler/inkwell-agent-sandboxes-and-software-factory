#!/usr/bin/env bash
# fleet-download-all.sh — archive EVERY exe.dev VM's app directory locally,
# with a runtime manifest + sha256 checksums so a later fleet-restore.sh can
# recreate the sandbox perfectly (same files, same server command, same URL).
#
# Usage:
#   fleet-download-all.sh [dest-dir] [remote-app-dir] [concurrency]
#   defaults:              ./archives  /home/exedev/app  5
#
# Per VM, produces:
#   <dest>/<vm>/app/                    the app directory (rsync; default excludes
#                                       skip only rebuildables: .venv, __pycache__,
#                                       node_modules, .git, dist, build, caches)
#   <dest>/<vm>/MANIFEST.json           server start command(s), runtimes, URL
#   <dest>/<vm>/CHECKSUMS.sha256        sha256 of every archived file (local truth)
#   <dest>/<vm>/REMOTE_CHECKSUMS.sha256 sha256 computed ON the VM pre-download
#   <dest>/<vm>/DOWNLOAD_VERIFIED       present only if local == remote checksums
#
# NOTE: SQLite DBs are copied live; for these app archives that's acceptable —
# stop the server first if you need transactional consistency.

set -uo pipefail

CLI="$(cd "$(dirname "${BASH_SOURCE[0]}")/../exedev_cli" && pwd)"
DEST="$(mkdir -p "${1:-./archives}" && cd "${1:-./archives}" && pwd)"
REMOTE="${2:-/home/exedev/app}"
CONC="${3:-5}"

# rsync exclude parity (mirrors DEFAULT_RSYNC_EXCLUDES in the exedev CLI)
PRUNE_NAMES=(.venv venv __pycache__ .pytest_cache .mypy_cache .ruff_cache .tox .uv node_modules .npm .bun dist build .next .nuxt .output .turbo .parcel-cache .svelte-kit coverage .nyc_output .git .cache)
PRUNE_EXPR=""
for n in "${PRUNE_NAMES[@]}"; do PRUNE_EXPR+=" -name $n -o"; done
PRUNE_EXPR="${PRUNE_EXPR% -o}"

cd "$CLI"
VMS=$(uv run exedev vm list --json 2>/dev/null | python3 -c "import json,sys; [print(v['vm_name']) for v in json.load(sys.stdin)['vms']]")
if [ -z "$VMS" ]; then echo "no VMs found"; exit 0; fi
echo "archiving $(echo "$VMS" | wc -l | tr -d ' ') VMs -> $DEST (concurrency $CONC)"

archive_one() {
  local vm="$1" out="$DEST/$1" rc=0
  mkdir -p "$out"
  local log="$out/archive.log"
  : > "$log"

  # 1) runtime facts + remote checksums in one exec
  uv run exedev exec "$vm" "
    echo '##PY##'; python3 --version 2>&1
    echo '##NODE##'; node --version 2>/dev/null || echo none
    echo '##PI##'; pi --version 2>/dev/null || echo none
    echo '##PROCS##'; ps -eo args | grep -E 'uvicorn|http\.server|fastapi|node .*(server|index)|bun run' | grep -vE 'grep|ps -eo' || true
    echo '##DU##'; du -sb $REMOTE 2>/dev/null | cut -f1
    echo '##SUMS##'
    cd $REMOTE && find . \\( $PRUNE_EXPR \\) -prune -o -type f -print0 | sort -z | xargs -0 -r sha256sum
  " > "$out/_facts.txt" 2>>"$log" || rc=1

  # split facts -> manifest + remote checksums
  python3 - "$vm" "$out" "$REMOTE" <<'PYEOF' 2>>"$log" || rc=1
import json, sys, re, datetime
vm, out, remote = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(f"{out}/_facts.txt").read()
def sect(name):
    m = re.search(rf"##{name}##\n(.*?)(?=\n##|\Z)", raw, re.S)
    return m.group(1).strip() if m else ""
procs = [l.strip() for l in sect("PROCS").splitlines() if l.strip()]
# prefer the human-launched wrapper (uv run ...) over its child interpreter
start = next((p for p in procs if p.startswith("uv run")), procs[0] if procs else "")
manifest = {
    "vm": vm,
    "url": f"https://{vm}.exe.xyz/",
    "remote_app_dir": remote,
    "archived_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "python": sect("PY"), "node": sect("NODE"), "pi": sect("PI"),
    "pi_binary_present": sect("PI") not in ("", "none"),
    "needs_node_pi": None,  # filled after download by grepping the app source
    "server_processes": procs,
    "start_cmd": start,
    "port": 5173,
    "app_bytes": sect("DU"),
}
json.dump(manifest, open(f"{out}/MANIFEST.json", "w"), indent=2)
open(f"{out}/REMOTE_CHECKSUMS.sha256", "w").write(sect("SUMS") + "\n")
PYEOF
  rm -f "$out/_facts.txt"

  # 2) download the app dir
  rm -rf "$out/app"
  uv run exedev files download-dir "$vm" "$REMOTE" "$out/app" >>"$log" 2>&1 || rc=1

  # 3) local checksums + verify against remote
  ( cd "$out/app" && find . \( $(printf -- '-name %s -o ' "${PRUNE_NAMES[@]}" | sed 's/ -o $//') \) -prune -o -type f -print0 | sort -z | xargs -0 shasum -a 256 ) > "$out/CHECKSUMS.sha256" 2>>"$log" || rc=1
  if python3 - "$out" <<'PYEOF' 2>>"$log"
import sys
out = sys.argv[1]
def load(p):
    d = {}
    for line in open(p):
        line = line.strip()
        if not line: continue
        h, _, f = line.partition("  ")
        d[f.strip()] = h.strip()
    return d
local, remote = load(f"{out}/CHECKSUMS.sha256"), load(f"{out}/REMOTE_CHECKSUMS.sha256")
missing = [f for f in remote if f not in local]
extra   = [f for f in local if f not in remote]
diff    = [f for f in remote if f in local and local[f] != remote[f]]
if missing or extra or diff:
    print(f"MISMATCH missing={missing[:5]} extra={extra[:5]} diff={diff[:5]}")
    sys.exit(1)
print(f"verified {len(local)} files")
PYEOF
  then touch "$out/DOWNLOAD_VERIFIED"; else rc=1; fi

  # does the app actually shell out to pi? (base image may ship a pi binary)
  if grep -rqE '"pi"|'"'"'pi'"'"'|pi -p|--model.*gemini|earendil|GEMINI_API_KEY' "$out/app" --include="*.py" 2>/dev/null; then needs=True; else needs=False; fi
  python3 -c "import json;m=json.load(open('$out/MANIFEST.json'));m['needs_node_pi']=$needs;json.dump(m,open('$out/MANIFEST.json','w'),indent=2)" 2>>"$log" || rc=1

  if [ $rc -eq 0 ]; then echo "[ok]   $vm  ($(wc -l < "$out/CHECKSUMS.sha256" | tr -d ' ') files)"
  else echo "[FAIL] $vm  — see $log"; fi
  return $rc
}

fails=0; running=0
for vm in $VMS; do
  archive_one "$vm" &
  running=$((running+1))
  if [ "$running" -ge "$CONC" ]; then wait -n || fails=$((fails+1)); running=$((running-1)); fi
done
while [ "$running" -gt 0 ]; do wait -n || fails=$((fails+1)); running=$((running-1)); done

echo
if [ "$fails" -eq 0 ]; then echo "ALL ARCHIVES VERIFIED -> $DEST"
else echo "$fails VM(s) FAILED — check archive.log files"; exit 1; fi
