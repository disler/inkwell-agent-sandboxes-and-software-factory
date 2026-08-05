# Observe a sandbox and report on it

`just sbx lifecycle observe <run-id>` makes a mounted sandbox watchable from **outside**, without reaching in.
`just sbx mount` ends here.

```bash
just sbx lifecycle observe <run-id>
```

Six steps, all idempotent — a server already listening is left alone, so re-running never stacks a
second bun on the same port:

```
── observe <run-id> · vm <vm> ──────────────────────────────
[1/6] ssh ok — <vm>.exe.xyz
[2/6] app  :4501
       started pid <pid>
       up
[3/6] obs  :4600
       started pid <pid>
       up
[4/6] proxy -> :4501, public
[5/6] recording ports
[6/6] verifying
       app  200 anonymous
       obs  307 anonymous — expected, it is owner-gated

════════════════════════════════════════════════════════════
  app  https://<vm>.exe.xyz/
  obs  https://<vm>.exe.xyz:4600/
════════════════════════════════════════════════════════════
```

The proxy retarget in step 4 is **mandatory**: a fresh exeuntu VM proxies port 8000 (the smallest
`EXPOSE`d port ≥1024), so without `ssh exe.dev share port <vm> 4501` the bare hostname hits nothing.
Servers must bind `0.0.0.0`; bun does by default, which `ss -ltn` confirms as `*:4501`.

## The two URLs

| | URL | Anonymous | Serves |
|---|---|---|---|
| app | `https://<vm>.exe.xyz/` | **200** | Inkwell, the app under development, port 4501 |
| obs | `https://<vm>.exe.xyz:4600/` | **307** | the SSSF trace UI: sessions, phases, events, cost |

Measured live on the e2e VM, 2026-08-04: `app 200`, `obs 307`.

## The 307 is correct, not a bug

**Only ONE port on a VM can ever be anonymous** — whichever one `ssh exe.dev share port` names.
`share set-public` applies to that primary port only. Ports 3000–9999 are transparently forwarded by
the proxy, but the alternates stay **auth-gated to users with VM access**. So:

- anonymous request to `:4600` → **307**, a redirect into exe.dev's login;
- the same URL in a browser already signed in as the VM's owner → **opens fine**.

`observe` treats it that way: it only fails the obs check on `000` (dead proxy) or a 5xx. Anything
else means the port is reachable and gated, which is the intended posture — the app is for showing
people, the trace UI is yours.

Do not try to "fix" it by making 4600 public. You cannot have both, and swapping the primary port
would take the app offline.

## What to tell the user

Say the two URLs, say which one is which, and pre-empt the 307 in one clause:

> `<run-id>` is up.
> App: `https://<vm>.exe.xyz/` — public, anyone can open it.
> Trace UI: `https://<vm>.exe.xyz:4600/` — opens for you in a browser signed in to exe.dev; it
> redirects (307) for anyone else, which is expected: only one port per VM can be anonymous.

If a run is in flight, add the one-line status from the trace db (below) rather than pasting a log.

## Reading progress from the trace db

The db is **on the VM**, at `app/adws/adw_data/sssf.db`. It is WAL, so reads never block the running
writers — poll it as often as you like.

```bash
just sbx run cmd <run-id> 'sqlite3 adws/adw_data/sssf.db "select adw_id,status,total_tokens,round(total_cost,4) from sessions order by started_at desc limit 5;"'
```

Real output from the e2e VM:

```
84b6551f|success|902831|0.528
944f7f67|fail|1694137|0.956
```

One row is usually the whole report: which run, whether it finished, what it cost. Then
drill in with the `adw_id`:

```bash
# where the run stands, phase by phase
just sbx run cmd <run-id> 'sqlite3 adws/adw_data/sssf.db "select seq,name,kind,owner,status,attempt from phases where adw_id='"'"'84b6551f'"'"' order by seq;"'

# live event tail — same query the visualizer polls
just sbx run cmd <run-id> 'sqlite3 adws/adw_data/sssf.db "select rowid,type,name,started_at from events where adw_id='"'"'84b6551f'"'"' order by rowid desc limit 25;"'

# why a phase failed
just sbx run cmd <run-id> 'sqlite3 adws/adw_data/sssf.db "select gate,passed,violations_json from gate_results where adw_id='"'"'84b6551f'"'"' order by id;"'

# what is running right now (ended_at NULL = believed alive)
just sbx run cmd <run-id> 'sqlite3 adws/adw_data/sssf.db "select kind,name,pid,started_at from processes where adw_id='"'"'84b6551f'"'"' and ended_at is null;"'
```

Nested quoting gets ugly fast. When it does, put the sql in a heredoc-free single hop instead:

```bash
ssh <vm>.exe.xyz "cd app && sqlite3 adws/adw_data/sssf.db \"select adw_id,status from sessions;\""
```

> **`just obs sessions`, `just obs phases`, `just obs tail`, `just obs procs`, `just obs ui` read the LOCAL db** —
> `adws/adw_data/sssf.db` on your laptop, from runs that happened here. They know nothing about a
> sandbox. For a mounted run, always go through `just sbx run cmd <run-id> 'sqlite3 …'`.

## When a server is not there

| Symptom | Cause | Fix |
|---|---|---|
| `visualizer never bound :4600` | `adws/adw_data/sssf.db` missing — the visualizer **exits** without it | re-run `just sbx lifecycle setup <run-id>`; provision step 8 creates it (DDL is `CREATE TABLE IF NOT EXISTS`, so it is idempotent) |
| `bun: No such file or directory` in `~/inkwell-app.log` | each `ssh vm cmd` is a fresh non-interactive shell that reads no rc file | provision symlinks bun into `/usr/local/bin` — re-run setup |
| obs page 404s but the API answers | `dist/` was never built | provision step 7 runs `bunx vite build` — re-run setup |

The logs are on the VM at `~/inkwell-app.log` and `~/visualizer.log`; `observe` tails them for you
on failure, and `just sbx run cmd <run-id> 'tail -40 ~/visualizer.log'` gets them any time.

## Reporting a finished run

1. **Status and cost** — the `sessions` row above, or the panel at the end of `run.log`:
   `status ✓ success · phases 5/5 passed · tokens 902,831 · cost $0.5280 · adw_id 84b6551f`.
2. **What landed** — `just sbx run cmd <run-id> 'git log --oneline -5'`. SSSF commits the plan, the code
   and the docs **separately**, so the shape of the run is in the commit graph, not the diff.
3. **Artifacts** — `specs/<adw_id>_*.md` and `app_docs/<adw_id>_*.md` on the VM.
4. **Spend** — recorded into the run record by `teardown` (read from the runtime key *before* it is
   revoked; after the DELETE the number is unrecoverable). Note this is the **OpenRouter** spend:
   `just sbx run agent` work goes through exe.dev's key-free gateway and does not appear there.

Everything above stays on the VM until teardown pulls it: `teardown` copies `specs/`, `app_docs/`,
`adws/adw_data/sssf.db` and `run.log` into `.sandbox/runs/<run-id>-artifacts/`, plus a
`git bundle` of every commit at `.sandbox/runs/<run-id>.bundle` — which you inspect locally with:

```bash
just sbx manage harvest <run-id>
git log --oneline --graph <commit_sha>..refs/sandbox/<run-id>
```

> `harvest` does the bundling, the verification and the fetch. Do not hand-roll `git bundle` — the
> recipe ranges from the recorded `commit_sha` so the bundle stays small and refuses to import
> history that does not descend from the pin.
