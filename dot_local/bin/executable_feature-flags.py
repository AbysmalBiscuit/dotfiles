#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["tabulate>=0.9.0"]
# ///
"""PostHog feature flags from the terminal, on top of `posthog-cli api`.

Reads come from three sources and are merged by flag id:
  * `feature-flag-get-all`      - key, name, updated_at, tags, archived state
  * `system.feature_flags`      - created_at and the release-condition JSON
  * `$feature_flag_called`      - per-flag evaluation counts, split on the response

The evaluation split is not just true/false. A flag that is disabled is absent
from the flags payload PostHog sends the SDK, so the SDK reports
`$feature_flag_error: flag_missing` and the caller falls through to its own
default. Those land in the "off" column alongside explicit `false` responses,
because both mean the same thing to the code being gated.
"""

from __future__ import annotations

import argparse
import base64
import contextlib
import copy
import itertools
import json
import os
import shutil
import subprocess
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

from tabulate import tabulate

CLI = os.environ.get("POSTHOG_CLI", "posthog-cli")
PAGE = 100

HEADERS = [
    "flag",
    "created",
    "last changed",
    "rollout",
    "status",
    "reqs off",
    "reqs on",
]
ALIGN = ("left", "left", "left", "right", "left", "right", "right")


# --------------------------------------------------------------------------- io


class ToolError(RuntimeError):
    pass


def api_cli_bundle() -> str | None:
    """The JS bundle shipped beside the launcher, on an npm-style install."""
    launcher = shutil.which(CLI)
    if launcher is None:
        return None
    bundle = os.path.join(
        os.path.dirname(os.path.realpath(launcher)), "lib", "posthog-api-cli.mjs"
    )
    return bundle if os.path.isfile(bundle) and os.path.getsize(bundle) else None


def build_tool_env() -> dict[str, str]:
    """The environment every CLI call runs under.

    posthog-cli implements its `api` subcommand in JavaScript and embeds the
    bundle in the binary, so it materializes a 7 MB copy into ~/.posthog and
    runs node on that. It rewrites the copy on every invocation and does not
    write it atomically, so a concurrent call can import a half-written file and
    die with `SyntaxError: Unexpected end of input`. Naming a bundle that
    already exists skips the write, which removes the race rather than racing
    more carefully. An empty value is its own error, so drop it if it is set
    that way upstream.
    """
    env = dict(os.environ)
    if env.get("POSTHOG_API_CLI_PATH"):
        return env
    bundle = api_cli_bundle()
    if bundle:
        env["POSTHOG_API_CLI_PATH"] = bundle
    else:
        env.pop("POSTHOG_API_CLI_PATH", None)
    return env


TOOL_ENV = build_tool_env()


def run_tool(tool: str, payload: dict, *, dry_run: bool = False):
    """Call one PostHog MCP tool and return its decoded JSON result."""
    cmd = [CLI, "api", "call", "--json"]
    if dry_run:
        cmd.append("--dry-run")
    cmd += [tool, json.dumps(payload)]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, env=TOOL_ENV)
    except FileNotFoundError:
        raise ToolError(f"{CLI} is not on PATH. Install it, or set POSTHOG_CLI.")
    out = (proc.stdout or "").strip()
    err = (proc.stderr or "").strip()
    if proc.returncode != 0 or out.startswith("Error:"):
        detail = out or err or f"exit {proc.returncode}"
        if "auth" in detail.lower() or "401" in detail:
            detail += "\nRun `posthog-cli login` first."
        raise ToolError(f"{tool} failed: {detail}")
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        raise ToolError(f"{tool} returned output that is not JSON:\n{out[:500]}")


def run_sql(query: str) -> list[dict]:
    """Run HogQL. execute-sql answers with pipe-delimited text, header first."""
    result = run_tool("execute-sql", {"query": query, "truncate": False})
    if not isinstance(result, str):
        raise ToolError(f"execute-sql returned {type(result).__name__}, expected text")
    lines = result.splitlines()
    if not lines:
        return []
    cols = lines[0].split("|")
    return [dict(zip(cols, line.split("|", len(cols) - 1))) for line in lines[1:] if line]


# ---------------------------------------------------------------------- progress


