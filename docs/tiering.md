# Tiering guide

## Guidance is a tree

An agent doesn't need everything you know about a repo at once. It needs the
root at launch, and the rest as the work reaches it. Tiering gives guidance
that shape: a root every session loads, and branches that open only when
something calls for them. Each node holds just enough to act on at that depth,
plus a pointer for when more is needed.

Here's the guidance for an example repo, `acme-widget`. Only the top row is
paid for in every session:

```mermaid
%%{ init: { 'look': 'handDrawn' } }%%
flowchart TD
    subgraph Launch["Every session"]
        Root["AGENTS.md"]
        Desc["release skill: one line"]
    end
    Root -->|edits under src/api/| Rule["api.md rule"]
    Rule -->|needs an error code| Errors["guides/api-errors.md"]
    Root -->|works in migrations/| Nested["migrations/AGENTS.md"]
    Desc -->|user asks for a release| Body["release SKILL.md"]
    Body -->|reaches the changelog| Format["references/changelog.md"]
```

| Node | Holds |
| --- | --- |
| `AGENTS.md` | what the repo is, how to build and test it |
| release skill, one line | when to use it |
| `api.md` rule | validate every input; the error codes are in `guides/api-errors.md` |
| `guides/api-errors.md` | the full table of error codes |
| `migrations/AGENTS.md` | never edit a migration that has run |
| release `SKILL.md` | the release steps |
| `references/changelog.md` | the changelog format |

A session that fixes a typo in the README pays for the top row and nothing
else. A session that adds an API endpoint opens the `api.md` rule, and opens
the error table only if it returns an error. Tiering a repo means pushing each
detail down to the deepest node that still opens when it's needed.

## Measuring the root

`cleat check` reports `launch-cost` when the root grows past the budget, and
names this guide by its path in the plugin. The `context-tiering` skill reads
it too, when you ask Claude to cut what your instructions cost. To see the
numbers yourself:

```bash
scripts/cleat cost .
```

It lists each file and listing entry a session loads at launch, with its tier
and size, and the total against the budget. It exits 1 past the budget, so it
can run in CI. The budget is 16 KiB unless you set your own:

```bash
git config cleat.launchBudget 12000
```

## Seeing the rest of the tree

The root is only what loads up front. A skill's body, the guides it points to,
and the scripts it runs load later, and they're where a session's cost grows
without anyone measuring it. `cleat graph` walks the whole tree a session can
open, across the repo, your user scope, and every enabled plugin, and gives
each node two numbers:

- **Reach cost**, what a session has already paid by the time the node opens.
- **Closure cost**, the node plus everything it pulls in. This is the branch
  you'd remove by splitting a skill, filtering a plugin, or trimming a guide.

```bash
scripts/cleat graph .
```

It opens a two-pane browser in the terminal, starting with **insights**: what
stands out in your setup, such as the type of file taking the biggest share of
launch, the skill that pulls in the most, a guide many skills share, or files
copied byte for byte. Select one to see the files it names. The left pane rolls everything up
by kind (instructions, rules, skills, plugins, hooks), each with what it costs
at launch and what it pulls in; open a row with enter or space. The right pane
shows the heaviest files under the selected row, or the tree a selected skill
or rule opens. Every row is colored from gray to red by what it pulls in, so
the hotspots stand out. Press `g` to roll up by owner instead.

Costs are in tokens, estimated at about 2.8 bytes each (what `/context` reports
for instruction files). Each row in the tree answers four questions:

| Column | What it tells you |
| --- | --- |
| spent | What the session has already paid to get here, down the path you opened |
| this | What opening this file costs |
| +next | What opening it one level further adds |
| all | Everything it pulls in, each file once |

A skill that another one invokes is counted at its own row rather than added to
the caller's `+next` and `all`: invoking it is a separate step.

The strip under the panes says when the selected file loads, and which line
opens it. A rule waiting on `**/*.yml` loads only when such a file is touched,
and is tagged `[**/*.yml]` in the list; one whose globs match nothing here is
tagged `[retired]`. A guide loads when the agent follows the reference to it,
shown as the file and line holding it, such as
`SKILL.md:42  See the [forge cookbook](guides/forge-cookbook.md)`.

Narrow it with `--plugin`, `--marketplace`, `--scope`, or `--tier`. `--json`
gives the data to a script of your own.

`--html` opens the same graph as a page in your browser, starting on a view of
it as a universe. Launch sits at the center, and every other file sits as far
out as the context a session spends to reach it, in a wedge for the plugin or
scope it comes from. Files that only open on a condition (a glob, a hook, a
typed command) are drawn dashed. The Graph tab shows the same files as a
node-link graph.

Every view reports three numbers, because each answers a different question:

| Number | What it answers |
| --- | --- |
| At launch | What every session pays before you type |
| Deepest path | What a session spends to reach the farthest file, one path at a time |
| Every file | What reading everything a session could reach would cost |

The budget under the universe measures either of the last two. "Down one path"
lights what a session reaches spending that much along a single route; this is
what a session actually pays. "Everything" opens files nearest first until the
budget runs out; this is how much there is to find. Press Expand to watch either
grow from launch outward. Click a wedge to see that owner's numbers, and Drill
in to see it alone.

What follows is the guide as the agent reads it. Why each tier costs what it
does is in [Background](/background).

---

[`guides/tiering`](guides/tiering.md ':include')
