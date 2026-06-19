#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.14"
# dependencies = ["rich>=13", "click>=8"]
# ///
"""issue-end — triage and clean up finished issue worktrees, fast.

A scriptable replacement for most of the /issue-end command. A worktree is
**finished** only when all three hold: its GitHub PR is MERGED, its Linear issue
is Done (state type == completed), and the tree is clean.

Two subcommands (default is `status`):

  issue-end.py                 status of every issue worktree of the current repo
  issue-end.py status [IDS..]  same, optionally limited to given issue IDs
  issue-end.py clean  [IDS..]  interactively remove FINISHED worktrees
  issue-end.py clean --clean-worktree SEL..  remove the named worktrees, gate bypassed

`status` is always read-only. `clean` lists each finished worktree's artifacts,
asks y/n per worktree (unless -y), then calls issue-end-cleanup.sh. With
--clean-worktree the finished gate is skipped and the args name worktrees directly
(by issue id, branch, or path) — the escape hatch for scratch trees with no PR or
Linear issue.

Worktrees are discovered with `git worktree list`, and every worktree's PR is
resolved from a single bulk `gh pr list --state all` call matched by head branch
(one network round-trip for the whole repo, always live — no cache). The Linear
"Done" gate is checked directly against Linear's GraphQL API using a personal
API key in $LINEAR_API_KEY (create one at https://linear.app/settings/api).
Without the key, the Linear column shows "no key" and nothing is ever treated as
finished — `clean` refuses to remove anything it cannot confirm is Done.

Requires: gh (authenticated), uv. Optional: $LINEAR_API_KEY for the Linear gate.
"""

# rich/click are supplied at runtime via the uv inline-dependency block above; a
# repo-level type checker won't see that ephemeral env. The reportFunctionMember
# /reportCallIssue suppressions cover click's decorator magic (group().command,
# callback args injected at call time), which Pyright can't model statically.
# pyright: reportMissingImports=false, reportFunctionMemberAccess=false, reportCallIssue=false
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import NamedTuple

import click
from rich.console import Console
from rich.progress import (
    BarColumn,
    MofNCompleteColumn,
    Progress,
    SpinnerColumn,
    TextColumn,
    TimeElapsedColumn,
)
from rich.table import Table
from rich.text import Text

SCRIPTS = Path.home() / ".claude" / "scripts"
CLEANUP = SCRIPTS / "issue-end-cleanup.sh"

PR_FETCH_LIMIT = 500  # most-recent PRs scanned; worktree PRs are recent, so this is ample
STATE_RANK = {"MERGED": 3, "OPEN": 2, "CLOSED": 1}  # prefer a merged PR when a head has several

LINEAR_URL = "https://api.linear.app/graphql"
ID_RE = re.compile(r"^([A-Za-z]+)-([0-9]+)$")

console = Console()
err = Console(stderr=True)


class Row(NamedTuple):
    worktree: str
    branch: str
    issue_id: str
    dirty: str  # "clean" | "dirty"
    pr_number: str
    pr_state: str  # MERGED | OPEN | CLOSED | NO_PR
    pr_url: str


class LinearState(NamedTuple):
    type: str  # completed | started | unstarted | backlog | triage | canceled
    name: str  # human label, e.g. "Done"


# --- discovery: native git worktree walk + one bulk PR fetch ------------------


def gh(args: list[str], cwd: str) -> list[dict]:
    """Run a `gh` command expected to emit a JSON array and return it."""
    try:
        res = subprocess.run(
            ["gh", *args], capture_output=True, text=True, cwd=cwd, check=True
        )
    except FileNotFoundError:
        err.print("[red]gh not installed[/]")
        sys.exit(1)
    except subprocess.CalledProcessError as exc:
        err.print(f"[red]gh {' '.join(args)} failed:[/]\n{exc.stderr.strip()}")
        sys.exit(1)
    return json.loads(res.stdout) if res.stdout.strip() else []


def git(args: list[str], cwd: str) -> str:
    return subprocess.run(
        ["git", "-C", cwd, *args], capture_output=True, text=True
    ).stdout


