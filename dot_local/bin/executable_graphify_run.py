#!/usr/bin/env python3
"""Bring a project's graphify graph up to date through a chosen LLM backend.

Runs graphify's three refresh steps in order:

  update  re-extract changed code through graphify's AST extractors (no LLM)
  docs    send new or changed docs, papers and images to the model
  label   name any community that is missing a name or still a placeholder

With no phase named it runs all three. Each step is already incremental:
unchanged files are held back by graphify's own manifest, and labelling is
skipped outright when every community already has a real name. The `update`
phase needs no model and never touches a backend.

Backends differ only in how they resolve a model and how they size a call, so
each one supplies a Plan and the rest of the run is shared. Anything after a
bare `--` is passed through to graphify untouched.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

PHASES = ("update", "docs", "label")

# Labelling costs one community's worth of prompt per batch entry, its top_k
# node labels plus its god-node hints, against a much smaller reply.
LABEL_REPLY = 2048
LABEL_OVERHEAD = 512
TOKENS_PER_COMMUNITY = 280
MAX_BATCH = 100

PLACEHOLDER = re.compile(r"^Community \d+$")

# graphify exits 0 after a failed LLM batch and falls back to a name taken from
# the community's top node, which reads as a real label. Its own log line is the
# only reliable signal that a run came back empty-handed.
TROUBLE = re.compile(r"\b(?:warning|error):|\bfailed:", re.I)

_TTY = sys.stdout.isatty()


def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _TTY else text


def step(msg: str) -> None:
    print(_c("36", f"==> {msg}"), flush=True)


def note(msg: str) -> None:
    print(_c("90", f"    {msg}"), flush=True)


def warn(msg: str) -> None:
    print(_c("33", f"    {msg}"), flush=True)


def die(msg: str):
    print(_c("31", f"error: {msg}"), file=sys.stderr)
    raise SystemExit(1)


def require(name: str, hint: str) -> str:
    exe = shutil.which(name)
    if not exe:
        die(f"{name!r} not on PATH. {hint}")
    return exe


def capture_json(exe: str, *args: str):
    """Parsed stdout of a --json CLI call, or None.

    stderr is dropped rather than merged: lms writes update notices there, and a
    notice in front of the payload makes it unparseable.
    """
    try:
        proc = subprocess.run([exe, *args], capture_output=True, text=True)
    except OSError:
        return None
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None


def sizing_note(prefix: str, phase_env: dict[str, str]) -> str:
    cap = phase_env.get("GRAPHIFY_MAX_OUTPUT_TOKENS")
    return f"{prefix}, reply cap {cap}" if cap else prefix


def label_batch_size(window: int) -> int:
    return min(MAX_BATCH, max(4, (window - LABEL_REPLY - LABEL_OVERHEAD) // TOKENS_PER_COMMUNITY))


@dataclass
class CommunityState:
    total: int
    stale: int


def community_state(graph: Path) -> CommunityState | None:
    """Communities with no name, or still holding graphify's 'Community N'.

    Read off the graph itself rather than the labels sidecar, so a re-clustering
    that invented new communities counts as stale.
    """
    if not graph.is_file():
        return None
    with graph.open(encoding="utf-8") as fh:
        data = json.load(fh)
    names: dict[str, str | None] = {}
    for node in data.get("nodes", []):
        cid = node.get("community")
        if cid is None:
            continue
        names[str(cid)] = node.get("community_name")
    stale = sum(1 for v in names.values() if not v or PLACEHOLDER.match(v))
    return CommunityState(len(names), stale)


@dataclass
class Plan:
    """What a backend resolved for this run: a model, call sizes, and env."""

    model: str
    token_budget: int
    batch_size: int
    env: dict[str, str] = field(default_factory=dict)
    docs_env: dict[str, str] = field(default_factory=dict)
    label_env: dict[str, str] = field(default_factory=dict)
    extract_takes_model: bool = True


class Backend:
    name = ""
    cli: tuple[str, str] = ("", "")

    def plan(self, opts) -> Plan:
        raise NotImplementedError

    def escalation(self, opts) -> Plan | None:
        """A second, stronger pass over whatever the first one left behind."""
        return None


class LmStudio(Backend):
    name = "lmstudio"
    cli = ("lms", "Install LM Studio, then run: lms bootstrap")

    PROVIDERS = Path.home() / ".graphify" / "providers.json"
    API_KEY_VAR = "LMSTUDIO_API_KEY"

    # Extraction sends a doc chunk plus graphify's node/edge schema prompt and
    # gets back JSON whose size tracks the chunk's, so the window has to hold all
    # three. The 6000 chunk ceiling is not a context limit: recall on a 7-8B
    # model degrades on long inputs well before the window fills, and a chunk the
    # model half-reads costs a re-extraction.
    DOCS_OVERHEAD = 2500
    DOCS_MAX_REPLY = 8192
    MAX_CHUNK = 6000

    # KV cache per token, measured across Q4 7-8B GGUFs: 57 KiB for
    # qwen2.5-coder-7b, 106 KiB for qwen3-8b. Rounded well above both because the
    # fit has to err small. `lms load` does not refuse a window too large for the
    # card, it fills VRAM to the last hundred megabytes and reports success,
    # leaving the run to stall in a partial offload. VRAM_RESERVE_MB covers the
    # desktop's own allocation plus that error margin.
    KV_KB_PER_TOKEN = 128
    VRAM_RESERVE_MB = 2560

    # Past this both the chunk budget and the batch size are pinned to their own
    # ceilings, and the extra KV cache buys nothing but VRAM pressure.
    MAX_USEFUL_CONTEXT = max(
        MAX_CHUNK + DOCS_MAX_REPLY + DOCS_OVERHEAD,
        MAX_BATCH * TOKENS_PER_COMMUNITY + LABEL_REPLY + LABEL_OVERHEAD,
    )

    CODE_TUNED = re.compile(r"coder|codellama|starcoder|codegemma|codestral", re.I)

    def plan(self, opts) -> Plan:
        lms = require(*self.cli)
        base_url = f"http://localhost:{opts.port}/v1"

        catalog = [m for m in (capture_json(lms, "ls", "--json") or []) if m.get("type") == "llm"]
        model = opts.model or self._best_model(catalog)
        if not model:
            die("No LM Studio LLM with a usable context window found. Download one, or pass --model.")
        entry = next((m for m in catalog if m.get("modelKey") == model), None)
        if not entry:
            die(f"{model} is not in the LM Studio catalog. Check: lms ls")

        provider = self._sync_provider(opts, model, base_url)
        # graphify reads the provider's env_key; any non-empty value satisfies
        # the OpenAI client, which demands a key even against a local server.
        key_name = provider.get("env_key") or self.API_KEY_VAR
        if not os.environ.get(key_name):
            os.environ[key_name] = "lm-studio"
            note(f"{key_name} was unset; using a placeholder for this run")

        if not opts.dry_run:
            self._ensure_server(lms, base_url, opts.port)

        ctx, slots = self._ensure_model(opts, lms, entry, model)
        window = ctx // slots
        note(f"{model} - {ctx}-token context across {slots} slot(s), {window} per call")

        reply = min(self.DOCS_MAX_REPLY, window // 2)
        budget = min(self.MAX_CHUNK, max(1000, window - reply - self.DOCS_OVERHEAD))
        return Plan(
            model=model,
            token_budget=opts.token_budget or budget,
            batch_size=opts.batch_size or label_batch_size(window),
            docs_env={"GRAPHIFY_MAX_OUTPUT_TOKENS": str(reply)},
            label_env={"GRAPHIFY_MAX_OUTPUT_TOKENS": str(LABEL_REPLY)},
        )

    @classmethod
    def _best_model(cls, catalog) -> str | None:
        """Pick from the catalog when the caller named no model.

        graphify only ever sends prose to a model, since source files go through
        its local AST extractors, so a code-tuned model is the wrong pick even on
        a code repo. Tool-use training is the closest signal the catalog carries
        for how reliably a model returns well-formed JSON.
        """
        ranked = []
        for m in catalog:
            if int(m.get("maxContextLength") or 0) < 8192:
                continue
            score = 20 if m.get("trainedForToolUse") else 0
            if cls.CODE_TUNED.search(f"{m.get('modelKey', '')} {m.get('displayName', '')}"):
                score -= 40
            ranked.append((score, float(m.get("sizeBytes") or 0), m))
        if not ranked:
            return None
        return max(ranked, key=lambda r: (r[0], r[1]))[2].get("modelKey")

    @staticmethod
    def _vram_mb() -> int:
        exe = shutil.which("nvidia-smi")
        if not exe:
            return 0
        try:
            proc = subprocess.run(
                [exe, "--query-gpu=memory.total", "--format=csv,noheader,nounits"],
                capture_output=True, text=True)
            return int(proc.stdout.splitlines()[0].strip())
        except (OSError, ValueError, IndexError):
            return 0

    @classmethod
    def _fitting_context(cls, entry, ceiling: int) -> int:
        """Largest window that fits alongside the weights.

        Bounded by the model's own maximum, which is the only ceiling when there
        is no nvidia GPU to measure.
        """
        ctx = ceiling
        if int(entry.get("maxContextLength") or 0) > 0:
            ctx = min(ctx, int(entry["maxContextLength"]))
        vram = cls._vram_mb()
        size = float(entry.get("sizeBytes") or 0)
        if vram > 0 and size > 0:
            kv_mb = vram - cls.VRAM_RESERVE_MB - math.ceil(size / 1024 ** 2)
            ctx = min(ctx, kv_mb * 1024 // cls.KV_KB_PER_TOKEN)
        return max(4096, (ctx // 1024) * 1024)

    def _sync_provider(self, opts, model: str, base_url: str) -> dict:
        providers = {}
        if self.PROVIDERS.is_file():
            providers = json.loads(self.PROVIDERS.read_text(encoding="utf-8"))
        entry = providers.get(opts.backend)
        dirty = False

        if entry is None:
            step(f"Registering provider {opts.backend!r} in {self.PROVIDERS}")
            entry = {
                "base_url": base_url,
                "default_model": model,
                "env_key": self.API_KEY_VAR,
                "model_env_key": "GRAPHIFY_LMSTUDIO_MODEL",
                "temperature": 0,
                "reasoning_effort": "none",
                "pricing": {"input": 0.0, "output": 0.0},
            }
            providers[opts.backend] = entry
            dirty = True
        else:
            # A hybrid-reasoning model like Qwen3 spends most of its reply budget
            # thinking before it emits any JSON, and LM Studio ignores the
            # enable_thinking chat template kwarg. reasoning_effort it does
            # honour, and non-reasoning models ignore it, so leaving it set is
            # safe.
            for key, value in (("default_model", model), ("reasoning_effort", "none")):
                if entry.get(key) != value:
                    entry[key] = value
                    dirty = True
            # LM Studio's server rejects response_format.type json_object
            # outright: it takes only json_schema or text. Constrained decoding
            # would need a schema per call site, and the provider entry is one
            # static blob shared by extraction and labelling, so there is nothing
            # correct to put here. A stale json_object 400s every request.
            extra = entry.get("extra_body")
            if isinstance(extra, dict) and "response_format" in extra:
                del extra["response_format"]
                if not extra:
                    entry.pop("extra_body", None)
                dirty = True
            # max_completion_tokens wins over max_tokens in graphify's
            # openai-compat path, so a stale one silently caps every reply for
            # anyone calling graphify directly. Each phase sets its own cap
            # through GRAPHIFY_MAX_OUTPUT_TOKENS, which overrides the entry.
            if entry.pop("max_completion_tokens", None) is not None:
                dirty = True
            if dirty:
                note(f"Updating provider {opts.backend!r} for {model}")

        if dirty and not opts.dry_run:
            self.PROVIDERS.parent.mkdir(parents=True, exist_ok=True)
            self.PROVIDERS.write_text(json.dumps(providers, indent=2) + "\n", encoding="utf-8")
        return entry

    @staticmethod
    def _server_up(base_url: str, wait: float) -> bool:
        deadline = time.monotonic() + wait
        while True:
            try:
                urllib.request.urlopen(f"{base_url}/models", timeout=4).read()
                return True
            except (urllib.error.URLError, OSError):
                if time.monotonic() >= deadline:
                    return False
                time.sleep(0.5)

    def _ensure_server(self, lms: str, base_url: str, port: int) -> None:
        if self._server_up(base_url, 0):
            return
        step(f"Starting LM Studio server on port {port}")
        subprocess.run([lms, "server", "start", "--port", str(port)], check=False)
        if not self._server_up(base_url, 15):
            die(f"LM Studio server did not answer on {base_url}")

    def _resident(self, lms: str) -> list[dict]:
        return capture_json(lms, "ps", "--json") or []

    def _ensure_model(self, opts, lms: str, entry: dict, model: str) -> tuple[int, int]:
        vram_ctx = self._fitting_context(entry, 2 ** 31)
        if opts.context_length:
            ceiling = int(entry.get("maxContextLength") or opts.context_length)
            target = min(opts.context_length, ceiling)
            if opts.context_length > target:
                note(f"{model} tops out at {target} context; "
                     f"loading at that instead of {opts.context_length}")
        else:
            target = self._fitting_context(entry, self.MAX_USEFUL_CONTEXT * opts.concurrency)
        if target > vram_ctx:
            warn(f"{target} context is past the {vram_ctx} this card is estimated "
                 "to hold; expect a partial offload")

        resident = self._resident(lms)
        current = next((m for m in resident if m.get("identifier") == model), None)
        # Parallel slots divide one shared window rather than each getting their
        # own, so a model loaded with more slots than this run uses hands every
        # call a smaller prompt window than its context length advertises.
        reusable = (bool(current)
                    and int(current["contextLength"]) >= target
                    and int(current["parallel"]) <= opts.concurrency)

        if not opts.dry_run and not reusable:
            # The fit was computed against the whole card, so anything else
            # resident would push this load into a partial offload.
            for other in resident:
                if other.get("type") == "llm":
                    note(f"Unloading {other['identifier']}")
                    subprocess.run([lms, "unload", other["identifier"]], check=False)
            step(f"Loading {model} at {target} context, {opts.concurrency} slot(s)")
            subprocess.run([lms, "load", model, "-y", "--gpu", "max",
                            "-c", str(target), "--parallel", str(opts.concurrency)], check=False)
            current = next((m for m in self._resident(lms) if m.get("identifier") == model), None)
            if not current:
                die(f"Failed to load {model} at {target} context. "
                    "If it did not fit VRAM, retry with a smaller --context-length.")

        # Under --dry-run a model that would have been reloaded is still
        # resident, and its window is not the one the run would get.
        effective = current if (reusable or (current and not opts.dry_run)) else None
        if effective:
            return int(effective["contextLength"]), max(1, int(effective["parallel"]))
        return target, opts.concurrency


class ClaudeCli(Backend):
    name = "claude-cli"
    cli = ("claude", "Install from https://claude.ai/code, then run it once to authenticate.")

    DEFAULT_MODEL = "haiku"
    # Well under graphify's 60000 default because the extraction JSON grows with
    # the chunk: a chunk large enough to overrun Claude Code's reply cap comes
    # back truncated and gets bisected and re-sent, so an oversized budget costs
    # tokens rather than saving calls.
    DEFAULT_TOKEN_BUDGET = 20000

    def plan(self, opts) -> Plan:
        require(*self.cli)
        model = opts.model or self.DEFAULT_MODEL
        line = f"{model} via claude-cli"
        if opts.escalate:
            line += f", escalating leftovers to {opts.escalate_model}"
        note(line)
        return self._plan_for(opts, model)

    def escalation(self, opts) -> Plan | None:
        if not opts.escalate:
            return None
        return self._plan_for(opts, opts.escalate_model)

    def _plan_for(self, opts, model: str) -> Plan:
        # Extraction reads GRAPHIFY_CLAUDE_CLI_MODEL and ignores --model;
        # labelling passes --model straight to `claude -p` and never reads the
        # env var. Set both so the caller need not care which phase is running.
        env = {"GRAPHIFY_CLAUDE_CLI_MODEL": model}
        # graphify serialises claude-cli unless this is set. Each call is a
        # separate `claude -p` process, so raising concurrency multiplies memory
        # and rate-limit pressure rather than sharing one session.
        if opts.concurrency > 1:
            env["GRAPHIFY_CLAUDE_CLI_PARALLEL"] = "1"
        return Plan(
            model=model,
            token_budget=opts.token_budget or self.DEFAULT_TOKEN_BUDGET,
            batch_size=opts.batch_size or MAX_BATCH,
            env=env,
            extract_takes_model=False,
        )


class Ollama(Backend):
    name = "ollama"
    cli = ("ollama", "Install from https://ollama.com, then: ollama pull llama3.1:8b")

    DEFAULT_MODEL = "llama3.1:8b"
    # Weights plus KV cache have to fit a 10 GB card; at the auto-derived 64k
    # window Ollama spills roughly 70% of the layers to CPU.
    NUM_CTX = 16384
    DEFAULT_TOKEN_BUDGET = 4000

    def plan(self, opts) -> Plan:
        require(*self.cli)
        model = opts.model or self.DEFAULT_MODEL
        ctx = opts.context_length or self.NUM_CTX
        note(f"{model} - {ctx}-token context")
        return Plan(
            model=model,
            token_budget=opts.token_budget or self.DEFAULT_TOKEN_BUDGET,
            batch_size=opts.batch_size or label_batch_size(ctx),
            env={
                "OLLAMA_MODEL": model,
                "GRAPHIFY_OLLAMA_NUM_CTX": str(ctx),
                # Any non-empty value; silences the no-key warning.
                "OLLAMA_API_KEY": "ollama",
            },
        )


BACKENDS: dict[str, Backend] = {
    "lmstudio": LmStudio(),
    "claude": ClaudeCli(),
    "claude-cli": ClaudeCli(),
    "ollama": Ollama(),
}

EXAMPLES = """\
examples:
  graphify-run                            all three phases, LM Studio
  graphify-run docs label                 skip re-extraction
  graphify-run -b claude --escalate       haiku first, sonnet over the leftovers
  graphify-run label --relabel -j 4       rename every community, 4 calls at once
  graphify-run --path ../other -b ollama
  graphify-run label -- --min-community-size 5
