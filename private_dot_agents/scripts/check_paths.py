#!/usr/bin/env python3
"""Ask the live deny list what it does with specific paths.

Reads permissions.deny from settings.json rather than a hardcoded copy, so it
cannot drift from the rules actually in force. Anchoring semantics come from
verify_permissions.py.

    python3 check_paths.py /c/Users/Lev/.config/chezmoi/chezmoi.toml ...

With no arguments it runs the built-in chezmoi and age cases.
"""

import importlib.util
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).parent
spec = importlib.util.spec_from_file_location(
    "verify", HERE / "verify_permissions.py"
)
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)

SETTINGS = pathlib.Path.home() / ".claude" / "settings.json"

# (path, should_be_denied)
CASES = [
    ("/c/Users/Lev/.config/chezmoi/chezmoi.toml", True),
    ("/c/Users/Lev/.config/chezmoi/key.txt", True),
    ("/c/Users/Lev/.config/chezmoi/encryption-key.txt", True),
    ("/c/Users/Lev/.config/chezmoi/secrets.toml", True),
    ("/c/Users/Lev/.config/chezmoi/secrets.yaml", True),
    ("/c/Users/Lev/.config/chezmoi/private/tokens.toml", True),
    ("/c/Users/Lev/.config/chezmoi/foo.age", True),
    ("/c/Users/Lev/.local/share/chezmoi/dot_bashrc", True),
    ("/c/Users/Lev/x.age", True),
    ("/c/Users/Lev/projects/app/deep/nested/secret.age", True),
    ("/home/lev/.config/chezmoi/chezmoi.toml", True),
    ("/mnt/c/Users/Lev/.config/chezmoi/key.txt", True),
    ("/c/Users/Lev/.config/chezmoi/ignore", False),
    ("/c/Users/Lev/.config/chezmoi/chezmoi.toml.tmpl", False),
    ("/c/Users/Lev/.config/chezmoi/scripts/setup.sh", False),
    ("/c/Users/Lev/projects/app/src/index.ts", False),
]


def main():
    deny = json.loads(SETTINGS.read_text(encoding="utf-8"))["permissions"]["deny"]
    rules = [r for r in (verify.compile_rule(x) for x in deny) if r]

    cases = [(p, None) for p in sys.argv[1:]] or CASES
    failures = 0

    for path, expected in cases:
        read = verify.blocked_by(rules, "Read", path)
        edit = verify.blocked_by(rules, "Edit", path)
        denied = bool(read and edit)
        mark = ""
        if expected is not None and denied != expected:
            mark = "   <-- EXPECTED %s" % ("DENY" if expected else "open")
            failures += 1
        print("%-6s %-58s %s%s" % (
            "DENY" if denied else "open", path,
            read[0] if read else "", mark))
        if read and not edit:
            print("       read denied but edit allowed, by %s" % read[0])
        if edit and not read:
            print("       edit denied but read allowed, by %s" % edit[0])

    if any(e is not None for _, e in cases):
        print("\n%d/%d as expected" % (len(cases) - failures, len(cases)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
