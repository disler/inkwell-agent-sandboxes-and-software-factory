"""
SSH runner — the heart of every exedev command.

Two surfaces:

  * `control_plane(*verbs, json=True)` invokes `ssh exe.dev <verb>...` (the lobby).
    Returns parsed JSON when `json=True`, else raw stdout.

  * `vm_exec(vm, cmd, ...)` invokes `ssh <vm>.exe.xyz "<cmd>"` (the data plane).
    Returns CompletedProcess. Adds optional `cwd`, `env`, `sudo`, `shell`, `stdin`,
    `background`, `timeout` shaping so the wrapper feels like `sbx exec`.

  * `vm_scp(...)` thin wrapper over `scp` for binary-safe upload/download.

  * `vm_rsync(...)` recursive transfer with E2B-parity exclude defaults.

Design constraint: never shell out to anything other than `ssh`, `scp`, `rsync`.
We deliberately do *not* talk to https://exe.dev/exec — SSH is unbounded; HTTPS
caps at 30s and 64KB.
"""

from __future__ import annotations

import json as _json
import shlex
import subprocess
from dataclasses import dataclass
from typing import Iterable, Optional, Sequence

# Exclusion set used by E2B's files download-dir / upload-dir. We mirror the
# exact list so users get identical behaviour out of both skills.
DEFAULT_RSYNC_EXCLUDES: tuple[str, ...] = (
    ".venv", "venv", "__pycache__", ".pytest_cache", ".mypy_cache",
    ".ruff_cache", ".tox", ".uv", "node_modules", ".npm", ".bun",
    "dist", "build", ".next", ".nuxt", ".output", ".turbo",
    ".parcel-cache", ".svelte-kit", "coverage", ".nyc_output",
    ".git", ".cache",
)


class ExeDevError(RuntimeError):
    """Raised when an exe.dev command fails or returns an unexpected payload."""


@dataclass
class CmdResult:
    """Uniform return value for vm_exec / control_plane raw modes."""
    returncode: int
    stdout: str
    stderr: str

    @property
    def ok(self) -> bool:
        return self.returncode == 0


# ---------------------------------------------------------------------------
# Control plane — `ssh exe.dev <verb>...`
# ---------------------------------------------------------------------------

