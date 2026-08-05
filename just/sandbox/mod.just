# just/sandbox/mod.just — the `sbx` namespace: out-of-sandbox orchestration.
#
# Loaded from the root justfile:
#     mod sbx 'just/sandbox/mod.just'
#
# This namespace ships to the sandbox like everything else. What stops a sandbox
# from mounting sandboxes is not the absence of these recipes but the absence of
# the CREDENTIALS they need: the exe.dev account and OPENROUTER_PROVISIONING_KEY
# never leave the host. A box that runs `just sbx mount` gets an auth failure,
# not a nested VM.
#
# A module inherits NOTHING from its parent — not variables, not settings, and
# its working directory defaults to its own file's directory. Hence the three
# lines below, repeated in each submodule with one more level of `..`. Files
# pulled in by `import` share their parent's scope and need no settings.
#
# THE SHAPE:
#   just sbx mount        the chain — the entry point, so it stays at this level
#   just sbx lifecycle    the six phases the chain is made of
#   just sbx manage       auxiliary: preflight, readback, fleet ops
#   just sbx run          put work in / look at a box: `run agent`, `run cmd`
#   just sbx orch         boot a host-side orchestrator agent
set working-directory := '../..'
set positional-arguments
set dotenv-load

mod lifecycle
mod manage
mod run
mod orch

import 'mount.just'

# list the sandbox commands
default:
    @just --list sbx
