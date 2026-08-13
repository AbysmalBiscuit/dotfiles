#!/bin/sh
''':'
# sh/python polyglot: sh runs this block and execs the first working
# interpreter; python parses it as a harmless string. The -c '' probe
# rejects Windows' fake Microsoft Store python stubs, which resolve on
# PATH but only open the Store.
for py in python3 python; do
    "$py" -c '' >/dev/null 2>&1 && exec "$py" "$0" "$@"
done
command -v uv >/dev/null 2>&1 && exec uv run --no-project --script "$0" "$@"
echo "statusline-cost.py: no python interpreter found" >&2
exit 127
':'''
"""Fleet-wide agent cost statusline for ccstatusline custom-command widgets.

  default: read Claude Code statusline JSON on stdin, print
           S D W M Y L (session/today/week/month/year/lifetime, USD).
  refresh [session_id] [stdin_cost]: synchronously merge ccusage rows into
           this machine's synced ledger, then aggregate every machine's
           ledger into the local render cache.
  report:  per-agent and per-machine breakdown tables.

D/W/M/Y/L cover ALL machines (usage-*.json in the sync dir) and ALL agents
ccusage detects. Ledgers are merge ledgers keyed by (date, agent), max on
conflict -- deleting an agent's local logs never erases fleet history.
"""

import json
import math
import os
import shutil
import socket
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path


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

MACHINE_ID = os.environ.get("COST_MACHINE_ID") or f"{socket.gethostname().lower()}-{FLAVOR}"
CACHE_DIR = Path(os.environ.get("COST_CACHE_DIR") or Path.home() / ".claude" / "statusline-cache")
CACHE_FILE = CACHE_DIR / "cost.json"
USAGE_FILE = SYNC_DIR / f"usage-{MACHINE_ID}.json"
COLLECTORS_DIR = Path(
    os.environ.get("COST_COLLECTORS_DIR") or Path.home() / ".claude" / "cost-collectors"
)
LOCK = CACHE_DIR / "refresh.lock"
try:
    TTL = int(os.environ.get("COST_TTL", "60"))
except ValueError:
    TTL = 60
TODAY = os.environ.get("COST_TODAY") or time.strftime("%Y-%m-%d")
SEP = " │ "
LABELS = ["S", "D", "W", "M", "Y", "L"]

if os.environ.get("COST_CCUSAGE_BIN"):
    CCUSAGE = [os.environ["COST_CCUSAGE_BIN"]]
elif shutil.which("ccusage"):
    CCUSAGE = ["ccusage"]
elif shutil.which("bunx"):
    CCUSAGE = ["bunx", "ccusage@latest"]
else:
    CCUSAGE = ["npx", "-y", "ccusage@latest"]

# Monday-based week; boundaries derived from TODAY so tests can pin the date.
_today = datetime.strptime(TODAY, "%Y-%m-%d")
WEEK_START = (_today - timedelta(days=_today.weekday())).strftime("%Y-%m-%d")
MONTH_START = TODAY[:8] + "01"
YEAR_START = TODAY[:4] + "-01-01"


# Resolved via PATH: on Windows a bare "bash" in subprocess would hit
# CreateProcess's search order, where System32's WSL bash.exe shadows
# Git Bash even though PATH says otherwise.
BASH = shutil.which("bash") or "bash"


def run_out(args):
    """Run a command through bash so shebang scripts and PATH shims resolve
    identically on Git Bash (Windows) and POSIX. Bash is always present:
    it is what launches this script. Failures return whatever stdout the
    command produced, like `cmd || true`."""
    try:
        r = subprocess.run(
            [BASH, "-c", '"$0" "$@"', *[str(a) for a in args]],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
        )
    except OSError:
        return ""
    return r.stdout or ""


def load_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def is_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def normalize(cost):
    """Whole floats become ints so ledger costs serialize as 2, not 2.0."""
    if isinstance(cost, float) and cost.is_integer():
        return int(cost)
    return cost


def atomic_write(target, content):
    tmp = target.with_name(f"{target.name}.tmp.{os.getpid()}")
    try:
        tmp.write_text(content, encoding="utf-8")
        # Replace can transiently fail on NTFS while the Nextcloud client
        # holds the target open; skip this cycle, the next refresh retries.
        os.replace(tmp, target)
    except OSError:
        try:
            tmp.unlink()
        except OSError:
            pass
        return False
    return True


def acquire_lock():
    try:
        LOCK.mkdir()
        return True
    except FileExistsError:
        pass
    except OSError:
        return False
    try:
        age = time.time() - LOCK.stat().st_mtime
    except OSError:
        age = 0
    if age > 300:  # crashed holder; break the lock
        try:
            LOCK.rmdir()
            LOCK.mkdir()
            return True
        except OSError:
            pass
    return False