FRAMES = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"


@contextlib.contextmanager
def spinner(label: str):
    """Animate `label` on stderr while a slow call runs.

    Results go to stdout, so a piped or redirected run stays clean and the
    animation is skipped entirely when stderr is not a terminal. The first
    frame waits out the interval, so a fast call draws nothing at all.
    """
    if not sys.stderr.isatty():
        yield
        return
    done = threading.Event()

    def spin() -> None:
        for tick in itertools.count():
            if done.wait(0.08):
                return
            sys.stderr.write(f"\r\033[2K{FRAMES[tick % len(FRAMES)]} {label}")
            sys.stderr.flush()

    thread = threading.Thread(target=spin, daemon=True)
    thread.start()
    try:
        yield
    finally:
        done.set()
        thread.join()
        sys.stderr.write("\r\033[2K")
        sys.stderr.flush()


# ---------------------------------------------------------------------- fetching


def fetch_flags(include_archived: bool) -> list[dict]:
    flags: dict[int, dict] = {}
    queries: list[dict] = [{}]
    if include_archived:
        queries.append({"archived": "true"})
    for extra in queries:
        offset = 0
        while True:
            page = run_tool(
                "feature-flag-get-all", {"limit": PAGE, "offset": offset, **extra}
            )
            for row in page.get("results", []):
                row["archived"] = bool(extra)
                flags[row["id"]] = row
            offset += PAGE
            if not page.get("next"):
                break
    return list(flags.values())


def fetch_active_ids() -> set[int]:
    ids: set[int] = set()
    for archived in ("false", "true"):
        offset = 0
        while True:
            page = run_tool(
                "feature-flag-get-all",
                {"active": "true", "archived": archived, "limit": PAGE, "offset": offset},
            )
            ids.update(row["id"] for row in page.get("results", []))
            offset += PAGE
            if not page.get("next"):
                break
    return ids


def fetch_meta() -> dict[int, dict]:
    """created_at and release conditions, straight out of the flag mirror table.

    The conditions come back base64-encoded so a `|` inside a property value
    cannot split a column.
    """
    rows = run_sql(
        "SELECT id, toString(created_at) AS created_at, "
        "base64Encode(toString(filters)) AS filters "
        "FROM system.feature_flags WHERE deleted = 0"
    )
    meta: dict[int, dict] = {}
    for row in rows:
        try:
            filters = json.loads(base64.b64decode(row["filters"]))
        except Exception:
            filters = {}
        meta[int(row["id"])] = {"created_at": row["created_at"], "filters": filters}
    return meta


def fetch_calls(days: int, key: str | None = None) -> dict[str, dict[str, int]]:
    where = f"event = '$feature_flag_called' AND timestamp > now() - INTERVAL {days} DAY"
    if key:
        where += f" AND properties.$feature_flag = '{key.replace(chr(39), chr(39) * 2)}'"
    rows = run_sql(
        "SELECT properties.$feature_flag AS flag, "
        "countIf(JSONExtractRaw(properties, '$feature_flag_response') = 'false' "
        "OR JSONExtractRaw(properties, '$feature_flag_error') = '\"flag_missing\"') AS n_off, "
        "countIf(JSONExtractRaw(properties, '$feature_flag_response') "
        "NOT IN ('', 'false', 'null')) AS n_on, "
        "countIf(JSONExtractRaw(properties, '$feature_flag_error') "
        "NOT IN ('', '\"flag_missing\"')) AS n_err "
        f"FROM events WHERE {where} GROUP BY flag"
    )
    return {
        r["flag"]: {k: int(r[k] or 0) for k in ("n_off", "n_on", "n_err")} for r in rows
    }


def fetch_definition(flag_id: int) -> dict:
    return run_tool("feature-flag-get-definition", {"id": flag_id})


def recent_evaluations(keys: list[str], hours: int) -> dict[str, int]:
    """Evaluation counts over a short window, to catch flags a deploy still reads."""
    quoted = ", ".join("'" + k.replace("'", "''") + "'" for k in keys)
    with spinner(f"checking the last {hours}h of evaluations"):
        rows = run_sql(
            "SELECT properties.$feature_flag AS flag, count() AS n FROM events "
            "WHERE event = '$feature_flag_called' "
            f"AND timestamp > now() - INTERVAL {hours} HOUR "
            f"AND properties.$feature_flag IN ({quoted}) GROUP BY flag"
        )
    return {r["flag"]: int(r["n"] or 0) for r in rows}


