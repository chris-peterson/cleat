# Changelog

## Unreleased

### Added
- `cleat graph` walks everything a session can load (the repo, your user
  scope with the skills claude.ai syncs into it and agents in folders of their
  own, and every enabled plugin) and follows each reference a file states:
  a listing entry to its skill body, a body to the guides it reads, the
  scripts it runs, and the skills it names. Each node carries its size, its
  reach cost (what a session has paid before it opens), and its closure cost
  (everything it pulls in), so the expensive branches stand out. Costs show as
  estimated tokens: what's spent to reach a file, what it costs, what opening
  it one level further adds, and everything below it. It opens a
  two-pane browser in the terminal, rolled up by kind of artifact and colored
  by cost; `--html` opens the graph as a page in your browser, and `--json`
  prints the data. `--plugin`, `--marketplace`, `--scope`, and `--tier` narrow
  any of them.
- `cleat graph` opens with insights on what stands out: the biggest share of
  launch, the heaviest skill, the guide the most skills share, duplicate files,
  skills naming a typed-only skill, and SessionStart hooks it can't size. Each
  shows how it was computed, and Show narrows the view to the files involved.
- Every file in `cleat graph` says when it loads (at launch, for files matching
  its globs, never, only when typed, on a hook event, or when a reference to it
  is followed), and every reference says where it is: the file, line, and text
  that opens the next file.
- `cleat graph --html` is one radar: launch at the center, each file as far
  out as the context it takes to reach, colored by what it pulls in, with a
  halo on each file past the ideal for its tier. A meter under it runs out to
  a 1M context window, with a line where a 200k window ends, filled by what
  loads at start; ask about a term and it fills
  on, hop by hop, with what that prompt opens, while the radar lights those
  files. Drag the meter to see what a session has opened by any point. The
  panel beside it says what to look at first: what launch is made of and the
  fixes that save the most, or the heaviest files a prompt reaches. Filters,
  insights, and the scorecard wait in a drawer, and each file's particulars
  behind More. A `?` walks through what each mark means with examples from
  your own setup; clicking a plugin's wedge shows its numbers and
  double-clicking drills into it. Esc, the mouse's back button, and the
  browser's back step back one view at a time, and the home button at the
  top left, or the repo's name beside it, returns to where the page
  opened. In the terminal browser, `w` opens what it shows as this page. The
  page
  loads nothing from the network, so it renders offline, and comes in a day
  and a night theme (Alucard and Dracula), following your system until you
  pick: cost runs slate to purple to pink, orange marks a file past its
  ideal, and red is kept for a remote site, in the terminal browser too.
- `cleat graph` shows its external dependencies: every web address your
  files name, by host, with what following them costs a session and the files
  and lines that send it there. Press `e` in the terminal, click Web addresses
  or the perimeter on the radar, or read `sites` in `--json`.
- Every `cleat graph` view reports the same three numbers: what launch costs,
  what the deepest path costs, and what every file would cost.
- Ask the radar about what an agent would be after. Type a term, say
  `release`, or a whole prompt, say `deploy this to candidate`, and the
  loaded files that mention it (any of the prompt's words but the common
  ones, each where a word starts) light up, the skills saying the most of
  them first; quote a phrase to look for it as typed; following their
  references lights what an agent wanting more would reach, hop by hop, with
  what reading it all costs. Files that mention the term but that nothing
  lit leads to are islands, past a horizon, and each names the line that
  would connect it. Each remote site a lit line names sits
  on the perimeter, one per host, because a trip off the machine is slower, less
  certain, and needs a network: context an agent needs belongs beside the
  file that names it. In the terminal browser, `p` takes the same probe and rolls
  the left pane up by distance, each hop with what reading it costs;
  `--probe TERM` carries it in the JSON, and with no term gives everything by
  distance. `--json` carries each file's web addresses.
- `cleat graph` finds orphans: files beside your guidance, in a skill's folder
  or one a skill or rule links into, that nothing links to, so no session
  reads them. Each comes with where to name it (the line already about the
  same thing, or the skill that names only its folder), or the advice to
  delete it. The radar draws them past the horizon as hollow quatrefoils,
  the mark military symbology gives an unknown contact, and lists them by
  owner; the terminal browser lists them under Orphans; `--json` carries
  them.
- The `context-tiering` skill maps what calls what with `cleat graph`.
- `examples/graph-hotspots.py` reads `cleat graph --json` and prints the
  heaviest branches, the files several roots share, and what each plugin
  costs: a starting point for your own tooling.
