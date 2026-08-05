#!/usr/bin/env python3
"""Render the run-record table for `just runs`.

Lives in a file rather than embedded in the recipe for two reasons. An
unindented line inside a just recipe body TERMINATES the recipe, so embedded
python is a parse error waiting to happen. And the record has legitimately-empty
fields — `spend` is null until teardown — which a tab-delimited shell read-loop
mis-assigns, landing the vm name in the SPEND column.

Reads run records from stdin as JSON; takes the live VM list as argv[1] (a
comma-separated string, or the literal `__unknown__` when the control plane
could not be reached). "unknown" is deliberately distinct from "gone": a failed
lookup must never render as "every VM is destroyed".
"""
import json
import sys


def main() -> int:
    raw = sys.stdin.read().strip() or "[]"
    try:
        records = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"runs: could not parse run records: {exc}", file=sys.stderr)
        return 1

    live_arg = sys.argv[1] if len(sys.argv) > 1 else "__unknown__"
    alive = None if live_arg == "__unknown__" else {v for v in live_arg.split(",") if v}

    if not records:
        print("no runs yet — start one with: just mount <task-name>")
        return 0

    print(f"{'RUN':<34} {'STATE':<8} {'VM':<7} {'SPEND':<10} CREATED")
    for rec in records:
        vm = rec.get("vm_name") or ""
        state = "closed" if rec.get("closed_at") else "open"
        if alive is None:
            vm_state = "?"
        elif vm and vm in alive:
            vm_state = "up"
        else:
            vm_state = "gone"
        spend = rec.get("spend")
        spend_s = f"${spend}" if spend is not None else "-"
        created = (rec.get("created_at") or "").split("T")[0]
        print(f"{rec.get('run_id', '?'):<34} {state:<8} {vm_state:<7} {spend_s:<10} {created}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