# --------------------------------------------------------------------- formatting


def colorize(text: str, code: str, enabled: bool) -> str:
    return f"\033[{code}m{text}\033[0m" if enabled else text


def parse_ts(value: str | None) -> datetime | None:
    if not value:
        return None
    text = value.replace("Z", "+00:00").replace(" ", "T", 1)
    try:
        stamp = datetime.fromisoformat(text)
    except ValueError:
        return None
    return stamp if stamp.tzinfo else stamp.replace(tzinfo=timezone.utc)


def fmt_date(value: str | None, *, age: bool = False) -> str:
    stamp = parse_ts(value)
    if stamp is None:
        return "-"
    text = stamp.strftime("%Y-%m-%d")
    if age:
        days = (datetime.now(timezone.utc) - stamp).days
        text += f" ({days}d)" if days else " (today)"
    return text


def describe_rollout(filters: dict | None) -> str:
    groups = (filters or {}).get("groups") or []
    if not groups:
        return "-"
    parts, gated = [], False
    for group in groups:
        pct = group.get("rollout_percentage")
        parts.append(f"{100 if pct is None else pct:g}%")
        if group.get("properties"):
            gated = True
    return " / ".join(parts) + ("*" if gated else "")


def describe_variants(filters: dict | None) -> str:
    variants = ((filters or {}).get("multivariate") or {}).get("variants") or []
    return ", ".join(f"{v['key']} {v.get('rollout_percentage', 0):g}%" for v in variants)


def build_row(flag: dict, color: bool) -> list:
    if flag["archived"]:
        status = colorize("archived", "2", color)
    elif flag["active"]:
        status = colorize("enabled", "32", color)
    else:
        status = colorize("disabled", "31", color)
    calls = flag["calls"]
    return [
        flag["key"],
        fmt_date(flag.get("created_at")),
        fmt_date(flag.get("updated_at"), age=True),
        describe_rollout(flag.get("filters")),
        status,
        f"{calls['n_off']:,}",
        f"{calls['n_on']:,}",
    ]


def render(flags: list[dict], days: int, color: bool) -> None:
    if not flags:
        print("No flags matched.")
        return
    table = [build_row(f, color) for f in flags]
    print(tabulate(table, headers=HEADERS, tablefmt="simple", colalign=ALIGN))
    notes = [f"requests counted over the last {days} days"]
    if any("*" in row[3] for row in table):
        notes.append("* release condition carries property filters")
    if any(f["calls"]["n_err"] for f in flags):
        errored = sum(f["calls"]["n_err"] for f in flags)
        plural = "evaluation" if errored == 1 else "evaluations"
        notes.append(f"{errored:,} {plural} errored, counted in neither column")
    print("\n" + "; ".join(notes))


def as_json(flags: list[dict]) -> None:
    print(
        json.dumps(
            [
                {
                    "id": f["id"],
                    "key": f["key"],
                    "created_at": f.get("created_at"),
                    "updated_at": f.get("updated_at"),
                    "rollout": describe_rollout(f.get("filters")),
                    "active": f["active"],
                    "archived": f["archived"],
                    "requests_off": f["calls"]["n_off"],
                    "requests_on": f["calls"]["n_on"],
                    "requests_error": f["calls"]["n_err"],
                    "tags": f.get("tags", []),
                }
                for f in flags
            ],
            indent=2,
        )
    )


# ----------------------------------------------------------------------- filters

# `rollout>50` makes the shell open a file called 50, so every comparison also
# has a dotted spelling that survives an unquoted command line.
DOTTED = {".gte.": ">=", ".lte.": "<=", ".gt.": ">", ".lt.": "<",
          ".eq.": "==", ".ne.": "!=", ".has.": "~"}
OPERATORS = (">=", "<=", "==", "!=", "!~", ">", "<", "=", "~")


def days_since(value: str | None) -> int | None:
    stamp = parse_ts(value)
    return None if stamp is None else (datetime.now(timezone.utc) - stamp).days


