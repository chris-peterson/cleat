#!/usr/bin/env python3
"""What cleat predicts a prompt opens, against what a headless Claude opens.

    python3 examples/probe-vs-claude.py [DIR] [PROMPT ...] [--budget USD]
    just compare-probe [DIR] [PROMPT ...]

For each prompt, `cleat graph DIR --probe PROMPT --json` says what lights, and
`claude -p PROMPT` run in DIR says what a session actually reached for: the
skills it invoked and the files it read. Claude runs in plan mode with only
Read, Glob, Grep, and Skill, so a prompt like "release a new version" can look
but not act. Each run spends tokens and answers differently from run to run,
so this sits outside `just test`.

What it reports per prompt:
  - each skill Claude invoked, and its rank among the skill entries cleat lit
    at launch, ordered by how many of the prompt's words each one says
  - the files Claude read that the graph knows, and how many cleat lit
  - how much cleat lit in all, against what Claude opened
"""
import argparse
import concurrent.futures
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

PROMPTS = (
    "open a merge request for this branch",
    "why is CI failing on my PR",
    "write a retro for this session",
    "add a hook that blocks recursive deletes",
    "tier these rules to cut startup context",
    "release a new version",
)
CLEAT = pathlib.Path(__file__).resolve().parent.parent / "scripts" / "cleat"
TOOLS = "Read,Glob,Grep,Skill"


def predict(directory, prompt):
    run = subprocess.run([sys.executable, str(CLEAT), "graph", str(directory), "--probe", prompt, "--json"],
                         capture_output=True, text=True)
    if run.returncode:
        raise RuntimeError("cleat graph failed: {}".format(run.stderr.strip()))
    return json.loads(run.stdout)


def observe(directory, prompt, budget, keep):
    """The stream a headless session writes, saved under keep, and what it
    invoked and read."""
    # --strict-mcp-config with no config loads no MCP server: their tool
    # schemas cost every turn and play no part in which skill a prompt picks.
    command = ["claude", "-p", prompt, "--output-format", "stream-json", "--verbose",
               "--permission-mode", "plan", "--tools", TOOLS, "--strict-mcp-config",
               "--no-session-persistence", "--max-budget-usd", str(budget)]
    run = subprocess.run(command, cwd=directory, capture_output=True, text=True)
    stream = keep / "{}.jsonl".format("-".join(prompt.lower().split())[:60])
    stream.write_text(run.stdout, encoding="utf-8")
    skills, reads, result = [], [], None
    for line in run.stdout.splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if event.get("type") == "result":
            result = event
        if event.get("type") != "assistant":
            continue
        for block in event.get("message", {}).get("content", []):
            if block.get("type") != "tool_use":
                continue
            if block["name"] == "Skill":
                skills.append(block["input"].get("skill", ""))
            elif block["name"] == "Read":
                reads.append(block["input"].get("file_path", ""))
    if result is None:
        raise RuntimeError("claude -p wrote no result for {!r} (exit {}): {}".format(
            prompt, run.returncode, (run.stderr or run.stdout).strip()[-400:]))
    return {"skills": skills, "reads": reads, "result": result, "stream": stream}


def compare(graph, seen):
    probe = graph["probe"]
    nodes = {n["id"]: n for n in graph["nodes"]}
    lit = {h["id"] for h in probe["hits"]}
    ranked = sorted((h for h in probe["hits"] if h["hop"] == 0 and nodes[h["id"]]["kind"] == "entry"),
                    key=lambda h: (-len(h["matched"]), h["label"]))
    rank = {h["label"]: i + 1 for i, h in enumerate(ranked)}
    by_path = {}
    for n in graph["nodes"]:
        if n.get("path"):
            by_path.setdefault(str(pathlib.Path(n["path"]).resolve()), []).append(n["id"])
    skills = []
    for name in dict.fromkeys(seen["skills"]):
        label = "/" + name.lstrip("/")
        skills.append((label, rank.get(label), len(ranked)))
    known = outside = lit_reads = 0
    for path in dict.fromkeys(seen["reads"]):
        ids = by_path.get(str(pathlib.Path(path).resolve()))
        if not ids:
            outside += 1
            continue
        known += 1
        lit_reads += any(id in lit for id in ids)
    return {"words": probe["words"], "skills": skills, "known": known, "outside": outside,
            "lit_reads": lit_reads, "lit": len(lit), "entries": len(ranked)}


def report(prompt, c, seen):
    lines = ["> {}".format(prompt), "  words: {}".format(", ".join(c["words"]))]
    if not c["skills"]:
        lines.append("  claude invoked no skill; cleat lit {} skill entries".format(c["entries"]))
    for label, rank, of in c["skills"]:
        lines.append("  claude invoked {}: {}".format(
            label, "cleat ranks it {} of {}".format(rank, of) if rank else "cleat did not light it"))
    lines.append("  claude read {} {} the graph knows, {} lit by cleat; {} outside the graph".format(
        c["known"], "file" if c["known"] == 1 else "files", c["lit_reads"], c["outside"]))
    lines.append("  cleat lit {} files in all (${:.2f}, {})".format(
        c["lit"], seen["result"].get("total_cost_usd") or 0, seen["result"].get("subtype", "?")))
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("directory", nargs="?", default=".")
    parser.add_argument("prompt", nargs="*", help="prompts to compare; without one, the built-in set")
    parser.add_argument("--budget", type=float, default=1.5, help="USD cap per headless run")
    parser.add_argument("--keep", help="where to save each run's stream-json; default, a new temp dir")
    args = parser.parse_args()
    if shutil.which("claude") is None:
        sys.stderr.write("probe-vs-claude: no `claude` on PATH\n")
        return 2
    directory = pathlib.Path(args.directory).resolve()
    keep = pathlib.Path(args.keep) if args.keep else pathlib.Path(tempfile.mkdtemp(prefix="probe-vs-claude."))
    keep.mkdir(parents=True, exist_ok=True)
    prompts = args.prompt or PROMPTS
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(prompts)) as pool:
        seen = dict(zip(prompts, pool.map(lambda p: observe(directory, p, args.budget, keep), prompts)))
    found = top = invoked = 0
    cost = 0.0
    for prompt in prompts:
        c = compare(predict(directory, prompt), seen[prompt])
        print(report(prompt, c, seen[prompt]) + "\n")
        cost += seen[prompt]["result"].get("total_cost_usd") or 0
        for _label, rank, _of in c["skills"]:
            invoked += 1
            found += rank is not None
            top += rank is not None and rank <= 3
    print("{} skills invoked across {} prompts: cleat lit {}, ranked {} in its top 3. "
          "${:.2f} spent; streams in {}".format(invoked, len(prompts), found, top, cost, keep))
    return 0


if __name__ == "__main__":
    sys.exit(main())