def issue_id_of(branch: str, path: str) -> str:
    """Derive an ENG-1234-style id from the branch, falling back to the dir name."""
    for source in (branch, os.path.basename(path)):
        m = re.search(r"[A-Za-z]+-[0-9]+", source)
        if m:
            return m.group(0).upper()
    return "UNKNOWN"


def discover(start: str) -> tuple[str, list[tuple[str, str]]]:
    """Return (main_repo_path, [(worktree_path, branch), ...]) excluding the main repo.

    Branch is "DETACHED" for a detached-HEAD worktree. Mirrors issue-end-scan.sh:
    the first listed worktree is the main repo and is not reported.
    """
    out = git(["worktree", "list", "--porcelain"], start)
    blocks: list[tuple[str, str]] = []  # (path, branch) in listing order
    path: str | None = None
    branch: str | None = None
    for line in out.splitlines():
        if line.startswith("worktree "):
            if path is not None:
                blocks.append((path, branch or "DETACHED"))
            path = line[len("worktree "):]
            branch = None
        elif line.startswith("branch refs/heads/"):
            branch = line[len("branch refs/heads/"):]
    if path is not None:
        blocks.append((path, branch or "DETACHED"))

    if not blocks:
        err.print(f"[red]not inside a git repo:[/] {start}")
        sys.exit(1)
    return blocks[0][0], blocks[1:]  # first block is the main repo; report the rest


def build_rows(
    start: str, progress: Progress | None = None, task: int | None = None
) -> list[Row]:
    """Discover worktrees and resolve each one's PR via a single bulk gh call."""
    main, others = discover(start)

    if progress is not None:
        progress.update(task, description="Fetching pull requests from GitHub…", total=None)
    prs = gh(
        ["pr", "list", "--state", "all", "--limit", str(PR_FETCH_LIMIT),
         "--json", "number,state,url,headRefName"],
        cwd=main,
    )
    best: dict[str, dict] = {}
    for pr in prs:
        head = pr["headRefName"]
        key = (STATE_RANK.get(pr["state"], 0), pr["number"])
        chosen = best.get(head)
        if chosen is None or key > (STATE_RANK.get(chosen["state"], 0), chosen["number"]):
            best[head] = pr

    if progress is not None:
        progress.update(
            task, description="Scanning worktrees", total=len(others) or 1, completed=0
        )
    rows: list[Row] = []
    for path, branch in others:
        iid = issue_id_of(branch, path)
        dirty = "dirty" if git(["status", "--porcelain"], path).strip() else "clean"
        pr = best.get(branch) if branch != "DETACHED" else None
        if pr:
            rows.append(
                Row(path, branch, iid, dirty, str(pr["number"]), pr["state"], pr["url"])
            )
        else:
            rows.append(Row(path, branch, iid, dirty, "none", "NO_PR", "-"))
        if progress is not None:
            progress.advance(task)
    return rows


# --- Linear "Done" gate: one batched GraphQL request --------------------------