def rollout_of(flag: dict) -> float:
    """A flag's widest release condition. Absent percentage means 100 in PostHog."""
    groups = (flag.get("filters") or {}).get("groups") or []
    if not groups:
        return 0.0
    return max(
        100.0 if g.get("rollout_percentage") is None else float(g["rollout_percentage"])
        for g in groups
    )


NUMERIC = {
    "rollout": rollout_of,
    "reqs": lambda f: f["calls"]["n_off"] + f["calls"]["n_on"],
    "on": lambda f: f["calls"]["n_on"],
    "off": lambda f: f["calls"]["n_off"],
    "err": lambda f: f["calls"]["n_err"],
    "age": lambda f: days_since(f.get("created_at")),
    "changed": lambda f: days_since(f.get("updated_at")),
}

BOOLEAN = {
    "enabled": lambda f: f["active"],
    "disabled": lambda f: not f["active"],
    "archived": lambda f: f["archived"],
    "stale": lambda f: (f.get("status") or "").upper() == "STALE",
    "used": lambda f: f["calls"]["n_off"] + f["calls"]["n_on"] > 0,
    "unused": lambda f: f["calls"]["n_off"] + f["calls"]["n_on"] == 0,
    "tagged": lambda f: bool(f.get("tags")),
}

TEXT = {
    "key": lambda f: [f["key"]],
    "name": lambda f: [f.get("name") or ""],
    "tag": lambda f: f.get("tags") or [],
}

COMPARISONS = {
    ">": lambda a, b: a > b,
    ">=": lambda a, b: a >= b,
    "<": lambda a, b: a < b,
    "<=": lambda a, b: a <= b,
    "==": lambda a, b: a == b,
    "=": lambda a, b: a == b,
    "!=": lambda a, b: a != b,
}


def vocabulary() -> str:
    """Every filter field, grouped by the kind of value it holds."""
    return (
        f"  boolean, on its own:  {', '.join(sorted(BOOLEAN))}\n"
        f"  numeric, compared:    {', '.join(sorted(NUMERIC))}\n"
        "                        with > >= < <= == !=\n"
        f"  text, matched:        {', '.join(sorted(TEXT))}\n"
        "                        with = exact, ~ contains, !~ excludes\n"
        "\n"
        f"  quote-free spellings: {' '.join(sorted(DOTTED))}\n"
        "  prefix any term with ! to invert it\n"
        "  age and changed are whole days; rollout is the widest release condition"
    )


def filter_help() -> str:
    """The filter reference, shown under both `--help` and `list --help`."""
    return (
        "filters, comma-separated, all of which must hold:\n"
        "  -f enabled,rollout.lt.100               enabled but not fully rolled out\n"
        "  -f 'disabled,rollout==100'              armed to 100 but switched off\n"
        "  -f unused,age.gt.60                     old and never evaluated\n"
        "  -f 'tag~kysely,!archived,off.gt.500'    busy kysely gates still serving off\n"
        "\n"
        f"{vocabulary()}"
    )


def split_term(term: str) -> tuple[str, str, str] | None:
    for dotted, operator in DOTTED.items():
        if dotted in term:
            field, _, value = term.partition(dotted)
            return field, operator, value
    for operator in OPERATORS:
        at = term.find(operator)
        if at > 0:
            return term[:at], operator, term[at + len(operator):]
    return None


