"""
exedev share — port exposure & access control (mostly unique-to-exe.dev).

This group has no clean E2B equivalent. E2B URLs are publicly reachable
by default (`get-host` returns a URL anyone can hit); exe.dev URLs are
**private-by-default** behind an exe.dev login proxy. To match the E2B
"anyone with the URL can hit it" behaviour, run:

    exedev share set-public <vm>

We also expose `share get-host` for ergonomic parity with `sbx sandbox get-host`.
The exe.dev URL is **deterministic** — it's always:

    https://<vm>.exe.xyz/         (primary port, set with `share port <vm> <p>`)
    https://<vm>.exe.xyz:<p>/     (any auth-only alt port in 3000-9999)

…so `get-host` doesn't actually call out; it composes the URL locally.
"""

from __future__ import annotations

import json as _json

import click
from rich.console import Console

from ..modules.ssh_runner import control_plane

console = Console()


@click.group()
def share():
    """HTTPS proxy port + access-control management (unique-to-exe.dev)."""


@share.command("get-host")
@click.argument("vm_name")
@click.option("--port", "-p", type=int, default=None,
              help="Port on the VM (3000-9999 are auto-proxied; omit for the primary URL).")
def share_get_host(vm_name, port):
    """
    Print the public HTTPS URL for a VM (mirrors `sbx sandbox get-host`).

    The URL is deterministic and always exists — even if nothing is listening
    on the port yet. **Reachability** depends on `share set-public` (anonymous)
    or `share add` (per-user) or login at exe.dev (default).
    """
    if port is None or port == 80 or port == 443:
        url = f"https://{vm_name}.exe.xyz/"
    else:
        if not (3000 <= port <= 9999):
            console.print(f"[yellow]! exe.dev only proxies ports 3000-9999 as :PORT URLs (got {port}).[/yellow]")
            console.print(f"[yellow]  To reach this port, set it as the primary with `exedev share port {vm_name} {port}` first.[/yellow]")
        url = f"https://{vm_name}.exe.xyz:{port}/"

    console.print(url)
    console.print(f"[dim]Visibility: run `exedev share show {vm_name}` to inspect; `share set-public` to anonymise.[/dim]")


@share.command("show")
@click.argument("vm_name")
def share_show(vm_name):
    """Show current shares + visibility for a VM."""
    payload = control_plane("share", "show", vm_name)
    click.echo(_json.dumps(payload, indent=2))


@share.command("port")
@click.argument("vm_name")
@click.argument("port", type=int)
def share_port(vm_name, port):
    """Set which VM port the primary HTTPS proxy forwards to."""
    payload = control_plane("share", "port", vm_name, str(port))
    console.print(f"[green]✓[/green] primary proxy port → {port}")
    console.print(_json.dumps(payload, indent=2))


@share.command("set-public")
@click.argument("vm_name")
def share_set_public(vm_name):
    """
    Make the primary URL anonymously accessible.

    This is the closest analog to E2B's default "anyone with the URL can hit it"
    behaviour. Only the **primary** port can be public; alternate ports
    (`https://<vm>.exe.xyz:<p>/`) remain auth-gated.
    """
    payload = control_plane("share", "set-public", vm_name)
    console.print(f"[green]✓[/green] {vm_name} is now public")
    console.print(_json.dumps(payload, indent=2))


@share.command("set-private")
@click.argument("vm_name")
def share_set_private(vm_name):
    """Re-gate the primary URL behind exe.dev login."""
    payload = control_plane("share", "set-private", vm_name)
    console.print(f"[green]✓[/green] {vm_name} is now private")
    console.print(_json.dumps(payload, indent=2))


@share.command("add")
@click.argument("vm_name")
@click.argument("email_or_team")
@click.option("--message", default=None, help="Optional invite message.")
def share_add(vm_name, email_or_team, message):
    """Grant a specific user (or team) access to the VM's HTTPS proxy."""
    args = ["share", "add", vm_name, email_or_team]
    if message:
        args.append(f"--message={message}")
    payload = control_plane(*args)
    console.print(f"[green]✓[/green] shared {vm_name} with {email_or_team}")
    console.print(_json.dumps(payload, indent=2))


@share.command("remove")
@click.argument("vm_name")
@click.argument("email_or_team")
def share_remove(vm_name, email_or_team):
    """Revoke a previously-granted user/team."""
    payload = control_plane("share", "remove", vm_name, email_or_team)
    console.print(f"[green]✓[/green] revoked {email_or_team} from {vm_name}")
    console.print(_json.dumps(payload, indent=2))


@share.command("add-link")
@click.argument("vm_name")
def share_add_link(vm_name):
    """Issue a tokenized share-link (anyone with the link → register/login → access)."""
    payload = control_plane("share", "add-link", vm_name)
    click.echo(_json.dumps(payload, indent=2))


@share.command("remove-link")
@click.argument("vm_name")
@click.argument("token")
def share_remove_link(vm_name, token):
    """Revoke a previously-issued share-link."""
    payload = control_plane("share", "remove-link", vm_name, token)
    console.print(f"[green]✓[/green] removed link")
    console.print(_json.dumps(payload, indent=2))
