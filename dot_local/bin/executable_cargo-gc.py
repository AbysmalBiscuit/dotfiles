#!/usr/bin/env python3
"""Reclaim disk space taken by cargo build artifacts and the registry cache.

Sweeps stale artifacts out of the target dirs under each configured project
root, drops artifacts built by toolchains rustup has since replaced, then
removes the unpacked registry sources cargo re-extracts from the .crate
tarballs it already keeps.

Settings come from $CARGO_HOME/cargo_gc.toml, and command line arguments
override them:

    roots = ["~/Git", "D:/work/rust"]
    days = 30
    maxsize = 4096
    keep_registry = false
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

CONFIG_NAME: str = "cargo_gc.toml"
DEFAULT_DAYS: int = 30
KNOWN_KEYS: frozenset[str] = frozenset({"roots", "days", "maxsize", "keep_registry"})


def default_config_path() -> Path:
    cargo_home = os.environ.get("CARGO_HOME")
    return (Path(cargo_home) if cargo_home else Path.home() / ".cargo") / CONFIG_NAME


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="cargo-gc",
        description="Reclaim disk space from cargo build artifacts.",
    )
    parser.add_argument(
        "roots",
        nargs="*",
        help="project roots to sweep, overriding the ones in the config file",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=default_config_path(),
        help="config file to read (default: %(default)s)",
    )
    parser.add_argument(
        "--days",
        type=int,
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
        default=None,
        help="leave the cargo registry cache alone",
    )
    parser.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        help="report what would be removed without removing it",
    )
    return parser.parse_args()


def load_config(path: Path) -> dict[str, object]:
    if not path.is_file():
        return {}
    with path.open("rb") as handle:
        config = tomllib.load(handle)
    unknown = sorted(set(config) - KNOWN_KEYS)
    if unknown:
        print(f"{path}: ignoring unknown keys: {', '.join(unknown)}", file=sys.stderr)
    return config


def resolve_roots(entries: list[str]) -> list[Path]:
    roots: list[Path] = []
    for entry in entries:
        path = Path(os.path.expandvars(entry)).expanduser()
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
    config = load_config(args.config)

    configured = config.get("roots", [])
    if not isinstance(configured, list) or not all(isinstance(r, str) for r in configured):
        print(f"{args.config}: roots must be a list of strings", file=sys.stderr)
        return 1

    entries = args.roots or configured
    if not entries:
        print("no roots configured, so nothing to sweep", file=sys.stderr)
        print(f'list them in {args.config}:\n\n    roots = ["~/Git"]\n', file=sys.stderr)
        return 1

    days = args.days if args.days is not None else config.get("days", DEFAULT_DAYS)
    maxsize = args.maxsize if args.maxsize is not None else config.get("maxsize")
    keep_registry = (
        args.keep_registry
        if args.keep_registry is not None
        else config.get("keep_registry", False)
    )

    missing = [t for t in ("cargo-sweep", "cargo-cache") if shutil.which(t) is None]
    if missing:
        print(f"not installed: {', '.join(missing)}", file=sys.stderr)
        print(f"install with: cargo install {' '.join(missing)}", file=sys.stderr)
        return 1

    roots = resolve_roots(entries)
    if not roots:
        print("none of the configured roots exist", file=sys.stderr)
        return 1

    worst = 0
    for root in roots:
        worst = max(worst, sweep(root, ["--time", str(days)], dry_run=args.dry_run))
        worst = max(worst, sweep(root, ["--installed"], dry_run=args.dry_run))
        if maxsize is not None:
            worst = max(
                worst,
                sweep(root, ["--maxsize", str(maxsize)], dry_run=args.dry_run),
            )

    if not keep_registry:
        if args.dry_run:
            print("\nwould run: cargo cache --autoclean")
        else:
            worst = max(worst, run(["cargo", "cache", "--autoclean"]))

    return worst


if __name__ == "__main__":
    sys.exit(main())
