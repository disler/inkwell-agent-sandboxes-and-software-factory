#!/usr/bin/env -S uv run
# /// script
# dependencies = ["pydantic", "python-dotenv", "pyyaml", "rich"]
# ///
"""ADW Document — write up the work that was just done, from the diff.

Usage:
    uv run adws/adw_document.py "<prompt or path/to/prompt.md>" [--base main] [--config adws/adw_sssf_config/sssf.config.yaml] [--adw-id a1b2c3d4]

Phases: engineer(request) -> code(changes) -> documenter

This runs AFTER a build, and the guard is structural rather than advisory: the
change capture is a code phase, and an empty diff raises there — before the
documenter is ever spawned. There is nothing to document until something was
built, and the phase says so instead of paying an agent to discover it.

`git diff` against `--base` (main by default) is what "the latest changes"
means here; see adw_modules/changes.py for how the base commit is resolved on a
branch, on main, and on a clean tree right after a chain committed.
"""

import argparse
import sys

from adw_modules import agents, changes, gates, session, utils
from adw_modules.data_types import (AgentCall, ChangeCapture, DocumentOutput,
                                    PhaseParams)

REQUIRED_AGENTS = ["documenter"]

DOCUMENT_NOTES = ("Read diff_path in full before writing. Document only what the "
                  "diff shows, then copy the write-up into app_docs/ as your task "
                  "describes.")


def main(prompt: str, base: str = "main",
         config: str = "adws/adw_sssf_config/sssf.config.yaml", adw_id: str | None = None) -> int:
    cfg = agents.load_config(config)
    agents.validate(cfg, REQUIRED_AGENTS)
    run = session.ensure(cfg, adw_id)

    with run.phase(PhaseParams(name="request", kind="engineer", owner=run.engineer,
                               description="Capture the incoming ask")) as ph:
        ph.log(input=prompt)

    with run.phase(PhaseParams(name="changes", kind="code", owner="git",
                               description=f"Diff the working tree against {base} — the change to be written up")) as ph:
        changeset = changes.capture(run, ChangeCapture(base=base))
        ph.log(base=f"{changeset.base.label} @ {changeset.base.commit[:7]}",
               reason=changeset.base.reason,
               files=len(changeset.files) + len(changeset.untracked),
               lines=f"+{changeset.insertions} -{changeset.deletions}",
               diff=changeset.diff_path)
        if changeset.empty:
            raise RuntimeError(
                f"nothing changed since {changeset.base.label} ({changeset.base.reason}) "
                f"— documenting runs after a build. Build something first, or point "
                f"--base at the ref the work should be measured from.")

    with run.phase(PhaseParams(name="document", kind="agent", owner="documenter", retries=1,
                               description="Turn the captured diff into a write-up an engineer can read")) as ph:
        ph.call(AgentCall(output_type=DocumentOutput, prompt=prompt,
                          previous=changes.as_envelope(changeset, DOCUMENT_NOTES),
                          gates=[gates.artifacts_exist, gates.files_non_empty]))

    return run.finish()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("prompt", help="inline text or a path to a prompt file")
    parser.add_argument("--base", default="main", help="ref the change is measured against")
    parser.add_argument("--config", default="adws/adw_sssf_config/sssf.config.yaml")
    parser.add_argument("--adw-id", default=None, help="join or pin an existing session")
    args = parser.parse_args()
    sys.exit(main(utils.resolve_prompt(args.prompt), args.base, args.config, args.adw_id))
