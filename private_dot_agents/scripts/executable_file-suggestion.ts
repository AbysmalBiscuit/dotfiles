#!/usr/bin/env bun
/**
 * Custom @ file-path autocomplete for Claude Code.
 *
 * Receives {"query": "<typed text>"} on stdin and prints candidate paths, one
 * per line, best first. Gitignored files are included (`--no-ignore-vcs`).
 *
 * Matching is fuzzy: query characters must appear in order, but not
 * contiguously, so `72.md` reaches `ISSUE_72.md` and `plugsettings` reaches
 * `plugins/settings.json`. A `/` in the query only ever matches a real path
 * separator, which keeps `skills/plugin-settings` anchored to that structure.
 *
 * Two matching modes, so both can be lived with and compared:
 *   - default: the query matches anywhere in the path.
 *   - `//` prefix: the segment after the last `/` matches the basename only,
 *     and any part before it must appear literally in the directory portion.
 *     Narrower, and much quieter for short queries.
 *
 * Ranking favours word-boundary and consecutive hits, matches in the basename
 * over matches in directory names, and shallow paths over deep ones, so
 * entries near the working directory surface first.
 *
 * Home- and absolute-rooted queries (`~/.local`, `/etc/ho`, `C:/Users`) are
 * directory navigation instead: one segment inside the named directory, under
 * relaxed ignores so hidden and ignored entries appear. Recursing from `~` or
 * `/` would be far too broad to be useful.
 *
 * `.git` and `node_modules` are excluded unless the query names them.
 */

const MAX_RESULTS = 15;
const SCAN_LIMIT = 60_000;
const SCAN_BUDGET_MS = 250;
const NOISY_DIRS = [".git", "node_modules"];

export type Mode = "path" | "basename";

const WEIGHT = {
  consecutive: 8,
  boundary: 10,
  inBasename: 6,
  basenameStart: 12,
  gap: 1,
  maxGapPenalty: 10,
  depth: 4,
  exactBasename: 200,
  basenamePrefix: 100,
  basenameSubstring: 50,
  length: 0.02,
} as const;

const WORD_BREAKS = new Set(["/", "_", "-", ".", " "]);

function isLower(c: string): boolean {
  return c !== c.toUpperCase() && c === c.toLowerCase();
}

function isUpper(c: string): boolean {
  return c !== c.toLowerCase() && c === c.toUpperCase();
}

function startsWord(hay: string, i: number): boolean {
  if (i === 0) return true;
  const prev = hay[i - 1] as string;
  const cur = hay[i] as string;
  return WORD_BREAKS.has(prev) || (isLower(prev) && isUpper(cur));
}

function sameChar(needle: string, hay: string, caseSensitive: boolean): boolean {
  if (needle === "/") return hay === "/";
  return caseSensitive ? needle === hay : needle.toLowerCase() === hay.toLowerCase();
}

/**
 * Locate `needle` as a subsequence of `hay`, returning one index per needle
 * character, or null when there is no match.
 *
 * A forward scan finds the earliest position at which the needle can complete,
 * then a backward scan from there pulls the matched characters as far right as
 * they will go. Two linear passes rather than a full DP: the tightest window
 * ending at that point, which is close enough to optimal for ranking and cheap
 * enough to run over tens of thousands of paths.
 */
export function findPositions(
  hay: string,
  needle: string,
  caseSensitive: boolean,
): number[] | null {
  if (needle === "") return [];
  let n = 0;
  let end = -1;
  for (let i = 0; i < hay.length; i++) {
    if (sameChar(needle[n] as string, hay[i] as string, caseSensitive)) {
      if (++n === needle.length) {
        end = i;
        break;
      }
    }
  }
  if (end < 0) return null;

  const positions = new Array<number>(needle.length);
  let m = needle.length - 1;
  for (let i = end; i >= 0 && m >= 0; i--) {
    if (sameChar(needle[m] as string, hay[i] as string, caseSensitive)) positions[m--] = i;
  }
  return positions;
}

