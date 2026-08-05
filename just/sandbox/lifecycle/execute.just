# ─── just/sandbox/execute.just — PHASE 4: EXECUTE ─────────────────────────
# Out-of-sandbox orchestration. IMPORTED by the root justfile, so this file
# defines no `set` lines and no top-level variables: settings and variables are
# shared with the root and with the five sibling phase files, and a duplicate is
# either an error or a silent shadow. Everything below is local shell state.
#
# Three ways to drive a mounted sandbox:
#   just sbx run cmd            — generic escape hatch, synchronous, prints output
#   just sbx lifecycle execute  — the default: full SDLC, DETACHED, returns a PID
#   just sbx run agent          — hand off to Claude Code and keep talking to it
#
# Nothing here ever destroys a VM. A failure reports and exits non-zero with the
# box left alive, because the evidence you need to diagnose it is on that box.
# Teardown is always a separate, explicit decision.
#
# OPENROUTER_PROVISIONING_KEY is never read in this file and must never be. Only
# the mint/revoke phases touch it, and it never leaves the host. We also never
# ask ssh to forward host env (no SendEnv), so nothing from .env leaks over.

# usage: just sbx lifecycle execute <run-id> "add a word-count badge to the editor footer"
#        just sbx lifecycle execute <run-id> prompts/06-redesign-quiet-room.md adws/adw_sssf_config/sssf.frontier.config.yaml
#
# PROMPT is passed through verbatim: adw_plan_build_test resolves it with
# utils.resolve_prompt(), so a path to a file IN THE SANDBOX'S CHECKOUT reads as
# that file's contents and anything else stays inline text. For fan-out, a path
# is the better handle — every arm then provably runs the same bytes.
#
# CONFIG is optional and picks the roster. It is appended as a trailing
# `--config` to `adw sdlc`, whose recipe already passes "$@" through to
# argparse; argparse keeps the LAST --config, so this wins over the module
# default without the module needing to know about us. SSSF_CONFIG (the env
# route) cannot work here at all: `ssh vm "cmd"` reads no profile and carries no
# environment.

# ADW picks WHICH workflow runs — any recipe name from `just adw` (sdlc,
# simple-sdlc, plan-build-test-quality, scout, …). It defaults to `sdlc`, so
# every existing call site is unchanged. It is a separate argument rather than
# something smuggled into PROMPT because the recipe name is the FIRST token
# after `adw` and the prompt is quoted as one word; concatenating them would put
# the prompt where just expects a recipe.

# EXTRA is appended verbatim after the config, for the ADW's own flags — most
# usefully `--adw-id <id>`, which rejoins an existing session so the agents keep
# their pi context instead of starting cold. Interpolated as typed, like
# `run cmd`: these are flags, not prose, and re-quoting them would break pairs.

# the default: full SDLC inside the sandbox, detached — returns a PID. CONFIG picks the roster, ADW the workflow
execute RUN_ID PROMPT CONFIG="" ADW="sdlc" *EXTRA:
    #!/usr/bin/env bash
    set -euo pipefail
    RR="{{justfile_directory()}}/sandbox_mount/host/run_record.py"
    VM=$("$RR" get {{RUN_ID}} vm_name)
    [ -n "$VM" ] || { echo "execute {{RUN_ID}}: no vm_name in the run record — is it mounted?" >&2; exit 1; }

    # quote() hands bash a correct single-quoted literal, so apostrophes in the
    # prompt survive hop 1 (just -> host bash). printf %q then survives hop 2
    # (host bash -> the remote login shell), which parses the ssh command string.
    PROMPT={{ quote(PROMPT) }}
    Q=$(printf '%q' "$PROMPT")

    # Same two-hop treatment for the roster path, and the whole flag collapses to
    # the empty string when no config was asked for — so the default call site
    # builds the exact command it built before this argument existed.
    CONFIG={{ quote(CONFIG) }}
    CFG_ARG=""
    if [ -n "$CONFIG" ]; then
        CFG_ARG=" --config $(printf '%q' "$CONFIG")"
        echo "→ roster: $CONFIG"
    fi

    # All three detachment pieces are mandatory or ssh never returns: nohup
    # (survive session end), the redirect (release stdout/stderr), < /dev/null
    # (release stdin). `echo $!` inside the subshell is what gives us the PID —
    # \$! so it is expanded by the REMOTE shell, not here.
    #
    # --shell bash --shell-arg -c is mandatory too: the repo's justfile sets
    # shell := ["zsh", "-ic"] and zsh is not in the exeuntu image (installing it
    # is ~35s of apt for no benefit). `adw sdlc` is the module recipe.
    #
    # NOTE: run.log is truncated on every execute — one detached SDLC per
    # sandbox at a time is the intended shape. Pull the old log first if you
    # care about it.
    echo "→ execute {{RUN_ID}} on $VM (detached): adw {{ADW}} $PROMPT"
    # tail -n 1: the PID is the last thing printed, so any stray remote stdout
    # (a shell rc that talks, an motd) does not corrupt the capture.
    # The trailing `< /dev/null` on the LOCAL ssh is separate from the one inside
    # the remote command, and both are needed. The inner one detaches the remote
    # SDLC from its stdin; this outer one stops ssh reading the CALLER's stdin.
    # Without it a `while read ... done < arms.map` loop around this recipe runs
    # exactly once — ssh eats the rest of the map and the loop sees EOF.
    PID=$(ssh "$VM".exe.xyz "cd app && ( nohup just --shell bash --shell-arg -c adw {{ADW}} $Q$CFG_ARG {{EXTRA}} > run.log 2>&1 < /dev/null & echo \$! )" < /dev/null | tail -n 1)

    # A non-numeric answer means the remote shell printed an error where the PID
    # should be. Fail here rather than writing garbage into the record.
    case "$PID" in
        ''|*[!0-9]*) echo "execute {{RUN_ID}}: expected a PID, got: ${PID:-<empty>}" >&2; exit 1 ;;
    esac

    "$RR" set {{RUN_ID}} pid="$PID"
    echo "→ pid $PID recorded; SDLC is running detached"
    echo "→ watch it:  just sbx run cmd {{RUN_ID}} 'tail -f run.log'"
