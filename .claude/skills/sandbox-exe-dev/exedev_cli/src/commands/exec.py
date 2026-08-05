"""
exedev exec — run a command on a VM (mirrors `sbx exec`).

Maps `sbx exec <id> "<cmd>"` flags one-for-one onto SSH idioms:

    --cwd PATH        prepended as `cd PATH && `
    --env KEY=VAL     prepended as `KEY=VAL `
    --root            wraps inner command with `sudo` (login user is `exedev`)
    --shell           wraps inner command with `bash -c "..."` (note: SSH runs
                      remote commands via the login shell by default, so shell
                      features often work without --shell; the flag is retained
                      for muscle-memory parity with sbx, not strict semantic
                      equivalence)
    --stdin           pipes stdin through SSH (native; works as advertised,
                      unlike `sbx exec --stdin` which is a known no-op upstream)
    --background      detaches with `nohup ... > /tmp/exedev-bg.log 2>&1 &`
                      and returns the remote PID
    --timeout S       kills the local SSH client after S seconds. Pass 0 or
                      omit for unbounded (translated to None internally).

There is no 30-second ceiling here. The 30s cap on exe.dev only applies to
`POST https://exe.dev/exec` (HTTPS API), not direct SSH — and we never use
the HTTPS API.
"""

import sys

import click
from rich.console import Console

from ..modules.ssh_runner import vm_exec

console = Console()


@click.command()
@click.argument("vm_name")
@click.argument("command", nargs=-1, required=True)
@click.option("--cwd", default=None, help="Run inside this directory on the VM.")
@click.option("--env", "-e", multiple=True, help="Environment KEY=VALUE (repeatable).")
@click.option("--root", is_flag=True, help="Run as root via sudo (login user is `exedev`).")
@click.option("--shell", is_flag=True, help="Wrap with `bash -c \"...\"`. Note: SSH already runs commands via the login shell by default, so this is for sbx parity, not strict equivalence.")
@click.option("--stdin", "stdin_flag", is_flag=True, help="Pipe local stdin through to the remote command.")
@click.option("--background", is_flag=True, help="Detach with nohup; returns remote PID.")
@click.option("--timeout", type=int, default=None, help="Seconds before killing the SSH client (default unbounded; pass 0 explicitly for unbounded too).")
def exec(vm_name, command, cwd, env, root, shell, stdin_flag, background, timeout):
    """
    Run a command on a VM via SSH.

    \b
    Examples:
      exedev exec my-vm "uname -a"
      exedev exec my-vm "ls -la" --cwd /home/exedev/project
      exedev exec my-vm "echo \\$FOO" --env FOO=bar --shell
      exedev exec my-vm "apt-get install -y htop" --root --timeout 120
      exedev exec my-vm "python -m http.server 5173" --background
      cat config.json | exedev exec my-vm "cat > /home/exedev/config.json" --stdin
    """
    cmd_str = " ".join(command)
    env_dict = {}
    for kv in env:
        if "=" not in kv:
            raise click.ClickException(f"--env expects KEY=VALUE, got: {kv}")
        k, v = kv.split("=", 1)
        env_dict[k] = v

    stdin_data = sys.stdin.read() if stdin_flag else None

    result = vm_exec(
        vm_name,
        cmd_str,
        cwd=cwd,
        env=env_dict or None,
        sudo=root,
        shell=shell,
        stdin=stdin_data,
        background=background,
        timeout=timeout,
    )

    if result.stdout:
        click.echo(result.stdout, nl=False)
    if result.stderr:
        click.echo(result.stderr, nl=False, err=True)

    if background and result.ok:
        console.print(f"[green]✓[/green] background command started (PID: {result.stdout.strip()})")
        console.print(f"[dim]Logs: ssh {vm_name}.exe.xyz 'tail -f /tmp/exedev-bg.log'[/dim]")

    sys.exit(result.returncode)
