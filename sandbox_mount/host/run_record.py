#!/usr/bin/env python3
"""The run record — the only state shared across the six sandbox phases.

Each phase (create, fill, setup, execute, observe, teardown) is a separate
process, so nothing survives between them except what is on disk. Teardown has
no other way to learn which OpenRouter key to revoke: lose the record and the
key is unrevokable and keeps burning credit. One JSON file per run, keyed by
run_id, under .sandbox/runs/ (gitignored).

Usage:
    run_record.py create  <run-id>
    run_record.py get     <run-id> [field]
    run_record.py set     <run-id> key=value [key=value ...]
    run_record.py close   <run-id>
    run_record.py list
    run_record.py path    <run-id>
    run_record.py new-id  <task>

`get <run-id> <field>` prints the bare value so shell can capture it:
    RUN_VM=$(sandbox_mount/host/run_record.py get my-run vm_name)

Stdlib only, on purpose: this runs on the host before any toolchain exists and
must never be the reason a teardown cannot start.
"""

from __future__ import annotations

import json
import os
import re
import secrets
import sys
from datetime import datetime, timezone
from pathlib import Path

# sandbox_mount/host/run_record.py -> repo root
REPO_ROOT = Path(__file__).resolve().parents[2]
RUNS_DIR = REPO_ROOT / ".sandbox" / "runs"

# The closed schema. Every field is referenced by name somewhere in the six
# phases, so a typo in a `set` is a silent data loss bug -- reject unknown keys
# rather than write them.
FIELDS = (
    "run_id",
    "vm_name",
    "https_url",
    "key_hash",
    "limit",
    "spend",
    "session_id",
    "commit_sha",
    "ports",
    "pid",
    "created_at",
    "closed_at",
)

# Identity, not state. run_id is also the filename, so rewriting it would leave
# the record answering to a name that is not its own.
IMMUTABLE = ("run_id", "created_at")

# CLI values arrive as strings. Per-field coercion instead of "try JSON first",
# because a commit_sha of 5734129 is a string that happens to parse as a number.
# `spend` is what the key actually cost, read back from OpenRouter at teardown.
# It is what makes best-of-N comparable: same prompt, N models, cost beside result.
_COERCE = {"ports": "json", "pid": "int", "limit": "float", "spend": "float"}


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def path(run_id: str) -> Path:
    """Where this run's record lives. Does not create anything."""
    return RUNS_DIR / f"{run_id}.json"


def new_run_id(task: str) -> str:
    """A run id that has never existed before: <task>-<YYYYMMDD>-<6 hex>.

    Generated, never supplied by the caller. The run id becomes the VM name and
    the VM name becomes a public URL, so a collision is not a local annoyance --
    it is two runs fighting over one hostname. The task is slugified because
    that hostname has to survive DNS.
    """
    slug = re.sub(r"[^a-z0-9]+", "-", task.lower()).strip("-") or "run"
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d")
    return f"{slug}-{stamp}-{secrets.token_hex(3)}"


def create(run_id: str) -> dict:
    """Seed the record with run_id + created_at. Refuses to clobber."""
    record = {f: None for f in FIELDS}
    record["run_id"] = run_id
    record["created_at"] = _now()

    RUNS_DIR.mkdir(parents=True, exist_ok=True)
    target = path(run_id)
    # O_EXCL, not `if target.exists()`: overwriting a live record orphans that
    # run's key, and the check-then-write window is exactly when a retrying
    # phase would land.
    try:
        fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        raise FileExistsError(f"run record already exists: {target}") from None
    with os.fdopen(fd, "w") as fh:
        json.dump(record, fh, indent=2)
        fh.write("\n")
    return record


def get(run_id: str, field: str | None = None):
    """The whole record, or one field."""
    target = path(run_id)
    try:
        record = json.loads(target.read_text())
    except FileNotFoundError:
        raise FileNotFoundError(f"no run record: {target}") from None
    if field is None:
        return record
    if field not in FIELDS:
        raise ValueError(f"unknown field {field!r}; known: {', '.join(FIELDS)}")
    return record.get(field)


