# Prevent Overwriting Specs and App Docs in Reused Sessions

## Summary of Changes
Updated prompt engineering templates and runtime prompts for the `documenter` and `planner` agents, as well as the SSSF install cookbook documentation. The prompt updates instruct the documenter and planner agents to list `app_docs/` and `specs/` respectively before naming new output files, appending version suffixes (`_v2`, `_v3`, etc.) if a target file with the same `adw_id` and `slug` already exists. This prevents multiple runs within the same session from overwriting existing documentation or specification files.

## Changed Files
- **`.claude/skills/sssf/cookbooks/install.md`**: Updated starter ADW count reference from 10 to 12.
- **`.claude/skills/sssf/templates/prompt_engineering/documenter/system.md`** & **`adws/adw_data/prompt_engineering/documenter/system.md`**:
  - Added instruction to list `app_docs/` before naming write-ups to avoid overwriting existing documents when an `adw_id` is reused across multiple runs.
- **`.claude/skills/sssf/templates/prompt_engineering/documenter/user.md`** & **`adws/adw_data/prompt_engineering/documenter/user.md`**:
  - Added step-by-step instructions for checking existing files in `app_docs/` and appending `_v2`, `_v3`, etc., to the base filename `app_docs/<adw_id>_<slug>.md` if a collision occurs.
- **`.claude/skills/sssf/templates/prompt_engineering/planner/system.md`** & **`adws/adw_data/prompt_engineering/planner/system.md`**:
  - Added instruction to list `specs/` before naming plan copies to prevent overwriting prior specs.
- **`.claude/skills/sssf/templates/prompt_engineering/planner/user.md`** & **`adws/adw_data/prompt_engineering/planner/user.md`**:
  - Added step-by-step instructions for checking existing files in `specs/` and appending `_v2`, `_v3`, etc., to the base filename `specs/<adw_id>_<slug>.md` if a collision occurs.

## Usage & Verification
When documenter or planner agents run in a session where an `adw_id` has already produced a spec or doc file:
1. The agent lists the `specs/` or `app_docs/` directory.
2. If `app_docs/<adw_id>_<slug>.md` or `specs/<adw_id>_<slug>.md` exists, the agent names the new artifact with a `_v2` (or incremented version) suffix.
3. Existing documentation and specifications remain preserved in the repository.
