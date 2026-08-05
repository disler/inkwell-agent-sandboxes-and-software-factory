# just/sandbox/setup.just — PHASE 3 of 6: SETUP.
#
# Imported by the root justfile (not a module), so it shares the root's scope
# and settings. No `set` lines here on purpose: duplicating `dotenv-load` or
# `positional-arguments` is a hard error at parse time.
#
# What this phase does: run provision.sh inside the sandbox, wait for its
# sentinel, then run the five-assertion health gate. Nothing here creates or
# destroys a VM. On failure it prints how to get into the box and exits
# non-zero, because a gate that auto-destroys throws away the evidence.
#
# The OpenRouter PROVISIONING key never appears in this file. The gate spends
# money, so it uses the disposable RUNTIME key — which already lives on the VM
# in app/.env (written in FILL). That is why assertions C/D/E execute inside the
# sandbox: the key never has to travel, and the gate proves the sandbox's own
# egress works rather than the host's.

# CONFIG picks which roster assertion C pings, and defaults to the starter
# roster. It has to be an ARGUMENT: C used to read $SSSF_CONFIG out of the
# remote environment, but `ssh host 'cmd'` carries no environment at all, so
# that read always fell through to the default. On a fan-out where each arm runs
# a different roster, every arm was gated against models it would never call —
# the gate passed and told you nothing. Pass the same path here that you pass to
# `just sbx lifecycle execute`.

