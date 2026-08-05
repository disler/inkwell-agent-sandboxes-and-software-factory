# Super Simple Software Factory — Scaffold

A reusable software factory: **agents plus code**, packaged as a skill, deployed into any codebase.

Doctrine (from `ai_docs/` debate summaries): code owns the control plane — ADW scripts are deterministic Python that own sequencing, retries, and acceptance; agents are bounded nodes inside that graph. Agent proposes, code disposes. Informed by the TAC ADW lineage (`adws/` + `adw_modules/`, the `agents/{adw_id}/{agent_name}/` output sink) and tac-8's primitives (Prompts + Workflows), but deliberately simpler — a fresh minimal rebuild, not a port.

## Feature Legend

| Tag | Feature |
|---|---|
| `[config]` | Model configuration — per-agent coding agent (Claude Code / Pi), model, thinking |
| `[handoff]` | Context pass-off — JSON envelopes, adw state, session dirs, prompt refs |
| `[obs]` | Observability — agents → SQLite → polled web UI (one path for live + history) |
| `[all]` | Supports all three |

## Tree

```
super-simple-software-factory/
├── scaffold.md                                  [all]      this file — the build map
├── .env.sample                                  [config]   env vars at root: ANTHROPIC_API_KEY, PI keys, CLAUDE_CODE_PATH, PI_PATH
├── ai_docs/                                     [all]      boundary doctrine the factory is built on
│   ├── code-vs-agents-debate1-fused-summary.html
│   └── code-vs-agents-debate2-fused-summary.html
├── prototypes/                                  [obs]      UI mocks across versions — see the "UI reference mocks" table for which mock informs which view
│
├── .claude/
│   └── skills/
│       └── sssf/                                [all]      THE PRODUCT — the deployable factory
│           ├── SKILL.md                         [all]      frontmatter (name, description) + /install setup, make-config / make-adw usage, orchestrator rules (run, observe, interact — never do the work); progressive disclosure into references/ + cookbooks/
│           │
│           ├── references/
│           │   ├── config.md                    [config]   full sssf.config.yaml spec + model/thinking mapping per coding agent
│           │   ├── handoff.md                   [handoff]  envelope schema + context_handoff contract + session dir layout
│           │   └── observability.md             [obs]      event schema, db tables, polling/cursor contract
│           │
│           ├── cookbooks/                       [all]      orchestrator playbooks — the agent building/running the ADW system operates from these
│           │   ├── sssf_overview.md             [all]      ALWAYS read on startup — system map; every other cookbook loads lazily per request
│           │   ├── install.md                   [all]      /install — initial clone/setup of the entire system from the skill into the cwd
│           │   ├── create_adw.md                [all]      compose a new ADW script from agents in the config
│           │   ├── update_adw.md                [all]      modify an existing ADW chain
│           │   ├── create_config.md             [config]   generate sssf.config.yaml for a target repo
│           │   ├── update_config.md             [config]   add or retune agents: coding agent, model, thinking, prompts
│           │   ├── update_modules.md            [all]      extend adw_modules with new low-level logic
│           │   └── run_adw.md                   [all]      run + monitor an ADW — observe only, never step into the process
│           │
│           ├── scripts/                         generators the operating agent runs
│           │   ├── install.py                   [all]      stamp templates/ into the cwd (target repo root), idempotent — backs /install
│           │   ├── make_config.py               [config]   generate sssf.config.yaml with great defaults
│           │   └── make_adw.py                  [all]      generate a new ADW script + its agents' prompt dirs
│           │
│           ├── templates/                       what /install stamps into a target repo
│           │   ├── env.sample                   [config]
│           │   ├── sssf.config.yaml             [config]   the config file — sketched below
│           │   ├── prompt_engineering/          4 starter agents — one agent, one prompt, one purpose (meta-prompt format)
│           │   │   ├── planner/
│           │   │   │   ├── system.md            [handoff]  Purpose, Instructions — the agent's static identity, nothing else
│           │   │   │   └── user.md              [handoff]  Variables (h3 per incoming datum: {{prompt}}, {{previous_envelope}}, {{context_handoff_dir}}) + task + Report (the output contract)
│           │   │   ├── builder/                 [handoff]  system.md + user.md — implement exactly, report changed files
│           │   │   ├── scout/                   [handoff]  system.md + user.md — read-only recon, change nothing
│           │   │   └── tester/                  [handoff]  system.md + user.md — run tests, report verbatim failures, fix nothing
│           │   └── adws/
│           │       ├── adw_prompt.py            [all]      smallest ADW: one agent, one prompt, traced end-to-end
│           │       ├── adw_scout.py             [all]      scout only — find and report, read-only
│           │       ├── adw_plan.py              [all]      plan only — request → plan artifact in context_handoff
│           │       ├── adw_plan_build.py        [all]      two-agent chain: planner → envelope → builder (the TAC pattern)
│           │       ├── adw_build_test.py        [all]      build → test; failures flow back into builder (bounded fix loop, MAX_FIX_LOOPS=3)
│           │       ├── adw_plan_build_test.py   [all]      the full starter chain: plan → build → test w/ fix loop
│           │       └── adw_modules/             [all]      ALL low-level logic lives here — ADW scripts stay thin
│           │           ├── __init__.py          [all]
│           │           ├── data_types.py        [handoff]  Pydantic: AgentCall, PhaseParams, Phase, Envelope + a concrete output type for EVERY agent call — starter: PlanOutput, BuildOutput, ScoutOutput, TestOutput (4-param rule lives here)
│           │           ├── agents.py            [config]   validate ADW's required agent names against config; resolve entry → coding agent interface + model + thinking + harness extensions
│           │           ├── runner.py            [all]      the Run object — binds config + adw_id + agent_map + tracer once; run.phase(PhaseParams) context manager; agent phases expose ph.call(AgentCall)
│           │           ├── agent_cc.py          [all]      Claude Code interface: `claude -p --model --output-format stream-json` → JSONL; continue_agent via --resume <session_id>
│           │           ├── agent_pi.py          [all]      Pi interface: non-interactive `pi` run, model from ~/.pi/agent/models.json, JSONL session log; continue_agent via session resume (planned shape — shipped code has no continue_agent, see "V1 scope: Pi only" below)
│           │           ├── gates.py             [all]      validation gates — predicates over the envelope's CLAIMS (files exist, json parses, tests pass); failures → continue_agent with the violation list as correction
│           │           ├── prompts.py           [handoff]  load system/user prompt refs from config, render placeholders
│           │           ├── session.py           [handoff]  mint or join adw_id (--adw-id pin-or-create), maintain agent_map.json (agent → session_id + model), create adw_data/sessions/{adw_id}/ dirs incl. context_handoff/
│           │           ├── tracer.py            [obs]      append JSONL + insert every event into sssf.db AS IT HAPPENS (WAL, small transactions); no push transport — the UI polls
│           │           ├── git_helper.py        [all]      low-level git ops: branch, status, diff, commit
│           │           └── utils.py             [all]      safe subprocess env, logging
│           │
│           └── apps/                            [all]      full applications that ship inside the skill
│               └── visualizer/                  [obs]      voidzero Vite+Vue+TS app — runs from the skill, points at any target repo
│                   ├── package.json             [obs]      vite, vue, vue-tsc, oxlint, oxfmt
│                   ├── vite.config.ts           [obs]
│                   ├── tsconfig.json            [obs]
│                   ├── .oxlintrc.json           [obs]
│                   ├── shared/
│                   │   └── types.ts             [obs]      event + envelope types shared by server and client
│                   ├── server/
│                   │   ├── index.ts             [obs]      read-only query API over sssf.db + serves the built UI — no ingest, no websocket
│                   │   └── db.ts                [obs]      SQLite reader (WAL) — cursor queries by rowid; db file lives in the TARGET repo
│                   └── src/
│                       ├── main.ts              [obs]
│                       ├── App.vue              [obs]
│                       └── components/
│                           ├── SwimLanes.vue    [obs]      fixed actor lanes: engineer (top), code, then one lane per agent (name · model)
│                           ├── PhaseBlock.vue   [obs]      one phase in its owner's lane: name + description + status (default fail); agent phases expand into tool-call spans; queued = dashed
│                           └── EventCard.vue    [obs]      one event logged against adw + phase; click → span details (input/output/attributes, duration, tokens)
│
│  ── stamped into a target repo by /install (scripts/install.py) — this repo is the first target ──
│
└── adws/
    ├── adw_sssf_config/
    │   └── sssf.config.yaml                     [config]   this repo's agent roster — sketched below
    ├── adw_modules/                             [all]      stamped from skill templates
    ├── adw_prompt.py                            [all]
    ├── adw_plan_build.py                        [all]
    └── adw_data/                                factory data — prompt_engineering/ tracked; sessions/ + sssf.db gitignored
        ├── prompt_engineering/                  [handoff]  THE user-owned home for prompts after generation — edit here, never inside the skill
        │   └── {agent_name}/
        │       ├── system.md                    [handoff]  who the agent is, its single purpose — static identity only
        │       └── user.md                      [handoff]  task template: {{prompt}}, {{previous_envelope}}, {{context_handoff_dir}} + Report (the output contract)
        ├── sssf.db                              [obs]      runtime (gitignored) — SQLite trace db, the standard shippable package
        └── sessions/                            runtime (gitignored)
            └── {adw_id}/
                ├── agent_map.json               [handoff]  agent name → coding-agent session_id + model — the key that lets ADWs rejoin each agent's existing context window
                ├── context_handoff/             [handoff]  the single location agents write reference files to (plans, notes, artifacts) for the agents that follow
                └── {agent_name}/
                    ├── prompts/                 [handoff]  exact prompts sent, saved before execution
                    ├── raw_output.jsonl         [obs]      full stream from the coding agent
                    └── envelope.json            [handoff]  the agent's final valid-JSON response — captured, validated, persisted by code
```

