"""
exedev files — file operations on a VM (mirrors `sbx files` group).

Implementation note: there is **no** exe.dev "files API". All ops decompose
to vanilla SSH/SCP/RSYNC idioms (per `ai_docs/exedev/faq-copy-files.md`).
That makes this group a thin, transparent wrapper — the ergonomics match
`sbx files` so /agent-sandboxes users feel at home.

Mappings:

    files ls           -> ssh <vm>.exe.xyz 'ls -la <path>'
    files read         -> ssh <vm>.exe.xyz 'cat <path>'
    files write        -> echo|stdin -> ssh <vm>.exe.xyz 'cat > <path>'
    files edit         -> Python on the VM (literal-string read+replace+write
                          for E2B parity; sed would be regex by default)
    files upload       -> scp local <vm>:<remote>
    files download     -> scp <vm>:<remote> local
    files upload-dir   -> rsync -avz --exclude=... local/ <vm>:<remote>/
    files download-dir -> rsync -avz --exclude=... <vm>:<remote>/ local/
    files exists       -> ssh <vm>.exe.xyz 'test -e <path> && echo yes || echo no'
    files info         -> ssh <vm>.exe.xyz 'stat <path>'
    files mkdir        -> ssh <vm>.exe.xyz 'mkdir -p <path>'
    files mv           -> ssh <vm>.exe.xyz 'mv <old> <new>'
    files rm           -> ssh <vm>.exe.xyz 'rm <path>' (file-only by default;
                          --recursive enables `rm -rf` to match E2B behaviour)
"""

from __future__ import annotations

import shlex
import sys

import click
from rich.console import Console

from ..modules.ssh_runner import (
    DEFAULT_RSYNC_EXCLUDES,
    vm_exec,
    vm_rsync,
    vm_scp,
)

console = Console()


def _check(result, label: str):
    if not result.ok:
        if result.stderr:
            click.echo(result.stderr, err=True, nl=False)
        raise click.ClickException(f"{label} failed (exit {result.returncode})")


@click.group()
def files():
    """File operations on a VM (transparent SSH/SCP/RSYNC wrappers)."""


@files.command("ls")
@click.argument("vm_name")
@click.argument("path", default="/home/exedev")
@click.option("--depth", "-d", type=int, default=1, help="Traversal depth.")
def files_ls(vm_name, path, depth):
    """List files (uses `find -maxdepth` for depth, `ls -la` for depth=1)."""
    if depth <= 1:
        cmd = f"ls -la {shlex.quote(path)}"
    else:
        cmd = f"find {shlex.quote(path)} -maxdepth {depth} -printf '%M %s %p\\n'"
    result = vm_exec(vm_name, cmd)
    if result.stdout:
        click.echo(result.stdout, nl=False)
    if not result.ok and result.stderr:
        click.echo(result.stderr, err=True, nl=False)
    sys.exit(result.returncode)


@files.command("read")
@click.argument("vm_name")
@click.argument("path")
def files_read(vm_name, path):
    """Read a text file from the VM."""
    result = vm_exec(vm_name, f"cat {shlex.quote(path)}")
    if result.stdout:
        click.echo(result.stdout, nl=False)
    if not result.ok and result.stderr:
        click.echo(result.stderr, err=True, nl=False)
    sys.exit(result.returncode)


@files.command("write")
@click.argument("vm_name")
@click.argument("path")
@click.argument("content", required=False)
@click.option("--stdin", "from_stdin", is_flag=True,
              help="Read full file contents from stdin (recommended for complex content).")
def files_write(vm_name, path, content, from_stdin):
    """Write a text file. Use --stdin for content with brackets/quotes/globs."""
    if from_stdin:
        body = sys.stdin.read()
    elif content is not None:
        body = content
    else:
        raise click.ClickException("provide CONTENT or use --stdin")

    # `cat > path` is binary-safe for text and avoids shell-mangling the body.
    result = vm_exec(vm_name, f"cat > {shlex.quote(path)}", stdin=body)
    _check(result, "write")
    console.print(f"[green]✓[/green] wrote {len(body)} bytes to {vm_name}:{path}")


@files.command("edit")
@click.argument("vm_name")
@click.argument("path")
@click.option("--old", required=True, help="Literal string to find.")
@click.option("--new", required=True, help="Literal replacement string.")
@click.option("--all", "replace_all", is_flag=True, help="Replace every occurrence (default: first only).")
def files_edit(vm_name, path, old, new, replace_all):
    """Literal-string find/replace inside a file (matches E2B's `files edit` semantics)."""
    # We embed a tiny Python program on the VM rather than `sed` so that
    # behaviour matches E2B exactly — literal strings, no regex.
    py = (
        "import sys, pathlib\n"
        "p = pathlib.Path(sys.argv[1])\n"
        "text = p.read_text()\n"
        "old, new = sys.argv[2], sys.argv[3]\n"
        "all_flag = sys.argv[4] == '1'\n"
        "if old not in text:\n"
        "    sys.exit('String not found in file: ' + old)\n"
        "n = text.count(old) if all_flag else 1\n"
        "p.write_text(text.replace(old, new, -1 if all_flag else 1))\n"
        "print(f'replaced {n} occurrence(s)')\n"
    )
    cmd = (
        f"python3 -c {shlex.quote(py)} {shlex.quote(path)} "
        f"{shlex.quote(old)} {shlex.quote(new)} {'1' if replace_all else '0'}"
    )
    result = vm_exec(vm_name, cmd)
    if result.stdout:
        click.echo(result.stdout, nl=False)
    _check(result, "edit")