function scorePositions(hay: string, positions: number[], basenameStart: number): number {
  let total = 0;
  let prev = -2;
  for (const i of positions) {
    total += i === prev + 1 ? WEIGHT.consecutive : 1;
    if (startsWord(hay, i)) total += WEIGHT.boundary;
    if (i >= basenameStart) total += WEIGHT.inBasename;
    if (prev >= 0 && i > prev + 1) {
      total -= Math.min(i - prev - 1, WEIGHT.maxGapPenalty) * WEIGHT.gap;
    }
    prev = i;
  }
  // A name the query opens beats one where it merely resumes at some inner
  // word break, which otherwise scores identically.
  if (positions[0] === basenameStart) total += WEIGHT.basenameStart;
  return total;
}

/**
 * Rank one candidate against the query, or return null when it does not match.
 * `path` is relative to the search root; a trailing `/` marks a directory and
 * is ignored for matching.
 */
export function scoreCandidate(path: string, query: string, mode: Mode): number | null {
  const clean = path.endsWith("/") ? path.slice(0, -1) : path;
  if (clean === "") return null;

  const lastSlash = clean.lastIndexOf("/");
  const basenameStart = lastSlash + 1;
  const basename = clean.slice(basenameStart);
  const depth = lastSlash < 0 ? 0 : clean.split("/").length - 1;

  // Smart case: an all-lowercase query ignores case, any uppercase makes it strict.
  const caseSensitive = /[A-Z]/.test(query);

  const cut = query.lastIndexOf("/");
  const queryTail = query.slice(cut + 1);

  let score: number;
  if (mode === "basename") {
    const queryDir = cut < 0 ? "" : query.slice(0, cut);
    if (queryDir !== "") {
      const dirPart = clean.slice(0, basenameStart);
      const haystack = caseSensitive ? dirPart : dirPart.toLowerCase();
      const needle = caseSensitive ? queryDir : queryDir.toLowerCase();
      if (!haystack.includes(needle)) return null;
    }
    const positions = findPositions(basename, queryTail, caseSensitive);
    if (positions === null) return null;
    score = scorePositions(basename, positions, 0);
    if (queryDir !== "") score += WEIGHT.boundary;
  } else {
    const positions = findPositions(clean, query, caseSensitive);
    if (positions === null) return null;
    score = scorePositions(clean, positions, basenameStart);
  }

  if (queryTail !== "") {
    const lowerBase = basename.toLowerCase();
    const lowerTail = queryTail.toLowerCase();
    if (lowerBase === lowerTail) score += WEIGHT.exactBasename;
    else if (lowerBase.startsWith(lowerTail)) score += WEIGHT.basenamePrefix;
    else if (lowerBase.includes(lowerTail)) score += WEIGHT.basenameSubstring;
  }

  return score - depth * WEIGHT.depth - clean.length * WEIGHT.length;
}

/** Best `limit` candidates for `query`, highest score first. */
export function rank(paths: string[], query: string, mode: Mode, limit: number): string[] {
  if (query === "") return [...paths].sort((a, b) => a.localeCompare(b)).slice(0, limit);

  const scored: Array<{ path: string; score: number }> = [];
  for (const path of paths) {
    const score = scoreCandidate(path, query, mode);
    if (score !== null) scored.push({ path, score });
  }
  scored.sort((a, b) => b.score - a.score || a.path.length - b.path.length || a.path.localeCompare(b.path));
  return scored.slice(0, limit).map((entry) => entry.path);
}

export interface Plan {
  /** Directory fd searches. */
  root: string;
  /** Text re-attached to every result so the suggestion stays insertable. */
  prefix: string;
  /** Recurse into descendants, or list a single segment (directory navigation). */
  recursive: boolean;
  query: string;
  mode: Mode;
}

