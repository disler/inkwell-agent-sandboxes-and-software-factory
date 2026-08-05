# just/sandbox/run/mod.just — put work into a mounted box, or look inside it.
#
# Two ways in, and they are not interchangeable:
#
#   just sbx run cmd    generic escape hatch, SYNCHRONOUS, prints stdout. Your
#                       inspection tool — a log, a git state, a table.
#   just sbx run agent  hand off to Claude Code inside the box over a RESUMABLE
#                       session, then keep talking to it. For steering.
#
# The third way in is `just sbx lifecycle execute` — the detached full SDLC, and
# the default for real work. It lives with the phases because it writes `pid` to
# the run record; these two write nothing and are not phases.
#
# Nothing here ever destroys a VM. A failure reports and exits non-zero with the
# box left alive, because the evidence you need to diagnose it is on that box.
#
# OPENROUTER_PROVISIONING_KEY is never read in this file and must never be. Only
# the mint/revoke phases touch it, and it never leaves the host. We also never
# ask ssh to forward host env (no SendEnv), so nothing from .env leaks over.
set working-directory := '../../..'
set positional-arguments
set dotenv-load

# list the ways into a sandbox
default:
    @just --list sbx::run

# usage: just sbx run cmd <run-id> uname -a   |   just sbx run cmd <run-id> "tail -20 run.log"
# generic escape hatch: run any command inside a sandbox, synchronously
cmd RUN_ID +CMD:
    #!/usr/bin/env bash
    set -euo pipefail
    RR="{{justfile_directory()}}/sandbox_mount/host/run_record.py"
    # The run record is the only cross-phase state; `get` fails loudly if the run
    # does not exist, which is the check we want before touching the network.
    VM=$("$RR" get {{RUN_ID}} vm_name)
    [ -n "$VM" ] || { echo "run cmd {{RUN_ID}}: no vm_name in the run record — is it mounted?" >&2; exit 1; }
    echo "→ run cmd {{RUN_ID}} on $VM: {{CMD}}"
    # {{CMD}} is interpolated verbatim rather than rebuilt from "$@" on purpose:
    # this is an escape hatch, so the pipes, globs and quotes you typed are meant
    # to reach the remote shell intact. `cd app` matches where FILL clones.
    ssh "$VM".exe.xyz "cd app && {{CMD}}"

# usage: just sbx run agent <run-id> "remember the number 42, reply STORED"
#        just sbx run agent <run-id> "what number did I ask you to remember?"
# hand off to Claude Code inside the sandbox, then keep talking to it
agent RUN_ID PROMPT:
    #!/usr/bin/env bash
    set -euo pipefail
    RR="{{justfile_directory()}}/sandbox_mount/host/run_record.py"
    VM=$("$RR" get {{RUN_ID}} vm_name)
    [ -n "$VM" ] || { echo "run agent {{RUN_ID}}: no vm_name in the run record — is it mounted?" >&2; exit 1; }
    SID=$("$RR" get {{RUN_ID}} session_id)
    [ -n "$SID" ] || { echo "run agent {{RUN_ID}}: no session_id in the run record — CREATE writes it" >&2; exit 1; }

    # First call must be --session-id, every later one --resume, so we need one
    # bit of "has this session started". Chosen: a host sentinel file beside the
    # run record. WHY not the alternatives:
    #   - the run record schema is closed (run_id vm_name https_url key_hash
    #     limit spend session_id commit_sha ports pid created_at closed_at) and
    #     rejects unknown keys, so there is nowhere to put a boolean;
    #   - probing the VM for the session costs an extra ssh round trip on every
    #     turn and depends on Claude Code's on-disk session layout, which we have
    #     NOT verified — an implementation detail is a bad source of truth.
    # The sentinel path is derived from the record's own path so it inherits
    # .sandbox/runs/ (gitignored) rather than hardcoding it here.
    REC=$("$RR" path {{RUN_ID}})
    STARTED="${REC%.json}.agent-started"

    if [ -e "$STARTED" ]; then
        FLAG="--resume $SID"
        echo "→ run agent {{RUN_ID}} on $VM: resuming session $SID"
    else
        FLAG="--session-id $SID"
        echo "→ run agent {{RUN_ID}} on $VM: starting session $SID"
    fi

    PROMPT={{ quote(PROMPT) }}
    Q=$(printf '%q' "$PROMPT")

    # Verbatim from the verified invocation. The base URL is exe.dev's key-free
    # gateway, NOT OpenRouter — OpenRouter does not serve the Anthropic Messages
    # API cleanly, and this lane needs no key at all (ANTHROPIC_API_KEY is a
    # placeholder the client insists on). Synchronous by design: the whole point
    # is to read the reply and send the next turn.
    ssh "$VM".exe.xyz "cd app && ANTHROPIC_API_KEY=implicit ANTHROPIC_BASE_URL=https://llm.int.exe.xyz claude -p $FLAG --dangerously-skip-permissions $Q"

    # Only after a successful turn: a first call that died never created a
    # session, and --resume on a session that does not exist would fail forever.
    touch "$STARTED"
