"""
exedev vm — lifecycle commands (mirrors `sbx sandbox` group).

Maps to:
    vm list      -> ssh exe.dev ls --json
    vm info      -> ssh exe.dev ls --json | filter to one VM (+ stat)
    vm kill      -> ssh exe.dev rm <name>
    vm restart   -> ssh exe.dev restart <name>     [unique-to-exe.dev]
    vm rename    -> ssh exe.dev rename <old> <new> [unique-to-exe.dev]
    vm resize    -> ssh exe.dev resize <name> ...  [unique-to-exe.dev]
    vm tag       -> ssh exe.dev tag [-d] <name>... [unique-to-exe.dev]
    vm comment   -> ssh exe.dev comment <name> ... [unique-to-exe.dev]
    vm snapshot  -> ssh exe.dev cp <src> [name]    [unique-to-exe.dev]
    vm stat      -> ssh exe.dev stat <name>        [unique-to-exe.dev]

There is no pause / extend-lifetime here on purpose — exe.dev VMs are
persistent, no timeout, no expiry. The SKILL.md documents this gap
explicitly so users coming from /agent-sandboxes don't reach for them.
"""

import json as _json

import click
from rich.console import Console
from rich.table import Table

from ..modules.ssh_runner import ExeDevError, control_plane

console = Console()


@click.group()
def vm():
    """VM lifecycle: list, info, kill, restart, rename, resize, tag, snapshot, stat."""


@vm.command("list")
@click.option("--all", "-a", "include_team", is_flag=True, help="Include team VMs.")
@click.option("--json", "as_json", is_flag=True, help="Emit raw JSON instead of a table.")
@click.argument("pattern", required=False)
def vm_list(include_team: bool, as_json: bool, pattern: str | None):
    """List your VMs (mirrors `sbx sandbox list`)."""
    args = ["ls"]
    if include_team:
        args.append("-a")
    if pattern:
        args.append(pattern)
    payload = control_plane(*args)

    if as_json:
        click.echo(_json.dumps(payload, indent=2))
        return

    vms = payload.get("vms", [])
    if not vms:
        console.print("[dim]No VMs.[/dim]")
        return

    table = Table(title="exe.dev VMs")
    table.add_column("Name", style="cyan")
    table.add_column("Status")
    table.add_column("Region")
    table.add_column("HTTPS URL")
    table.add_column("SSH dest", style="dim")
    for v in vms:
        table.add_row(
            v.get("vm_name", "?"),
            v.get("status", "?"),
            v.get("region", "?"),
            v.get("https_url", ""),
            v.get("ssh_dest", ""),
        )
    console.print(table)


@vm.command("info")
@click.argument("name")
@click.option("--range", "stat_range", default=None, help="Optional metrics window: 24h | 7d | 30d.")
def vm_info(name: str, stat_range: str | None):
    """Show info for a single VM (mirrors `sbx sandbox info`).

    Composes `ssh exe.dev ls --json` (identity + URL + status) with
    `ssh exe.dev stat <name>` (CPU/mem/disk/IO metrics).
    """
    payload = control_plane("ls")
    matches = [v for v in payload.get("vms", []) if v.get("vm_name") == name]
    if not matches:
        raise click.ClickException(f"No VM named '{name}'.")
    info = matches[0]

    console.print(f"[cyan]Name:[/cyan]      {info.get('vm_name')}")
    console.print(f"[cyan]Status:[/cyan]    {info.get('status')}")
    console.print(f"[cyan]Region:[/cyan]    {info.get('region_display', info.get('region', ''))}")
    console.print(f"[cyan]HTTPS URL:[/cyan] {info.get('https_url')}")
    console.print(f"[cyan]SSH dest:[/cyan]  {info.get('ssh_dest')}")
    console.print(f"[dim]exe.dev VMs are persistent — no expiry, no auto-timeout.[/dim]")

    if stat_range:
        try:
            metrics = control_plane("stat", name, f"--range={stat_range}")
            console.print("\n[bold]Metrics[/bold]")
            console.print(_json.dumps(metrics, indent=2))
        except ExeDevError as e:
            console.print(f"[yellow]metrics unavailable: {e}[/yellow]")


