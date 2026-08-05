# The just command model

One justfile, two layers, and a boundary that is enforced by `just`'s own semantics. Read this
before you type any `just` command in this repo — the difference between `just adw sdlc "..."` and
`just sbx lifecycle execute <run-id> "..."` is the difference between the factory running **on your laptop** and
the factory running **in a throwaway VM**, and the two commands look almost identical.

## The two layers

| | OUT-sandbox — orchestration | IN-sandbox — execution |
|---|---|---|
| Files | `just/sandbox/` (`lifecycle/`, `manage/`, `run/`, `orch/`) | `just/adws.just` |
| Wired by | `mod sbx 'just/sandbox/mod.just'` | `mod adw 'just/adws.just'` |
| Namespace | flattened into the root: `just sbx lifecycle create`, `just sbx lifecycle fill`, `just sbx lifecycle setup`, `just sbx lifecycle execute`, `just sbx run cmd`, `just sbx run agent`, `just sbx lifecycle observe`, `just sbx lifecycle teardown`, `just sbx manage reap` | prefixed: `just adw sdlc`, `just adw scout`, … |
| Runs where | your machine | the VM (and, dangerously, your machine too) |
| Credential | exe.dev account + `OPENROUTER_PROVISIONING_KEY` | the disposable runtime key in `app/.env` |

The boundary rule is one question: **what credential does it need?** Provisioning key or exe.dev
account means host-only. Runtime key only means it runs inside. Both halves ship to the sandbox —
the boundary is which credentials are present, not which files are.

## `mod` is not `import`, and that is the whole design

Verified on `just 1.49` (host) and `just 1.58` (VM).

| Behavior | `import` | `mod` |
|---|---|---|
| Recipe names | flattened into the root | namespaced under the module name |
| Parent **variables** | inherited | **NOT** inherited |
| Working directory | the root justfile's dir | **the module file's own dir** (`just/`) |
| Parent **settings** (`set …`) | inherited | **NOT** inherited |
| Setup cost | none | four `set` lines at the top of the module |

Both halves of that table are load-bearing here.

### Why `just/adws.just` carries four declarations

Each one exists because its absence produced a specific failure:

```just
set working-directory := '..'   # without it cwd is just/, so adws/ does not exist
config := env_var_or_default("SSSF_CONFIG", "adws/adw_sssf_config/sssf.config.yaml")
set positional-arguments        # without it "$@" is EMPTY and every argument is dropped
set dotenv-load                 # without it the ADWs see no OPENROUTER_API_KEY
```

- **`set working-directory := '..'`** — a module runs from *its own* directory. Every recipe body
  says `uv run adws/adw_*.py`, and from `just/` that path does not exist. Symptom: "No such file
  or directory" on every ADW.
- **`config :=`** — parent variables are not inherited, so the root's `config` is simply undefined
  inside the module. It has to be declared again.
- **`set positional-arguments`** — this is the nasty one, because it fails **silently**. The
  recipes forward arguments with `"$@"` (and `"${@:2}"` in `ask`). Without the setting, `$@` is
  empty: `just adw sdlc "add a badge"` runs the SDLC with **no prompt** and the failure looks like
  a bad agent, not a bad justfile.
- **`set dotenv-load`** — same non-inheritance; the ADWs read their key from `.env`.