def parse_term(term: str):
    """Compile one filter expression into a predicate over a table row."""
    term = term.strip()
    if not term:
        raise SystemExit("Empty filter term.")
    negate = term.startswith("!")
    if negate:
        term = term[1:]

    def negated(predicate):
        return (lambda f: not predicate(f)) if negate else predicate

    parts = split_term(term)
    if parts is None:
        if term.lower() not in BOOLEAN:
            raise SystemExit(
                f"Unknown filter {term!r}. Filters are:\n{vocabulary()}"
            )
        return negated(BOOLEAN[term.lower()])

    field, operator, value = (parts[0].strip().lower(), parts[1], parts[2].strip())
    if field in NUMERIC:
        if operator in ("~", "!~"):
            raise SystemExit(f"{field!r} is a number; ~ only works on {', '.join(TEXT)}.")
        try:
            wanted = float(value.rstrip("%"))
        except ValueError:
            raise SystemExit(f"{value!r} is not a number, in filter {term!r}.")
        compare = COMPARISONS[operator]

        def numeric(flag, get=NUMERIC[field], compare=compare, wanted=wanted):
            actual = get(flag)
            return actual is not None and compare(float(actual), wanted)

        return negated(numeric)

    if field in TEXT:
        wanted = value.lower()
        contains = operator in ("~", "!~")
        invert = operator in ("!=", "!~")

        def text(flag, get=TEXT[field], wanted=wanted, contains=contains, invert=invert):
            values = [str(v).lower() for v in get(flag)]
            hit = any(wanted in v for v in values) if contains else wanted in values
            return hit != invert

        return negated(text)

    raise SystemExit(f"Unknown filter field {field!r}. Filters are:\n{vocabulary()}")


def compile_filters(terms: list[str]) -> list:
    return [parse_term(term) for term in terms]


# ----------------------------------------------------------------------- loading


EMPTY_CALLS = {"n_off": 0, "n_on": 0, "n_err": 0}


def load_all(days: int, include_archived: bool) -> list[dict]:
    with spinner("loading flags"), ThreadPoolExecutor(max_workers=4) as pool:
        jobs = [
            pool.submit(fetch_flags, include_archived),
            pool.submit(fetch_active_ids),
            pool.submit(fetch_meta),
            pool.submit(fetch_calls, days),
        ]
        flags, active, meta, calls = (job.result() for job in jobs)
    for flag in flags:
        flag["active"] = flag["id"] in active
        flag.update(meta.get(flag["id"], {}))
        flag["calls"] = calls.get(flag["key"], dict(EMPTY_CALLS))
    return flags


def candidates(flags: list[dict], name: str) -> list[dict]:
    """Exact key wins, then a case-insensitive key, then a unique substring of one."""
    lowered = name.lower()
    for pick in (
        [f for f in flags if f["key"] == name],
        [f for f in flags if f["key"].lower() == lowered],
        [f for f in flags if lowered in f["key"].lower()],
    ):
        if pick:
            return pick
    return []


def resolve_many(names: list[str]) -> list[dict]:
    """Resolve every name against one listing, reporting all bad names together.

    Resolution happens before any write, so a typo in the tenth flag of a batch
    fails the run instead of leaving the first nine changed. Repeats collapse.
    """
    with spinner("resolving flags"):
        flags = fetch_flags(include_archived=False)
    archived: list[dict] | None = None
    resolved: dict[int, dict] = {}
    problems: list[str] = []
    for name in names:
        matches = candidates(flags, name)
        if not matches:
            if archived is None:
                with spinner("searching archived flags"):
                    archived = fetch_flags(include_archived=True)
            matches = candidates(archived, name)
        if not matches:
            problems.append(f"No flag matches {name!r}.")
        elif len(matches) > 1:
            listing = "\n  ".join(sorted(f["key"] for f in matches))
            problems.append(f"{name!r} matches {len(matches)} flags:\n  {listing}")
        else:
            resolved.setdefault(matches[0]["id"], matches[0])
    if problems:
        raise SystemExit("\n".join(problems))
    return list(resolved.values())


def load_one(flag_id: int, key: str, days: int) -> dict:
    """One flag, read from the definition endpoint so a just-written change shows."""
    with spinner(f"reading {key}"), ThreadPoolExecutor(max_workers=2) as pool:
        counts = pool.submit(fetch_calls, days, key)
        defn = fetch_definition(flag_id)
    defn["calls"] = counts.result().get(defn["key"], dict(EMPTY_CALLS))
    return defn


def show_one(flag_id: int, key: str, args) -> None:
    flag = load_one(flag_id, key, args.days)
    if args.json:
        as_json([flag])
        return
    render([flag], args.days, args.color)
    variants = describe_variants(flag.get("filters"))
    if variants:
        print(f"variants: {variants}")
    if flag.get("last_called_at"):
        print(f"last evaluated: {fmt_date(flag['last_called_at'], age=True)}")
    if flag.get("tags"):
        print(f"tags: {', '.join(flag['tags'])}")
    print(flag.get("_posthogUrl", ""))