- `cleat graph` scores what a session can load against the ideal for each
  tier: listing entries of about 100 tokens, skill bodies under 5,000 tokens
  and 500 lines, references linked straight from the body, a table of contents
  atop any reference over 100 lines (Anthropic's published skill budgets), and
  launch within cleat's launch budget. The page's new "vs ideal" view shows a
  scorecard per plugin and scope and a list of fixes, what every session pays
  first; the terminal browser lists the same fixes under "vs ideal", and
  `--json` carries both.
- `cleat metrics` records the graph's numbers over time. Each run appends a
  snapshot to `~/.local/state/cleat/metrics.yml` (or `--history PATH`) and
  prints it: the totals, the context per load tier and per hop from a root,
  the depth curve (how much context is within reach on a budget of 1k, 2k, 4k
  tokens and so on), the budgets at which half and 90% of it is within reach,
  the largest single file, and each owner's totals with a plugin's version and
  a digest that changes when any of its files does. Run it from your own
  machine: the numbers come mostly from your user scope and plugins.
- Files in `cleat graph` open from where they're shown. In the terminal
  browser, cmd+click a file's name (or whatever opens a link in your terminal)
  to open it; the details strip shows the selected file's path, with its folder
  linked too. The page's details panel links the file and its folder the same
  way.
- Following a web address now counts toward what a prompt spends. Each
  address a lit line names is counted once, after the local files, at an
  estimate of what WebFetch hands back (about 2k tokens), and the meter marks
  that stretch as estimated. `cleat graph --measure-remote` fetches each
  address, measures its text, and keeps the result for 30 days in
  `~/.cache/cleat/remote.json`, so later runs use it without the network.
  Selecting a site says what reading its pages raw would cost, and which
  addresses could not be fetched.
- The terminal browser opens compact: a meter of what loads at start, marked
  where the 200k and 1M windows end, and a cost bar and one number per row. `d` shows every cost
  column and the full details strip. Esc or backspace steps back: out of the
  right pane, then to the view before the last probe, filter, or regrouping.
- The terminal browser takes the mouse: click a row to pick it, click it again
  to expand it, click the pane title to switch the grouping, scroll either
  pane with the wheel, and use the mouse's back button to step back.
- Double-click a file on the radar to see only what it pulls in. A key says
  what each mark means, including the dashed files, which load only on a
  trigger.
- Select an owner in the scorecard (or "What to change" on a plugin's wedge)
  for a plan of what to change there: a step per kind of fix, largest
  savings first, with the files each one touches, and a starter prompt to copy
  into a coding agent session in that owner's repository.

## 0.5.0

### Added
- A Background page on the docs site for readers new to coding agents:
  instruction files, the context window, context tiering, and hooks.
- `cleat cost` lists what a session in a directory loads at launch (instruction
  files and their `@` imports, always-on rules, project skill and command
  listing entries), each with its tier and size, and the total against a
  16 KiB budget. It exits 1 past the budget, so CI can gate on it. Set your
  own budget with `git config cleat.launchBudget <bytes>`.
- `cleat check` reports `launch-cost`, an advisory, when that total is past the
  budget, naming the largest piece.
- A `context-tiering` skill: ask why your context is so big, or to trim what
  your instructions cost, and it measures, asks what's in scope, and moves each
  piece to the cheapest tier that still reaches the agent. The steps are in a
  new Tiering guide, also on the docs site.

### Changed
- The docs sidebar reads in order: Background, then Harness engineering and the
  lab, then Feedback loops. The guides and SPEC sit under Reference.
- The docs home page states when Claude Code reads `AGENTS.md`.
- After an edit, a `restated` finding tells the agent what to do with it: fix
  it in the same change when the edit touched one of the two copies, or name
  it to you in the wrap-up when it didn't.
- For a `README.md` outside `docs/`, the `restated` repair is to cut it to the
  pitch, the install line, and the development pointer, and link to the docs
  page for the rest. A forge can't include one file in another.
- The nudge's "`AGENTS.md` is canonical" note appears only under findings that
  involve `AGENTS.md` or `CLAUDE.md`.

### Fixed
- The lab's controls work from the moment it loads: add a layer while the
  baseline plays, and changing the harness during any run starts it over with
  the new harness.
- The lab works on a phone: the run's progress and the next step stay in view
  under the title bar, and tapping a disc shows its tooltip.
- The README's debugging section shows the hook line Claude Code 2.1.296 and
  later logs.

## 0.4.0

### Added
- `cleat check` reports `shadowed`, an error, for a nested `AGENTS.md` with no
  `CLAUDE.md` beside it under a root `CLAUDE.md`, a file no Claude Code session
  reads. A repo whose check was green can report it after upgrading; the repair
  is a `CLAUDE.md` pointer beside it.
- Reading a shadowed `AGENTS.md` offers to add that pointer.
- When a write adds guidance to `CLAUDE.md` or `AGENTS.md`, cleat also asks
  whether it's bound to one directory, and suggests a nested `AGENTS.md` and
  pointer there.
- Two docs pages: Feedback loops, the model behind cleat's placement, and
  Harness engineering, with an interactive stove scene and a lab that runs 100
  edits through a harness you build.

### Changed
- The placement guide holds only what the agent acts on; the docs site shows it
  and the rubric with a short intro on how cleat uses each.
- The rubric no longer sends a `/verify` shortcut to `CLAUDE.md` when it names a
  `verify` skill, which Claude Code already runs before each commit.
- The plugin lists the docs site as its documentation.

## 0.3.0

### Added
- `cleat check` reports `restated`, an advisory, when a run of three or more
  lines is copied between two documentation files, and keeps the copy in the
  file with the wider audience.
- `cleat check` reports `narrowing-ref`, an error, when a relative link points
  toward a narrower audience, such as a `docs/` page linking into the repo or
  `AGENTS.md` linking `CLAUDE.md`. A repo whose check was green can report it
  after upgrading.
- Before a write adds guidance to `CLAUDE.md`, `AGENTS.md`, or a topic rule,
  cleat asks once per file per session whether a hook could enforce it,
  whether every session needs it, and whether it's already written elsewhere.
  Re-issuing the same write lets it through.
- Rules directories beyond `.claude/rules/` are configured with
  `git config --add cleat.rulesDir <dir>`.
- A `CLAUDE.md` that is only the pointer, in a repo with no `AGENTS.md`, is
  reported as `dangling-ref`, with the repair to write `AGENTS.md`. It was
  reported as `no-agents`, whose repair asked for the pointer it already was.
- A topic rule whose glob is absolute, climbs out of the repo with `..`, or
  expands to more than 64 patterns is reported as `bad-glob` instead of being
  classified.

### Changed
- Re-issuing a denied write exempts that file for the rest of the session.
- The nudge also runs on writes to documentation files, and reports a finding
  once while it persists.
- The pointer `CLAUDE.md` cleat asks for is the single line `@AGENTS.md`, the
  shape Claude Code's docs give. A pointer that also links to `AGENTS.md` still
  passes the check.
- A hook run without `CLAUDE_PLUGIN_DATA` reports that in a `systemMessage`
  instead of keeping session state under a guessed path, which was right only
  for installs from one marketplace.
- Reading an `AGENTS.md` with no `CLAUDE.md` beside it no longer triggers a
  bootstrap offer, since Claude Code reads that `AGENTS.md` at startup by
  default. `cleat check` still reports `no-claude` as an advisory for the
  sessions that skip it. A `CLAUDE.md` without the `@AGENTS.md` ref still gets
  the offer.
- When the smallest index a repo's rules allow is itself over budget,
  `toc-bloat`'s repair says to consolidate rules into fewer glob sets, and the
  nudge no longer pastes rows that wouldn't clear it. A `toc-bloat` within
  budget now comes with the rendered index, as `unlisted-rule` does.
- A blank `AGENTS.md` no longer lets a full `CLAUDE.md` past the write gate.

### Fixed
- `cleat check` and the hooks no longer hang on a repo with a directory symlink
  cycle, or on a rule glob with many brace groups.

## 0.2.0

### Added
- First release. cleat keeps a repo's agent instructions in one canonical
  `AGENTS.md` with `CLAUDE.md` reduced to a pointer that imports it, so the same
  guidance reaches Claude Code and the tools that read `AGENTS.md`. Three hooks
  and no commands: a `PreToolUse` gate that stops a substantive `CLAUDE.md` write
  in a repo with no `AGENTS.md` and asks for it as two writes, a `PostToolUse`
  nudge that reports near-miss shapes with their repairs for in-turn correction,
  and a `PostToolUse` `Read` trigger that offers to bootstrap the convention
  where it's absent. `cleat check` reports the same findings from the command
  line, exiting non-zero on errors and green on advisories. (#1)
- cleat offers itself to sessions already working with agent instruction files.
  A session that reads `.cursorrules`, `.cursor/rules`,
  `.github/copilot-instructions.md`, `.windsurfrules`, `GEMINI.md`, or
  `AGENTS.md` sees an install suggestion for cleat. Suggestions appear only
  where an administrator has allowlisted this marketplace in managed settings'
  `pluginSuggestionMarketplaces`.
- `.claude/rules/` is a supported home for topic guidance, so long as
  `AGENTS.md` indexes it. `cleat check` reports a path-scoped rule the index
  misses, a row naming a rule whose globs match no file, and an index grown past
  what every session pays to load it. `cleat index` prints the index a repo
  should carry, derived from the rules themselves.
