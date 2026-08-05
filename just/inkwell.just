# just/inkwell.just — the `inkwell` namespace: boot and test the app itself.
#
# Loaded from the root justfile:
#     mod inkwell 'just/inkwell.just'
#
# A module inherits NOTHING from its parent — not variables, not settings, and
# its cwd defaults to this file's directory. Hence the three lines below.
# Recipes run bash (not the root's interactive zsh): they call real binaries
# only, and that keeps them identical on the host and inside a sandbox.
set working-directory := '..'
set positional-arguments
set dotenv-load

# list the inkwell commands
default:
    @just --list inkwell

# boot the app: just inkwell run [4501]  — PORT and INKWELL_DB env override
run PORT="4501":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "inkwell → http://localhost:{{PORT}}"
    PORT={{PORT}} bun run apps/inkwell/server.ts

# boot with reload-on-save, for working on the app
dev PORT="4501":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "inkwell (watch) → http://localhost:{{PORT}}"
    PORT={{PORT}} bun --watch run apps/inkwell/server.ts

# the suite the factory's test phase runs, by name
test:
    bun test apps/inkwell/server.test.ts
