#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["plotext>=5.3,<6"]
# ///
"""Bar charts of fleet-wide agent cost, bucketed by day, month, or year.

Reads the same synced merge ledgers that statusline-cost.py writes:
usage-*.json in the Nextcloud sync dir, one per machine, each a list of
(date, agent, cost) rows. Every machine and every agent is included.

  agent-cost-chart.py                 last 30 days
  agent-cost-chart.py months          last 12 months
  agent-cost-chart.py years           every year on record
  agent-cost-chart.py days --by agent --limit 14

The ledger reader is deliberately a copy of statusline-cost.py's rather than
an import: this script lives on PATH in ~/.local/bin, so importing would
hardcode a path into ~/.claude.
"""

import argparse
import json
import os
import re
import shutil
import sys
from datetime import datetime, timedelta
from pathlib import Path

import plotext as plt

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
BAR_COLOR = "cyan"
STACK_COLORS = ["cyan", "orange", "green", "magenta", "blue", "red", "gray"]


def flavor():
    if os.name == "nt":
        return "windows"
    try:
        if "microsoft" in Path("/proc/version").read_text().lower():
            return "wsl"
    except OSError:
        pass
    return "linux"


FLAVOR = flavor()
if os.environ.get("AGENT_COST_SYNC_DIR"):
    SYNC_DIR = Path(os.environ["AGENT_COST_SYNC_DIR"])
elif FLAVOR == "wsl":
    SYNC_DIR = Path("/mnt/c/Users/Lev/Nextcloud/claude-usage")
else:
    SYNC_DIR = Path.home() / "Nextcloud" / "claude-usage"


def load_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def is_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def ledger_files():
    try:
        files = sorted(SYNC_DIR.glob("usage-*.json"))
    except OSError:
        return []
    # Nextcloud conflict copies duplicate rows; skip them.
    return [f for f in files if "conflict" not in f.name.lower()]


def all_rows():
    """Every ledger row, tagged with the machine that reported it. Anything
    that doesn't parse is skipped -- one bad machine never breaks the fleet."""
    rows = []
    for f in ledger_files():
        data = load_json(f)
        if not isinstance(data, dict) or not isinstance(data.get("rows"), list):
            continue
        machine = str(data.get("machine") or f.stem.replace("usage-", "", 1))
        for r in data["rows"]:
            if not isinstance(r, dict) or not is_number(r.get("cost")):
                continue
            if not (isinstance(r.get("date"), str) and DATE_RE.match(r["date"])):
                continue
            rows.append(
                {
                    "date": r["date"],
                    "agent": str(r.get("agent") or "?"),
                    "machine": machine,
                    "cost": float(r["cost"]),
                }
            )
    return rows


def day_keys(first, last):
    d = datetime.strptime(first, "%Y-%m-%d")
    end = datetime.strptime(last, "%Y-%m-%d")
    while d <= end:
        yield d.strftime("%Y-%m-%d")
        d += timedelta(days=1)


def month_keys(first, last):
    y, m = int(first[:4]), int(first[5:7])
    ey, em = int(last[:4]), int(last[5:7])
    while (y, m) <= (ey, em):
        yield f"{y:04d}-{m:02d}"
        m += 1
        if m > 12:
            y, m = y + 1, 1


def year_keys(first, last):
    for y in range(int(first[:4]), int(last[:4]) + 1):
        yield f"{y:04d}"


PERIODS = {
    "days": (10, day_keys, "DAY", 30),
    "months": (7, month_keys, "MONTH", 12),
    "years": (4, year_keys, "YEAR", 0),
}


def money(v):
    return f"${v:,.2f}"


def build_chart(labels, series, width, mono):
    plt.clear_figure()
    if len(series) == 1:
        plt.simple_bar(labels, series[0][1], width=width, color=BAR_COLOR)
    else:
        colors = [STACK_COLORS[i % len(STACK_COLORS)] for i in range(len(series))]
        plt.simple_stacked_bar(
            labels,
            [values for _, values in series],
            width=width,
            labels=[name for name, _ in series],
            colors=colors,
        )
    out = plt.build()
    return ANSI_RE.sub("", out) if mono else out


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="agent-cost-chart.py",
        description="Bar charts of fleet-wide agent cost by day, month, or year.",
    )
    ap.add_argument("period", nargs="?", default="days", choices=sorted(PERIODS))
    ap.add_argument(
        "--limit", type=int, metavar="N",
        help="show only the most recent N buckets; 0 for all "
             "(default: 30 days / 12 months / all years)",
    )
    ap.add_argument("--since", metavar="YYYY-MM-DD", help="drop buckets before this date")
    ap.add_argument(
        "--by", choices=("agent", "machine"),
        help="split each bar into stacked segments",
    )
    ap.add_argument("--width", type=int, metavar="N", help="chart width in columns")
    ap.add_argument("--no-color", action="store_true", help="strip ANSI colors")
    args = ap.parse_args(argv)

    if args.since and not DATE_RE.match(args.since):
        ap.error("--since must be YYYY-MM-DD")

    rows = all_rows()
    if not rows:
        print(f"no ledger rows found in {SYNC_DIR}", file=sys.stderr)
        return 1

    keylen, key_range, unit, default_limit = PERIODS[args.period]
    if args.since:
        rows = [r for r in rows if r["date"] >= args.since]
        if not rows:
            print(f"no rows on or after {args.since}", file=sys.stderr)
            return 1

    dates = [r["date"] for r in rows]
    # Gap-fill so idle stretches stay visible instead of collapsing into
    # whatever activity happens to sit next to them.
    labels = list(key_range(min(dates), max(dates)))
    limit = default_limit if args.limit is None else args.limit
    if limit > 0:
        labels = labels[-limit:]
    shown = set(labels)

    categories = [""]
    if args.by:
        totals = {}
        for r in rows:
            if r["date"][:keylen] in shown:
                totals[r[args.by]] = totals.get(r[args.by], 0.0) + r["cost"]
        categories = sorted(totals, key=lambda c: (-totals[c], c))

    index = {label: i for i, label in enumerate(labels)}
    series = [(c or "total", [0.0] * len(labels)) for c in categories]
    slot = {c: i for i, c in enumerate(categories)}
    for r in rows:
        i = index.get(r["date"][:keylen])
        if i is not None:
            series[slot[r[args.by] if args.by else ""]][1][i] += r["cost"]

    totals = [sum(values[i] for _, values in series) for i in range(len(labels))]
    grand = sum(totals)
    width = args.width or max(40, shutil.get_terminal_size((100, 24)).columns - 1)
    mono = args.no_color or not sys.stdout.isatty()

    span = f"{labels[0]} → {labels[-1]}" if len(labels) > 1 else labels[0]
    heading = f"AGENT COST BY {unit} (USD)  {span}"
    if args.by:
        heading += f"  by {args.by}"
    print(heading)
    print(build_chart(labels, series, width, mono), end="")

    peak = max(range(len(labels)), key=lambda i: totals[i])
    print(
        f"TOTAL {money(grand)}   MEAN/{unit} {money(grand / len(labels))}   "
        f"PEAK {labels[peak]} {money(totals[peak])}   {unit}S {len(labels)}"
    )
    return 0


if __name__ == "__main__":
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, OSError):
            pass
    sys.exit(main())
