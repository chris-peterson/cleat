#!/usr/bin/env python3
"""Where a session's context goes, from `cleat graph --json` on stdin.

    scripts/cleat graph . --json | python3 examples/graph-hotspots.py [--top N]

An example of building on the JSON rather than the browser: three views that
answer "what should I split, filter, or trim first?"
"""
import argparse
import collections
import json
import sys


BYTES_PER_TOKEN = 2.8


def human(size):
    """Bytes as estimated tokens, at the ratio the graph was built with."""
    n = size / BYTES_PER_TOKEN
    if n < 1000:
        return "{:.0f}".format(n)
    if n < 1_000_000:
        return "{:.1f}k".format(n / 1000)
    return "{:.1f}M".format(n / 1_000_000)


def owner(node):
    if node["scope"] == "plugin":
        return "{}@{}".format(node["plugin"], node["marketplace"] or "")
    return node["scope"]


def pulled_in(start, nodes, out):
    """Everything start pulls in, by the same rule as `cleat graph`'s closure
    cost: a body naming another skill hands off to that skill's own root."""
    seen, stack = {start}, [start]
    while stack:
        current = stack.pop()
        for target, kind in out.get(current, ()):
            if kind == "invoke" and nodes[current]["kind"] != "entry":
                continue
            if target not in seen:
                seen.add(target)
                stack.append(target)
    return seen


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--top", type=int, default=10, help="rows per view (default 10)")
    args = parser.parse_args()

    graph = json.load(sys.stdin)
    global BYTES_PER_TOKEN
    BYTES_PER_TOKEN = graph["bytesPerToken"]
    nodes = {n["id"]: n for n in graph["nodes"]}
    out = collections.defaultdict(list)
    for edge in graph["edges"]:
        out[edge["source"]].append((edge["target"], edge["kind"]))
    roots = [n for n in nodes.values() if n["root"]]

    totals = graph["totals"]
    print("\n{} files, in ~tokens: {} at launch, {} if every file opened, {} down the "
          "deepest path; {} unmeasured".format(
              totals["nodes"], human(totals["launch"]), human(totals["reachable"]),
              human(totals["deepest"]), totals["unmeasured"]))

    print("\nHeaviest branches: the roots that pull in the most once opened")
    print("  {:>10}  {:>9}  {:<34} {}".format("all", "this", "owner", "root"))
    for n in sorted(roots, key=lambda n: -n["closure"])[:args.top]:
        print("  {:>10}  {:>9}  {:<34} {}".format(
            human(n["closure"]), human(n["size"]), owner(n)[:34], n["label"]))

    # A big file many roots pull in is paid again in every session that opens
    # any of them: the place a split saves the most.
    reached_by = collections.Counter()
    for root in roots:
        for id in pulled_in(root["id"], nodes, out) - {root["id"]}:
            reached_by[id] += 1
    hubs = [(nodes[id], count) for id, count in reached_by.items()
            if count > 1 and nodes[id]["measured"]]
    print("\nShared hubs: files several roots pull in, by size times reach")
    print("  {:>9}  {:>6}  {:<34} {}".format("this", "roots", "owner", "file"))
    for n, count in sorted(hubs, key=lambda h: -h[0]["size"] * h[1])[:args.top]:
        print("  {:>9}  {:>6}  {:<34} {}".format(
            human(n["size"]), count, owner(n)[:34], n["label"]))

    by_owner = collections.defaultdict(lambda: [0, 0, 0])
    for n in nodes.values():
        row = by_owner[owner(n)]
        row[0] += n["size"] if n["tier"] == "launch" else 0
        row[1] += n["size"]
        row[2] += 1
    print("\nBy owner: what each scope and plugin costs")
    print("  {:>10}  {:>10}  {:>6}  {}".format("at launch", "reachable", "nodes", "owner"))
    for name, (launch, reach, count) in sorted(by_owner.items(), key=lambda kv: -kv[1][1])[:args.top]:
        print("  {:>10}  {:>10}  {:>6}  {}".format(human(launch), human(reach), count, name))
    print()


if __name__ == "__main__":
    main()