def release_lock():
    try:
        LOCK.rmdir()
    except OSError:
        pass


def collect_rows():
    """All (date, agent, cost) rows ccusage + collectors can currently see."""
    rows = []
    dump = run_out(CCUSAGE + ["daily", "--json", "--by-agent"])
    if dump.strip():
        try:
            daily = json.loads(dump).get("daily")
        except (ValueError, AttributeError):
            daily = None
        for day in daily if isinstance(daily, list) else []:
            if not isinstance(day, dict):
                continue
            agents = day.get("agents")
            if agents is None:
                agents = [{"agent": "all", "totalCost": day.get("totalCost")}]
            if not isinstance(agents, list):
                continue
            for a in agents:
                if isinstance(a, dict):
                    rows.append(
                        {"date": day.get("period"), "agent": a.get("agent"),
                         "cost": a.get("totalCost")}
                    )
    if COLLECTORS_DIR.is_dir():
        for c in sorted(COLLECTORS_DIR.iterdir()):
            if not (c.is_file() and os.access(c, os.X_OK)):
                continue
            out = run_out([c])
            if not out.strip():
                continue
            try:
                extra = json.loads(out)
            except ValueError:
                continue
            if isinstance(extra, list):
                rows.extend(e for e in extra if isinstance(e, dict))
    return rows


def merged_ledger(new_rows):
    """Merge new rows into the existing ledger: keys are (date, agent), value
    is max(old, new) -- costs only legitimately grow, so a lower value means
    source logs were deleted and the ledger keeps the truth. Keys missing from
    the new rows are kept; empty new rows are a no-op on content."""
    existing = load_json(USAGE_FILE)
    old_rows = existing.get("rows") if isinstance(existing, dict) else None
    if not isinstance(old_rows, list):
        old_rows = []
    best = {}
    for r in old_rows + list(new_rows):
        if not isinstance(r, dict) or not is_number(r.get("cost")):
            continue
        try:
            key = (r.get("date"), r.get("agent"))
            if key not in best or r["cost"] > best[key]:
                best[key] = r["cost"]
        except TypeError:  # unhashable date/agent in a corrupt row
            continue
    merged = [
        {"date": d, "agent": a, "cost": normalize(c)} for (d, a), c in best.items()
    ]
    merged.sort(key=lambda r: (str(r["date"]), str(r["agent"])))
    return {
        "machine": MACHINE_ID,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "rows": merged,
    }


def ledger_files():
    try:
        files = sorted(SYNC_DIR.glob("usage-*.json"))
    except OSError:
        return []
    # Nextcloud conflict copies are never our writes; skip them.
    return [f for f in files if "conflict" not in f.name.lower()]


def all_rows():
    """Concatenated rows from every machine's ledger. Skips anything that
    doesn't parse -- one bad machine never breaks the fleet."""
    rows = []
    for f in ledger_files():
        data = load_json(f)
        if isinstance(data, dict) and isinstance(data.get("rows"), list):
            rows.extend(r for r in data["rows"] if isinstance(r, dict))
    return rows


def cost_sum(rows, pred):
    return sum(r["cost"] for r in rows if is_number(r.get("cost")) and pred(r))


def date_ge(start):
    return lambda r: isinstance(r.get("date"), str) and r["date"] >= start


def slot_sums(rows):
    return [
        cost_sum(rows, lambda r: r.get("date") == TODAY),
        cost_sum(rows, date_ge(WEEK_START)),
        cost_sum(rows, date_ge(MONTH_START)),
        cost_sum(rows, date_ge(YEAR_START)),
        cost_sum(rows, lambda r: True),
    ]


def write_cache(session_id, session_cost, stdin_cost):
    d, w, m, y, l = slot_sums(all_rows())
    cache = {
        "d": d, "w": w, "m": m, "y": y, "l": l,
        "sessionId": session_id,
        "sessionCost": session_cost,
        "stdinAtRefresh": stdin_cost,
    }
    return atomic_write(CACHE_FILE, json.dumps(cache))


def refresh(session_id="", stdin_cost=0.0):
    # Dirs first: the lock lives inside CACHE_DIR, so it must exist to lock.
    for d in (SYNC_DIR, CACHE_DIR):
        try:
            d.mkdir(parents=True, exist_ok=True)
        except OSError:
            pass
    if not acquire_lock():
        return
    try:
        atomic_write(USAGE_FILE, json.dumps(merged_ledger(collect_rows())))
        sess = 0.0
        if session_id:
            try:
                entries = json.loads(run_out(CCUSAGE + ["session", "--json"])).get("session")
            except (ValueError, AttributeError):
                entries = None
            for e in entries if isinstance(entries, list) else []:
                if (isinstance(e, dict) and e.get("period") == session_id
                        and is_number(e.get("totalCost"))):
                    sess += e["totalCost"]
        # A zero transcript cost means the session wasn't found; cache no id
        # so render falls back to the plain stdin counter.
        sid = session_id if session_id and sess > 0 else ""
        write_cache(sid, sess, stdin_cost)
    finally:
        release_lock()


