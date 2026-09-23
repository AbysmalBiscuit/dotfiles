import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { findPositions, planQuery, rank, scoreCandidate } from "./file-suggestion.ts";

const HOME = "C:/Users/Lev";
const CWD = "C:/Users/Lev/.agents";

describe("findPositions", () => {
  test("matches a scattered subsequence", () => {
    expect(findPositions("ISSUE_72.md", "72.md", false)).toEqual([6, 7, 8, 9, 10]);
  });

  test("tightens a match rather than taking the first character it can", () => {
    expect(findPositions("a_long_path/abc.md", "abc", false)).toEqual([12, 13, 14]);
  });

  test("rejects out-of-order characters", () => {
    expect(findPositions("abc", "cb", false)).toBeNull();
  });

  test("a slash in the query only matches a real separator", () => {
    expect(findPositions("a-b/c", "a/c", false)).toEqual([0, 3, 4]);
    expect(findPositions("a-b-c", "a/c", false)).toBeNull();
  });

  test("smart case: uppercase in the query makes matching strict", () => {
    expect(findPositions("readme.md", "R", true)).toBeNull();
    expect(findPositions("readme.md", "r", false)).toEqual([0]);
  });
});

describe("scoreCandidate", () => {
  test("finds ISSUE_72.md from 72.md", () => {
    expect(scoreCandidate("ISSUE_72.md", "72.md", "path")).not.toBeNull();
  });

  test("ranks a shallower path above a deeper one", () => {
    const shallow = scoreCandidate("notes.md", "notes", "path");
    const deep = scoreCandidate("a/b/c/notes.md", "notes", "path");
    expect(shallow!).toBeGreaterThan(deep!);
  });

  test("ranks a name the query opens above one it resumes inside", () => {
    const opens = scoreCandidate("scripts/file-suggestion.sh", "fsh", "path");
    const resumes = scoreCandidate("scripts/alacritree-follow.sh", "fsh", "path");
    expect(opens!).toBeGreaterThan(resumes!);
  });

  test("ranks a basename hit above a directory hit", () => {
    const inBasename = scoreCandidate("x/settings.json", "settings", "path");
    const inDirectory = scoreCandidate("settings/x.json", "settings", "path");
    expect(inBasename!).toBeGreaterThan(inDirectory!);
  });

  test("directory queries stay anchored to path structure", () => {
    expect(scoreCandidate("plugins/skills/plugin-settings/SKILL.md", "skills/plugin-settings", "path")).not.toBeNull();
    expect(scoreCandidate("skills-plugin-settings.md", "skills/plugin-settings", "path")).toBeNull();
  });

  test("a trailing slash marks a directory without breaking the match", () => {
    expect(scoreCandidate("scripts/", "scripts", "path")).not.toBeNull();
  });

  describe("basename mode", () => {
    test("ignores directory names the query did not ask for", () => {
      expect(scoreCandidate("forms/shared.ts", "fsh", "basename")).toBeNull();
      expect(scoreCandidate("x/file-suggestion.sh", "fsh", "path")).not.toBeNull();
    });

    test("still honours an explicit directory part", () => {
      expect(scoreCandidate("a/skills/plugin-settings.md", "skills/plugin-settings", "basename")).not.toBeNull();
      expect(scoreCandidate("a/other/plugin-settings.md", "skills/plugin-settings", "basename")).toBeNull();
    });
  });
});

describe("rank", () => {
  test("orders the current directory ahead of descendants", () => {
    const paths = ["deep/nested/config.json", "config.json", "a/config.json"];
    expect(rank(paths, "config", "path", 5)).toEqual(["config.json", "a/config.json", "deep/nested/config.json"]);
  });

  test("an empty query lists everything alphabetically", () => {
    expect(rank(["b.md", "a.md"], "", "path", 5)).toEqual(["a.md", "b.md"]);
  });

  test("honours the result limit", () => {
    expect(rank(["a1.md", "a2.md", "a3.md"], "a", "path", 2)).toHaveLength(2);
  });
});

