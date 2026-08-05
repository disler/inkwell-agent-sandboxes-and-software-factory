# Models: rosters, rates, ZDR

One mechanism: **OpenRouter**. A long-lived provisioning key on the host mints one disposable
runtime key per sandbox (`sbx-<run-id>`, `$50` default), which is revoked at teardown by hash.
Chosen over exe.dev's BYOK LLM integration purely on **portability** — a credential layer bound
to one provider's hostname stops being a transferable asset the moment the sandbox provider
changes, and the whole point of this system is that it moves.

One exception: `just sbx run agent` runs **Claude Code** against exe.dev's key-free gateway
(`ANTHROPIC_BASE_URL=https://llm.int.exe.xyz`, `ANTHROPIC_API_KEY=implicit`). OpenRouter does not
serve the Anthropic Messages API cleanly, and that lane needs no key at all.

---

## The two rosters

Per-run variation lives in exactly three places: **the prompt**, **`SSSF_CONFIG`**, and **the
model**. Nothing else changes between N runs.

### `adws/adw_sssf_config/sssf.config.yaml` — the default roster

`defaults.model: openrouter/deepseek/deepseek-v4-flash-0731`, `thinking: medium`

| Agent | Model | Thinking | Rate in/out per M |
| --- | --- | --- | --- |
| planner | `openrouter/google/gemini-3.6-flash` | high | $1.50 / $7.50 |
| builder | *(inherits the default)* `deepseek/deepseek-v4-flash-0731` | medium | $0.09 / $0.18 |
| scout | *(inherits the default)* `deepseek/deepseek-v4-flash-0731` | medium | $0.09 / $0.18 |
| reviewer | `openrouter/z-ai/glm-5.2` | high | $0.76 / $2.42 |
| documenter | `openrouter/openai/gpt-5.6-luna` | medium | $0.10 / $0.60 |

### `adws/adw_sssf_config/sssf.frontier.config.yaml` — the frontier roster

Also known as the sota roster, the big models. `defaults.model:
openrouter/anthropic/claude-opus-5`, `thinking: high` across the board. **Nothing but the roster
changes** — same ADW scripts, same prompts, same gates, same trace. Swapping the file in is the
whole migration:

```bash
uv run adws/adw_plan_build_test.py "<request>" \
  --config adws/adw_sssf_config/sssf.frontier.config.yaml
```

| Agent | Model | Rate in/out per M | Cast for |
| --- | --- | --- | --- |
| planner | `openrouter/anthropic/claude-opus-5` | $5.00 / $25.00 | 1M context; the plan is the highest-leverage artifact |
| builder | `openrouter/moonshotai/kimi-k3` | $3.00 / $15.00 | 1M context, strong tool use; the only agent that writes code |
| scout | `openrouter/openai/gpt-5.6-sol` | $5.00 / $30.00 | search-heavy recon |
| reviewer | `openrouter/anthropic/claude-opus-5` | $5.00 / $25.00 | judgement against a spec — the same strength that earns it the plan |
| documenter | `openrouter/moonshotai/kimi-k3` | $3.00 / $15.00 | a long diff read end to end, then written up once |

Both rosters write to the **same** `adws/adw_data/sssf.db`, so runs sit side by side in the
visualizer.

### There is no tester agent

Running the suite is a known command, so it is a `kind="code"` phase over
`adws/adw_modules/quality.py`, not an agent that has to rediscover it.

---

## The model-tiering rule

**Cheap models for mechanical lanes, expensive for plan and judge.**

A mechanical lane executes something already decided — scout follows a search, builder follows a
plan, documenter follows a diff. Judgement lanes decide what is true: the planner turns a request
into something implementable without asking questions, the reviewer decides whether what was
built is what was asked for. Judgement is where model quality converts into outcome; mechanics is
where it converts into bill.

The default roster is that rule applied literally: the two mechanical lanes run on the cheapest
model in the registry ($0.09/$0.18, ~17x cheaper in than the planner), the write-up lane on the
next cheapest, and the two expensive slots are plan and judge. The frontier roster applies the
same rule with the whole tier list shifted up.

Two ids that cost a verification cycle:

