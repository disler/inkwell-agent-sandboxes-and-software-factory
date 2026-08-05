# SSSF model routing and visualizer model metadata

## What changed

SSSF now routes the reviewer and documenter agents directly through OpenAI instead of the OpenRouter-qualified model IDs. Both configuration copies were updated:

- `.claude/skills/sssf/templates/sssf.config.yaml`
- `adws/adw_sssf_config/sssf.config.yaml`

The values are now `openai/gpt-5.6-terra` for `reviewer` and `openai/gpt-5.6-luna` for `documenter`.

The Pi adapter now resolves models and context limits from Pi's merged `pi --list-models` catalog, which includes built-in providers as well as custom models. `_pi_catalog()` parses the catalog once per process (including compact `K`/`M` counts), and `resolve_model()` uses it for explicit provider/model pairs and unambiguous pattern matches. This allows direct provider-qualified models such as `openai/gpt-5.6-terra` without requiring them to be re-registered in the local models JSON. If the catalog cannot be read, resolution returns the existing actionable errors rather than guessing.

`context_window()` still prefers the configured `models.json` entry, then falls back to the matching Pi catalog row. As a result, the visualizer can receive the actual context-window ceiling for models that are present in Pi's merged catalog but absent from the local registry. The same implementation is present in both:

- `adws/adw_modules/agent_pi.py`
- `.claude/skills/sssf/templates/adws/adw_modules/agent_pi.py`

The visualizer model metadata was expanded in `.claude/skills/sssf/apps/visualizer/src/lib/models.ts`:

- Kimi/Moonshot model names map to `/models/kimi.png`.
- `modelName()` displays only the final slash-delimited segment, e.g. `openai/gpt-5.6-terra` becomes `gpt-5.6-terra`.

That compact display is used in both `.claude/skills/sssf/apps/visualizer/src/components/SessionTrace.vue` and `PhaseDetail.vue`. The full model ID remains available through the existing `title` attributes, so the compact label does not remove model identity when inspecting a lane or phase configuration. The new icon asset is `.claude/skills/sssf/apps/visualizer/public/models/kimi.png`.

## How to use and verify

Use provider-qualified model IDs in SSSF configuration, for example `openai/gpt-5.6-terra`. At runtime the adapter checks that exact pair against Pi's merged catalog; a bare or partial pattern is accepted only when it resolves uniquely. The visualizer will show the provider-specific icon when a known model name is present, render the compact model ID in session lanes and phase details, and expose the full ID on hover.

The completed changes were validated with:

```bash
python -m py_compile adws/adw_modules/agent_pi.py \
  .claude/skills/sssf/templates/adws/adw_modules/agent_pi.py
(cd .claude/skills/sssf/apps/visualizer && bun run typecheck)
```

Both Python files compiled successfully, and `vue-tsc --noEmit` completed successfully for the visualizer.
