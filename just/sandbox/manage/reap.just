# just/sandbox/manage/reap.just — the fleet-wide backstop.
#
# No RUN_ID on `reap`: it is the fleet-wide backstop, not a per-run step.
# OpenRouter keys have no native TTL, so a teardown that never ran leaves a key
# spending forever.
#
# The sbx- prefix is the entire safety model. The engineer's personal keys carry
# NO prefix (verified: mac-mini-agent, OAuth: localhost, m4 global, benchy) and
# deleting one is unrecoverable. Nothing without that prefix is ever considered.

# revoke orphaned sbx- keys — dry run by default; pass --yes to actually delete
reap *FLAGS:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ justfile_directory() }}"

    API="https://openrouter.ai/api/v1"
    PREFIX="sbx-"
    RUNS=".sandbox/runs"
    SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15)

    # Interpolating the variadic straight into a `for ... in` list is a syntax
    # error when no flags were passed; through a variable an empty expansion is
    # simply zero iterations.
    RAW_FLAGS="{{ FLAGS }}"
    APPLY=0
    for a in $RAW_FLAGS; do
        case "$a" in
            --yes) APPLY=1 ;;
            *) echo "reap: unknown flag $a (only --yes)"; exit 2 ;;
        esac
    done

    [ -n "${OPENROUTER_PROVISIONING_KEY:-}" ] || { echo "!! OPENROUTER_PROVISIONING_KEY unset — cannot list or delete keys"; exit 1; }

    umask 077   # these temp files hold key hashes; not secrets, but not public either
    TMPD=$(mktemp -d -t sbx-reap)
    trap 'rm -rf "$TMPD"' EXIT

    # UNVERIFIED: whether GET /keys paginates past some page size. Observed 4 keys
    # in one response with no pagination envelope. If a fleet ever exceeds that,
    # this needs an `offset` loop.
    curl -sS --max-time 30 "$API/keys" -H "Authorization: Bearer $OPENROUTER_PROVISIONING_KEY" > "$TMPD/keys.json" \
        || { echo "!! could not list keys"; exit 1; }
    ssh "${SSH_OPTS[@]}" exe.dev ls --json > "$TMPD/vms.json" 2>/dev/null || echo '{"vms":[]}' > "$TMPD/vms.json"

    # Selection in python (stdlib, same reason run_record.py is): three-way join of
    # key list x vm list x run records is not a thing to write in jq.
    RUNS="$RUNS" PREFIX="$PREFIX" python3 - "$TMPD/keys.json" "$TMPD/vms.json" > "$TMPD/plan.tsv" <<'PY'
    import json, os, sys
    from pathlib import Path

    keys = json.loads(Path(sys.argv[1]).read_text()).get("data", [])
    live_vms = {v.get("vm_name") for v in json.loads(Path(sys.argv[2]).read_text()).get("vms", [])}
    runs_dir = Path(os.environ["RUNS"])
    prefix = os.environ["PREFIX"]

    for k in keys:
        name = k.get("name") or ""
        if not name.startswith(prefix):
            continue  # personal key. Never considered, never printed as a candidate.
        run_id = name[len(prefix):]
        rec_path = runs_dir / f"{run_id}.json"
        # No record left? Fall back to the run id: create.just passes it as --name,
        # so vm_name == run_id unless the record says otherwise.
        closed, vm = None, run_id
        if rec_path.is_file():
            try:
                rec = json.loads(rec_path.read_text())
            except ValueError as e:
                # Loud: an unreadable record is a key nobody can account for.
                print(f"!! unreadable run record {rec_path}: {e}", file=sys.stderr)
                sys.exit(1)
            closed = rec.get("closed_at")
            vm = rec.get("vm_name") or run_id

        if closed:
            reason = f"record closed {closed}"
        elif vm not in live_vms:
            reason = f"vm {vm} no longer exists"
        else:
            continue  # live run: vm up and record open. Leave it alone.
        print("\t".join([name, k.get("hash") or "", f'{k.get("usage", 0)}', reason]))
    PY

    if [ ! -s "$TMPD/plan.tsv" ]; then
        echo "reap: no orphaned ${PREFIX}* keys"
        exit 0
    fi

    echo "reap: orphaned ${PREFIX}* keys"
    printf '  %-38s %-8s %s\n' "NAME" "SPEND" "WHY"
    while IFS=$'\t' read -r name hash usage reason; do
        printf '  %-38s $%-7s %s\n' "$name" "$usage" "$reason"
    done < "$TMPD/plan.tsv"

    if [ "$APPLY" != 1 ]; then
        echo
        echo "dry run — nothing deleted. To actually revoke these:  just sbx manage reap --yes"
        exit 0
    fi

    echo
    while IFS=$'\t' read -r name hash usage reason; do
        # Defence in depth: re-assert the prefix at the point of deletion, not just
        # at selection. A bug upstream must not be able to reach a personal key.
        case "$name" in
            "$PREFIX"?*) ;;
            *) echo "!! refusing to delete '$name' — no $PREFIX prefix"; exit 1 ;;
        esac
        [ -n "$hash" ] || { echo "!! $name has no hash — skipping"; continue; }
        CODE=$(curl -sS --max-time 30 -o /dev/null -w '%{http_code}' -X DELETE "$API/keys/$hash" \
               -H "Authorization: Bearer $OPENROUTER_PROVISIONING_KEY")
        case "$CODE" in
            2*)  echo "  ✗ revoked $name" ;;
            404) echo "  · $name already gone" ;;
            *)   echo "  !! $name: DELETE returned $CODE — still live"; exit 1 ;;
        esac
    done < "$TMPD/plan.tsv"

    # Same gate as teardown, for the same measured reason: the LIST is authoritative.
    curl -sS --max-time 30 "$API/keys" -H "Authorization: Bearer $OPENROUTER_PROVISIONING_KEY" > "$TMPD/after.json" \
        || { echo "!! could not re-list keys — revocation UNVERIFIED"; exit 1; }
    if python3 - "$TMPD/after.json" "$TMPD/plan.tsv" <<'PY'
    import json, sys
    from pathlib import Path
    live = {k.get("hash") for k in json.loads(Path(sys.argv[1]).read_text()).get("data", [])}
    still = [l.split("\t")[0] for l in Path(sys.argv[2]).read_text().splitlines() if l and l.split("\t")[1] in live]
    if still:
        print("!! still listed after DELETE: " + ", ".join(still), file=sys.stderr)
        sys.exit(1)
    PY
    then
        echo "✓ gate: every reaped key is absent from $API/keys"
    else
        exit 1
    fi
