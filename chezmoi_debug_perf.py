#!/usr/bin/env python3
"""Parse chezmoi --debug log output and identify performance bottlenecks."""

import re
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path


def parse_line(line: str) -> dict | None:
    # time=2026-03-08T15:32:59.292+01:00 level=INFO msg=Stat component=system name=/home/...
    m = re.match(r"time=(\S+)\s+level=(\w+)\s+msg=(\S+)\s*(.*)", line.strip())
    if not m:
        return None

    timestamp_str, level, msg, rest = m.groups()

    # Parse timestamp - handle timezone offset like +01:00
    # Python's %z needs +0100 not +01:00 in older versions, so use fromisoformat
    try:
        ts = datetime.fromisoformat(timestamp_str)
    except ValueError:
        return None

    # Parse key=value pairs from rest, handling quoted values
    attrs = {}
    for km in re.finditer(r'(\w+)=(?:"((?:[^"\\]|\\.)*)"|(\S+))', rest):
        key = km.group(1)
        val = km.group(2) if km.group(2) is not None else km.group(3)
        attrs[key] = val

    return {
        "timestamp": ts,
        "level": level,
        "msg": msg,
        "attrs": attrs,
        "raw": line.strip(),
    }


def analyze(lines: list[dict]) -> None:
    if not lines:
        print("No log lines parsed.")
        return

    # Total time
    t_start = lines[0]["timestamp"]
    t_end = lines[-1]["timestamp"]
    total_ms = (t_end - t_start).total_seconds() * 1000

    print("=" * 70)
    print("CHEZMOI DEBUG LOG ANALYSIS")
    print("=" * 70)
    print(f"Total log lines:  {len(lines)}")
    print(f"Time span:        {total_ms:.1f} ms")
    print(f"First timestamp:  {t_start.isoformat()}")
    print(f"Last timestamp:   {t_end.isoformat()}")
    print()

    # --- Top gaps between consecutive lines ---
    gaps = []
    for i in range(1, len(lines)):
        dt = (lines[i]["timestamp"] - lines[i - 1]["timestamp"]).total_seconds() * 1000
        gaps.append((dt, i - 1, i))

    gaps.sort(reverse=True)

    print("-" * 70)
    print("TOP 20 LARGEST GAPS BETWEEN CONSECUTIVE LINES")
    print("-" * 70)
    for dt, i_before, i_after in gaps[:20]:
        if dt < 0.5:
            break
        before = lines[i_before]
        after = lines[i_after]
        b_name = before["attrs"].get("name", "")
        a_name = after["attrs"].get("name", "")
        print(f"\n  {dt:8.1f} ms  (line {i_before + 1} → {i_after + 1})")
        print(f"    BEFORE: {before['msg']:20s} {b_name}")
        print(f"    AFTER:  {after['msg']:20s} {a_name}")

    print()

    # --- Time by operation type ---
    print("-" * 70)
    print("TIME BY OPERATION (msg)")
    print("-" * 70)

    op_times = defaultdict(lambda: {"total_ms": 0.0, "count": 0, "max_ms": 0.0, "max_name": ""})

    for dt, i_before, _ in gaps:
        op = lines[i_before]["msg"]
        name = lines[i_before]["attrs"].get("name", "")
        entry = op_times[op]
        entry["total_ms"] += dt
        entry["count"] += 1
        if dt > entry["max_ms"]:
            entry["max_ms"] = dt
            entry["max_name"] = name

    for op, data in sorted(op_times.items(), key=lambda x: -x[1]["total_ms"]):
        if data["total_ms"] < 0.5:
            continue
        print(
            f"  {op:30s}  total={data['total_ms']:8.1f} ms  "
            f"count={data['count']:5d}  avg={data['total_ms'] / data['count']:6.2f} ms  "
            f"max={data['max_ms']:8.1f} ms"
        )
        if data["max_ms"] > 5:
            print(f"    max at: {data['max_name']}")

    print()

    # --- Time by directory (group by parent dir of 'name') ---
    print("-" * 70)
    print("TIME BY DIRECTORY (top 20)")
    print("-" * 70)

    dir_times = defaultdict(lambda: {"total_ms": 0.0, "count": 0})

    for dt, i_before, _ in gaps:
        name = lines[i_before]["attrs"].get("name", "")
        if name:
            parent = str(Path(name).parent)
            dir_times[parent]["total_ms"] += dt
            dir_times[parent]["count"] += 1

    for d, data in sorted(dir_times.items(), key=lambda x: -x[1]["total_ms"])[:20]:
        if data["total_ms"] < 0.5:
            break
        print(f"  {data['total_ms']:8.1f} ms  ({data['count']:4d} ops)  {d}")

    print()

    # --- Slow individual files (top 20) ---
    print("-" * 70)
    print("SLOWEST INDIVIDUAL FILES (top 20)")
    print("-" * 70)

    file_times = defaultdict(lambda: {"total_ms": 0.0, "count": 0})

    for dt, i_before, _ in gaps:
        name = lines[i_before]["attrs"].get("name", "")
        if name:
            file_times[name]["total_ms"] += dt
            file_times[name]["count"] += 1

    for f, data in sorted(file_times.items(), key=lambda x: -x[1]["total_ms"])[:20]:
        if data["total_ms"] < 0.5:
            break
        print(f"  {data['total_ms']:8.1f} ms  ({data['count']:3d} ops)  {f}")

    print()

    # --- Error summary ---
    errors = [l for l in lines if l["level"] == "ERROR"]
    if errors:
        print("-" * 70)
        print(f"ERRORS ({len(errors)})")
        print("-" * 70)
        err_msgs = defaultdict(int)
        for e in errors:
            err_text = e["attrs"].get("err", e["msg"])
            err_msgs[err_text] += 1
        for msg, count in sorted(err_msgs.items(), key=lambda x: -x[1]):
            print(f"  {count:4d}x  {msg}")
        print()

    # --- Lines with no timestamp gap (potential CPU-bound blocks) ---
    print("-" * 70)
    print("DENSE REGIONS (many ops in <1ms, suggests CPU-bound work)")
    print("-" * 70)

    window = 50
    for start in range(0, len(lines) - window, window // 2):
        end = min(start + window, len(lines) - 1)
        span = (lines[end]["timestamp"] - lines[start]["timestamp"]).total_seconds() * 1000
        if span < 1 and end - start >= window:
            print(
                f"  Lines {start + 1}-{end + 1}: {end - start} ops in {span:.1f} ms"
                f"  ({lines[start]['msg']} ... {lines[end]['msg']})"
            )


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <chezmoi-debug.log>")
        print(f"       cm status --debug --verbose 2>debug.log && {sys.argv[0]} debug.log")
        sys.exit(1)

    log_path = sys.argv[1]
    with open(log_path) as f:
        raw_lines = f.readlines()

    lines = []
    for raw in raw_lines:
        parsed = parse_line(raw)
        if parsed:
            lines.append(parsed)

    if not lines:
        print(f"No parseable log lines in {log_path}")
        sys.exit(1)

    analyze(lines)


if __name__ == "__main__":
    main()