- There is **no** deepseek v3 0731 — the v3 line ends at v3.2. The build you want is
  `deepseek/deepseek-v4-flash-0731`. The plain `deepseek-v4-flash` is the April preview at
  $0.14/$0.28; the 0731 build is 36% cheaper and is the A-tier weights.
- `moonshotai/kimi-k3` is $3.00/$15.00 — about **5x** `kimi-k2.6` ($0.59/$2.48). Good as a
  frontier builder, expensive as a default one.

---

## The ten registered models

`sandbox_mount/guest/models.json.tmpl` → written to `~/.pi/agent/models.json` by
`provision.sh` step 5/10, `chmod 600` because it holds a live key. Ten models, one provider
block. Per-million-token rates, pulled live from OpenRouter 2026-08-04 — regenerate when
pricing moves.

| Model | input | output | cacheRead | cacheWrite | Provider under ZDR | In a roster? |
| --- | --- | --- | --- | --- | --- | --- |
| `deepseek/deepseek-v4-flash-0731` | 0.09 | 0.18 | 0.018 | 0.0 | **Parasail** (US) | default: builder, scout |
| `openai/gpt-5.6-luna` | 0.1 | 0.6 | 0.01 | 0.125 | **Azure** | default: documenter |
| `z-ai/glm-5.2` | 0.76 | 2.42 | 0.14 | 0.0 | **CoreWeave** (US) | default: reviewer |
| `openai/gpt-5.6-terra` | 1.0 | 6.0 | 0.1 | 1.25 | **Azure** | registered only |
| `google/gemini-3.6-flash` | 1.5 | 7.5 | 0.15 | 0.0833 | **Google** | default: planner |
| `anthropic/claude-sonnet-5` | 2.0 | 10.0 | 0.2 | 2.5 | **Google Vertex** | registered only |
| `x-ai/grok-4.5` | 2.0 | 6.0 | 0.3 | 0.0 | **xAI** | registered only |
| `moonshotai/kimi-k3` | 3.0 | 15.0 | 0.3 | 0.0 | **Moonshot AI** | frontier: builder, documenter |
| `anthropic/claude-opus-5` | 5.0 | 25.0 | 0.5 | 6.25 | **Google Vertex** | frontier: planner, reviewer |
| `openai/gpt-5.6-sol` | 5.0 | 30.0 | 0.5 | 6.25 | *not in the ZDR verification table* | frontier: scout |

Three models are registered but unused by either roster (`gpt-5.6-terra`,
`claude-sonnet-5`, `grok-4.5`) so they can be swapped into a config without re-provisioning the
sandbox. Nine were verified ZDR-capable on 2026-08-04 — every one returned `pong` under
`provider: {"zdr": true, "data_collection": "deny"}`. `gpt-5.6-sol` is registered and used by the
frontier scout but was not in that nine; its ZDR routing is unverified.

### The cost block is mandatory and all-or-nothing

`pi` defaults every rate to zero when a model carries no `cost` block, and
`adws/adw_modules/agent_pi.py` reads `usage.cost.total` straight out of pi — so a missing rate
table means every run reports **$0.0000 while really spending money**. Observed: a 463.6k-token
run logged $0.0000. Verified fixed: with rates loaded, a 1,797-token run reported $0.0081.

Worse, the schema requires **all four** of `input`, `output`, `cacheRead`, `cacheWrite`. A
partial block fails validation and pi drops **the entire roster**, not just that model —
`must have required properties cacheRead, cacheWrite` → `No models available`. Use `0.0` where
a provider publishes no cache-write rate. Gate assertion D exists for exactly this.

### The limit block is mandatory too — and its default is the silent killer

A model entry that omits `contextWindow` / `maxTokens` does **not** inherit pi's built-in registry
values. pi applies its schema defaults instead: **128K context and `maxTokens: 16384`**, and it
also treats the model as non-reasoning (`thinking` in any roster becomes inert) and text-only.

Nothing fails loudly. `pi --list-models` exits 0, the roster loads, gates B/C/D all pass — and
then the **builder** truncates mid-edit, because it is the one agent that emits whole files.
Observed 2026-08-05: both arms whose builder was `kimi-k3` failed at build while all three arms
building on `deepseek-v4-flash-0731` (the only entry that declared limits) succeeded. Frontier's
builder returned an **empty response** three times in a row; open-weights' builder reported
*"the session ended after the reconnaissance phase … before any edits were applied."* Cost of the
two failed arms: $4.39.

