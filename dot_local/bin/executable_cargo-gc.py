#!/usr/bin/env python3
"""Reclaim disk space taken by cargo build artifacts and the registry cache.

Sweeps stale artifacts out of the target dirs under each project root, drops
artifacts built by toolchains rustup has since replaced, then removes the
unpacked registry sources cargo re-extracts from the .crate tarballs it keeps.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

DEFAULT_ROOTS: tuple[str, ...] = ("~/Git",)
DEFAULT_DAYS: int = 30


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="cargo-gc",
        description="Reclaim disk space from cargo build artifacts.",
    )
    parser.add_argument(
        "roots",
        nargs="*",
        default=list(DEFAULT_ROOTS),
        help=f"project roots to sweep (default: {' '.join(DEFAULT_ROOTS)})",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=DEFAULT_DAYS,
        help=f"keep artifacts used within this many days (default: {DEFAULT_DAYS})",
    )
    parser.add_argument(
        "--maxsize",
        type=int,
        metavar="MB",
        help="also cap each target dir at this size, which ignores timestamps",
    )
    parser.add_argument(
        "--keep-registry",
        action="store_true",
        help="leave the cargo registry cache alone",
    )
    parser.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        help="report what would be removed without removing it",
    )
    return parser.parse_args()


def resolve_roots(entries: list[str]) -> list[Path]:
    roots: list[Path] = []
    for entry in entries:
        path = Path(entry).expanduser()
        if path.is_dir():
            roots.append(path)
        else:
            print(f"skipping missing root: {path}", file=sys.stderr)
    return roots


def run(argv: list[str]) -> int:
    print(f"\n$ {' '.join(argv)}", flush=True)
    return subprocess.run(argv).returncode


def sweep(root: Path, mode: list[str], *, dry_run: bool) -> int:
    argv = ["cargo", "sweep", "--recursive", *mode]
    if dry_run:
        argv.append("--dry-run")
    argv.append(str(root))
    return run(argv)


def main() -> int:
    args = parse_args()

    missing = [t for t in ("cargo-sweep", "cargo-cache") if shutil.which(t) is None]
    if missing:
        print(f"not installed: {', '.join(missing)}", file=sys.stderr)
        print(f"install with: cargo install {' '.join(missing)}", file=sys.stderr)
        return 1

    roots = resolve_roots(args.roots)
    if not roots:
        print("no existing roots to sweep", file=sys.stderr)
        return 1

    worst = 0
    for root in roots:
        worst = max(worst, sweep(root, ["--time", str(args.days)], dry_run=args.dry_run))
        worst = max(worst, sweep(root, ["--installed"], dry_run=args.dry_run))
        if args.maxsize is not None:
            worst = max(
                worst,
                sweep(root, ["--maxsize", str(args.maxsize)], dry_run=args.dry_run),
            )

    if not args.keep_registry:
        if args.dry_run:
            print("\nwould run: cargo cache --autoclean")
        else:
            worst = max(worst, run(["cargo", "cache", "--autoclean"]))

    return worst


if __name__ == "__main__":
    sys.exit(main())