def control_plane(
    *verbs: str,
    json: bool = True,
    stdin: Optional[str] = None,
    timeout: int = 30,
):
    """Run `ssh exe.dev <verbs...> [--json]` and optionally parse JSON."""
    args = ["ssh", "exe.dev", *verbs]
    if json and "--json" not in verbs:
        args.append("--json")

    try:
        proc = subprocess.run(
            args,
            capture_output=True,
            text=True,
            input=stdin,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as e:
        raise ExeDevError(f"control-plane timeout after {timeout}s: {' '.join(args)}") from e

    if proc.returncode != 0:
        raise ExeDevError(
            f"`ssh exe.dev {' '.join(verbs)}` failed (exit {proc.returncode}):\n"
            f"stderr: {proc.stderr.strip()}"
        )

    if not json:
        return CmdResult(proc.returncode, proc.stdout, proc.stderr)

    try:
        return _json.loads(proc.stdout)
    except _json.JSONDecodeError as e:
        raise ExeDevError(
            f"could not parse JSON from `ssh exe.dev {' '.join(verbs)}`:\n"
            f"stdout: {proc.stdout[:500]}"
        ) from e


# ---------------------------------------------------------------------------
# Data plane — `ssh <vm>.exe.xyz "<cmd>"`
# ---------------------------------------------------------------------------

def vm_host(vm: str) -> str:
    """Bare hostname — login user 'exedev' is implied by SSH config."""
    return f"{vm}.exe.xyz"


def vm_exec(
    vm: str,
    cmd: str,
    *,
    cwd: Optional[str] = None,
    env: Optional[dict[str, str]] = None,
    sudo: bool = False,
    shell: bool = False,
    stdin: Optional[str] = None,
    background: bool = False,
    timeout: Optional[int] = None,
) -> CmdResult:
    """Run a command on a VM via SSH.

    Mapping to `sbx exec` flags:
        --cwd PATH        -> cwd=PATH         (we prepend `cd PATH && `)
        --env KEY=VALUE   -> env={'KEY':'VAL'} (we prepend `KEY=VAL ` per pair)
        --root            -> sudo=True        (login user is `exedev`, not root)
        --shell           -> shell=True       (we wrap in `bash -c "..."`)
        --stdin           -> stdin=str        (native SSH passthrough)
        --background      -> background=True  (we wrap in `nohup ... > /tmp/exedev-bg-<n>.log 2>&1 &`)
        --timeout S       -> timeout=S        (Python-side, kills the SSH client)

    For long-running servers, prefer `background=True` plus `timeout=None`
    (SSH returns immediately once the remote process is detached).
    """
    # Compose the remote command.
    remote_parts: list[str] = []
    if cwd:
        remote_parts.append(f"cd {shlex.quote(cwd)} &&")
    if env:
        remote_parts.extend(f"{k}={shlex.quote(v)}" for k, v in env.items())

    # When env vars combine with sudo, default sudoers strip the environment.
    # Use `sudo env K=V cmd` to forward them. We rebuild remote_parts so the
    # final order is `[cd PATH &&] sudo env K=V <cmd>` rather than `K=V sudo`,
    # which loses the vars under most sudo policies.
    sudo_env_prefix = ""
    if sudo and env:
        env_kvs = remote_parts[1:] if cwd else remote_parts[:]
        remote_parts = remote_parts[:1] if cwd else []
        sudo_env_prefix = "sudo env " + " ".join(env_kvs) + " "

    if shell:
        # Force bash -c so pipes/globs/redirection are honoured even if the
        # user's default shell is dash-y. NOTE: SSH executes remote commands via
        # the user's login shell by default, so shell features often Just Work
        # without --shell; this flag is retained for muscle-memory parity with
        # sbx, not for strict semantic equivalence.
        wrapped = f"bash -c {shlex.quote(cmd)}"
        if sudo_env_prefix:
            inner = sudo_env_prefix + wrapped
        elif sudo:
            inner = f"sudo {wrapped}"
        else:
            inner = wrapped
    else:
        if sudo_env_prefix:
            inner = sudo_env_prefix + cmd
        elif sudo:
            inner = f"sudo {cmd}"
        else:
            inner = cmd

    if background:
        # Detach the remote process so SSH returns immediately.
        #
        # Three things are required to actually return:
        #   1. nohup           — survive the SSH session ending.
        #   2. > log 2>&1      — close stdout / stderr from the parent shell.
        #   3. < /dev/null     — close stdin (without this, SSH waits for EOF).
        # And we wrap the whole thing in `( ... & )` so the parent shell forks
        # before backgrounding, guaranteeing it returns even if the user's
        # remote login shell is picky about job control.
        #
        # Without these, `exedev exec --background "python -m http.server ..."`
        # hangs the local terminal: the server runs, but SSH never closes.
        log_path = "/tmp/exedev-bg.log"
        inner = f"( nohup {inner} > {log_path} 2>&1 < /dev/null & echo $! )"

    remote_parts.append(inner)
    remote_cmd = " ".join(remote_parts)

    args = ["ssh", vm_host(vm), remote_cmd]

    # Mirror sbx exec: --timeout 0 means "unbounded" (Python's subprocess uses
    # None for no-timeout, so translate before passing through).
    effective_timeout = None if (timeout is None or timeout == 0) else timeout

    try:
        proc = subprocess.run(
            args,
            capture_output=True,
            text=True,
            input=stdin,
            timeout=effective_timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as e:
        return CmdResult(124, e.stdout or "", (e.stderr or "") + f"\n[timeout after {effective_timeout}s]")

    return CmdResult(proc.returncode, proc.stdout, proc.stderr)


# ---------------------------------------------------------------------------
# File transfer — scp + rsync
# ---------------------------------------------------------------------------

def vm_scp(local: str, remote: str, vm: str, *, push: bool, recursive: bool = False) -> CmdResult:
    """Upload (push=True) or download (push=False) a single file via scp."""
    args = ["scp"]
    if recursive:
        args.append("-r")
    if push:
        args.extend([local, f"{vm_host(vm)}:{remote}"])
    else:
        args.extend([f"{vm_host(vm)}:{remote}", local])
    proc = subprocess.run(args, capture_output=True, text=True, check=False)
    return CmdResult(proc.returncode, proc.stdout, proc.stderr)


def vm_rsync(
    local: str,
    remote: str,
    vm: str,
    *,
    push: bool,
    excludes: Sequence[str] = DEFAULT_RSYNC_EXCLUDES,
    extra_args: Iterable[str] = (),
) -> CmdResult:
    """Recursive transfer via rsync over SSH, with E2B-parity excludes by default.

    Note: we deliberately do **not** pass --delete-excluded. E2B's upload-dir /
    download-dir simply skip excluded paths; they don't delete excluded paths
    that already exist on the destination. Matching that behaviour avoids data
    loss surprises.
    """
    args = ["rsync", "-avz", *extra_args]
    for ex in excludes:
        args.extend(["--exclude", ex])
    src = f"{local.rstrip('/')}/" if push else f"{vm_host(vm)}:{remote.rstrip('/')}/"
    dst = f"{vm_host(vm)}:{remote.rstrip('/')}/" if push else f"{local.rstrip('/')}/"
    args.extend([src, dst])
    proc = subprocess.run(args, capture_output=True, text=True, check=False)
    return CmdResult(proc.returncode, proc.stdout, proc.stderr)