@files.command("upload")
@click.argument("vm_name")
@click.argument("local_path")
@click.argument("remote_path")
def files_upload(vm_name, local_path, remote_path):
    """Upload a single file (binary-safe via scp)."""
    result = vm_scp(local_path, remote_path, vm_name, push=True)
    _check(result, "upload")
    console.print(f"[green]✓[/green] uploaded {local_path} → {vm_name}:{remote_path}")


@files.command("download")
@click.argument("vm_name")
@click.argument("remote_path")
@click.argument("local_path")
def files_download(vm_name, remote_path, local_path):
    """Download a single file (binary-safe via scp)."""
    result = vm_scp(local_path, remote_path, vm_name, push=False)
    _check(result, "download")
    console.print(f"[green]✓[/green] downloaded {vm_name}:{remote_path} → {local_path}")


@files.command("upload-dir")
@click.argument("vm_name")
@click.argument("local_path")
@click.argument("remote_path")
@click.option("--exclude", "-e", multiple=True, help="Additional rsync exclude patterns.")
@click.option("--all", "include_all", is_flag=True, help="No exclusions (override defaults).")
def files_upload_dir(vm_name, local_path, remote_path, exclude, include_all):
    """Recursively upload a directory (rsync; default excludes match `sbx files upload-dir`)."""
    excludes = () if include_all else tuple(DEFAULT_RSYNC_EXCLUDES) + tuple(exclude)
    result = vm_rsync(local_path, remote_path, vm_name, push=True, excludes=excludes)
    if result.stdout:
        click.echo(result.stdout)
    _check(result, "upload-dir")


@files.command("download-dir")
@click.argument("vm_name")
@click.argument("remote_path")
@click.argument("local_path")
@click.option("--exclude", "-e", multiple=True, help="Additional rsync exclude patterns.")
@click.option("--all", "include_all", is_flag=True, help="No exclusions (override defaults).")
def files_download_dir(vm_name, remote_path, local_path, exclude, include_all):
    """Recursively download a directory."""
    excludes = () if include_all else tuple(DEFAULT_RSYNC_EXCLUDES) + tuple(exclude)
    result = vm_rsync(local_path, remote_path, vm_name, push=False, excludes=excludes)
    if result.stdout:
        click.echo(result.stdout)
    _check(result, "download-dir")


@files.command("exists")
@click.argument("vm_name")
@click.argument("path")
def files_exists(vm_name, path):
    """Test whether a file or directory exists on the VM."""
    result = vm_exec(vm_name, f"test -e {shlex.quote(path)} && echo yes || echo no")
    out = result.stdout.strip()
    if out == "yes":
        console.print(f"[green]✓[/green] {path} exists")
        sys.exit(0)
    console.print(f"[red]✗[/red] {path} does not exist")
    sys.exit(1)


@files.command("info")
@click.argument("vm_name")
@click.argument("path")
def files_info(vm_name, path):
    """Show POSIX metadata for a path."""
    result = vm_exec(vm_name, f"stat {shlex.quote(path)}")
    if result.stdout:
        click.echo(result.stdout, nl=False)
    sys.exit(result.returncode)


@files.command("mkdir")
@click.argument("vm_name")
@click.argument("path")
def files_mkdir(vm_name, path):
    """Create a directory (mkdir -p)."""
    result = vm_exec(vm_name, f"mkdir -p {shlex.quote(path)}")
    _check(result, "mkdir")
    console.print(f"[green]✓[/green] mkdir {path}")


@files.command("mv")
@click.argument("vm_name")
@click.argument("old_path")
@click.argument("new_path")
def files_mv(vm_name, old_path, new_path):
    """Rename / move a file or directory."""
    result = vm_exec(vm_name, f"mv {shlex.quote(old_path)} {shlex.quote(new_path)}")
    _check(result, "mv")
    console.print(f"[green]✓[/green] {old_path} → {new_path}")


@files.command("rm")
@click.argument("vm_name")
@click.argument("path")
@click.option("-r", "--recursive", is_flag=True, help="Recursive delete (use this to match E2B's `files rm`).")
def files_rm(vm_name, path, recursive):
    """Remove a file (file-only by default — safer than E2B). Pass -r for recursive."""
    flag = "-rf" if recursive else ""
    result = vm_exec(vm_name, f"rm {flag} {shlex.quote(path)}")
    _check(result, "rm")
    console.print(f"[green]✓[/green] removed {path}")
