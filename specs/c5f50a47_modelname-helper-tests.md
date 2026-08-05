# Plan: Unit tests for the visualizer `modelName` helper

## Goal

Add focused unit tests for `modelName()` in
`.claude/skills/sssf/apps/visualizer/src/lib/models.ts` so that:

- Provider-qualified IDs (`openai/gpt-5.6-terra`, `anthropic/claude-opus-4-8`) display only their **final slash-delimited segment** (`gpt-5.6-terra`, `claude-opus-4-8`).
- Bare model names (`gpt-5.6-terra`, `claude-sonnet-4-5`) remain **unchanged**.

## Context

- The helper already exists and works:
  ```ts
  export function modelName(model: string | null | undefined): string {
    if (!model) return ''
    return model.split('/').filter(Boolean).at(-1) ?? model
  }
  ```
  Tests lock in this behavior — no source change expected.
- The visualizer app has **no test framework configured** (no `*.test.*` files, no test script in `package.json`).
- The app runs on **Bun** (`bun.lock`, `@types/bun` devDep, `bun run server/index.ts` scripts). Use **`bun test`** (built-in `bun:test` module) — zero new dependencies, no vitest/jest config needed.

## Changes

### 1. New file: `.claude/skills/sssf/apps/visualizer/src/lib/models.test.ts`

Import from `bun:test` and the sibling module:

```ts
import { describe, expect, test } from 'bun:test'
import { modelName } from './models'
```

Cover, in one `describe('modelName')` block:

- **Provider-qualified IDs → final segment only**
  - `'openai/gpt-5.6-terra'` → `'gpt-5.6-terra'`
  - `'anthropic/claude-opus-4-8'` → `'claude-opus-4-8'`
  - Multi-segment path (e.g. `'openrouter/google/gemini-3-pro'`) → `'gemini-3-pro'`
- **Bare model names unchanged**
  - `'gpt-5.6-terra'` → `'gpt-5.6-terra'`
  - `'claude-sonnet-4-5'` → `'claude-sonnet-4-5'`
- **Edge cases** (current contract — cheap to pin down)
  - `undefined` → `''`, `null` → `''`, `''` → `''`
  - Trailing slash `'openai/'` → `'openai'` (empty segments filtered)

Keep it to this one file — do not add tests for `modelIcon` or anything else.

### 2. Edit: `.claude/skills/sssf/apps/visualizer/package.json`

Add a script alongside the existing ones:

```json
"test": "bun test"
```

## Verify

From `.claude/skills/sssf/apps/visualizer/`:

1. `bun test` — exits 0, all assertions pass.
2. `bun run typecheck` — still clean (the test file is TypeScript; `bun:test` types come from `@types/bun`, already a devDependency).
3. `bun run lint` — still clean (oxlint runs over the repo, new file included).

All three commands must exit 0.