## sssf.config.yaml — sketch

One agent, one prompt, one purpose. Every agent is a named entry: pick the coding agent, the model, the thinking level, and point at exactly one system prompt and one user prompt.

```yaml
# adws/adw_sssf_config/sssf.config.yaml — generated by make_config.py, edited by humans
defaults:
  coding_agent: pi                 # v1: pi only; claude_code is schema-valid but stubbed until v2
  model: gemini-3.6-flash          # registry pattern, resolved via ~/.pi/agent/models.json → provider + id
  thinking: medium                 # pi levels: off | minimal | low | medium | high | xhigh | max
  harness_engineering: []          # pi extensions loaded into the harness (-e)
  data_dir: adws/adw_data          # runtime home: {data_dir}/sessions/{adw_id}/{agent_name}/

observability:
  db: adws/adw_data/sssf.db                  # tracer writes here directly; the UI polls it — agents → sqlite → web ui
  poll_ms: 500                               # visualizer live-poll cadence; history = same queries, lazy-paged

agents:
  - name: planner                  # inherits defaults; override coding_agent/model per agent when needed
    thinking: high
    purpose: Turn a request into a plan the builder can implement without asking questions.
    prompt_engineering:
      system: adws/adw_data/prompt_engineering/planner/system.md
      user: adws/adw_data/prompt_engineering/planner/user.md

  - name: builder
    purpose: Implement the plan exactly; report every changed file in the envelope.
    prompt_engineering:
      system: adws/adw_data/prompt_engineering/builder/system.md
      user: adws/adw_data/prompt_engineering/builder/user.md

  - name: scout
    purpose: Find and report where things live; change nothing.
    prompt_engineering:
      system: adws/adw_data/prompt_engineering/scout/system.md
      user: adws/adw_data/prompt_engineering/scout/user.md
    tools:                         # optional allowlist — omitted entirely = all tools usable
      - read                       # pi builtin tool names: read, bash, edit, write
      - bash

  - name: tester
    thinking: low
    purpose: Run the tests and report exactly what passed and failed; fix nothing.
    prompt_engineering:
      system: adws/adw_data/prompt_engineering/tester/system.md
      user: adws/adw_data/prompt_engineering/tester/user.md
    tools:
      - read
      - bash
```

