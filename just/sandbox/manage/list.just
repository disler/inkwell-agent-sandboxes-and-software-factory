# just/sandbox/runs.just — readback. What ran, what it cost, which one won.
#
# This is the half of best-of-N that is not "launch N sandboxes". Launching is
# easy; the decision needs the results side by side. Every phase writes to
# .sandbox/runs/<id>.json, so these recipes are pure reads over that plus, while
# a run is still alive, its trace db on the VM.
#
# Formatting is done in python rather than a shell read-loop: the record has
# legitimately-empty fields (spend is null until teardown), and a tab-delimited
# read-loop mis-assigns them, which showed up as the vm name landing in the
# SPEND column. One pass, no field shifting.
#
# Imported by the root justfile, so no `set` lines here.

# every run: state, whether its VM is still alive, spend
list:
    #!/usr/bin/env bash
    set -uo pipefail
    RECORDS="$(sandbox_mount/host/run_record.py list 2>/dev/null || echo '[]')"
    # One control-plane call, not one per run. "unknown" is distinct from "gone":
    # a failed lookup must never read as "every VM is destroyed".
    LIVE="$(ssh -o BatchMode=yes -o ConnectTimeout=15 exe.dev ls --json 2>/dev/null \
            | jq -r '[.vms[].vm_name] | join(",")' 2>/dev/null)"
    LIVE="${LIVE:-__unknown__}"
    printf '%s' "$RECORDS" | sandbox_mount/host/runs_table.py "$LIVE"
