# just/sandbox/mount.just — the phase chain.
#
# Lives here rather than inline in the root justfile so the whole `sbx` surface
# sits in one directory, split from the in-sandbox `adw` layer by which
# credential it needs.
#
# Imported by the root justfile, so no `set` lines here.

# create -> fill -> setup -> observe. Stops at observe by design: teardown is
# ALWAYS an explicit separate decision, never chained.
mount RUN_ID *FLAGS:
    #!/usr/bin/env bash
    set -euo pipefail
    just sbx lifecycle create "{{RUN_ID}}" {{FLAGS}}
    ID=$(sandbox_mount/host/run_record.py list | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["run_id"])')
    just sbx lifecycle fill    "$ID"
    just sbx lifecycle setup   "$ID"
    just sbx lifecycle observe "$ID"
    printf '\nmounted: %s\n  execute: just sbx lifecycle execute %s "<prompt>"\n  agent:   just sbx run agent %s "<prompt>"\n  harvest: just sbx manage harvest %s\n  destroy: just sbx lifecycle teardown %s\n' "$ID" "$ID" "$ID" "$ID" "$ID"

