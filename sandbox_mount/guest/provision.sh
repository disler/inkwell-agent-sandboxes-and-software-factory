#!/usr/bin/env bash
# provision.sh — turn a freshly cloned repo on a blank exeuntu VM into a
# running software factory. Runs INSIDE the sandbox:
#
#   ssh <vm> 'bash app/sandbox_mount/guest/provision.sh'
#
# Idempotent by construction: every install is skip-if-present and the tracer's
# DDL is CREATE TABLE IF NOT EXISTS. Re-running is cheap and safe.
#
# NEVER add apt to this file. Measured from the dal region: ~148 kB/s, ~35s per
# package. bun and just come from their own CDNs in ~1s combined.
set -euo pipefail

STEP="startup"
# shellcheck disable=SC2154   # rc is assigned by the trap body itself
trap 'rc=$?; echo "" >&2; echo "[provision] FAILED during: ${STEP} (line ${LINENO}, exit ${rc})" >&2; exit "$rc"' ERR

step() { STEP="$1"; echo ""; echo "── $1 ──────────────────────────────────"; }
say()  { echo "   $*"; }

# ── 1. locate the repo ───────────────────────────────────────────────────────
# Derived from this script's own path, never hardcoded to /home/exedev/app: the
# clone target is the host's choice and this file is the only thing that knows
# where it actually landed.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "$REPO_ROOT"

step "1/9 repo root"
say "$REPO_ROOT"
say "commit $(git rev-parse --short HEAD 2>/dev/null || echo 'not a git checkout')"

# ── 2. bun ───────────────────────────────────────────────────────────────────
step "2/9 bun"
if command -v bun >/dev/null 2>&1; then
  say "already installed: $(bun --version)"
else
  curl -fsSL https://bun.sh/install | bash
  say "installed"
fi
# The installer only edits shell rc files, which this non-interactive shell never
# reads — put it on PATH by hand for the rest of the run.
if [[ -d "$HOME/.bun/bin" ]]; then
  export PATH="$HOME/.bun/bin:$PATH"
fi
# ...and symlink it where every FUTURE ssh session will find it. Each `ssh vm cmd`
# is a fresh non-interactive shell that reads no rc file, so a PATH export here
# dies with this script. OBSERVE hit exactly that: it started the app with nohup
# and got `bun: No such file or directory` while provision had just used bun
# successfully. just avoids this by installing to /usr/local/bin already.
if [[ -x "$HOME/.bun/bin/bun" ]] && [[ ! -e /usr/local/bin/bun ]]; then
  sudo ln -sf "$HOME/.bun/bin/bun" /usr/local/bin/bun
  sudo ln -sf "$HOME/.bun/bin/bunx" /usr/local/bin/bunx 2>/dev/null || true
  say "linked into /usr/local/bin for non-interactive ssh"
fi
command -v bun >/dev/null 2>&1 || { echo "[provision] bun not on PATH after install" >&2; exit 1; }

# ── 3. just ──────────────────────────────────────────────────────────────────
# Never apt. Note for anything that calls just in here later:
#   just --shell bash --shell-arg -c
# the root justfile sets `zsh -ic` and zsh is not in the image.
step "3/9 just"
if command -v just >/dev/null 2>&1; then
  say "already installed: $(just --version)"
else
  curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh \
    | sudo bash -s -- --to /usr/local/bin
  say "installed"
fi
command -v just >/dev/null 2>&1 || { echo "[provision] just not on PATH after install" >&2; exit 1; }

# ── 4. pi model registry ─────────────────────────────────────────────────────
# ~/.pi/agent/models.json does not exist on a fresh VM, and without it
# `pi --list-models` prints "No models available" and EXITS 0 — the most likely
# silent mount failure there is. The cost block is all-or-nothing: a partial one
# fails schema validation and pi drops THE ENTIRE ROSTER.
step "4/9 pi models.json"
TMPL="sandbox_mount/guest/models.json.tmpl"
[[ -f "$TMPL" ]] || { echo "[provision] missing ${TMPL}" >&2; exit 1; }
mkdir -p "$HOME/.pi/agent"

models_json="$(cat "$TMPL")"
# The template ships apiKey "env:OPENROUTER_API_KEY". pi only sees that variable
# when its parent exported it — true for ADWs (uv run + dotenv), not true for a
# bare `ssh <vm> 'pi --list-models'`, which is exactly what the health gate runs.
# So bake the runtime key in when .env has one.
api_key=""
if [[ -f .env ]]; then
  api_key="$(grep -E '^[[:space:]]*(export[[:space:]]+)?OPENROUTER_API_KEY=' .env \
             | tail -n 1 | sed -E 's/^[^=]*=//; s/^["'"'"']//; s/["'"'"']$//' || true)"
fi
if [[ -n "$api_key" ]]; then
  models_json="${models_json//env:OPENROUTER_API_KEY/$api_key}"   # bash substitution, never argv
  say "runtime key baked in from .env"
else
  say "no OPENROUTER_API_KEY in .env — leaving the env: placeholder (pi will need it exported)"
fi
printf '%s\n' "$models_json" > "$HOME/.pi/agent/models.json"
chmod 600 "$HOME/.pi/agent/models.json"                            # it holds a live key
unset models_json api_key
say "wrote $HOME/.pi/agent/models.json ($(grep -c '"id"' "$HOME/.pi/agent/models.json" || true) models)"

