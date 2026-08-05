# The two kickoff paths

When work goes into a sandbox, there are two distinct ways to fire it, and they differ in *who
pulls the trigger inside the box*. Both are supported; they are lanes, not rivals.

---

## Path 1 — Direct: the host fires the factory itself

```bash
just sbx lifecycle execute <run-id> "<prompt-or-path>" [config]
```

The host ssh-es in and detaches `nohup just --shell bash --shell-arg -c adw sdlc ...` directly.
**No agent mediates the kickoff** — the deterministic factory process starts because a
deterministic recipe started it. The recipe records the pid in the run record, output lands in
`run.log`, and the ADW's own tracer streams every phase into `sssf.db`.

**Properties:** reproducible (same prompt bytes + same config = the same run, which is what makes
best-of-N comparable) · zero orchestration tokens · pid-tracked and killable · one detached SDLC
per box at a time.

**Reach for it when:** the work order is already shaped (`prompts/*.md` passed verbatim), you are
fanning out N boxes and need the arms identical, or you intend to walk away and read the trace
later. **This is the default for real work.**

## Path 2 — Agent-mediated: the host asks the in-box orchestrator to kick off the work

```bash
just sbx run agent <run-id> "run the redesign in prompts/06... with the top-speed roster, then watch it"
```

The host talks to the **orchestrator agent inside the sandbox** — the resumable Claude Code
session whose id was minted at CREATE — and *that agent* runs the factory: it chooses the ADW,
shapes the invocation, launches `just adw ...`, watches it, and reports back. Interactive attach
([access_a_running_sandbox.md](../cookbooks/access_a_running_sandbox.md) flow B) is the same lane
with a human in the seat.

**Properties:** judgment at the kickoff point (which ADW, which roster, how to phrase the prompt)
· conversational — you can ask "how is it going?" and get an answer with context · resumable
memory across the run's whole life · costs agent tokens, but on the key-free exe.dev gateway, so
it never touches the run's $50 OpenRouter budget · non-deterministic by nature.

**Reach for it when:** the ask is fuzzy and needs shaping before it becomes a work order,
something mid-run needs diagnosis or intervention, or you want the box to self-manage a sequence
("run the SDLC, and if tests fail, run build-test again").

### The delegation contract: equip the agent first

Every work-kickoff delegation MUST open with the skill read, then the work:

```bash
just sbx run agent <run-id> "If you have not already: READ and EXECUTE .claude/skills/sssf/SKILL.md. Then: <the work>"
```

The "if you have not already" guard makes the preamble safe to repeat — a session that already
read the skill skips straight to the work instead of re-reading it every delegation.

The in-box agent is a bare Claude Code session in `app/` — it has the repo, but nothing has
briefed it on the factory: which ADWs exist, the orchestrator rules, or that in-sandbox `just`
needs `--shell bash --shell-arg -c`. The `/sssf` skill is that briefing, and it ships in the
clone. An unequipped delegate improvises; an equipped one routes. The preamble goes on the
**first work turn** — the session is resumable, so later turns ("how is it going?") ride the
memory and need no re-read.

## The boundary line

**Path 1 is a command; Path 2 is a delegation.** Direct kickoff keeps the host's guarantee: what
ran is exactly what you typed. Agent-mediated kickoff trades that guarantee for judgment — the
agent may run something better than you asked for, or different from it. That is the whole trade,
stated plainly.

Two operational deltas to know: an agent-launched ADW does **not** write its pid into the run
record (only `lifecycle execute` does — though the ADW still registers its own processes in
`sssf.db`, so `just obs procs` works either way), and the agent must use
`--shell bash --shell-arg -c` plus the full detach incantation if it walks away from a long run —
the recipes encode that; the agent must not hand-roll it wrong.

Both paths converge on the same trace: whichever finger pulled the trigger, the factory writes
the same `sssf.db`, and observability does not care who started it.