describe("planQuery", () => {
  test("a bare relative query searches the working directory", () => {
    expect(planQuery("notes", HOME, CWD)).toEqual({
      root: CWD, prefix: "", recursive: true, query: "notes", mode: "path",
    });
  });

  test("a parent-relative query re-roots and keeps the prefix", () => {
    expect(planQuery("../72.md", HOME, CWD)).toEqual({
      root: CWD + "/../", prefix: "../", recursive: true, query: "72.md", mode: "path",
    });
  });

  test("repeated parent segments all count", () => {
    expect(planQuery("../../x", HOME, CWD).prefix).toBe("../../");
  });

  test("a leading // selects basename mode and is not part of the path", () => {
    expect(planQuery("//72.md", HOME, CWD)).toEqual({
      root: CWD, prefix: "", recursive: true, query: "72.md", mode: "basename",
    });
  });

  test("mode selection composes with a parent-relative query", () => {
    const plan = planQuery("//../72.md", HOME, CWD);
    expect(plan.mode).toBe("basename");
    expect(plan.prefix).toBe("../");
  });

  test("a home-rooted query navigates one segment", () => {
    expect(planQuery("~/.local/sh", HOME, CWD)).toEqual({
      root: HOME + "/.local/", prefix: "~/.local/", recursive: false, query: "sh", mode: "path",
    });
  });

  test("a bare tilde lists the home directory", () => {
    expect(planQuery("~", HOME, CWD)).toEqual({
      root: HOME, prefix: "~/", recursive: false, query: "", mode: "path",
    });
  });

  test("an absolute query navigates from the filesystem root", () => {
    expect(planQuery("/etc", HOME, CWD)).toMatchObject({ root: "/", prefix: "/", recursive: false, query: "etc" });
  });

  test("a drive-rooted query navigates and accepts backslashes", () => {
    expect(planQuery("C:\\Users\\Lev\\.ag", HOME, CWD)).toMatchObject({
      root: "C:/Users/Lev/", prefix: "C:/Users/Lev/", recursive: false, query: ".ag",
    });
  });
});

describe("end to end", () => {
  let fixture: string;

  beforeAll(() => {
    fixture = mkdtempSync(join(tmpdir(), "file-suggestion-"));
    mkdirSync(join(fixture, "work"));
    mkdirSync(join(fixture, "docs", "deep"), { recursive: true });
    mkdirSync(join(fixture, "node_modules", "junk"), { recursive: true });
    writeFileSync(join(fixture, "ISSUE_72.md"), "");
    writeFileSync(join(fixture, "work", "notes.md"), "");
    writeFileSync(join(fixture, "docs", "deep", "plugin-settings.md"), "");
    writeFileSync(join(fixture, "node_modules", "junk", "ISSUE_72.md"), "");
  });

  afterAll(() => rmSync(fixture, { recursive: true, force: true }));

  async function suggest(query: string, cwd: string): Promise<string[]> {
    const proc = Bun.spawn(["bun", join(import.meta.dir, "file-suggestion.ts")], {
      cwd,
      stdin: new TextEncoder().encode(JSON.stringify({ query })),
      stdout: "pipe",
      stderr: "inherit",
    });
    const text = await new Response(proc.stdout).text();
    return text.split("\n").map((line) => line.trimEnd()).filter((line) => line !== "");
  }

  test("suggests a partially typed sibling of the parent directory", async () => {
    expect(await suggest("../72.md", join(fixture, "work"))).toContain("../ISSUE_72.md");
  });

  test("reaches descendants, not just the working directory", async () => {
    expect(await suggest("plugsettings", fixture)).toContain("docs/deep/plugin-settings.md");
  });

  test("excludes node_modules unless the query names it", async () => {
    expect(await suggest("ISSUE_72", fixture)).toEqual(["ISSUE_72.md"]);
    expect(await suggest("node_modules/ISSUE", fixture)).toContain("node_modules/junk/ISSUE_72.md");
  });

  test("an unparseable payload prints nothing", async () => {
    const proc = Bun.spawn(["bun", join(import.meta.dir, "file-suggestion.ts")], {
      cwd: fixture,
      stdin: new TextEncoder().encode("not json"),
      stdout: "pipe",
      stderr: "ignore",
    });
    expect(await new Response(proc.stdout).text()).toBe("");
  });
});