def linear_states(
    ids: list[str], key: str | None,
    progress: Progress | None = None, task: int | None = None,
) -> tuple[dict[str, LinearState], str | None]:
    """Map each ENG-1234-style id to its Linear workflow state, in one request.

    Also returns the workspace url slug (for building issue links), or None.
    Returns ({}, None) when no key or no resolvable ids. Ids that don't exist
    (or that the key can't see) are simply absent from the state map.
    """
    wanted = {i: ID_RE.match(i) for i in ids}
    resolvable = {i: m for i, m in wanted.items() if m}
    if not key or not resolvable:
        return {}, None

    aliases: dict[str, str] = {}
    parts: list[str] = []
    for idx, (iid, m) in enumerate(resolvable.items()):
        team, num = m.group(1).upper(), int(m.group(2))
        alias = f"i{idx}"
        aliases[alias] = iid
        parts.append(
            f'{alias}: issues(filter: {{ team: {{ key: {{ eq: "{team}" }} }}, '
            f"number: {{ eq: {num} }} }}) "
            f"{{ nodes {{ identifier state {{ type name }} }} }}"
        )
    query = "query { org: organization { urlKey } " + " ".join(parts) + "}"

    if progress is not None:
        progress.update(task, description="Checking Linear issue status…", total=None)
    req = urllib.request.Request(
        LINEAR_URL,
        data=json.dumps({"query": query}).encode(),
        headers={"Content-Type": "application/json", "Authorization": key},
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            payload = json.loads(resp.read())
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        err.print(f"[yellow]Linear lookup failed:[/] {exc}")
        return {}, None

    if payload.get("errors"):
        msg = "; ".join(e.get("message", "?") for e in payload["errors"])
        err.print(f"[yellow]Linear API error:[/] {msg}")
    data = payload.get("data") or {}

    url_key = (data.get("org") or {}).get("urlKey")
    out: dict[str, LinearState] = {}
    for alias, block in data.items():
        if alias == "org":
            continue
        nodes = (block or {}).get("nodes") or []
        if nodes:
            st = nodes[0]["state"]
            out[aliases[alias]] = LinearState(st["type"], st["name"])
    return out, url_key


# --- verdict ------------------------------------------------------------------


def reason_not_finished(
    row: Row, linear: LinearState | None, has_key: bool, pr_only: bool = False
) -> str | None:
    """None when finished; otherwise a short reason it is not.

    With pr_only, the Linear "Done" gate is dropped — a worktree is finished on
    PR-merged + clean tree alone.
    """
    bits: list[str] = []
    if row.issue_id == "UNKNOWN":
        return "not an issue worktree"
    if row.pr_state != "MERGED":
        bits.append("PR not merged" if row.pr_state != "NO_PR" else "no PR")
    if not pr_only:
        if linear is None:
            bits.append("Linear unknown" if has_key else "no Linear key")
        elif linear.type != "completed":
            bits.append(f"Linear {linear.name}")
    if row.dirty == "dirty":
        bits.append("dirty")
    return ", ".join(bits) if bits else None


# --- rendering ----------------------------------------------------------------


def pr_cell(row: Row) -> Text:
    style = {
        "MERGED": "green",
        "OPEN": "yellow",
        "CLOSED": "red",
        "NO_PR": "dim",
    }.get(row.pr_state, "")
    label = "no PR" if row.pr_state == "NO_PR" else f"{row.pr_state} #{row.pr_number}"
    if row.pr_url and row.pr_url != "-":
        return Text(label, style=f"{style} link {row.pr_url}")
    return Text(label, style=style)


def issue_cell(row: Row, states: dict[str, LinearState], url_key: str | None) -> Text:
    """The issue id, linked to its Linear page when it resolves to a real issue."""
    style = "cyan" if row.issue_id != "UNKNOWN" else "dim"
    if url_key and row.issue_id in states:
        url = f"https://linear.app/{url_key}/issue/{row.issue_id}"
        return Text(row.issue_id, style=f"{style} link {url}")
    return Text(row.issue_id, style=style)


def linear_cell(linear: LinearState | None, has_key: bool) -> Text:
    if linear is None:
        return Text("unknown" if has_key else "no key", style="dim")
    style = {
        "completed": "green",
        "started": "yellow",
        "canceled": "red",
    }.get(linear.type, "dim")
    return Text(linear.name, style=style)


def render(
    rows: list[Row], states: dict[str, LinearState], has_key: bool, url_key: str | None
) -> int:
    """Print the status table. Returns the number of finished worktrees."""
    table = Table(box=None, pad_edge=False, header_style="dim", expand=False)
    table.add_column("ISSUE", no_wrap=True)
    # Branch is secondary (the issue ID identifies the worktree); cap it so the
    # PR/LINEAR/VERDICT columns always survive a narrow terminal.
    table.add_column("BRANCH", no_wrap=True, overflow="ellipsis", max_width=46)
    table.add_column("TREE", no_wrap=True)
    table.add_column("PR", no_wrap=True)
    table.add_column("LINEAR", no_wrap=True)
    table.add_column("VERDICT")

    finished = 0
    for row in sorted(rows, key=lambda r: r.issue_id):
        linear = states.get(row.issue_id)
        reason = reason_not_finished(row, linear, has_key)
        if reason is None:
            finished += 1
            verdict = Text("FINISHED", style="bold green")
        else:
            verdict = Text(reason, style="yellow" if "dirty" in reason else "dim")
        table.add_row(
            issue_cell(row, states, url_key),
            Text(row.branch, style="dim"),
            Text(row.dirty, style="red" if row.dirty == "dirty" else "dim"),
            pr_cell(row),
            linear_cell(linear, has_key),
            verdict,
        )

    console.print("[bold cyan]ISSUE WORKTREES[/]")
    if not rows:
        console.print("  [dim](none)[/]")
        return 0
    console.print(table)
    return finished


# --- artifact triage ----------------------------------------------------------


def artifacts(worktree: str) -> list[Path]:
    found: list[Path] = []
    for sub in ("pr-reviews", "reports"):
        d = Path(worktree) / sub
        if d.is_dir():
            found.extend(sorted(p for p in d.iterdir() if p.is_file()))
    return found


def show_artifacts(worktree: str) -> None:
    files = artifacts(worktree)
    if not files:
        console.print("    [dim]no artifacts (pr-reviews/, reports/)[/]")
        return
    console.print(f"    [yellow]{len(files)} artifact(s):[/]")
    for f in files:
        kb = f.stat().st_size / 1024
        console.print(f"      [dim]{kb:6.1f} KB[/]  {f}")


# --- CLI ----------------------------------------------------------------------


def select_explicit(rows: list[Row], selectors: tuple[str, ...]) -> list[Row]:
    """Pick the exact worktrees named by selectors, ignoring any finished gate.

    Each selector is matched case-insensitively against a row's issue id, branch,
    worktree basename, or full worktree path — so a non-issue scratch worktree can
    be named by its branch or directory. Selectors matching nothing warn; the
    result preserves selector order and de-duplicates by worktree.
    """
    chosen: list[Row] = []
    seen: set[str] = set()
    for sel in selectors:
        s = sel.lower()
        hits = [
            r for r in rows
            if s in {
                r.issue_id.lower(), r.branch.lower(),
                os.path.basename(r.worktree).lower(), r.worktree.lower(),
            }
        ]
        if not hits:
            err.print(f"[yellow]no worktree matches '{sel}'[/]")
        for r in hits:
            if r.worktree not in seen:
                seen.add(r.worktree)
                chosen.append(r)
    return chosen


def scan_progress() -> Progress:
    """A transient spinner+bar live display on stderr, so piped stdout stays clean."""
    return Progress(
        SpinnerColumn(spinner_name="dots", style="cyan"),
        TextColumn("[cyan]{task.description}"),
        BarColumn(bar_width=24, complete_style="cyan", finished_style="green"),
        MofNCompleteColumn(),
        TimeElapsedColumn(),
        console=err,
        transient=True,
    )


def gather(
    start: str, ids: tuple[str, ...]
) -> tuple[list[Row], dict[str, LinearState], bool, str | None]:
    key = os.environ.get("LINEAR_API_KEY")
    with scan_progress() as progress:
        task = progress.add_task("Discovering worktrees…", total=None)
        rows = build_rows(start, progress, task)
        if ids:
            wanted = {i.upper() for i in ids}
            rows = [r for r in rows if r.issue_id in wanted]
        issue_ids = [r.issue_id for r in rows if r.issue_id != "UNKNOWN"]
        states, url_key = linear_states(issue_ids, key, progress, task)
    return rows, states, bool(key), url_key


@click.group(invoke_without_command=True)
@click.option(
    "-C", "--dir", "start", default=None,
    help="A path inside the target repo or any worktree (default: cwd).",
)
@click.pass_context
def cli(ctx: click.Context, start: str | None) -> None:
    """Triage and clean up finished issue worktrees."""
    ctx.ensure_object(dict)
    ctx.obj["start"] = start or os.getcwd()
    if ctx.invoked_subcommand is None:
        ctx.invoke(status)


@cli.command()
@click.argument("issue_ids", nargs=-1)
@click.pass_context
def status(ctx: click.Context, issue_ids: tuple[str, ...]) -> None:
    """Read-only report of every issue worktree (optionally filtered by ID)."""
    rows, states, has_key, url_key = gather(ctx.obj["start"], issue_ids)
    finished = render(rows, states, has_key, url_key)
    if finished:
        console.print(
            f"\n[green]{finished} finished.[/] Run "
            f"[bold]issue-end.py clean[/] to remove them."
        )
    if not has_key:
        console.print(
            "\n[dim]LINEAR_API_KEY unset — Linear gate skipped. "
            "Create a key at https://linear.app/settings/api[/]"
        )


@cli.command()
@click.argument("issue_ids", nargs=-1)
@click.option("-y", "--yes", is_flag=True, help="Don't prompt per worktree; remove all finished.")
@click.option("--force", is_flag=True, help="Pass --force to the cleanup script (discards dirty trees).")
@click.option("--pr-only", is_flag=True, help="Ignore the Linear gate; finished = PR merged + clean tree.")
@click.option(
    "--clean-worktree", is_flag=True,
    help="Remove the exact worktrees named as args, bypassing the finished gate "
         "(PR/Linear ignored). Requires explicit selectors; for scratch worktrees.",
)
@click.pass_context
def clean(
    ctx: click.Context, issue_ids: tuple[str, ...], yes: bool, force: bool,
    pr_only: bool, clean_worktree: bool,
) -> None:
    """Interactively remove FINISHED worktrees (PR merged + Linear done + clean).

    With --pr-only the Linear gate is dropped: any merged, clean worktree is
    eligible. Useful when LINEAR_API_KEY is unset.

    With --clean-worktree the finished gate is dropped entirely and the positional
    args become explicit worktree selectors (matched against issue id, branch, or
    worktree path). This removes arbitrary worktrees — including scratch trees with
    no PR or Linear issue — so it never operates on every worktree at once.
    """
    start = ctx.obj["start"]

    if clean_worktree:
        if not issue_ids:
            err.print(
                "[red]--clean-worktree needs one or more selectors "
                "(issue id, branch, or worktree path).[/]"
            )
            ctx.exit(1)
        rows, states, has_key, url_key = gather(start, ())
        render(rows, states, has_key, url_key)
        targets = select_explicit(rows, issue_ids)
        if not targets:
            console.print("\n[dim]No matching worktrees.[/]")
            return
        console.print(
            f"\n[bold yellow]--clean-worktree: removing {len(targets)} selected "
            f"worktree(s), ignoring the PR/Linear/finished gate.[/]"
        )
    else:
        rows, states, has_key, url_key = gather(start, issue_ids)
        render(rows, states, has_key, url_key)
        if pr_only:
            console.print("[yellow]--pr-only: Linear 'Done' gate skipped.[/]")
        targets = [
            r for r in rows
            if reason_not_finished(r, states.get(r.issue_id), has_key, pr_only) is None
        ]
        if not targets:
            console.print("\n[dim]Nothing finished to clean up.[/]")
            return
        console.print(f"\n[bold green]{len(targets)} worktree(s) ready to remove:[/]")

    removed = 0
    for row in targets:
        label = row.issue_id if row.issue_id != "UNKNOWN" else row.branch
        console.print(f"\n[cyan]{label}[/]  {row.worktree}")
        show_artifacts(row.worktree)
        if not yes and not click.confirm(f"  Remove {label}?", default=False):
            console.print("    [dim]skipped[/]")
            continue
        cmd = ["bash", str(CLEANUP), row.worktree, row.issue_id]
        if force:
            cmd.append("--force")
        result = subprocess.run(cmd)
        if result.returncode == 0:
            removed += 1
        elif result.returncode == 2:
            err.print(
                f"    [yellow]{label} is dirty — rerun with --force to discard.[/]"
            )
        else:
            err.print(f"    [red]cleanup failed for {label} (exit {result.returncode}).[/]")

    console.print(f"\n[green]Removed {removed} of {len(targets)}.[/]")


if __name__ == "__main__":
    # Pin the completion env var; the default derived from the "issue-end.py" prog
    # name contains a dot (_ISSUE_END.PY_COMPLETE), which is not a valid shell
    # identifier. See the shell-completion setup note in the module docstring.
    cli(complete_var="_ISSUE_END_COMPLETE")
