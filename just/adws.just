# In-sandbox execution layer: every ADW, mounted at the root as `mod adw`.
# Nothing here talks to a VM — these are the same commands whether you run them
# on your machine or inside a sandbox that has the repo at /home/exedev/app.

# A `mod` runs with cwd set to the MODULE'S directory (just/), so `adws/` would
# be invisible and every recipe would die with "No such file or directory".
set working-directory := '..'

# A `mod` also does NOT inherit parent variables or settings — `config`,
# positional args, and dotenv all have to be declared again here.
config := env_var_or_default("SSSF_CONFIG", "adws/adw_sssf_config/sssf.config.yaml")
set positional-arguments
set dotenv-load

# No `set shell` on purpose. The root justfile uses interactive zsh so the
# engineer's shell functions resolve; zsh is not installed in the sandbox image,
# and these recipes only ever call the `uv` binary. In the sandbox, invoke as:
#   just --shell bash --shell-arg -c adw <recipe> ...
# (the default `sh` there is dash, which does not understand `${@:2}` in `ask`)

# list adw recipes — without this, a bare `just adw` runs the first recipe below
default:
    @just --justfile {{source_file()}} --list

# ── raw ADW runs (args pass straight through: "prompt" [--adw-id X] [--config Y]) ──

# one agent, one prompt (add --agent NAME to pick; default builder)
prompt *ARGS:
    uv run adws/adw_prompt.py --config {{config}} "$@"

# pick the agent by name: just ask scout "where does auth live"
ask AGENT *ARGS:
    uv run adws/adw_prompt.py --config {{config}} --agent {{AGENT}} "${@:2}"

# read-only recon
scout *ARGS:
    uv run adws/adw_scout.py --config {{config}} "$@"

# plan only
plan *ARGS:
    uv run adws/adw_plan.py --config {{config}} "$@"

# one-shot implementation, no plan
build *ARGS:
    uv run adws/adw_build.py --config {{config}} "$@"

# planner → builder
plan-build *ARGS:
    uv run adws/adw_plan_build.py --config {{config}} "$@"

# builder → deterministic test with bounded fix loop
build-test *ARGS:
    uv run adws/adw_build_test.py --config {{config}} "$@"

# builder → reviewer with bounded revise loop (is it what was asked for?)
build-review *ARGS:
    uv run adws/adw_build_review.py --config {{config}} "$@"

# deterministic only: lint, typecheck, build (pass the reason for the run)
quality *ARGS:
    uv run adws/adw_quality.py --config {{config}} "$@"

# write up the work just done, from git diff vs main (add --base REF to change it)
document *ARGS:
    uv run adws/adw_document.py --config {{config}} "$@"

# the full chain: plan → build → deterministic test/fix
sdlc *ARGS:
    uv run adws/adw_plan_build_test.py --config {{config}} "$@"

# sdlc plus a deterministic quality block at the end
plan-build-test-quality *ARGS:
    uv run adws/adw_plan_build_test_quality.py --config {{config}} "$@"

# plan → build → test → review → document, committing the plan, the code, and the docs separately
simple-sdlc *ARGS:
    uv run adws/adw_simple_sdlc.py --config {{config}} "$@"
