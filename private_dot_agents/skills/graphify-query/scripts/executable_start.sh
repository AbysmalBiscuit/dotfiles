#!/usr/bin/env bash
# Open a graph session: which graph answers queries here, what it holds, how far
# behind the code it is, and what earlier sessions recorded about it.
set -euo pipefail

# GRAPHIFY_GRAPH pins a graph explicitly; otherwise the nearest graphify-out/
# walking up from the current directory wins, so a subdirectory still finds the
# project graph.
graph="${GRAPHIFY_GRAPH:-}"
if [ -z "$graph" ]; then
    dir=$PWD
    while [ "$dir" != / ]; do
        if [ -f "$dir/graphify-out/graph.json" ]; then
            graph="$dir/graphify-out/graph.json"
            break
        fi
        dir=$(dirname "$dir")
    done
fi

if [ -z "$graph" ] || [ ! -f "$graph" ]; then
    echo "no graph found from $PWD upward" >&2
    echo "build one over code with:  graphify update ." >&2
    echo "build one over any corpus: run the graphify skill's full pipeline" >&2
    exit 1
fi

root=$(dirname "$(dirname "$graph")")
echo "run every graphify command from: $root"
echo "graph: $graph"

# One load answers both what the graph holds and when it was built. The BUILT_AT
# line is consumed below rather than printed.
summary=$(python3 - "$graph" <<'PY'
import collections, json, sys

with open(sys.argv[1]) as fh:
    g = json.load(fh)

nodes, links = g.get("nodes", []), g.get("links", [])
kinds = collections.Counter(n.get("file_type") or "?" for n in nodes)
rels = collections.Counter(l.get("relation") or "?" for l in links)
inferred = sum(1 for l in links if l.get("confidence") == "INFERRED")

print(f"holds: {len(nodes)} nodes ({', '.join(f'{n} {k}' for k, n in kinds.most_common(4))})"
      f", {len(links)} edges, {inferred} of them INFERRED")
print("relations: " + ", ".join(f"{r} {n}" for r, n in rels.most_common(6)))
print("BUILT_AT " + str(g.get("built_at_commit") or ""))
PY
)
echo "$summary" | grep -v '^BUILT_AT '
built=${summary##*BUILT_AT }

# Freshness in commits and files beats an mtime: it names what the graph has not
# seen yet.
if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    head=$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo unknown)
    if [ -n "$built" ] && git -C "$root" cat-file -e "${built}^{commit}" 2>/dev/null; then
        behind=$(git -C "$root" rev-list --count "$built"..HEAD 2>/dev/null || echo "?")
        changed=$(git -C "$root" diff --name-only "$built"..HEAD 2>/dev/null | wc -l)
        dirty=$(git -C "$root" status --porcelain 2>/dev/null | wc -l)
        echo "freshness: HEAD $head is $behind commits and $changed files past the build, $dirty uncommitted"
    else
        mtime=$(stat -c %Y "$graph" 2>/dev/null || stat -f %m "$graph")
        echo "freshness: HEAD $head; the graph names no reachable build commit, file is $(( ($(date +%s) - mtime) / 3600 ))h old"
    fi
    case "$(graphify hook status 2>/dev/null | head -1 || true)" in
        *"not installed"*) echo "rebuilds: by hand, with graphify update $root; git hooks are not installed here" ;;
        "") echo "rebuilds: by hand, with graphify update $root; hook status unavailable" ;;
        *) echo "rebuilds: git hooks installed, so commits refresh the graph" ;;
    esac
else
    mtime=$(stat -c %Y "$graph" 2>/dev/null || stat -f %m "$graph")
    echo "freshness: not a git checkout; the graph file is $(( ($(date +%s) - mtime) / 3600 ))h old"
fi

lessons="$root/graphify-out/reflections/LESSONS.md"
echo
if [ -f "$lessons" ]; then
    cat "$lessons"
else
    echo "no lessons recorded yet; the first graphify save-result plus reflect writes one"
fi