def show_many(flags: list[dict], args) -> None:
    """One table for a batch, read back from the definition endpoint.

    A single flag still gets the detailed view. Counts come from one grouped
    query rather than one per flag.
    """
    if not flags:
        return
    if len(flags) == 1:
        show_one(flags[0]["id"], flags[0]["key"], args)
        return
    with spinner(f"reading {len(flags)} flags"), ThreadPoolExecutor(
        max_workers=8
    ) as pool:
        counts = pool.submit(fetch_calls, args.days)
        defns = list(pool.map(lambda f: fetch_definition(f["id"]), flags))
    calls = counts.result()
    for defn in defns:
        defn["calls"] = calls.get(defn["key"], dict(EMPTY_CALLS))
    as_json(defns) if args.json else render(defns, args.days, args.color)


# ---------------------------------------------------------------------- commands


def cmd_list(args) -> None:
    terms = [t.strip() for group in (args.filters or []) for t in group.split(",")]
    terms += [name for name in ("enabled", "disabled") if getattr(args, name)]
    if args.tag:
        terms.append(f"tag={args.tag}")
    predicates = compile_filters([t for t in terms if t])

    flags = load_all(args.days, args.archived or any("archived" in t for t in terms))
    if args.search:
        needle = args.search.lower()
        flags = [
            f
            for f in flags
            if needle in f["key"].lower() or needle in (f.get("name") or "").lower()
        ]
    flags = [f for f in flags if all(match(f) for match in predicates)]

    oldest = datetime.min.replace(tzinfo=timezone.utc)
    keys = {
        "name": lambda f: f["key"],
        "created": lambda f: parse_ts(f.get("created_at")) or oldest,
        "changed": lambda f: parse_ts(f.get("updated_at")) or oldest,
        "rollout": rollout_of,
        "requests": lambda f: f["calls"]["n_off"] + f["calls"]["n_on"],
    }
    flags.sort(key=keys[args.sort], reverse=args.sort != "name")
    as_json(flags) if args.json else render(flags, args.days, args.color)


def cmd_status(args) -> None:
    show_many(resolve_many(args.flag), args)


def cmd_toggle(args) -> None:
    want = args.command == "enable"
    verb = "enabled" if want else "disabled"
    plan, blocked = [], []
    for flag in resolve_many(args.flag):
        with spinner(f"reading {flag['key']}"):
            defn = fetch_definition(flag["id"])
        if want and defn.get("archived"):
            blocked.append(
                f"{defn['key']} is archived. Unarchive it in PostHog before enabling."
            )
        elif defn["active"] == want:
            print(f"{defn['key']} is already {verb}.")
        else:
            print(f"{defn['key']}: {'disabled -> ' if want else 'enabled -> '}{verb}")
            plan.append(flag)
    if blocked:
        raise SystemExit("\n".join(blocked))
    if not plan or args.dry_run:
        if plan:
            print("dry run, nothing was written.")
        return
    with spinner(f"writing {len(plan)} flags"):
        for flag in plan:
            run_tool("update-feature-flag", {"id": flag["id"], "active": want})
    show_many(plan, args)


ARCHIVED_PREFIX = "[archived] "


def archive_changes(defn: dict) -> tuple[dict, list[str]]:
    """The fields still needing a write to leave this flag fully archived.

    Archived state lives in three places that can disagree: PostHog's own
    `archived` field, the `active` switch it requires, and the description
    prefix the HogQL views read because they cannot see `archived`. Each is
    written only when it is wrong, so a repeat run is a no-op and a partly
    archived flag gets just the missing piece.
    """
    payload: dict = {}
    notes: list[str] = []
    if defn["active"]:
        payload["active"] = False
        notes.append("disable")
    if not defn.get("archived"):
        payload["archived"] = True
        notes.append("archive")
    name = defn.get("name") or ""
    if not name.startswith(ARCHIVED_PREFIX):
        payload["name"] = ARCHIVED_PREFIX + name
        notes.append("prefix the description")
    return payload, notes


