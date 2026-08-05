# just/local.just — the `local` namespace: boot an orchestrator agent that works
# on THIS machine.
#
# `just local cc` drives the factory (the ADWs in `just adw`) right here.
# `just sbx  ...` drives sandboxes, where the factory runs on a throwaway VM.
# The namespace is the answer to "where does the work happen".
#
# Meant to run inside a sandbox: there this is exactly how you boot an
# orchestrator onto that sandbox's own factory.
#
# A MODULE inherits NOTHING from the root justfile, so the settings below are
# repeated deliberately. `shell` matters most: `ipi` is a zsh FUNCTION, not a
# binary, so it only resolves through an interactive zsh. Drop this line and
# `just local ipi` fails with "command not found" while cc and pi keep working.
set shell := ["zsh", "-ic"]
set working-directory := '..'
set positional-arguments

export SHELL_SESSIONS_DISABLE := "1"

# list the local commands
default:
    @just --list local

# Claude Code orchestrator — reads the sssf overview, then handles your ask
cc:
    claude --dangerously-skip-permissions "Read and Execute .claude/skills/sssf/SKILL.md"

# Pi orchestrator — same posture, pi harness
pi:
    pi "Read and Execute .claude/skills/sssf/SKILL.md"

# ipi orchestrator — same posture, ipi harness
ipi:
    ipi "Read and Execute .claude/skills/sssf/SKILL.md" --no-skills
