"""
exe.dev CLI — exedev <verb> ...

Mirrors the structure of the E2B `sbx` CLI from /agent-sandboxes so users
who already know that skill feel immediately at home. Differences from
`sbx` are documented in the SKILL.md mapping table — TL;DR:

    sbx init                    -> exedev init
    sbx exec <id>               -> exedev exec <vm-name>
    sbx files <verb>            -> exedev files <verb>
    sbx sandbox <verb>          -> exedev vm <verb>
    sbx sandbox get-host        -> exedev share get-host
    sbx sandbox kill            -> exedev vm kill
    sbx sandbox extend-lifetime -> N/A (exe.dev VMs don't expire)
    sbx browser <verb>          -> exedev browser <verb>   (verbatim copy)

Smoke-test before doing real work:  `exedev doctor`
"""

import json as _json
import sys

import click
from rich.console import Console

from .commands.browser import browser
from .commands.exec import exec as exec_cmd
from .commands.files import files
from .commands.share import share
from .commands.vm import vm
from .modules.ssh_runner import ExeDevError, control_plane

console = Console()


@click.group()
@click.version_option(version="0.1.0")
def cli():
    """
    exe.dev CLI — control persistent VMs from the command line.

    \b
    Quick start:
      exedev doctor                          # smoke-test SSH + account
      exedev init --name myvm                # create a VM
      exedev exec myvm "uname -a"            # run a command
      exedev files write myvm /home/exedev/x.txt "hi"
      exedev share set-public myvm           # make https://myvm.exe.xyz/ anonymous

    \b
    Multi-agent safe:
      VM names are user-chosen — pick names that are unique to your workflow
      (`<workflow_id>-<short-uuid>`). Capture the name in your context, not
      in shell variables. Many agents can operate concurrently, each with
      its own VM.
    """


# ---------------------------------------------------------------------------
# init / doctor / whoami — top-level helpers
# ---------------------------------------------------------------------------

@cli.command()
@click.option("--name", "-n", required=True, help="VM name (will become https://<name>.exe.xyz/).")
@click.option("--image", default=None, help="Container image (default: exeuntu).")
@click.option("--cpu", type=int, default=None, help="Number of CPUs (default: 2).")
@click.option("--memory", default=None, help="Memory, e.g. 4GB.")
@click.option("--disk", default=None, help="Disk size, e.g. 20GB.")
@click.option("--env", "-e", multiple=True, help="KEY=VALUE env var (repeatable).")
@click.option("--tag", "-t", multiple=True, help="Tag (repeatable).")
@click.option("--setup-script", default=None, help="Path to a local setup script (≤10KiB).")
@click.option("--no-shelley", is_flag=True, help="Disable the built-in Shelley agent on first boot.")
def init(name, image, cpu, memory, disk, env, tag, setup_script, no_shelley):
    """
    Create a new VM (mirrors `sbx init`).

    \b
    Differences from sbx init:
      * --name is required (it becomes the public URL; no auto-generated IDs).
      * --image takes any container image; no curated template registry.
      * No --timeout — exe.dev VMs are persistent.
      * --cpu / --memory / --disk are sized at create time (vs. baked into E2B templates).

    \b
    Examples:
      exedev init --name myvm
      exedev init --name api-test --image ubuntu:22.04 --cpu 4 --memory 8GB
      exedev init --name builder --tag ci --tag prod --env GITHUB_TOKEN=ghp_xxx
    """
    args = ["new", f"--name={name}"]
    if image:
        args.append(f"--image={image}")
    if cpu is not None:
        args.append(f"--cpu={cpu}")
    if memory:
        args.append(f"--memory={memory}")
    if disk:
        args.append(f"--disk={disk}")
    for kv in env:
        args.append(f"--env={kv}")
    for t in tag:
        args.append(f"--tag={t}")

    setup_stdin = None
    if setup_script:
        with open(setup_script, "r") as f:
            setup_stdin = f.read()
        args.append("--setup-script=/dev/stdin")

    try:
        payload = control_plane(*args, stdin=setup_stdin, timeout=120)
    except ExeDevError as e:
        raise click.ClickException(str(e))

    console.print(f"[green]✓[/green] VM created")
    console.print(f"[cyan]Name:[/cyan]      {name}")
    console.print(f"[cyan]SSH dest:[/cyan]  {name}.exe.xyz")
    console.print(f"[cyan]HTTPS URL:[/cyan] https://{name}.exe.xyz/  [dim](private by default)[/dim]")
    console.print(f"[dim]Run `exedev share set-public {name}` to make the URL anonymously accessible.[/dim]")
    console.print()
    console.print(_json.dumps(payload, indent=2))

    if no_shelley:
        # Best-effort. Boot can take a couple of seconds; we attempt and
        # surface failure as a warning, not an error.
        from .modules.ssh_runner import vm_exec
        result = vm_exec(name, "sudo systemctl disable --now shelley.service", sudo=False, timeout=30)
        if result.ok:
            console.print(f"[dim]✓ disabled built-in Shelley agent[/dim]")
        else:
            console.print(f"[yellow]! could not disable Shelley yet (VM may still be booting); retry later[/yellow]")


@cli.command()
def whoami():
    """Show your exe.dev account and registered SSH keys."""
    try:
        payload = control_plane("whoami")
        click.echo(_json.dumps(payload, indent=2))
    except ExeDevError as e:
        raise click.ClickException(str(e))


@cli.command()
def doctor():
    """
    Smoke-test the local exe.dev setup.

    Checks (in order):
      1. `ssh exe.dev whoami` returns identity.
      2. `ssh exe.dev ls --json` returns a parseable VM list.
      3. SSH key fingerprints look healthy.

    Use this before running any heavier exedev command. If any step fails,
    see the SKILL.md "Troubleshooting" section.
    """
    ok = True

    console.print("[bold]1. control-plane: ssh exe.dev whoami[/bold]")
    try:
        me = control_plane("whoami")
        email = me.get("email") or me.get("Email") or "?"
        keys = me.get("ssh_keys") or me.get("SSH Keys") or []
        console.print(f"   [green]✓[/green] authenticated as {email}")
        if keys:
            console.print(f"   [dim]{len(keys)} SSH key(s) registered[/dim]")
    except ExeDevError as e:
        console.print(f"   [red]✗[/red] {e}")
        ok = False

    console.print("[bold]2. control-plane: ssh exe.dev ls --json[/bold]")
    try:
        ls = control_plane("ls")
        n = len(ls.get("vms", []))
        console.print(f"   [green]✓[/green] {n} VM(s) visible")
    except ExeDevError as e:
        console.print(f"   [red]✗[/red] {e}")
        ok = False

    console.print("[bold]3. host-key fingerprint reminder[/bold]")
    console.print("   [dim]first connection should display fingerprint:[/dim]")
    console.print("   [dim]SHA256:JJOP/lwiBGOMilfONPWZCXUrfK154cnJFXcqlsi6lPo (source: ai_docs/exedev/faq-host-key.md)[/dim]")

    if not ok:
        console.print("\n[red]doctor: FAILED[/red] — see SKILL.md Troubleshooting.")
        sys.exit(1)
    console.print("\n[green]doctor: OK[/green]")


# ---------------------------------------------------------------------------
# Wire up groups
# ---------------------------------------------------------------------------

cli.add_command(vm)
cli.add_command(files)
cli.add_command(share)
cli.add_command(exec_cmd, name="exec")
cli.add_command(browser)


if __name__ == "__main__":
    cli()
