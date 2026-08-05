# just/obs.just — the `obs` namespace: read the trace db, watch a run.
#
# A MODULE, not an import: it inherits nothing, so it declares its own settings.
# working-directory points at the repo root because every query below is a path
# relative to it. This namespace is meant to work INSIDE a sandbox too — reading your
# own traces is exactly what you want inside a sandbox.
set working-directory := '..'
set positional-arguments

# list the observability commands
default:
    @just --list obs

# The roster is chosen per run — `--config <path>` on any ADW, or SSSF_CONFIG.
# This is how you find the path to pass.

# which rosters exist and who is in them
rosters:
    #!/usr/bin/env bash
    for f in adws/adw_sssf_config/*.yaml; do
      printf '%s\n' "$f"
      awk '
        /^agents:/ { in_agents = 1 }
        /^  model:/ && !in_agents { default_model = $2 }
        /^  - name:/ {
          if (name) printf "    %-11s %s\n", name, (model ? model : default_model " (inherited)")
          name = $3; model = ""
        }
        /^    model:/ { model = $2 }
        END { if (name) printf "    %-11s %s\n", name, (model ? model : default_model " (inherited)") }
      ' "$f"
    done

# recent sessions
sessions:
    sqlite3 adws/adw_data/sssf.db "select adw_id, status, substr(request,1,60), total_tokens, round(total_cost,4) from sessions order by started_at desc limit 10;"

# phases for one adw: just obs phases <adw_id>
phases ADW_ID:
    sqlite3 adws/adw_data/sssf.db "select seq, name, kind, owner, status, attempt from phases where adw_id='{{ADW_ID}}' order by seq;"

# live event tail for one adw: just obs tail <adw_id>
tail ADW_ID:
    sqlite3 adws/adw_data/sssf.db "select rowid, type, name, started_at from events where adw_id='{{ADW_ID}}' order by rowid desc limit 25;"

# what a run is running right now: just obs procs <adw_id>
procs ADW_ID:
    sqlite3 adws/adw_data/sssf.db "select kind, name, pid, command, started_at from processes where adw_id='{{ADW_ID}}' and ended_at is null order by id;"

# Verifies each pid still looks like the thing we recorded; pids get recycled.

# stop a stuck run — children first, then the workflow
kill ADW_ID:
    #!/usr/bin/env bash
    set -uo pipefail
    rows=$(sqlite3 adws/adw_data/sssf.db "select kind||' '||pid from processes where adw_id='{{ADW_ID}}' and ended_at is null order by case kind when 'agent' then 0 else 1 end, id desc;")
    [ -z "$rows" ] && { echo "no live processes recorded for {{ADW_ID}}"; exit 0; }
    while read -r kind pid; do
        [ -z "${pid:-}" ] && continue
        cmd=$(ps -p "$pid" -o command= 2>/dev/null || true)
        if [ -z "$cmd" ]; then echo "  · $kind $pid already gone"; continue; fi
        case "$cmd" in
            *pi*|*adw_*|*python*) kill "$pid" && echo "  ✗ killed $kind $pid — $cmd" ;;
            *) echo "  ! $kind $pid is now '$cmd' — pid reused, NOT killing" ;;
        esac
    done <<< "$rows"

# The db path resolves against the server's cwd, and the server runs from the
# app dir — so it is passed explicitly rather than left to be discovered.

# boot the observability UI (server :4600 + vite dev)
ui:
    cd .claude/skills/sssf/apps/visualizer && bun install && (SSSF_DB={{invocation_directory()}}/adws/adw_data/sssf.db bun run server/index.ts &) && bunx vite