# ── 5. bun install ───────────────────────────────────────────────────────────
step "5/9 bun install"
for dir in apps/inkwell .claude/skills/sssf/apps/visualizer; do
  if [[ -f "$dir/package.json" ]]; then
    ( cd "$dir" && bun install )
    say "installed ${dir}"
  else
    say "skipped ${dir} (no package.json)"
  fi
done

# ── 6. build the visualizer UI ───────────────────────────────────────────────
# Without dist/ the server still boots but only answers the JSON API — the page
# itself 404s. `bunx vite build` rather than `bun run build`, which also runs
# vue-tsc; type errors must not be able to fail a mount.
step "6/9 visualizer build"
VIZ=".claude/skills/sssf/apps/visualizer"
if [[ -d "$VIZ" ]]; then
  ( cd "$VIZ" && bunx vite build )
  say "dist/ built"
else
  say "skipped (visualizer absent)"
fi

# ── 7. trace db ──────────────────────────────────────────────────────────────
# VERIFIED: the visualizer process EXITS when sssf.db is missing, and `just
# mount` ends at observe BEFORE any ADW has run — so a fresh sandbox would start
# a UI that dies instantly. Tracer's DDL is all CREATE TABLE IF NOT EXISTS, so
# calling it here is idempotent and stays correct if the schema moves.
step "7/9 trace db"
INIT_DB="$(mktemp -t sssf_init_db.XXXXXX.py)"
cat > "$INIT_DB" <<'PY'
# /// script
# dependencies = ["pydantic", "python-dotenv", "pyyaml", "rich"]
# ///
"""Create sssf.db and its schema without running an ADW."""

import sys
from pathlib import Path

sys.path.insert(0, "adws")          # the import root `uv run adws/adw_*.py` gets

from adw_modules.agents import load_config
from adw_modules.tracer import Tracer

cfg = load_config()
db = Path(cfg.observability.db)
# Tracer only mkdirs the events file's PARENT, so passing the sessions dir
# itself creates that dir and leaves no stray session behind.
tracer = Tracer(db, Path(cfg.defaults.data_dir) / "sessions" / "events.jsonl")
tables = tracer.conn.execute(
    "SELECT count(*) FROM sqlite_master WHERE type='table'").fetchone()[0]
print(f"   {db} — {tables} tables")
PY
uv run "$INIT_DB"
rm -f "$INIT_DB"

# ── 8. warm the uv cache ─────────────────────────────────────────────────────
# The PEP-723 resolve is ~3s cold and near zero after. Pay it here rather than
# inside the first agent run, where it looks like the agent hanging.
step "8/9 warm uv"
if uv run adws/adw_prompt.py --help >/dev/null 2>&1; then
  say "uv cache warm"
else
  echo "[provision] uv run adws/adw_prompt.py --help failed" >&2
  uv run adws/adw_prompt.py --help >&2 || true
  exit 1
fi

# ── 8b. pre-answer Claude Code's interactive onboarding ──────────────────────
# `claude -p` (the `just sbx run agent` lane) skips onboarding, so nothing here
# exercised it until someone attached INTERACTIVELY with `claude --resume`.
# Interactive first run blocks on three gates in a row: theme picker, then
# "Detected a custom API key in your environment — use it?", then login method.
#
# The middle gate is the load-bearing one and its default is NO. Answering no is
# unrecoverable on a headless VM: ANTHROPIC_API_KEY=implicit plus
# ANTHROPIC_BASE_URL=llm.int.exe.xyz IS the key-free exe.dev gateway, so
# declining it falls through to a login prompt that can never complete here.
# The approval is keyed by the literal token "implicit" — the same string the
# env var carries.
#
# Idempotent: it rewrites three keys and preserves everything else in the file.
step "8b/9 claude onboarding"
if command -v claude >/dev/null 2>&1; then
  python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude.json")
d = json.load(open(p)) if os.path.exists(p) else {}
d["hasCompletedOnboarding"] = True
d["theme"] = "dark"
r = d.setdefault("customApiKeyResponses", {})
r["approved"] = sorted(set(r.get("approved", [])) | {"implicit"})
r["rejected"] = [x for x in r.get("rejected", []) if x != "implicit"]
json.dump(d, open(p, "w"))
PY
  say "onboarding pre-answered (theme, implicit key approved)"
else
  say "claude not installed — skipping"
fi

# ── summary ──────────────────────────────────────────────────────────────────
step "9/9 summary"
say "repo    $REPO_ROOT @ $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
say "bun     $(bun --version)"
say "just    $(just --version)"
say "uv      $(uv --version)"
say "pi      $(pi --version 2>/dev/null || echo 'not installed')"
say "claude  $(claude --version 2>/dev/null || echo 'not installed')"
say "python  $(python3 --version)"
# `|| true` inside the pipeline, not after it: pipefail would otherwise hand the
# failure of an absent/unhappy pi to the ERR trap and skip the sentinel below.
say "models  $( { pi --list-models 2>/dev/null || true; } | grep -c . || true ) lines from pi --list-models"
echo ""
echo "[provision] READY"

# The caller polls for this file — there is no other reliable completion signal.
# It must stay the last line: anything after it can fail after the host has
# already been told the sandbox is ready.
touch /tmp/PROVISION_READY