@vm.command("stat")
@click.argument("name")
@click.option("--range", "stat_range", default="24h", help="24h | 7d | 30d (default 24h).")
def vm_stat(name: str, stat_range: str):
    """Show CPU/memory/disk/IO metrics for a VM (unique-to-exe.dev)."""
    payload = control_plane("stat", name, f"--range={stat_range}")
    click.echo(_json.dumps(payload, indent=2))


@vm.command("kill")
@click.argument("name")
def vm_kill(name: str):
    """Delete a VM (mirrors `sbx sandbox kill` — no confirmation prompt).

    \b
    DESTRUCTIVE. The persistent disk and all its contents are removed.
    There is no undo. If you might want the state later, snapshot first:

        exedev vm snapshot <name> <name>-archive
    """
    payload = control_plane("rm", name)
    console.print(f"[green]✓[/green] {payload}")


@vm.command("restart")
@click.argument("name")
def vm_restart(name: str):
    """Reboot a VM. Disk is preserved (unique-to-exe.dev)."""
    payload = control_plane("restart", name)
    console.print(f"[green]✓[/green] {payload}")


@vm.command("rename")
@click.argument("old")
@click.argument("new")
def vm_rename(old: str, new: str):
    """Rename a VM. Note: this changes the public URL <new>.exe.xyz."""
    payload = control_plane("rename", old, new)
    console.print(f"[green]✓[/green] renamed {old} → {new}")
    console.print(_json.dumps(payload, indent=2))


@vm.command("resize")
@click.argument("name")
@click.option("--cpu", type=int, default=None, help="New CPU count.")
@click.option("--memory", default=None, help="New memory (e.g. 4GB, 8G).")
@click.option("--disk", default=None, help="New total disk size (must be larger than current).")
def vm_resize(name: str, cpu: int | None, memory: str | None, disk: str | None):
    """Live-resize a VM's CPU/RAM/disk (unique-to-exe.dev)."""
    args = ["resize", name]
    if cpu is not None:
        args.append(f"--cpu={cpu}")
    if memory:
        args.append(f"--memory={memory}")
    if disk:
        args.append(f"--disk={disk}")
    if len(args) == 2:
        raise click.ClickException("specify at least one of --cpu / --memory / --disk")
    payload = control_plane(*args)
    console.print(f"[green]✓[/green] resized {name}")
    console.print(_json.dumps(payload, indent=2))


@vm.command("tag")
@click.argument("name")
@click.argument("tags", nargs=-1, required=True)
@click.option("-d", "delete", is_flag=True, help="Remove the listed tags instead of adding them.")
def vm_tag(name: str, tags: tuple[str, ...], delete: bool):
    """Add or remove tags on a VM (unique-to-exe.dev)."""
    args = ["tag"]
    if delete:
        args.append("-d")
    args.append(name)
    args.extend(tags)
    payload = control_plane(*args)
    console.print(f"[green]✓[/green] tags updated")
    console.print(_json.dumps(payload, indent=2))


@vm.command("comment")
@click.argument("name")
@click.argument("text")
def vm_comment(name: str, text: str):
    """Set a free-text comment on a VM (≤200 bytes, unique-to-exe.dev)."""
    payload = control_plane("comment", name, text)
    console.print(f"[green]✓[/green] comment set")
    console.print(_json.dumps(payload, indent=2))


@vm.command("snapshot")
@click.argument("source")
@click.argument("new_name", required=False)
@click.option("--cpu", type=int, default=None)
@click.option("--memory", default=None)
@click.option("--disk", default=None)
@click.option("--no-tags", is_flag=True, help="Do not copy tags from source.")
def vm_snapshot(source: str, new_name: str | None, cpu: int | None, memory: str | None, disk: str | None, no_tags: bool):
    """Clone an entire VM (disk + config) into a new VM. Unique-to-exe.dev — no E2B equivalent."""
    args = ["cp", source]
    if new_name:
        args.append(new_name)
    if cpu is not None:
        args.append(f"--cpu={cpu}")
    if memory:
        args.append(f"--memory={memory}")
    if disk:
        args.append(f"--disk={disk}")
    if no_tags:
        args.append("--copy-tags=false")
    payload = control_plane(*args)
    console.print(f"[green]✓[/green] cloned {source}" + (f" → {new_name}" if new_name else ""))
    console.print(_json.dumps(payload, indent=2))
