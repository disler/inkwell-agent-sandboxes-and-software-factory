# Phase 2 — FILL. Put the code and the runtime key inside the VM.
#
# Imported into the root justfile, so no `set` lines here and no local variables:
# six phase files share one scope and a `repo :=` in each would collide.
#
# OPENROUTER_PROVISIONING_KEY is never read in this file, by design. The only key
# that crosses the wire is the disposable runtime key minted in CREATE.

# clone the factory into the VM, optionally pin a sha, write .env: just sbx lifecycle fill <run-id> [sha]
fill RUN_ID *SHA:
    #!/usr/bin/env bash
    set -euo pipefail

    # Recipes already run from the root justfile's directory; cd makes that true
    # even if just is ever invoked with --justfile from elsewhere.
    cd "{{justfile_directory()}}"
    RR="sandbox_mount/host/run_record.py"

    # Public repo: no auth, no GitHub integration, no exe.dev git integration.
    REPO="https://github.com/disler/inkwell-agent-sandboxes-and-software-factory.git"

    # *SHA is variadic: it interpolates to "" when unpinned, space-joined otherwise.
    # Only the first token is meaningful; extra words are a caller mistake we ignore.
    SHA_ARGS="{{SHA}}"
    PIN="${SHA_ARGS%% *}"

    VM=$("$RR" get {{RUN_ID}} vm_name)
    if [ -z "$VM" ]; then
        echo "fill: run record {{RUN_ID}} has no vm_name — run 'just sbx lifecycle create {{RUN_ID}}' first" >&2
        exit 1
    fi
    HOST="$VM.exe.xyz"   # all *.exe.xyz share one host key; the wildcard known_hosts entry is installed

    echo "==> fill: $VM — cloning app/ ${PIN:+(pin $PIN)}"

    # One remote script over stdin instead of a quoted one-liner: nothing here has
    # to survive two layers of shell quoting. Progress goes to stderr so stdout
    # carries exactly one machine-readable line: "<head_sha> <intended_sha>".
    # The OPTIONAL argument must be LAST. ssh does not pass argv — it joins the
    # args into one string that the remote login shell re-parses, so an empty "$PIN"
    # in the middle collapses to nothing and every argument after it shifts left.
    # MEASURED: with the pin second, an unpinned fill died on `$3: unbound variable`.
    CLONE_OUT=$(ssh "$HOST" bash -s -- "$REPO" "{{RUN_ID}}" "$PIN" <<'REMOTE'
    set -euo pipefail
    repo="$1"; run_id="$2"; pin="${3:-}"

    if [ -d app/.git ]; then
        # Idempotent re-run (also the golden-VM cp path, where app/ arrives stale).
        echo "app/ already present — fetching" >&2
        git -C app fetch --quiet --tags origin
        if [ -z "$pin" ]; then
            # ff-only: a sandbox that already ran an ADW carries commits that ARE
            # the run's output. Never reset over them; report and keep going.
            if ! { git -C app checkout --quiet main && git -C app merge --ff-only --quiet origin/main; }; then
                echo "WARN: could not fast-forward app/ to origin/main — keeping current HEAD" >&2
            fi
        fi
    else
        rm -rf app   # half-finished clone or a non-repo app/; the VM is disposable, the dir is not state
        git clone --quiet "$repo" app
    fi

    if [ -n "$pin" ]; then
        git -C app checkout --quiet "$pin"
    fi

    # The run branch. Created at whatever HEAD already is, so it adds no commit,
    # changes no file, and leaves the tree byte-identical — gate assertion A
    # compares HEAD's sha to the record and does not care what the branch is
    # called. Every commit the ADW makes now lands here instead of on main, which
    # is what lets HARVEST bundle exactly this run's work and nothing else.
    # Existing branch on a re-fill: switch to it, never re-create. Its commits ARE
    # the run's output.
    branch="sbx/$run_id"
    if git -C app rev-parse --verify --quiet "refs/heads/$branch" > /dev/null; then
        git -C app switch --quiet "$branch"
        echo "on existing run branch $branch" >&2
        # Switching back to the run branch UNDOES the `checkout $pin` above — the
        # branch still points where it did, so a re-fill onto a newer pin silently
        # kept the old code and only the gate noticed. Advance the branch itself,
        # ff-only so it can never move backwards over commits the run produced.
        # A pin that is not a descendant is a real conflict: say so, let the gate
        # fail, and leave the run's work alone.
        if [ -n "$pin" ] && ! git -C app merge --ff-only --quiet "$pin"; then
            echo "WARN: $branch cannot fast-forward to $pin — its commits are not on that line" >&2
        fi
    else
        git -C app switch --quiet -c "$branch"
        echo "run branch $branch created" >&2
    fi

    # Resolve the pin remotely rather than prefix-matching on the host: the pin may
    # be short, a tag or a branch, and only the clone can say what it means.
    intended=""
    if [ -n "$pin" ]; then
        intended=$(git -C app rev-parse --verify --quiet "$pin^{commit}" || true)
    fi
    printf '%s %s\n' "$(git -C app rev-parse HEAD)" "$intended"
    REMOTE
    )

    read -r HEAD_SHA INTENDED <<< "$CLONE_OUT"
    if [ -z "${HEAD_SHA:-}" ]; then
        echo "fill: clone produced no HEAD sha on $VM — VM left up for debugging" >&2
        exit 1
    fi

    # GATE FIRST, then record. A failed fill must leave commit_sha untouched: harvest
    # takes it as the baseline for `BASE..HEAD`, so writing the box's current HEAD here
    # would move that baseline PAST the run's own commits and harvest would then report
    # "the run committed nothing" while the commits sat on the branch, unbundled.
    if [ -n "$PIN" ]; then
        if [ -z "${INTENDED:-}" ]; then
            echo "fill: pin '$PIN' does not resolve to a commit in the clone — VM left up" >&2
            exit 1
        fi
        if [ "$HEAD_SHA" != "$INTENDED" ]; then
            echo "fill: GATE FAILED — HEAD $HEAD_SHA != intended $INTENDED — VM left up" >&2
            echo "      commit_sha left at $("$RR" get {{RUN_ID}} commit_sha) — harvest baseline intact" >&2
            exit 1
        fi
        echo "==> fill: gate ok — HEAD $HEAD_SHA matches pin $PIN"
    else
        echo "==> fill: no pin — HEAD $HEAD_SHA (recorded)"
    fi

    # commit_sha is what makes N runs comparable, so record the sha that is actually
    # checked out, never the one that was asked for.
    "$RR" set {{RUN_ID}} commit_sha="$HEAD_SHA"

    # .env lands here, not at CREATE: it lives inside app/, which does not exist
    # until the clone does. `new --env` is useless for it anyway — that lands in
    # /etc/profile.d and is invisible to `ssh vm "cmd"`.
    KEY_FILE=".sandbox/runs/{{RUN_ID}}.key"
    if [ ! -s "$KEY_FILE" ]; then
        echo "fill: no runtime key at $KEY_FILE — CREATE must mint it before FILL" >&2
        exit 1
    fi
    RUNTIME_KEY=$(tr -d '\r\n' < "$KEY_FILE")
    # Unverified which shape CREATE writes; tolerate both the bare key and KEY=value.
    RUNTIME_KEY="${RUNTIME_KEY#OPENROUTER_API_KEY=}"
    if [ -z "$RUNTIME_KEY" ]; then
        echo "fill: runtime key file $KEY_FILE is empty" >&2
        exit 1
    fi

    # printf is a builtin and cat reads stdin: the key never appears in argv on
    # either side, so it never shows up in ps. umask before the redirect so the
    # file is never briefly world-readable.
    printf 'OPENROUTER_API_KEY=%s\n' "$RUNTIME_KEY" \
        | ssh "$HOST" 'umask 077 && cat > app/.env && chmod 600 app/.env'

    # Prove it landed without ever printing it back. exeuntu is Ubuntu, so GNU stat.
    ENV_STAT=$(ssh "$HOST" 'stat -c "%a %s" app/.env')
    echo "==> fill: app/.env written (mode/size: $ENV_STAT) — provisioning key never left the host"