def cmd_archive(args) -> None:
    plan: list[tuple[dict, dict]] = []
    for flag in resolve_many(args.flag):
        with spinner(f"reading {flag['key']}"):
            defn = fetch_definition(flag["id"])
        payload, notes = archive_changes(defn)
        if not payload:
            print(f"{defn['key']} is already archived.")
            continue
        print(f"{defn['key']}: {', '.join(notes)}")
        plan.append((flag, payload))
    if not plan:
        return

    disabling = [flag["key"] for flag, payload in plan if "active" in payload]
    if disabling and not args.force:
        serving = {
            key: n
            for key, n in recent_evaluations(disabling, args.since).items()
            if n
        }
        if serving:
            listing = "\n  ".join(f"{k}: {n:,}" for k, n in serving.items())
            raise SystemExit(
                "Archiving disables the flag, so a caller that evaluated it in "
                f"the last {args.since}h would fall through to its off branch:\n  "
                f"{listing}\n"
                "Wait for the retirement to deploy, or pass --force."
            )
    if args.dry_run:
        print("dry run, nothing was written.")
        return
    with spinner(f"writing {len(plan)} flags"):
        for flag, payload in plan:
            run_tool("update-feature-flag", {"id": flag["id"], **payload})
    show_many([flag for flag, _ in plan], args)


def planned_filters(defn: dict, args) -> dict:
    """The flag's release conditions with the requested rollout applied."""
    filters = copy.deepcopy(defn.get("filters") or {})
    groups = filters.get("groups") or []

    if not groups:
        groups = [{"properties": [], "rollout_percentage": args.percent}]
    elif len(groups) == 1 or args.all_groups:
        for group in groups:
            group["rollout_percentage"] = args.percent
    elif args.group is None:
        listing = "\n  ".join(
            f"{i + 1}: {describe_rollout({'groups': [g]})}"
            f"{' with property filters' if g.get('properties') else ''}"
            for i, g in enumerate(groups)
        )
        raise SystemExit(
            f"{defn['key']} has {len(groups)} release conditions. "
            f"Pick one with --group, or use --all-groups:\n  {listing}"
        )
    else:
        if not 1 <= args.group <= len(groups):
            raise SystemExit(
                f"--group must be between 1 and {len(groups)} for {defn['key']}."
            )
        groups[args.group - 1]["rollout_percentage"] = args.percent
    filters["groups"] = groups
    return filters


def cmd_rollout(args) -> None:
    if not 0 <= args.percent <= 100:
        raise SystemExit("Rollout must be between 0 and 100.")
    plan, dormant = [], []
    for flag in resolve_many(args.flag):
        with spinner(f"reading {flag['key']}"):
            defn = fetch_definition(flag["id"])
        filters = planned_filters(defn, args)
        before, after = describe_rollout(defn.get("filters")), describe_rollout(filters)
        if before == after:
            print(f"{defn['key']} is already at {after}.")
            continue
        print(f"{defn['key']}: rollout {before} -> {after}")
        plan.append((flag, filters))
        if not defn["active"]:
            dormant.append(defn["key"])
    if not plan or args.dry_run:
        if plan:
            print("dry run, nothing was written.")
        return
    with spinner(f"writing {len(plan)} flags"):
        for flag, filters in plan:
            run_tool("update-feature-flag", {"id": flag["id"], "filters": filters})
    if dormant:
        tool = os.path.basename(sys.argv[0])
        print(
            f"\nNote: {len(dormant)} of these are disabled, so the rollout has no "
            f"effect until you run `{tool} {' '.join(dormant)} enable`."
        )
    show_many([flag for flag, _ in plan], args)


# ------------------------------------------------------------------------ parsing


COMMANDS = {
    "list",
    "ls",
    "status",
    "enable",
    "disable",
    "archive",
    "set",
    "rollout",
}


def normalize(argv: list[str]) -> list[str]:
    """Accept the flag-first grammar: `<flag>... enable` -> `enable <flag>...`.

    `set` is both a synonym for `rollout` and filler in front of it, so
    `a b set rollout 100`, `set a b rollout 100` and `rollout a b 100` agree.
    """
    if not argv or argv[0].startswith("-"):
        return argv
    at = next((i for i, arg in enumerate(argv) if arg in COMMANDS), None)
    if at is None:
        return ["status", *argv]
    command, flags, rest = argv[at], argv[:at], argv[at + 1 :]
    if command == "set":
        command = "rollout"
        if at == 0 and len(rest) > 1 and rest[-2] == "rollout":
            rest = [*rest[:-2], rest[-1]]
        elif rest and rest[0] == "rollout":
            rest = rest[1:]
    return [command, *flags, *rest]