And one deliberate **omission**: the module sets **no `shell`**. The root justfile sets
`shell := ["zsh", "-ic"]` so the engineer's shell functions (`ipi`) resolve on the laptop. The
exeuntu image has no zsh, and installing it is ~35s of apt from the dal region for zero benefit.
The module's recipes only ever call the `uv` binary, so the default shell is fine — but see
[Running just inside the sandbox](#running-just-inside-the-sandbox), because the **root** justfile
is still parsed and its `zsh -ic` still applies to root-level recipes.

### Why the six phase files declare nothing

They are `import`s, so they share the root's scope, settings and working directory. That means:

- **No `set` lines in a phase file.** Duplicating `set dotenv-load` or `set positional-arguments`
  is a hard parse error, and it breaks *every* recipe in the repo, not just that file.
- **No file-level variables in a phase file.** Six imports share one namespace, so a `repo :=` in
  two of them collides. Everything is bash-local inside the recipe body instead.
- Relative paths in a phase recipe resolve against the **repo root**, which is why
  `sandbox_mount/host/run_record.py` works unqualified.

## Discovery cheat-sheet

```bash
just --list                 # every out-sandbox phase recipe + the observability helpers
just --list adw             # every ADW inside the module
just --summary              # names only, one line
just --show execute         # the body of one recipe, including its comments
just --show adw::sdlc       # a module recipe's body (:: is the path separator)
just --evaluate             # every variable the root justfile resolved (config, dotenv)
just --fmt --check --unstable   # does the justfile still parse
```

**`just --list adw` is invalid syntax.** `--list` after a module name is read as a recipe name:

```
$ just --list adw
error: Justfile does not contain recipe `adw --list`
```

The flag goes **before** the module: `just --list adw`. (The module's own `default` recipe does the
same thing — a bare `just adw` lists rather than silently running the first recipe in the file.)

## The warning that matters most

> `just adw sdlc "..."` on the host runs the full software factory **on your laptop**: your working
> tree, your git state, your ports, your files. That is the exact thing this system was built to
> prevent.

The module exists so the ADWs are *identical* whether they run here or on a VM. That portability is
also the trap — nothing about the command tells you which machine it is about to modify. In-sandbox
work always goes through a phase recipe, which takes a **run id** as its first argument:

| You want | Type this | Not this |
|---|---|---|
| the factory, in a sandbox | `just sbx lifecycle execute <run-id> "<prompt>"` | `just adw sdlc "<prompt>"` |
| one ADW, in a sandbox | `just sbx run cmd <run-id> 'just --shell bash --shell-arg -c adw plan "<prompt>"'` | `just adw plan "<prompt>"` |
| the factory, here, on purpose | `just adw sdlc "<prompt>"` | — |

Rule of thumb: **if the command has no run id in it, it is running here.**

## Running `just` inside the sandbox

Any `just` invoked on the VM must be:

```bash
just --shell bash --shell-arg -c <recipe> …
```

The root justfile's `set shell := ["zsh", "-ic"]` is parsed on the VM too, and zsh is not in the
image. This is why `execute` launches
`nohup just --shell bash --shell-arg -c adw sdlc "$Q" > run.log 2>&1 < /dev/null &`.

Two related facts about remote invocation:

- Every `ssh vm 'cmd'` is a **fresh non-interactive shell that reads no rc file**. That is why
  `provision.sh` symlinks bun into `/usr/local/bin` (a `PATH` export inside provision dies with
  provision), and why `just` is installed to `/usr/local/bin` rather than a user dir.
- The sandbox's `sh` is dash, which does not understand `${@:2}` — another reason
  `--shell bash` is mandatory rather than cosmetic.

## Resolved: the strip used to break the imports

**Measured 2026-08-04 on the live e2e VM (`just 1.58`).** `import` is not optional in just: a
missing source file is a parse error that kills the whole justfile. While `provision.sh` deleted
`just/sandbox/`, a correctly stripped sandbox could not parse its own root justfile, so
`just --shell bash --shell-arg -c adw sdlc "..."` — the exact command `execute` runs — died at
parse time.

**The strip is gone, so this cannot happen any more.** The whole repo ships intact and the
justfile always parses. One habit from that era is still worth keeping:

- **A recorded pid does not mean the SDLC is running.** `nohup … & echo $!` returns a pid for a
  process that exits one millisecond later. Always confirm against `run.log`.

## Recipe-body rule

**An unindented line inside a recipe body TERMINATES the recipe.** Everything after it is parsed as
new top-level justfile syntax, which usually produces a confusing error somewhere else in the file.
This is why the gate in `setup.just` computes cost with `jq` instead of a multi-line heredoc of
python: python needs unindented lines, jq does not, and jq ships in the exeuntu image.