const DRIVE_ROOTED = /^[A-Za-z]:[\\/]/;
const PARENT_RUN = /^(?:\.\.\/)+/;

/** Split the typed text into a search root, a prefix to restore, and a query. */
export function planQuery(raw: string, home: string, cwd: string): Plan {
  let mode: Mode = "path";
  let text = raw;
  if (text.startsWith("//")) {
    mode = "basename";
    text = text.slice(2);
  }
  if (DRIVE_ROOTED.test(text)) text = text.replaceAll("\\", "/");

  const navigable = text === "~" || text.startsWith("~/") || text.startsWith("/") || DRIVE_ROOTED.test(text);
  if (navigable) {
    if (text === "~") return { root: home, prefix: "~/", recursive: false, query: "", mode };
    const cut = text.lastIndexOf("/");
    const prefix = text.slice(0, cut + 1);
    const query = text.slice(cut + 1);
    const root = prefix.startsWith("~/") ? home + "/" + prefix.slice(2) : prefix;
    return { root: root === "" ? "/" : root, prefix, recursive: false, query, mode };
  }

  const parents = PARENT_RUN.exec(text)?.[0] ?? "";
  if (parents !== "") {
    return { root: cwd + "/" + parents, prefix: parents, recursive: true, query: text.slice(parents.length), mode };
  }
  if (text.startsWith("./")) {
    return { root: cwd, prefix: "./", recursive: true, query: text.slice(2), mode };
  }
  return { root: cwd, prefix: "", recursive: true, query: text, mode };
}

function fdArgs(plan: Plan): string[] {
  const args = ["--base-directory", plan.root, "--path-separator", "/", "--hidden", "--color", "never"];
  if (plan.recursive) {
    args.push("--no-ignore-vcs");
    for (const dir of NOISY_DIRS) {
      if (!plan.query.includes(dir)) args.push("--exclude", dir);
    }
  } else {
    args.push("--no-ignore", "--max-depth", "1");
  }
  return [...args, "."];
}

/**
 * Read fd's output, stopping early once enough candidates are in hand or the
 * time budget expires. An unbounded walk of a large tree would blow past any
 * latency a per-keystroke menu can absorb.
 */
async function collect(args: string[]): Promise<string[]> {
  const proc = Bun.spawn(["fd", ...args], { stdout: "pipe", stderr: "ignore" });
  const deadline = Date.now() + SCAN_BUDGET_MS;
  const decoder = new TextDecoder();
  const lines: string[] = [];
  let buffer = "";

  for await (const chunk of proc.stdout) {
    buffer += decoder.decode(chunk, { stream: true });
    let nl = buffer.indexOf("\n");
    while (nl >= 0) {
      const line = buffer.slice(0, nl).replace(/\r$/, "");
      if (line !== "") lines.push(line);
      buffer = buffer.slice(nl + 1);
      nl = buffer.indexOf("\n");
    }
    if (lines.length >= SCAN_LIMIT || Date.now() > deadline) {
      proc.kill();
      break;
    }
  }
  const tail = buffer.trim();
  if (tail !== "") lines.push(tail);
  return lines;
}

async function main(): Promise<void> {
  const stdin = await Bun.stdin.text();
  let raw = "";
  try {
    raw = (JSON.parse(stdin || "{}") as { query?: unknown }).query as string ?? "";
  } catch {
    return;
  }
  if (typeof raw !== "string") return;

  const home = (process.env.HOME ?? process.env.USERPROFILE ?? "").replaceAll("\\", "/");
  const cwd = process.cwd().replaceAll("\\", "/");
  const plan = planQuery(raw, home, cwd);

  const paths = await collect(fdArgs(plan));
  const best = rank(paths, plan.query, plan.mode, MAX_RESULTS);
  if (best.length > 0) console.log(best.map((path) => plan.prefix + path).join("\n"));
}

if (import.meta.main) await main();