# phase 3: provision the sandbox, then gate it (never destroys the VM). CONFIG picks the roster C pings
setup RUN_ID CONFIG="":
    #!/usr/bin/env bash
    set -euo pipefail

    RR="sandbox_mount/host/run_record.py"
    VM=$("$RR" get {{RUN_ID}} vm_name)
    SHA=$("$RR" get {{RUN_ID}} commit_sha)

    # run_record prints an empty line for an unset field, so emptiness is the
    # real check — a missing vm_name means CREATE never finished.
    [ -n "$VM" ]  || { echo "[setup] run record {{RUN_ID}} has no vm_name — run: just sbx lifecycle create {{RUN_ID}}" >&2; exit 1; }
    [ -n "$SHA" ] || { echo "[setup] run record {{RUN_ID}} has no commit_sha — run: just sbx lifecycle fill {{RUN_ID}}" >&2; exit 1; }

    HOST="$VM.exe.xyz"
    # ConnectTimeout only: every *.exe.xyz shares one host key and the wildcard
    # known_hosts entry is already installed, so ssh is non-interactive already.
    SSH=(ssh -o ConnectTimeout=15 "$HOST")

    echo "[setup] run {{RUN_ID}}  vm ${VM}  sha ${SHA}"

    # Every failure below routes through here: report, hand over the debug
    # command, exit non-zero. NEVER destroy — teardown stays an explicit choice.
    gate_fail() {
      echo ""
      echo "[setup] FAILED: $*" >&2
      echo "[setup] the VM is still running on purpose — the evidence is on the box:" >&2
      echo "[setup]   ssh ${HOST}" >&2
      echo "[setup]   ssh ${HOST} 'cd app && git status --porcelain'" >&2
      echo "[setup]   ssh ${HOST} 'pi --list-models'" >&2
      echo "[setup] tear it down only when you are done: just sbx lifecycle teardown {{RUN_ID}}" >&2
      exit 1
    }

    # ── 1. provision ─────────────────────────────────────────────────────────
    # Clear the sentinel first: re-running setup on the same VM would otherwise
    # find the PREVIOUS run's sentinel and declare victory before provision ran.
    echo "[setup] 1/3 provisioning (streaming provision.sh output)"
    "${SSH[@]}" 'rm -f /tmp/PROVISION_READY' < /dev/null \
      || gate_fail "cannot reach ${HOST} over ssh"
    # < /dev/null so ssh does not swallow this script's stdin; output streams live.
    "${SSH[@]}" 'bash app/sandbox_mount/guest/provision.sh' < /dev/null \
      || gate_fail "provision.sh exited non-zero (its last '── step ──' line names the stage)"

    # ── 2. sentinel ──────────────────────────────────────────────────────────
    # provision.sh touches /tmp/PROVISION_READY as its literal last line, so on
    # this synchronous path the file is already there and the loop exits on the
    # first probe. The poll is bounded anyway: it is the only completion signal
    # that stays correct if provision is ever backgrounded, and an unbounded
    # wait on a dead box is a hang, not a failure.
    echo "[setup] 2/3 waiting for /tmp/PROVISION_READY (max 60s)"
    ready=0
    for _ in $(seq 1 30); do
      if "${SSH[@]}" 'test -f /tmp/PROVISION_READY' < /dev/null; then ready=1; break; fi
      sleep 2
    done
    [ "$ready" -eq 1 ] || gate_fail "sentinel /tmp/PROVISION_READY never appeared"
    echo "[setup]     sentinel present"

    # ── 3. the gate ──────────────────────────────────────────────────────────
    echo "[setup] 3/3 health gate (5 assertions)"

    # A — git integrity. Content, not existence: an unsynced golden-VM clone
    # produced 5,641 zero-byte files and reported success, and truncation shows
    # up as ' M path'. Expected-vs-actual SHA is compared by prefix so a short
    # commit_sha in the record still matches a full HEAD.
    #
    # The tree must be CLEAN. Nothing legitimately dirties it: the sandbox
    # clones the repo and provisions around it, so any porcelain line at all
    # means something wrote where it should not have.
    echo "[gate] A git integrity"
    if "${SSH[@]}" 'bash -s' "$SHA" <<'REMOTE_A'; then
    set -uo pipefail
    cd "$HOME/app" || { echo "   no ~/app on this VM — FILL never ran"; exit 1; }
    want="${1:-}"
    head="$(git rev-parse HEAD)" || { echo "   git rev-parse failed — .git is damaged"; exit 1; }
    echo "   HEAD     ${head}"
    echo "   expected ${want}"
    case "$head" in
      "$want"*) ;;
      *) echo "   HEAD does not match the recorded commit_sha"; exit 1 ;;
    esac

    porcelain="$(git status --porcelain)"
    if [ -n "$porcelain" ]; then
      echo "   unexpected working-tree changes (the tree must be clean):"
      printf '%s\n' "$porcelain" | sed 's/^/     /'
      exit 1
    fi
    echo "   working tree clean"
    REMOTE_A
      echo "[gate] A PASS  git integrity"
    else
      gate_fail "assertion A — git integrity"
    fi

    # B — pi has models. `pi --list-models` EXITS 0 while printing
    # "No models available", so never trust $?: assert on the output, and
    # reject that exact string, which is otherwise one non-empty line and would
    # sail through a naive non-empty check.
    echo "[gate] B pi --list-models is non-empty"
    if "${SSH[@]}" 'bash -s' <<'REMOTE_B'; then
    set -uo pipefail
    # `command -v` first: without it a missing pi prints one line of
    # "command not found" and a bare non-empty check calls that a pass.
    command -v pi >/dev/null 2>&1 || { echo "   pi is not on PATH"; exit 1; }
    out="$(pi --list-models 2>&1 || true)"
    n="$(printf '%s\n' "$out" | grep -c . || true)"
    if [ "${n:-0}" -eq 0 ]; then
      echo "   pi --list-models printed nothing"; exit 1
    fi
    if printf '%s' "$out" | grep -qi 'no models available'; then
      echo "   pi says: No models available — ~/.pi/agent/models.json did not load"; exit 1
    fi
    echo "   ${n} lines from pi --list-models"
    REMOTE_B
      echo "[gate] B PASS  pi model registry loaded"
    else
      gate_fail "assertion B — pi --list-models empty or 'No models available'"
    fi

    # C, D, E run as ONE script inside the sandbox. They all need the runtime
    # key, which lives in app/.env on the VM — keeping them there means the key
    # never crosses the wire and the gate exercises the sandbox's own egress.
    # D's usage baseline is also E's first reading, so this is one round trip.
    echo "[gate] C roster ping   D non-zero cost   E remaining credit"
    if "${SSH[@]}" 'bash -s' {{ quote(CONFIG) }} <<'REMOTE_CDE'; then
    set -uo pipefail
    cd "$HOME/app" || { echo "   no ~/app on this VM"; exit 1; }
    command -v jq >/dev/null 2>&1 || { echo "   jq missing (it ships in the exeuntu image)"; exit 1; }

    # Runtime key, read exactly the way provision.sh reads it. NEVER echoed.
    KEY="$(grep -E '^[[:space:]]*(export[[:space:]]+)?OPENROUTER_API_KEY=' .env \
           | tail -n 1 | sed -E 's/^[^=]*=//; s/^["'"'"']//; s/["'"'"']$//' || true)"
    [ -n "$KEY" ] || { echo "   no OPENROUTER_API_KEY in app/.env — FILL did not inject the runtime key"; exit 1; }

    key_usage() {   # dollars spent on this key so far
      curl -sS --max-time 60 https://openrouter.ai/api/v1/key \
        -H "Authorization: Bearer ${KEY}" | jq -r '.data.usage // 0'
    }

    usage_before="$(key_usage)"

    # ── C: ping every model in the ACTIVE roster ─────────────────────────────
    # Config values look like `openrouter/google/gemini-3.6-flash`: the first
    # segment is pi's PROVIDER name, not part of the OpenRouter id, so strip it.
    # $1 is the CONFIG argument, forwarded over ssh as a positional because the
    # remote shell inherits no environment. Empty means "caller did not pick",
    # so fall through to the old behaviour.
    CFG="${1:-}"
    [ -n "$CFG" ] || CFG="${SSSF_CONFIG:-adws/adw_sssf_config/sssf.config.yaml}"
    [ -f "$CFG" ] || { echo "   missing ${CFG}"; exit 1; }
    MODELS="$(awk '/^[[:space:]]*model:[[:space:]]/ {print $2}' "$CFG" \
              | sed 's|^openrouter/||' | sort -u)"
    [ -n "$MODELS" ] || { echo "   parsed zero models out of ${CFG}"; exit 1; }

    ping_fail=0
    for m in $MODELS; do
      body="$(printf '{"model":"%s","max_tokens":256,"provider":{"zdr":true,"data_collection":"deny"},"messages":[{"role":"user","content":"ping - respond with pong"}]}' "$m")"
      resp="$(curl -sS --max-time 180 https://openrouter.ai/api/v1/chat/completions \
                -H "Authorization: Bearer ${KEY}" \
                -H 'Content-Type: application/json' \
                -d "$body" || true)"
      # Reasoning models answer with content=null and the text under .reasoning.
      # Accepting only .content here produces false failures on those models.
      text="$(printf '%s' "$resp" | jq -r '
        ((.choices[0].message.content // "") + (.choices[0].message.reasoning // ""))
      ' 2>/dev/null || true)"
      if [ -n "$text" ] && [ "$text" != "null" ]; then
        echo "   pass  ${m}"
      else
        err="$(printf '%s' "$resp" | jq -r '.error.message // .error // "no content and no error field"' 2>/dev/null || echo 'unparseable response')"
        echo "   FAIL  ${m}: ${err}"
        ping_fail=1
      fi
    done

    usage_after="$(key_usage)"

    # ── D: pi actually REPORTS cost ──────────────────────────────────────────
    # The thing being guarded is precise: adw_modules/agent_pi.py reads
    # usage.cost.total straight out of pi, and pi defaults every rate to ZERO
    # when models.json carries no `cost` block. A factory in that state runs
    # fine and reports $0.0000 forever while genuinely spending. Observed: a
    # 463.6k-token run logged $0.0000.
    #
    # So ask pi directly rather than asking OpenRouter. An earlier version
    # diffed /api/v1/key usage before and after the pings; that is the WRONG
    # INSTRUMENT and it false-failed this gate on the first live mount — four
    # 250-token pings round to $0 in that endpoint, so a correctly configured
    # sandbox looked broken. A real pi call on the cheapest roster model reports
    # cost 4.3e-05 for one sentence, which is small but unambiguously > 0.
    cost_fail=0
    # jq, not python: an unindented line inside a recipe body TERMINATES the
    # recipe, and multi-line python cannot survive that. jq ships in the image.
    pi_cost="$(timeout 180 pi -p --mode json \
                 --provider openrouter --model deepseek/deepseek-v4-flash-0731 \
                 'Write one sentence about sandboxes.' 2>/dev/null \
               | jq -s '[.. | objects | select(has("cost")) | .cost.total // 0] | max // 0' \
               || echo 0)"
    if awk -v c="$pi_cost" 'BEGIN { exit !(c > 0) }'; then
      echo "   pi reports cost \$${pi_cost} on a live call (rate table is loaded)"
    else
      echo "   FAIL  pi reported cost 0 — models.json has no rate table, so every"
      echo "         run will log \$0.0000 while really spending money"
      cost_fail=1
    fi
    # Second half: the registry itself. Catches a partial rate table that the
    # single call above happened not to touch. NOTE pi's schema requires ALL
    # FOUR of input/output/cacheRead/cacheWrite — a partial block fails
    # validation and pi then drops THE ENTIRE ROSTER, not just that model.
    MJ="$HOME/.pi/agent/models.json"
    if [ -f "$MJ" ] && jq -e '[.providers[].models[] | (.cost.input // 0)] | (length > 0) and all(. > 0)' "$MJ" >/dev/null 2>&1; then
      echo "   rate table present: every model in models.json has a non-zero input cost"
    else
      echo "   FAIL  models.json is missing rates — pi will report \$0.0000 on every run"
      cost_fail=1
    fi

    # ── E: remaining credit on the runtime key ───────────────────────────────
    # Remaining is COMPUTED from limit-usage rather than read from a
    # limit_remaining field, so this cannot break on a field name we have not
    # verified. A null limit means the key is uncapped.
    kj="$(curl -sS --max-time 60 https://openrouter.ai/api/v1/key -H "Authorization: Bearer ${KEY}")"
    printf '%s' "$kj" | jq -r '
      .data as $d
      | "   limit     " + (if $d.limit == null then "uncapped" else ("$" + ($d.limit|tostring)) end),
        "   used      $" + (($d.usage // 0)|tostring),
        "   remaining " + (if $d.limit == null then "uncapped" else ("$" + (($d.limit - ($d.usage // 0))|tostring)) end)
    ' || { echo "   could not read /api/v1/key"; exit 1; }

    [ "$ping_fail" -eq 0 ] || exit 2
    [ "$cost_fail" -eq 0 ] || exit 3
    REMOTE_CDE
      echo "[gate] C PASS  every roster model answered"
      echo "[gate] D PASS  non-zero cost and a loaded rate table"
      echo "[gate] E PASS  credit reported above"
    else
      # Exit code tells which of the three failed; the per-line FAIL output above
      # already named the model or the reading.
      rc=$?
      case "$rc" in
        2) gate_fail "assertion C — at least one roster model did not answer" ;;
        3) gate_fail "assertion D — no spend delta and/or no rate table in models.json" ;;
        *) gate_fail "assertions C/D/E — the remote gate script exited ${rc} (see output above)" ;;
      esac
    fi

    echo ""
    echo "[setup] GATE PASSED — {{RUN_ID}} is healthy on ${HOST}"
    echo "[setup] next: just sbx lifecycle observe {{RUN_ID}}"
