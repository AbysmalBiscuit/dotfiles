#!/usr/bin/env python3
"""Run cargo with compiler optimizations enabled.

Port of the fish/PowerShell `ocargo` function. Leading `-nfldmh` style flags are
consumed by ocargo; the first token that isn't one of them starts the cargo
command, and everything from there on is forwarded untouched.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys

SHORT = {
    "n": "nightly",
    "f": "fat",
    "l": "lto",
    "d": "dylib",
    "m": "mold",
    "h": "help",
}

LONG = {
    "nightly": "nightly",
    "fat": "fat",
    "lto": "lto",
    "dylib": "dylib",
    "mold": "mold",
    "no-mold": "no_mold",
    "debug": "debug",
    "help": "help",
}

HELP = """\
Run cargo with compiler optimizations enabled

Usage: ocargo [OCARGO_OPTS] CARGO_CMD [CARGO_CMD_OPTS]

OCARGO_OPTS:
-n, --nightly    Use nightly compiler
-f, --fat        Enable fat LTO
-l, --lto        Enable thin LTO
-d, --dylib      Enable dylib-lto flag
-m, --mold       Use mold linker, even if $MOLD isn't set
--no-mold        Don't use mold linker, even if it's available
-h, --help       Print help
--debug          Print ocargo debug information

Run 'cargo --help' to see help for cargo\
"""

# Applied only when the inherited RUSTFLAGS doesn't already mention the marker,
# so a caller's own choice of opt-level or debuginfo wins.
DEFAULTS = (
    ("target-cpu", "-C target-cpu=native"),
    ("opt-level", "-C opt-level=3"),
    ("debuginfo", "-C debuginfo=none"),
    ("debug_assertions", "-C debug_assertions=no"),
    ("codegen-units", "-C codegen-units=1"),
)


def parse_flags(argv: list[str]) -> tuple[dict[str, bool], list[str]]:
    flags = dict.fromkeys(set(SHORT.values()) | set(LONG.values()), False)
    index = 0
    while index < len(argv):
        token = argv[index]
        long_match = re.fullmatch(r"--([a-z-]+)", token)
        short_match = re.fullmatch(r"-([a-z]+)", token)
        if long_match and long_match.group(1) in LONG:
            flags[LONG[long_match.group(1)]] = True
        elif short_match and all(char in SHORT for char in short_match.group(1)):
            for char in short_match.group(1):
                flags[SHORT[char]] = True
        else:
            break
        index += 1
    return flags, argv[index:]


def base_rustflags() -> str:
    inherited = os.environ.get("RUSTFLAGS_RELEASE") or os.environ.get("RUSTFLAGS") or ""
    if not inherited:
        return " ".join(flag for _, flag in DEFAULTS)
    parts = [inherited]
    parts.extend(flag for marker, flag in DEFAULTS if marker not in inherited)
    return " ".join(parts)


def mold_flag(explicit: bool) -> str | None:
    path = os.environ.get("MOLD") or shutil.which("mold")
    if path:
        return f"-C link-arg=-fuse-ld={path}"
    if explicit:
        print(
            "ocargo: mold not found on PATH, linking with the default linker",
            file=sys.stderr,
        )
    return None


def has_nightly() -> bool:
    override = os.environ.get("HAS_NIGHTLY_RUST")
    if override is not None:
        return override == "true"
    rustup = shutil.which("rustup")
    if not rustup:
        return False
    result = subprocess.run(
        [rustup, "toolchain", "list"], capture_output=True, text=True
    )
    return any(line.startswith("nightly") for line in result.stdout.splitlines())


def main() -> int:
    flags, cargo_args = parse_flags(sys.argv[1:])

    if flags["fat"] and flags["lto"]:
        print("ocargo: -f/--fat and -l/--lto are mutually exclusive", file=sys.stderr)
        return 2
    if flags["mold"] and flags["no_mold"]:
        print("ocargo: -m/--mold and --no-mold are mutually exclusive", file=sys.stderr)
        return 2

    if flags["help"]:
        print(HELP)
        return 0

    rustflags = base_rustflags()

    if (flags["mold"] or os.environ.get("MOLD")) and not flags["no_mold"]:
        link_arg = mold_flag(flags["mold"])
        if link_arg:
            rustflags += f" {link_arg}"

    if flags["lto"]:
        rustflags += " -C lto=thin -C embed-bitcode=yes"
    if flags["fat"]:
        rustflags += " -C lto=fat -C embed-bitcode=yes"

    if flags["nightly"]:
        if not has_nightly():
            print("nightly rust is not available. to install it run:")
            print("rustup toolchain install nightly")
            return 1
        cargo_args = ["+nightly"] + cargo_args
        if flags["dylib"]:
            rustflags += " -Zdylib-lto"

    if flags["debug"]:
        print("ocargo debug information:")
        print(f"RUSTFLAGS='{rustflags}'")
        print("cargo " + " ".join(cargo_args))
        return 0

    cargo = shutil.which("cargo")
    if not cargo:
        print("ocargo: cargo not found on PATH", file=sys.stderr)
        return 127

    env = dict(os.environ, RUSTFLAGS=rustflags)
    # cargo reads CARGO_ENCODED_RUSTFLAGS in preference to RUSTFLAGS, so an
    # inherited one would silently discard everything assembled above.
    env.pop("CARGO_ENCODED_RUSTFLAGS", None)
    try:
        return subprocess.run([cargo, *cargo_args], env=env).returncode
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
