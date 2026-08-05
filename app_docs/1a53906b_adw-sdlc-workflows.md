# SSSF Reviewer, Documenter, and Simple SDLC Integration

## Overview

This change introduces two new agents (`reviewer` and `documenter`), deterministic change capture via git, and three new ADW workflows (`adw_build_review`, `adw_document`, `adw_simple_sdlc`).

Prior to this update, SSSF workflows could plan, build, and test, but lacked explicit verification of whether a build met requirements (review) or automatic write-ups of completed work (documentation). This update fills those gaps by separating testing ("does it run?") from review ("is this what was asked for?"), capturing pure git diffs for documentation, and providing an end-to-end SDLC pipeline (`simple-sdlc`).

---

## What Changed and Why It Matters

### 1. New Agents & Prompts
* **`reviewer`**: Evaluates whether code on disk meets spec requirements (from `plan.md` or prompt). Operates read-only across code and writes findings/blocking items. Has a dedicated gate `verdict_consistent` to ensure `approved` status aligns with recorded findings.
* **`documenter`**: Reads captured diffs (`context_handoff/changes.diff`) and writes traceable documentation into `app_docs/<adw_id>_<slug>.md`. Cannot modify codebase source files or tests.
* **`planner` Prompt Update**: Updated to save durable repo copies of plans under `specs/<adw_id>_<slug>.md` alongside the session `plan.md`.

### 2. Deterministic Change Capture & Git Plumbing
* **`adw_modules/changes.py`**: Resolves base git refs intelligently (handles diverged branches, dirty working trees, or clean trees by falling back to `HEAD~1`), writes `context_handoff/changes.diff`, and wraps the change set in a `ChangesOutput` envelope.
* **`adw_modules/git_helper.py`**: Added low-level diff plumbing functions (`merge_base`, `diff_files`, `diff_stat`, `diff_counts`, `diff_text`, `untracked_files`, `repo_root`).
* **`adw_modules/data_types.py`**: Added data types for `ReviewFinding`, `ReviewOutput`, `DocumentOutput`, `ChangeCapture`, `BaseRef`, `ChangeSet`, and `ChangesOutput`.
* **`adw_modules/gates.py`**: Added `verdict_consistent` gate verifying that `approved=true` has no blocking findings and rejections provide explicit reasons.

### 3. New Runnable ADW Workflows
* **`adws/adw_build_review.py`**: `builder` -> `reviewer` with a bounded revision loop (`MAX_REVISION_LOOPS = 3`).
* **`adws/adw_document.py`**: `changes` (git capture) -> `documenter`. Errors if there are no uncommitted/committed changes since the base ref.
* **`adws/adw_simple_sdlc.py`**: Complete workflow: `planner` -> `builder` -> `tester` (fix loop) -> `reviewer` (revise loop) -> re-test if revised -> `changes` -> `documenter` -> `git commit`.

### 4. Configuration, Tooling & Documentation
* **`justfile`**: Added wrapper recipes `just build-review`, `just document`, and `just simple-sdlc`.
* **Config Files**: Added `reviewer` and `documenter` agent definitions to `sssf.config.yaml`, `sssf.frontier.config.yaml`, and skill templates.
* **Cookbooks & Docs**: Updated `scaffold.md`, `README.md`, `prime.md`, `create_adw.md`, `install.md`, `sssf_overview.md`, and `update_modules.md`.

---

## File Summary

| File Path | Role / Function |
| --- | --- |
| `adws/adw_modules/changes.py` | Deterministic git diff capture and envelope adapter |
| `adws/adw_modules/git_helper.py` | Git inspection and diff helper functions |
| `adws/adw_modules/data_types.py` | Envelope and data model definitions for review, document, and changes |
| `adws/adw_modules/gates.py` | Added `verdict_consistent` gate for review validation |
| `adws/adw_build_review.py` | Workflow for building and reviewing against prompt/plan |
| `adws/adw_document.py` | Workflow for generating documentation from git diffs |
| `adws/adw_simple_sdlc.py` | Full SDLC workflow: plan, build, test, review, document, commit |
| `adws/adw_data/prompt_engineering/reviewer/*` | System and user prompts for reviewer agent |
| `adws/adw_data/prompt_engineering/documenter/*` | System and user prompts for documenter agent |
| `.claude/skills/sssf/templates/*` | Synchronized templates for installer / skill distribution |
| `justfile` | Recipe shortcuts for running new workflows |
| `README.md` | Updated system map, workflow descriptions, and edge cases |

---

## How to Use & Verify

### Running the Workflows

```bash
# Run build -> review cycle
just build-review "Implement feature X"

# Generate documentation for latest changes
just document "Document work done"
# Or specify a custom base ref:
uv run adws/adw_document.py "Document work done" --base main

# Run complete end-to-end SDLC
just simple-sdlc "Add health check endpoint"
```

### Verification
1. Test workflow execution with a sample prompt using `uv run adws/adw_build_review.py ...` or `just simple-sdlc`.
2. Verify that plans land in `specs/`, documentation lands in `app_docs/`, and diff summaries land in `context_handoff/changes.diff`.