def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument(
        "--days", type=int, default=30, help="request-count window (default 30)"
    )
    common.add_argument("--json", action="store_true", help="emit JSON instead of a table")
    common.add_argument("--no-color", dest="color", action="store_false", default=None)

    write = argparse.ArgumentParser(add_help=False)
    write.add_argument(
        "--dry-run", action="store_true", help="print the change without writing it"
    )

    parser = argparse.ArgumentParser(
        prog="feature-flags.py",
        description="Inspect and change PostHog feature flags.",
        epilog=(
            "examples:\n"
            "  feature-flags.py                        every flag, newest change first\n"
            "  feature-flags.py swe-10519              status of the one flag matching it\n"
            "  feature-flags.py my-flag enable\n"
            "  feature-flags.py my-flag set rollout 50\n"
            "  feature-flags.py my-flag archive           once the code is deployed\n"
            "  feature-flags.py one two three enable      several at once\n"
            "  feature-flags.py rollout one two 100       command-first form\n"
            "\n"
            f"{filter_help()}\n"
            "\n"
            "Flag names match on the full key, or on any unique substring of it."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    subs = parser.add_subparsers(dest="command")

    listing = subs.add_parser(
        "list",
        aliases=["ls"],
        parents=[common],
        help="table of every flag",
        epilog=filter_help(),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    listing.add_argument("search", nargs="?", help="match against key and description")
    listing.add_argument(
        "-f",
        "--filters",
        action="append",
        metavar="EXPR[,EXPR...]",
        help="comma-separated filters, all of which must hold; fields listed below",
    )
    listing.add_argument("--tag", help="shorthand for --filters tag=TAG")
    listing.add_argument("--enabled", action="store_true", help="shorthand filter")
    listing.add_argument("--disabled", action="store_true", help="shorthand filter")
    listing.add_argument("--archived", action="store_true", help="include archived flags")
    listing.add_argument(
        "--sort",
        choices=["changed", "created", "name", "rollout", "requests"],
        default="changed",
    )
    listing.set_defaults(func=cmd_list)

    status = subs.add_parser("status", parents=[common], help="one row per flag")
    status.add_argument("flag", nargs="+")
    status.set_defaults(func=cmd_status)

    for verb in ("enable", "disable"):
        toggle = subs.add_parser(verb, parents=[common, write], help=f"{verb} flags")
        toggle.add_argument("flag", nargs="+")
        toggle.set_defaults(func=cmd_toggle)

    arch = subs.add_parser(
        "archive",
        parents=[common, write],
        help="disable, archive, and prefix the description",
    )
    arch.add_argument("flag", nargs="+")
    arch.add_argument(
        "--since",
        type=int,
        default=6,
        metavar="HOURS",
        help="evaluation window checked before disabling (default 6)",
    )
    arch.add_argument(
        "--force",
        action="store_true",
        help="archive even while callers still evaluate the flag",
    )
    arch.set_defaults(func=cmd_archive)

    roll = subs.add_parser(
        "rollout", parents=[common, write], help="set the rollout percentage"
    )
    roll.add_argument("flag", nargs="+")
    roll.add_argument("percent", type=lambda v: int(v.rstrip("%")))
    roll.add_argument("--group", type=int, help="1-based release condition to change")
    roll.add_argument("--all-groups", action="store_true")
    roll.set_defaults(func=cmd_rollout)

    return parser


def main() -> int:
    parser = build_parser()
    argv = normalize(sys.argv[1:])
    args = parser.parse_args(argv or ["list"])
    if args.color is None:
        args.color = sys.stdout.isatty() and os.environ.get("NO_COLOR") is None
    if getattr(args, "command", None) in ("ls", None):
        args.command = "list"
    try:
        args.func(args)
    except ToolError as error:
        print(error, file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