def spawn_refresh(session_id, stdin_cost):
    cmd = [sys.executable, str(Path(__file__).resolve()), "refresh",
           session_id, str(stdin_cost)]
    kwargs = {"stdin": subprocess.DEVNULL, "stdout": subprocess.DEVNULL,
              "stderr": subprocess.DEVNULL}
    if os.name == "nt":
        # CREATE_NO_WINDOW, not DETACHED_PROCESS: a detached process has no
        # console, so its console children (bash, ccusage) each force Windows
        # to allocate a new one -- popping a visible terminal window per
        # refresh. A hidden console is inherited by the whole child tree.
        kwargs["creationflags"] = subprocess.CREATE_NO_WINDOW
    else:
        kwargs["start_new_session"] = True
    try:
        subprocess.Popen(cmd, **kwargs)
    except OSError:
        pass


def money(v):
    a = abs(v)
    sign = "-" if v < 0 else ""
    if a < 1000:
        return f"${sign}{a:.2f}"
    for div, suf in ((1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "k")):
        if a >= div:
            scaled = a / div
            dec = 2 if scaled < 10 else (1 if scaled < 100 else 0)
            return f"${sign}{scaled:.{dec}f}{suf}"


def render():
    try:
        blob = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace"))
    except ValueError:
        blob = {}
    if not isinstance(blob, dict):
        blob = {}
    cost = blob.get("cost")
    sc = cost.get("total_cost_usd") if isinstance(cost, dict) else None
    if not is_number(sc):
        sc = 0.0
    sid = blob.get("session_id")
    if not isinstance(sid, str):
        sid = ""

    if not CACHE_FILE.is_file():
        refresh(sid, sc)  # first run: fill synchronously
    else:
        try:
            stale = time.time() - CACHE_FILE.stat().st_mtime >= TTL
        except OSError:
            stale = False
        if stale:
            spawn_refresh(sid, sc)

    cache = load_json(CACHE_FILE)
    vals = [sc, 0, 0, 0, 0, 0]
    if isinstance(cache, dict):
        def n(k):
            v = cache.get(k)
            return v if is_number(v) else 0
        s = sc
        if sid and cache.get("sessionId") == sid:
            s = n("sessionCost") + max(sc - n("stdinAtRefresh"), 0)
        vals = [s, n("d"), n("w"), n("m"), n("y"), n("l")]
    print(SEP.join(f"{lb} {money(v)}" for lb, v in zip(LABELS, vals)))


def fmt2(v):
    cents = math.floor(abs(v) * 100 + 0.5)  # round half away from zero
    return f"{'-' if v < 0 else ''}{cents / 100:.2f}"


def print_table(table):
    widths = [max(len(c) for c in col) for col in zip(*table)]
    for cells in table:
        print("  ".join(c.ljust(w) for c, w in zip(cells, widths)).rstrip())


def report():
    rows = all_rows()
    agents = sorted(
        {r.get("agent") for r in rows},
        key=lambda a: (a is not None, a if isinstance(a, str) else str(a)),
    )
    table = [["AGENT", "D", "W", "M", "Y", "L"]]
    for agent in agents:
        sums = slot_sums([r for r in rows if r.get("agent") == agent])
        table.append([str(agent)] + [fmt2(v) for v in sums])
    print_table(table)
    print()
    table = [["MACHINE", "D", "W", "M", "Y", "L", "UPDATED"]]
    for f in ledger_files():
        data = load_json(f)
        if not isinstance(data, dict):
            continue
        mrows = data.get("rows")
        sums = slot_sums(
            [r for r in mrows if isinstance(r, dict)] if isinstance(mrows, list) else []
        )
        table.append(
            [str(data.get("machine") or "?")]
            + [fmt2(v) for v in sums]
            + [str(data.get("generatedAt") or "?")]
        )
    print_table(table)


def main(argv):
    mode = argv[1] if len(argv) > 1 else "render"
    if mode == "refresh":
        sid = argv[2] if len(argv) > 2 else ""
        try:
            sc = float(argv[3]) if len(argv) > 3 else 0.0
        except ValueError:
            sc = 0.0
        refresh(sid, sc)
    elif mode == "report":
        report()
    elif mode == "render":
        render()


if __name__ == "__main__":
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, OSError):
            pass
    main(sys.argv)