Resolution rules: `agents.py` merges each entry over `defaults`, maps `thinking` to the coding agent's native control, resolves the `prompt_engineering.system/.user` refs, and passes `harness_engineering` extensions through to the interface (`pi -e`). The optional `tools` array is an allowlist mapped to the coding agent's native restriction (`pi --tools`; pi builtins: read, bash, edit, write) — omitted means all tools usable. Model patterns resolve explicitly against `~/.pi/agent/models.json` to provider + id (fuzzy `--model` alone can land on the wrong provider). ADW scripts never name models — they name agents.

**V1 scope: Pi only.** `agent_pi.py` is implemented end-to-end (`pi -p --mode json --session-id ...` — session-id creates-or-continues, so run and continue_agent are the same mechanism); `agent_cc.py` is a stub that raises with a clear message. Claude Code lands in v2.

**Validation rule: every ADW validates its agents before running.** Each `adw_*.py` declares the agent names it needs; on startup it checks each name exists in `sssf.config.yaml` and resolves to a usable coding agent + model + prompt files. Any missing or misnamed agent fails the run immediately — no agent is ever spawned against a half-valid config.

**Typed output rule: every agent call has a concrete output type.** Every agent call passes a Pydantic model from `adw_modules/data_types.py` into the harness, and the agent's final JSON response is parsed against exactly that type — no untyped handoffs. If parsing or validation fails, we do NOT restart the agent: the harness calls `continue_agent(session_id, fix_prompt)` to re-prompt the **same session with its existing context** until the declared structure parses (bounded retries). Both interfaces must implement `continue_agent` — `agent_cc.py` via `claude --resume <session_id>`, `agent_pi.py` via Pi's session resume.

