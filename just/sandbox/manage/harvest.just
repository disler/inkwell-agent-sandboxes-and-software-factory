# HARVEST. Pull a run's commits back to the host as a git bundle.
#
# Imported into the root justfile, so no `set` lines here and no local variables:
# the phase files share one scope and a duplicate name across them is a hard error.
#
# WHY A BUNDLE AND NOT A PUSH. The sandbox is filled by a public, unauthenticated
# `git clone`. It holds one disposable OpenRouter runtime key and no git credential
# of any kind — no PAT, no deploy key, no ssh identity. That is deliberate: the box
# runs an autonomous agent under --dangerously-skip-permissions, and a push
# credential would give that agent write access to the repo it was cloned from.
# A bundle moves commits across that gap with no credential at all, and the work
# lands in refs you inspect before anything touches a branch of yours.
#
# WHY A RANGE AND NOT --all. `git bundle create f --all` packs the entire history;
# `f <base>..<branch>` packs only the objects the run introduced — KB, not MB. The
# more useful half is the prerequisite: a ranged bundle records "you must already
# have <base>", and `git fetch` REFUSES it otherwise. So a run branch that somehow
# does not descend from the sha FILL pinned is caught here instead of importing
# disconnected history. Free integrity check on the return trip.
#
# NOT A SEVENTH PHASE. It writes nothing to the run record — the bundle's existence
# at .sandbox/runs/<id>.bundle IS the record, the same reasoning that makes
# `.agent-started` a sentinel file rather than a field. The schema stays closed.
#
# IDEMPOTENT: re-running overwrites the bundle and force-updates the ref. It only
# ever writes refs under refs/sandbox/ — never your working tree, index, or any
# branch you own.

# pull a run's commits home as a git bundle: just sbx manage harvest <run-id>
harvest RUN_ID:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ justfile_directory() }}"

    RR="sandbox_mount/host/run_record.py"
    RUN_ID="{{ RUN_ID }}"
    BUNDLE=".sandbox/runs/$RUN_ID.bundle"
    BRANCH="sbx/$RUN_ID"
    DEST="refs/sandbox/$RUN_ID"
    # Same options teardown uses: BatchMode so this never sits at a prompt,
    # timeouts so it never hangs on a half-dead VM.
    SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)

    "$RR" get "$RUN_ID" > /dev/null || { echo "!! harvest: no run record for $RUN_ID"; exit 1; }
    VM=$("$RR" get "$RUN_ID" vm_name)
    BASE=$("$RR" get "$RUN_ID" commit_sha)

    # Both of these are "nothing to do", not failures — teardown calls this on runs
    # that died anywhere, and a missing piece is the normal path.
    [ -n "$VM" ]   || { echo "   harvest: no vm_name in the record — nothing to harvest"; exit 0; }
    [ -n "$BASE" ] || { echo "   harvest: no commit_sha in the record — FILL never completed"; exit 0; }

    # Progress goes to stderr so stdout carries exactly one machine-readable line.
    OUT=$(ssh "${SSH_OPTS[@]}" "$VM".exe.xyz bash -s -- "$BASE" "$BRANCH" <<'REMOTE'
    set -euo pipefail
    base="$1"; branch="$2"

    cd app 2> /dev/null || { echo "NOREPO"; exit 0; }
    git rev-parse --git-dir > /dev/null 2>&1 || { echo "NOREPO"; exit 0; }

    # A run filled before run branches existed committed straight onto main. Give it
    # the branch at HEAD: `git branch` creates a ref and nothing else, so this does
    # not switch, does not touch the tree, and is safe on a box mid-run.
    git rev-parse --verify --quiet "refs/heads/$branch" > /dev/null || git branch "$branch" >&2

    tip=$(git rev-parse "refs/heads/$branch")
    if [ "$tip" = "$base" ]; then echo "NOCOMMITS"; exit 0; fi

    # An empty range is the only expected failure and it is handled above, so a
    # failure here is real: report it rather than shipping a truncated bundle.
    git bundle create /tmp/harvest.bundle "$base..refs/heads/$branch" >&2 || { echo "BUNDLEFAIL"; exit 0; }
    printf 'OK %s %s\n' "$tip" "$(git rev-list --count "$base..refs/heads/$branch")"
    REMOTE
    ) || { echo "!! harvest: could not reach $VM over ssh — VM left alone"; exit 1; }

    case "$OUT" in
        NOREPO*)     echo "   harvest: no app/ repo on $VM — nothing to harvest"; exit 0 ;;
        NOCOMMITS*)  echo "   harvest: $BRANCH is still at $BASE — the run committed nothing"; exit 0 ;;
        BUNDLEFAIL*) echo "!! harvest: git bundle failed on $VM — VM left alone"; exit 1 ;;
        OK\ *)       ;;
        *)           echo "!! harvest: unexpected reply from $VM: $OUT"; exit 1 ;;
    esac
    read -r _ TIP COUNT <<< "$OUT"

    mkdir -p .sandbox/runs
    scp "${SSH_OPTS[@]}" -q "$VM".exe.xyz:/tmp/harvest.bundle "$BUNDLE" \
        || { echo "!! harvest: could not copy the bundle off $VM — VM left alone"; exit 1; }

    # Verify BEFORE fetching. This is where a bundle whose base the host does not
    # have fails, and it fails loudly rather than importing something detached.
    if ! git bundle verify "$BUNDLE" > /dev/null 2>&1; then
        echo "!! harvest: $BUNDLE failed verification — this host may not have $BASE"
        git bundle verify "$BUNDLE" || true
        echo "!! the bundle is kept at $BUNDLE for inspection. VM left alone."
        exit 1
    fi

    # --force so a re-harvest of a run that committed more since last time updates
    # the ref instead of refusing a non-fast-forward.
    git fetch --force --quiet "$BUNDLE" "refs/heads/$BRANCH:$DEST" \
        || { echo "!! harvest: fetch into $DEST failed — bundle kept at $BUNDLE"; exit 1; }

    echo "   harvest: $COUNT commit(s) -> $DEST"
    echo "     bundle:  $BUNDLE"
    echo "     read it: git log --oneline --graph $BASE..$DEST"
    echo "     diff it: git diff $BASE..$DEST"