"""


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="graphify-run", allow_abbrev=False, description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter, epilog=EXAMPLES)
    p.add_argument("phase", nargs="*", metavar="PHASE",
                   help=f"any of {', '.join(PHASES)} (all three, in order, when omitted)")
    p.add_argument("-b", "--backend", default="lmstudio", choices=sorted(BACKENDS),
                   help="default: lmstudio")
    p.add_argument("--path", default=os.getcwd(), help="project root (default: cwd)")
    p.add_argument("-m", "--model", help="the backend's own default when omitted")
    p.add_argument("-j", "--concurrency", type=int, default=1,
                   help="parallel LLM calls, and the slots a local model loads with")
    p.add_argument("--context-length", type=int, default=0,
                   help="window to load a local model with (derived from VRAM when omitted)")
    p.add_argument("--token-budget", type=int, default=0, help="per-chunk prompt cap for docs")
    p.add_argument("--batch-size", type=int, default=0, help="communities per labelling call")
    p.add_argument("--mode", choices=("deep",), help="passed to the docs phase as --mode")
    p.add_argument("--escalate", action="store_true",
                   help="rerun each LLM phase over whatever the first pass left behind")
    p.add_argument("--escalate-model", default="sonnet")
    p.add_argument("-f", "--force", action="store_true",
                   help="skip the incremental manifest gate and the semantic cache")
    p.add_argument("--relabel", action="store_true",
                   help="rename every community, not only the missing ones")
    p.add_argument("--no-viz", action="store_true", help="skip graph.html regeneration")
    p.add_argument("--port", type=int, default=1234, help="LM Studio server port")
    p.add_argument("-n", "--dry-run", action="store_true",
                   help="print the resolved graphify commands without running them")
    return p


def main() -> int:
    argv = sys.argv[1:]
    passthrough: list[str] = []
    if "--" in argv:
        cut = argv.index("--")
        argv, passthrough = argv[:cut], argv[cut + 1:]

    parser = build_parser()
    opts, unknown = parser.parse_known_args(argv)
    passthrough = unknown + passthrough

    for word in opts.phase:
        if word not in PHASES:
            parser.error(f"unknown phase {word!r}; expected one of {', '.join(PHASES)} "
                         "(put graphify's own arguments after --)")
    phases = list(dict.fromkeys(opts.phase)) or list(PHASES)
    opts.concurrency = max(1, opts.concurrency)

    root = Path(opts.path).expanduser()
    if not root.is_dir():
        die(f"No such path: {root}")
    graphify = require("graphify", "Install with: uv tool install 'graphifyy[openai]'")
    graph = root / "graphify-out" / "graph.json"
    if "label" in phases and not graph.is_file():
        die(f"No graph found at {graph}. Run this without arguments to build one first.")

    backend = BACKENDS[opts.backend]
    opts.backend = backend.name
    step(f"Project: {root}  [{', '.join(phases)}]")

    plan = backend.plan(opts) if {"docs", "label"} & set(phases) else None

    troubles: list[str] = []

    def run(args: list[str], env: dict[str, str]) -> None:
        if opts.dry_run:
            print("graphify " + " ".join(args))
            return
        step("graphify " + " ".join(args))
        proc = subprocess.Popen([graphify, *args], env={**os.environ, **env},
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, bufsize=1, errors="replace")
        for line in proc.stdout:
            sys.stdout.write(line)
            if TROUBLE.search(line):
                troubles.append(line.rstrip())
        sys.stdout.flush()
        rc = proc.wait()
        if rc != 0:
            print(_c("31", f"graphify {args[0]} failed (exit {rc})"), file=sys.stderr)
            raise SystemExit(rc)

    started = time.monotonic()

    if "update" in phases:
        cmd = ["update", str(root)]
        if opts.force:
            cmd.append("--force")
        run(cmd + passthrough, {})

    if "docs" in phases:
        def docs_cmd(p: Plan, force: bool) -> list[str]:
            cmd = ["extract", str(root), "--backend", opts.backend,
                   "--token-budget", str(p.token_budget),
                   "--max-concurrency", str(opts.concurrency)]
            if p.extract_takes_model:
                cmd += ["--model", p.model]
            if opts.mode:
                cmd += ["--mode", opts.mode]
            if force:
                cmd.append("--force")
            return cmd + passthrough

        note(sizing_note(f"token-budget {plan.token_budget}", plan.docs_env))
        run(docs_cmd(plan, opts.force), {**plan.env, **plan.docs_env})

        second = backend.escalation(opts)
        if second:
            # --force would defeat this: the second pass is only cheap because
            # the manifest and semantic cache hold back everything the first pass
            # completed, leaving just the truncated and unparseable files.
            step(f"Re-running docs at {second.model} for anything {plan.model} left incomplete")
            run(docs_cmd(second, force=False), {**second.env, **second.docs_env})

    if "label" in phases:
        state = community_state(graph)
        if state and not state.stale and not opts.relabel:
            note(f"all {state.total} communities already named; skipping (--relabel to redo them)")
        else:
            if state:
                note(f"{state.stale} of {state.total} communities need a name")

            def label_cmd(p: Plan, missing_only: bool) -> list[str]:
                cmd = ["label", str(root), "--backend", opts.backend, "--model", p.model,
                       "--batch-size", str(p.batch_size),
                       "--max-concurrency", str(opts.concurrency)]
                if missing_only:
                    cmd.append("--missing-only")
                if opts.no_viz:
                    cmd.append("--no-viz")
                return cmd + passthrough

            note(sizing_note(f"batch-size {plan.batch_size}", plan.label_env))
            run(label_cmd(plan, missing_only=not opts.relabel), {**plan.env, **plan.label_env})

            second = backend.escalation(opts)
            state = community_state(graph)
            if second and not opts.dry_run and state and state.stale:
                step(f"Re-naming {state.stale} leftover communities at {second.model}")
                run(label_cmd(second, missing_only=True), {**second.env, **second.label_env})

    if opts.dry_run:
        return 0

    step(f"Done in {(time.monotonic() - started) / 60:.1f} min")
    state = community_state(graph)
    if state:
        note(f"{state.total} communities, {state.stale} unnamed")
    retry = f"{Path(sys.argv[0]).name} label -b {opts.backend} -j {opts.concurrency}"
    if state and state.stale and "label" in phases:
        warn(f"{state.stale} communities kept 'Community N' - the model overflowed "
             f"context or returned unparseable JSON. Retry with: {retry}")
    if troubles:
        warn(f"graphify reported {len(troubles)} problem(s):")
        for line in troubles[:5]:
            warn(f"  {line}")
        if len(troubles) > 5:
            warn(f"  ... and {len(troubles) - 5} more")
    return 1 if troubles else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
