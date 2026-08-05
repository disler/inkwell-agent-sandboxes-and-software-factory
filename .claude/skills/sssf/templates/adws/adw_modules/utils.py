"""Small shared helpers. Anything bigger belongs in its own module."""

from __future__ import annotations

import os
import secrets
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()


def operator_env() -> dict[str, str]:
    """The engineer's own environment, as their shell would hand it over.

    Agents and quality blocks are meant to see exactly what the operator sees:
    their PATH, their toolchains, their globally installed packages. Copying
    os.environ gets almost all the way there — but ADWs launch under `uv run`,
    which prepends its ephemeral venv's bin to PATH and sets VIRTUAL_ENV. That
    venv holds the ADW's OWN dependencies (pydantic, pyyaml), not the
    operator's, so anything a subprocess resolves through it — `python3`,
    `pip`, every globally pip-installed CLI — silently becomes the wrong one.

    Stripping the venv restores parity: `python3` in an agent's bash is the
    same `python3` the engineer gets in their terminal. The ADW's own imports
    are unaffected; this env is only ever handed to child processes.
    """
    env = os.environ.copy()
    venv = env.pop("VIRTUAL_ENV", "")
    if not venv:
        return env
    venv_bin = str(Path(venv) / "bin")
    parts = [p for p in env.get("PATH", "").split(os.pathsep) if p and p != venv_bin]
    env["PATH"] = os.pathsep.join(parts)
    return env


def new_id(length: int = 8) -> str:
    return secrets.token_hex(length // 2)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


def ensure_dir(path: str | Path) -> Path:
    p = Path(path)
    p.mkdir(parents=True, exist_ok=True)
    return p


def resolve_prompt(arg: str) -> str:
    """CLI prompt arg: a file path resolves to its contents, else inline text."""
    try:
        p = Path(arg)
        if p.is_file():
            return p.read_text()
    except OSError:
        pass
    return arg


def engineer_name() -> str:
    name = os.environ.get("ENGINEER_NAME", "").strip()
    if name:
        return name
    try:
        out = subprocess.run(["git", "config", "user.name"],
                             capture_output=True, text=True, timeout=5)
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except OSError:
        pass
    return os.environ.get("USER", "engineer")