**Validation gates: validate claims, not guesses.** File names and counts aren't knowable before an agent finishes — so gates never predict; they verify the envelope's declarations after the fact. The envelope is a manifest of claims, and code checks every claim: each declared artifact exists and is non-empty, declared JSON parses, declared changes appear in the diff, declared test commands pass. Quantity is gated as properties over the declared list (at least one artifact, ALL declared paths valid), never as hardcoded counts. A gate is just a callable — `gate(envelope, session) -> list[str]` of violations, empty = pass — so ADWs compose them on the fly: a stdlib in `adw_modules/gates.py` plus inline one-offs at the call site. On violations the harness does NOT restart: it sends the violation list as a correction via `continue_agent(session_id, ...)` — same session, context intact, bounded retries — and every gate result is traced. What no predicate can check (plan quality, code taste) is not a gate's job; that's a reviewer agent or a human.

**Output types live at the code level, never in config.** `sssf.config.yaml` defines who an agent *is* (system prompt, coding agent, model, thinking); the ADW call site defines how it's *used*. User prompt + output type together define the task shape, and they always travel as a pair — the user prompt asks for the shape, the type enforces it. This is what lets one agent serve many calls: same system prompt, different user prompt + output type per call. Config's `prompt_engineering.user` is the agent's default usage; an `AgentCall` that supplies a different output type overrides the user prompt alongside it, at the same call site.

**Four-param rule (skill-wide code rule).** Any function that takes more than 4 parameters gets them converted into a concrete data type in `adw_modules/data_types.py` — `AgentCall` and `PhaseParams` are the pattern. This rule ships in the skill (SKILL.md rules + enforced by the `update_modules` cookbook), so every module the factory generates obeys it.

## adw_*.py API — first look

Keep it simple: point to config, point to the incoming prompt, then we run.

```bash
uv run adws/adw_plan_build.py "add a /health endpoint"            # config defaults to adws/adw_sssf_config/sssf.config.yaml
uv run adws/adw_plan_build.py requests/health.md                  # prompt can be inline text or a file path
uv run adws/adw_plan_build.py "add a /health endpoint" --config path/to/other.config.yaml
uv run adws/adw_build.py "implement the plan" --adw-id a1b2c3d4   # join an existing session — chain ADWs under one adw_id
```