def set(run_id: str, **fields) -> dict:  # noqa: A001 - the verb the plan uses
    """Merge fields into the record. Unknown or immutable keys are rejected."""
    return _apply(run_id, fields)


def _apply(run_id: str, fields: dict) -> dict:
    """set() with the fields as a dict.

    The CLI cannot go through **fields: `set my-run run_id=x` would collide with
    the positional and die with a TypeError instead of the real complaint.
    """
    if not fields:
        raise ValueError("set requires at least one field")
    for key in fields:
        if key not in FIELDS:
            raise ValueError(f"unknown field {key!r}; known: {', '.join(FIELDS)}")
        if key in IMMUTABLE:
            raise ValueError(f"{key} is set once at create and cannot be changed")
    record = get(run_id)
    record.update(fields)
    _write(run_id, record)
    return record


def close(run_id: str) -> dict:
    """Mark the run torn down. Non-null closed_at means the key is revoked.

    Idempotent, and the first close wins: teardown is retryable and the moment
    that matters is when the key actually died.
    """
    record = get(run_id)
    if record.get("closed_at") is None:
        record["closed_at"] = _now()
        _write(run_id, record)
    return record


def list_runs() -> list[dict]:
    """Every record, newest first."""
    if not RUNS_DIR.is_dir():
        return []
    records = []
    for f in RUNS_DIR.glob("*.json"):
        try:
            records.append(json.loads(f.read_text()))
        except (OSError, ValueError) as e:
            # Loud, not skipped. `reap` walks this list to find keys nobody
            # revoked; a record quietly dropped for being malformed is a key
            # that quietly keeps spending.
            raise ValueError(f"unreadable run record {f}: {e}") from None
    records.sort(key=lambda r: (r.get("created_at") or "", r.get("run_id") or ""), reverse=True)
    return records


def _write(run_id: str, record: dict) -> None:
    target = path(run_id)
    tmp = target.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(record, indent=2) + "\n")
    os.replace(tmp, target)  # atomic: a crash mid-write leaves the old record, not half of one


def _coerce(key: str, raw: str):
    if raw == "null":
        return None
    kind = _COERCE.get(key)
    if kind == "int":
        return int(raw)
    if kind == "float":
        return float(raw)
    if kind == "json":
        return json.loads(raw)
    return raw


def _print(value) -> None:
    """Bare value for shell capture; JSON only for things shell cannot hold."""
    if value is None:
        print("")
    elif isinstance(value, (dict, list)):
        print(json.dumps(value))
    elif isinstance(value, bool):
        print("true" if value else "false")
    else:
        print(value)


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    cmd, args = argv[0], argv[1:]

    if cmd == "list":
        print(json.dumps(list_runs(), indent=2))
        return 0

    if cmd == "new-id":
        if len(args) != 1:
            print("usage: run_record.py new-id <task>", file=sys.stderr)
            return 2
        print(new_run_id(args[0]))
        return 0

    if not args:
        print(f"usage: run_record.py {cmd} <run-id>", file=sys.stderr)
        return 2
    run_id, rest = args[0], args[1:]

    if cmd == "path":
        print(path(run_id))
        return 0
    if cmd == "create":
        create(run_id)
        print(path(run_id))
        return 0
    if cmd == "get":
        if len(rest) > 1:
            print("usage: run_record.py get <run-id> [field]", file=sys.stderr)
            return 2
        if rest:
            _print(get(run_id, rest[0]))
        else:
            print(json.dumps(get(run_id), indent=2))
        return 0
    if cmd == "set":
        fields = {}
        for pair in rest:
            if "=" not in pair:
                print(f"expected key=value, got {pair!r}", file=sys.stderr)
                return 2
            key, raw = pair.split("=", 1)
            fields[key] = _coerce(key, raw)
        _apply(run_id, fields)
        return 0
    if cmd == "close":
        close(run_id)
        return 0

    print(f"unknown command {cmd!r}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, ValueError) as e:
        print(f"run_record: {e}", file=sys.stderr)
        sys.exit(1)
