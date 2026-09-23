#!/usr/bin/env python3
"""fable: the brief for getting a task in front of a more senior model."""

import argparse
import os
import re
import sys
import tomllib
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONFIG = HERE / "targets.toml"
PROMPTS = Path.home() / ".cache" / "fable"

MCP_SANDBOX = {"write": "workspace-write", "read": "read-only"}


def current_harness() -> str:
    """Which CLI this process runs under, as a name used in targets.toml.

    Claude Code always exports CLAUDECODE. Codex exports no marker that is reliably
    present, so its detection is best-effort and FABLE_HARNESS overrides both.
    """
    override = os.environ.get("FABLE_HARNESS")
    if override:
        return override.strip().lower()
    if os.environ.get("CLAUDECODE"):
        return "claude-code"
    if os.environ.get("CODEX_SANDBOX") or os.environ.get("CODEX_HOME"):
        return "codex"
    return "claude-code"


def load_config() -> dict:
    if not CONFIG.exists():
        raise SystemExit(f"missing {CONFIG}")
    try:
        return tomllib.loads(CONFIG.read_text())
    except tomllib.TOMLDecodeError as exc:
        raise SystemExit(f"{CONFIG} is not valid TOML: {exc}")


def pick_target(config: dict, harness: str, wanted: str | None) -> tuple[str, dict]:
    """A target by name, or by the model it wraps, falling back to the harness default."""
    targets = config.get("target", {})
    if not wanted:
        wanted = config.get("harness", {}).get(harness, {}).get("target")
        if not wanted:
            raise SystemExit(f"no default target for {harness} in {CONFIG}; name one with -m")
    if wanted in targets:
        return wanted, targets[wanted]
    for name, entry in targets.items():
        if entry.get("model") == wanted:
            return name, entry
    raise SystemExit(f"no target {wanted!r} in {CONFIG} (have: {', '.join(sorted(targets))})")


COMPOSE = "Invoke {skill} and write the handoff prompt the way it says to. The bar: someone who cannot see this conversation could do the task from that text alone. Carry the request in the user's own words, the absolute paths that matter, the constraints and conventions it has to respect, whatever you already tried and ruled out, and what you want back."

AGENT = """\
Hand this to {model} through the Agent tool. It starts on an empty context window, so all it knows is what you write it.

1. {compose}{constraint}

2. Call the Agent tool with:

       subagent_type   general-purpose
       model           {model}
       description     three to five words
       prompt          the text you just wrote

   This route runs at whatever reasoning effort this session is at. The Agent tool has no effort parameter, so {model} is the only thing being raised here.

3. {finish}{extra}
"""

MCP = """\
Hand this to {model} at {effort} reasoning effort through the codex MCP tool. It starts on an empty context window, so all it knows is what you write it.

1. {compose}

2. Call mcp__codex__codex with:

       prompt    the text you just wrote
       model     {model}
       config    {{"model_reasoning_effort": "{effort}"}}
       sandbox   {sandbox}
       cwd       {cwd}

3. {finish}{extra}
"""

CLI = """\
Hand this to {model} at {effort} reasoning effort. It starts on an empty context window in {cwd}, and {access}.

1. {compose}
   Write it to {prompt_path}.

2. Launch it:

       {command}

   It thinks for minutes, not seconds. Run it in the background, or with a timeout of at least 15 minutes. Wait for it and answer from its output.

3. {finish}{extra}
"""

ACCESS = {"write": "may edit files there", "read": "reads without editing"}
CONSTRAINT = {"write": "", "read": "\n   Say in the prompt that it investigates and answers without editing anything: this route has no sandbox flag, so the prompt is the only place that constraint lives."}
FINISH = {
    "write": "Report what came back, naming the files it changed. Read those files yourself before calling the task done.",
    "read": "Report what came back with its reasoning intact instead of compressed to a verdict. It edited nothing, so say what applying its answer would take.",
}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="~/.agents/skills/fable/fable.py",
        description="Print the brief for getting a task in front of a more senior model.",
    )
    parser.add_argument("-m", "--model", metavar="TARGET",
                        help="target from targets.toml, by name or by the model it wraps")
    parser.add_argument("-e", "--effort", metavar="LEVEL",
                        help="reasoning effort: low, medium, high, xhigh, max")
    parser.add_argument("-r", "--read", "--read-only", dest="read_only", action="store_true",
                        help="the senior model investigates and answers, editing nothing")
    parser.add_argument("request", nargs="*",
                        help="ignored; the request stays with you, for the prompt you write")
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    config = load_config()
    harness = current_harness()
    name, entry = pick_target(config, harness, args.model)

    route = entry.get("from", {}).get(harness)
    if not route:
        reachable = ", ".join(sorted(entry.get("from", {}))) or "nothing"
        raise SystemExit(f"target {name!r} declares no route from {harness} in {CONFIG} (reachable from: {reachable})")

    prefix = config.get("harness", {}).get(harness, {}).get("skill_prefix", "/")
    compose = COMPOSE.format(skill=f"{prefix}writing-for-agents")

    mode = "read" if args.read_only else "write"
    model = entry.get("model", name)
    effort = args.effort or entry.get("effort")
    if not effort:
        raise SystemExit(f"target {name!r} in {CONFIG} sets no effort; pass -e")

    if route == "agent":
        extra = ""
        if args.effort:
            extra = f"\n\nYou were asked for {args.effort} effort, which this route cannot set: the Agent tool has no effort parameter. Say so rather than letting it look like it took."
        print(AGENT.format(model=model, compose=compose, constraint=CONSTRAINT[mode],
                           finish=FINISH[mode], extra=extra))
        return 0

    if route == "mcp:codex":
        print(MCP.format(model=model, effort=effort, cwd=Path.cwd(), compose=compose,
                         sandbox=MCP_SANDBOX[mode], finish=FINISH[mode], extra=""))
        return 0

    permission = entry.get("permission", {}).get(mode)
    if permission is None:
        raise SystemExit(f"target {name!r} in {CONFIG} has no permission.{mode} fragment")
    PROMPTS.mkdir(parents=True, exist_ok=True)
    prompt_path = PROMPTS / f"{datetime.now():%Y%m%d-%H%M%S}-{name}.md"
    print(CLI.format(model=model, effort=effort, cwd=Path.cwd(), compose=compose,
                     prompt_path=prompt_path, access=ACCESS[mode], finish=FINISH[mode], extra="",
                     command=route.format(model=model, effort=effort, permission=permission, prompt=prompt_path)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