`--adw-id` is optional on **every** `adw_*.py`. Given one, the run joins that session if it exists or creates it under exactly that id (pinned ids for repeatable runs) — same `sessions/{adw_id}/` dirs, same `context_handoff/`, envelopes appended. The `adw_id` also maps down to each agent's coding-agent session: `agent_map.json` records agent name → `session_id` + model, so a joined run resumes each agent's **existing context window** via `continue_agent` instead of starting cold. (The map records the model each session was created with — if config drift changes an agent's model, that agent starts a fresh session and the map is updated, never a bad resume.) Omitted, a fresh `adw_id` is minted and printed so the next ADW can pick it up.

Every `adw_*.py` is a thin `uv` single-file script with the same skeleton — all real logic lives in `adw_modules/`:

```python
REQUIRED_AGENTS = ["planner", "builder"]        # names, never models

def main(prompt: str, config: str = "adws/adw_sssf_config/sssf.config.yaml", adw_id: str | None = None) -> int:
    cfg = agents.load_config(config)            # 1. point to config
    agents.validate(cfg, REQUIRED_AGENTS)       # 2. fail fast: every name must resolve, or exit before any agent spawns
    run = session.ensure(cfg, adw_id)           # 3. pin-or-create the session; returns the Run object
                                                #    (config + adw_id + agent_map + tracer, bound once)

    with run.phase(PhaseParams(name="request", kind="engineer", owner=run.engineer,
                               description="Capture the incoming ask")) as ph:
        ph.log(input=prompt)

    with run.phase(PhaseParams(name="plan", kind="agent", owner="planner",
                               description="Turn the request into an implementable plan")) as ph:
        plan = ph.call(AgentCall(output_type=PlanOutput, prompt=prompt,
                                 gates=[gates.artifacts_exist, gates.files_non_empty]))

    with run.phase(PhaseParams(name="branch", kind="code", owner="git",
                               description="Isolate the work on its own branch")) as ph:
        git_helper.create_branch(f"sssf-{run.adw_id}")

    with run.phase(PhaseParams(name="build", kind="agent", owner="builder", retries=1,
                               description="Implement the plan exactly")) as ph:
        build = ph.call(AgentCall(output_type=BuildOutput, prompt=prompt, previous=plan,
                                  gates=[gates.diff_matches_claims]))

    with run.phase(PhaseParams(name="commit", kind="code", owner="git",
                               description="Commit the verified changes")) as ph:
        git_helper.commit(build.summary)

    return 0 if run.succeeded else 1
```

## Phases — the unit of the swim lane

Every ADW run is a sequence of **phases**, marked with ONE uniform primitive: a context manager — simple enter/exit blocks for all three kinds. Every phase declares a `name`, a `description`, and an `owner`, and every traced event logs against its `adw_id` + phase, so the UI always answers "what is running right now" with no interpretation.

- **engineer** `[obs]` — the human lane. Today: the system-input phase (who kicked off the run + the ask). Later: human-in-the-loop approval phases — same primitive, no redesign.
- **agent** `[all]` — `ph.call(AgentCall(...))` inside the phase: prompt in → typed envelope out → gates verified.
- **code** `[all]` — deterministic steps that stand on their own (git branch, git commit, deploy, db migrate). Never buried inside an agent phase — the UI shows exactly when code ran vs. when an agent was working.

Status — **success must be earned; every phase defaults to `fail`.** A clean exit flips it to success (agent phases additionally require envelope parsed + all gates green). A raise inside the block keeps it failed: the exception is recorded as an error event, declared retries run, and when retries are exhausted the run aborts — phases that never started render as queued.

Retries are phase-level: `retries=N` on any phase. Agent phases retry via `continue_agent` (same session, context intact); code phases re-execute their block (tenacity-style — the phase yields attempts internally, since a `with` body can't be re-run directly).

Swim-lane UI (reference mock: `prototypes/version4/mock2.png` — the trace waterfall): actors get fixed lanes on the left — **engineer top, code second, then one lane per agent**, labeled `name · model` (e.g. `builder · sonnet`). A phase block renders in its owner's lane showing name + description + status; agent blocks expand into their inner tool-call spans (duration, tokens); clicking any span opens the details panel (input/output/events/attributes). To render not-yet-started phases as queued (dashed), an ADW may declare its phase manifest up front — names + owners only; execution stays imperative Python.

### Phase data types

`run.phase(...)` takes exactly one object — `PhaseParams` (the four-param rule in action):

```python
class PhaseParams(BaseModel):
    """Everything run.phase() needs. Passed as one object, never loose params."""
    name: str                                    # short id, unique within the run: "plan", "branch", "build"
    kind: Literal["engineer", "agent", "code"]   # which lane the block renders in
    owner: str                                   # lane label: engineer's name, "git", or an agent name from config
    description: str = ""                        # one human sentence, shown in the phase block
    retries: int = 0                             # agent phases via continue_agent; code phases re-execute

class Phase(BaseModel):
    """The persisted record — PhaseParams plus lifecycle."""
    phase_id: str
    adw_id: str
    seq: int                                     # order within the run
    params: PhaseParams
    status: Literal["queued", "running", "success", "fail"] = "fail"
    attempt: int = 0                             # 0..retries
    error: str | None = None
    started_at: datetime | None = None
    ended_at: datetime | None = None
```

Lifecycle invariants: `queued` only for manifest-declared phases not yet entered (dashed in UI); `running` on enter; only a clean exit writes `success` (agent phases additionally need envelope parsed + gates green); everything else resolves to `fail`.

## UI — breadcrumbs, drill in, no sidebar

No sidebar; full width for content. Navigation is a breadcrumb path that maps 1:1 to the URL. **ADW sessions are the top level.**

```
sessions  ›  adw_7f3a9c2e  ›  build  ›  evt_0a41
   L1            L2            L3        L4
```

**L1 — Sessions (top level):**

```
┌────────────────────────────────────────────────────────────────────────┐
│ sssf › sessions                                     [search] [filter]  │
├────────────────────────────────────────────────────────────────────────┤
│ adw_id        request                 status    phases   started   tok │
│ adw_7f3a9c2e  add a /health endpoint  ● running ●●◐○○    14:32     41k │
│ adw_c2d901aa  fix flaky retry test    ✓ success ●●●●●    13:10     88k │
│ adw_88b12f04  dark mode toggle        ✗ fail    ●●✗──    11:47     17k │
└────────────────────────────────────────────────────────────────────────┘
```

Row = one ADW session: id, request, run status, phase mini-progress (● done, ◐ running, ○ queued, ✗ failed), engineer, started, duration, tokens. Click → L2.

**L2 — Session (the trace waterfall):**

```
┌────────────────────────────────────────────────────────────────────────┐
│ sessions › adw_7f3a9c2e     add a /health endpoint   ● running   db ↗  │
├────────────────────────────────────────────────────────────────────────┤
│ lane             0:00      0:30      1:00      1:30      2:00     2:30 │
│ engineer · dan   ▐request▌                                             │
│ code                       ▐branch▌                     ┄commit┄       │
│ planner · opus    ▐███ plan ███▌                                       │
│ builder · sonnet           ▐██████ build ██████▌                       │
│ reviewer · pi                              ┄┄ review (queued) ┄┄       │
└────────────────────────────────────────────────────────────────────────┘
```

Fixed lanes, phase blocks colored by status, agent blocks show tool-call spans at this zoom. Click a block → L3.

**L3 — Phase (drill into one block):**

```
┌────────────────────────────────────────────────────────────────────────┐
│ sessions › adw_7f3a9c2e › build           ✗→✓ success (attempt 2/2)    │
├────────────────────────────────────────────────────────────────────────┤
│ Implement the plan exactly             owner: builder · kind: agent    │
│                                                                        │
│ attempt 1  ✗  gate diff_matches_claims: 2 violations   [correction ▸]  │
│ attempt 2  ✓  envelope valid · gates 3/3 green         [envelope ▸]    │
│                                                                        │
│ events (14)                                                            │
│   tool_call  Read src/server.ts        1:08–1:32   24.1s               │
│   tool_call  Edit src/server.ts        1:45–1:53    8.2s   1,240 tok   │
│   gate_fail  diff_matches_claims       2:31                            │
└────────────────────────────────────────────────────────────────────────┘
```

Name, description, owner, kind, per-attempt history (gate results + the exact correction sent), the envelope, the flat event list. Click an event → L4.

**L4 — Span (one event):** input / output / attributes tabs — payload JSON, duration, tokens, parent event, agent session id. Deepest level; the breadcrumb gets you back anywhere in one click.

**L2 view modes:** the session level has two toggleable views at the same breadcrumb depth — **waterfall** (default, time-based swim lanes) and **graph** (DAG of agent nodes connected by artifact-labeled handoff edges; clicking a node opens its stats panel, clicking an edge opens the envelope that crossed it).

### UI reference mocks

Stored in `prototypes/` — use these when building the visualizer. We take the *content patterns* from each; the chrome adapts to our breadcrumbs-only, no-sidebar layout.

| Mock | Reference for |
|---|---|
| `version2/mock3.png` | Top-level ADW sessions view — the runs table (run id, task, agents, status, duration, tokens, cost, started) with a selected-run timeline below; envelope rows expand inline to payload + artifact links |
| `version4/mock1.png` | Stats inside the phase block, in the owner's lane — `1m 02s · $0.18` on the block itself; handoff diamonds between lanes; dashed queued block |
| `version4/mock2.png` | The trace waterfall as a whole (original reference) |
| `version4/mock3.png` | Drill-down on one node in one phase in one lane — zoomed waterfall window + windowed event stream + event detail (parsed fields side-by-side with raw JSON payload) |
| `version7/mock3.png` | High-level card view of one ADW run — task, status, per-agent done · duration · tool calls, run totals (time/tokens/cost/tool calls), open-trace CTA |
| `version8/mock2.png` | Alternative sessions page layout — card grid, each card a compact swim lane (per-agent progress dots, hover popover with last event + agent statuses); candidate for the L1 default |
| `version9/mock2.png` | Graph view of the ADW workflow — agent nodes (status ring, duration, event count) with artifact-labeled edges; node click → stats panel (tokens in/out, tool calls, artifacts, session_dir, open envelope) |
| `version9/mock3.png` | Graph view with a handoff edge selected — the envelope JSON with schema-valid badge, emitted time, size, artifact link |

## Stored data models

Two stores, one truth: **files are the raw record** (`raw_output.jsonl` streams, `envelope.json`, `agent_map.json`), **SQLite (`sssf.db`) is the queryable mirror** the UI reads. `tracer.py` writes both; losing the db loses nothing that can't be rebuilt from files.

**WAL mode, always.** The db takes rapid event inserts while the UI reads live — open every connection with `PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA busy_timeout=5000;`. WAL allows readers during writes. Writers are the tracers of running ADW processes (concurrent writers are fine: one small transaction per event + busy_timeout); the visualizer only ever reads.

**Live + lazy, one mechanism: poll the db.** The UI never receives pushes. Live view polls on a rowid cursor (`SELECT ... WHERE rowid > ? ORDER BY rowid LIMIT 500`) every `poll_ms`; already-run history is the same queries with filters, lazy-paged as you scroll or drill in. No ingest endpoint, no WebSocket, no backfill/dedup logic — the data flow is always **agents → sqlite → web ui**. KISS.

```sql
sessions (
  adw_id        TEXT PRIMARY KEY,
  request       TEXT,              -- the engineer's ask
  status        TEXT,              -- running | success | fail
  engineer      TEXT,
  started_at    TEXT, ended_at TEXT,
  total_tokens  INTEGER, total_cost REAL
);

phases (
  phase_id      TEXT PRIMARY KEY,
  adw_id        TEXT REFERENCES sessions,
  seq           INTEGER,
  name TEXT, kind TEXT, owner TEXT, description TEXT,
  status        TEXT DEFAULT 'fail',   -- success must be earned
  attempt       INTEGER DEFAULT 0, retries INTEGER DEFAULT 0,
  error         TEXT,
  started_at    TEXT, ended_at TEXT
);

events (
  event_id      TEXT PRIMARY KEY,
  adw_id        TEXT REFERENCES sessions,
  phase_id      TEXT REFERENCES phases,   -- every event logs against adw + phase
  parent_id     TEXT,                     -- span nesting
  type          TEXT,   -- phase_start | phase_end | agent_start | agent_end | tool_call | handoff | gate_pass | gate_fail | log | error
  name          TEXT,
  payload_json  TEXT,
  tokens        INTEGER,
  started_at    TEXT, ended_at TEXT
);

envelopes (
  envelope_id   TEXT PRIMARY KEY,
  adw_id        TEXT REFERENCES sessions,
  phase_id      TEXT REFERENCES phases,
  agent         TEXT,
  output_type   TEXT,              -- name of the data_types model it parsed against
  payload_json  TEXT,
  valid         INTEGER,
  attempt       INTEGER,
  created_at    TEXT
);

gate_results (
  id            INTEGER PRIMARY KEY,
  adw_id        TEXT REFERENCES sessions,
  phase_id      TEXT REFERENCES phases,
  attempt       INTEGER,
  gate          TEXT,
  passed        INTEGER,
  violations_json TEXT,
  created_at    TEXT
);

agent_sessions (                   -- the queryable mirror of agent_map.json
  adw_id        TEXT REFERENCES sessions,
  agent         TEXT,
  coding_agent  TEXT, model TEXT,
  session_id    TEXT,
  created_at    TEXT, last_used_at TEXT,
  PRIMARY KEY (adw_id, agent)
);
```

Derived, never stored: phase durations (ended−started), session phase-progress (query phases by adw_id), lane layout (kind + owner).

## Flow (one-shot run)

1. `[config]` ADW script starts → validates every agent it names exists in `sssf.config.yaml`, then `agents.py` resolves each one (coding agent, model, thinking, prompt refs). Missing name = immediate fail, nothing spawns.
2. `[handoff]` `session.py` mints the `adw_id`, session dirs, and `context_handoff/`; `prompts.py` renders the agent's one system + one user prompt (previous envelope + context_handoff path injected). Agents have exactly two output channels: reference files into `context_handoff/`, and a final valid-JSON envelope as their direct response — code parses it against the call's declared output type, persists it as `envelope.json`, and hands it to the next agent. If the JSON doesn't parse, `continue_agent(session_id)` re-prompts the same session (context intact) until it does. Every agent run records its coding-agent `session_id` in `agent_map.json`, so later ADWs joining the same `adw_id` resume those context windows too. Context transfers in code, not in conversation.
3. `[obs]` `tracer.py` writes every event (phase_start, agent_start, tool, handoff, gate_pass, gate_fail, agent_end, phase_end, error) to JSONL and straight into `sssf.db` as it happens; the UI polls the db on a rowid cursor. The flow is always **agents → sqlite → web ui** — live view and history are the same queries at different cadence.

The orchestrator agent sits on top of this static layer: it runs the system, observes the system, and helps you interact with it. It does no work itself. It operates from `cookbooks/` — `sssf_overview.md` on startup, every other cookbook loaded lazily for the request at hand (build-out via create/update cookbooks, execution via `run_adw.md`).

**Build watchpoint — streaming.** With polling as the transport, the streaming crack narrows to one thing: the tracer must tail the coding agent's stdout stream and insert each event into `sssf.db` **while the agent is still working** — not batched when the phase ends. Crack that first with `adw_prompt.py` and a single agent before composing chains — everything downstream (poll → render) is conventional.