The tell is uniformity — every under-declared model reads exactly `128K / 16.4K / no / no`:

```bash
just sbx run cmd <id> 'pi --list-models'    # any row reading 128K 16.4K no no is under-declared
```

So every model needs **four** blocks, not one: `contextWindow`, `maxTokens`, `reasoning`, `input`,
plus `cost`. Pick `maxTokens` as the **minimum across healthy serving endpoints**, since
OpenRouter may route to any of them and the roster cannot pin a provider:

```bash
curl -sS https://openrouter.ai/api/v1/models/<author>/<slug>/endpoints \
  | jq -r '.data.endpoints[] | select(.status==0)
           | [.provider_name, .context_length, (.max_completion_tokens//"NULL")] | @tsv'
```

That minimum is why `kimi-k3` is pinned to 65535 (Chutes) and `glm-5.2` to 128000 (StreamLake)
rather than the 1M their model cards advertise. Rates and limits alike were pulled live
2026-08-05; they go stale.

### The provider block

```json
{ "providers": { "openrouter": {
  "baseUrl": "https://openrouter.ai/api/v1",
  "api": "openai-completions",
  "apiKey": "env:OPENROUTER_API_KEY",
  "models": [ { "id": "...",
                "contextWindow": …, "maxTokens": …, "reasoning": true, "input": ["text"],
                "cost": { "input": …, "output": …, "cacheRead": …, "cacheWrite": … } } ]
} } }
```

The template ships `apiKey: "env:OPENROUTER_API_KEY"`. pi only sees that variable when its parent
exported it — true for the ADWs (`uv run` + dotenv), **not** true for a bare
`ssh <vm> 'pi --list-models'`, which is exactly what gate B runs. So `provision.sh` bakes the
runtime key in from `app/.env` by bash string substitution (never argv) and chmods the file 600.

pi resolves `provider/id` by splitting on the **first slash**, so
`openrouter/google/gemini-3.6-flash` means provider `openrouter`, model
`google/gemini-3.6-flash`. Config values therefore carry a provider prefix that is not part of
the OpenRouter id — gate C strips `^openrouter/` before pinging.

---

## Zero data retention

| Param | Values | Effect |
| --- | --- | --- |
| `provider.zdr` | `true` / omitted | Route only to providers enforcing zero data retention |
| `provider.data_collection` | `allow` (default) / `deny` | `deny` restricts routing to providers that do not collect user data. **Independent of `zdr` — use both** |

**Enforcement is an ACCOUNT setting, not a per-request one.** pi's `models.json` supports custom
headers but **no arbitrary request-body fields**, so `provider: {...}` cannot be injected through
pi's config at all. Set the data policy once in the OpenRouter dashboard
(Settings → Privacy); it then applies to every request from every key, including minted runtime
keys, and covers Claude Code too.

The per-request param stays in the **gate ping** (assertion C sends
`"provider":{"zdr":true,"data_collection":"deny"}` on every roster model) so the gate proves ZDR
routing resolves before any real work runs.

This sharpens the IP-hygiene story rather than complicating it. Under ZDR,
`deepseek-v4-flash-0731` is served by **Parasail** and `glm-5.2` by **CoreWeave** — both US
providers. The "Chinese labs may train on your data" caution applies to those labs' own APIs, not
to their open weights on Western hosts. Under ZDR you are not talking to a Chinese lab at all.

---

## Credential lifecycle

| | Provisioning key | Runtime key |
| --- | --- | --- |
| Lives in | `OPENROUTER_PROVISIONING_KEY` in host `.env` | `.sandbox/runs/<id>.key` (600) → `app/.env` on the VM → baked into `~/.pi/agent/models.json` |
| Lifetime | long-lived; the only long-lived secret in the system | one sandbox |
| Can do | mint + revoke only — it **cannot do inference**, it returns `User not found` | inference only |
| Enters a sandbox | **never** | yes, that is the point |
| Killed by | manual rotation | `just sbx lifecycle teardown`, or `just sbx manage reap` as the backstop |

OpenRouter keys have **no native TTL**. If teardown never runs, the key outlives the sandbox
forever. Run `just sbx manage reap` at the start of every session; the `sbx-` prefix is the only thing
separating managed keys from personal ones.
