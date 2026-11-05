# cleat

**cleat your instructions once, for any agent.**

![Claude Code](https://img.shields.io/badge/Claude%20Code-%23D97757.svg?logo=claudecode&logoColor=white)
![GitHub top language](https://img.shields.io/github/languages/top/chris-peterson/cleat)
![GitHub Release](https://img.shields.io/github/v/release/chris-peterson/cleat?sort=semver&display_name=release&logo=github&label=latest)

Keep a repo's instructions in one `AGENTS.md` that every agent reads, with
`CLAUDE.md` reduced to a pointer at it. cleat works through hooks and spends as
little of a session's context as it can.

📖 **[Read the docs →](https://chris-peterson.github.io/cleat/)**

Repo layout, the `just` targets, and the conventions this codebase holds itself
to are in [AGENTS.md](./AGENTS.md), the same file the agents read. Requirements
are in [SPEC.md](./SPEC.md), their coverage in [STATUS.md](./STATUS.md).

## Exercising it without a session

The CLI is the whole implementation; the hooks are three registrations pointing
at it. Both halves run standalone. `just demo` walks the CLI on this repo, and
bare `just` lists the other demos.

Report a directory's findings:

```bash
scripts/cleat check ../some-repo
scripts/cleat check ../some-repo --json
```

Report what a session there loads at launch, against the budget:

```bash
scripts/cleat cost ../some-repo
```

Browse everything a session there can load (the repo, user scope, and enabled
plugins), with what each path costs. With no flag it opens in the terminal:

```bash
scripts/cleat graph ../some-repo
scripts/cleat graph ../some-repo --plugin anchor --json
scripts/cleat graph ../some-repo --html       # opens a temporary page in your browser
```

The page is a radar: every file as far out as the context it takes to reach.
Type a term an agent might be after and see which loaded files speak to it,
where following their references leads, and which of those references leave
the machine; `p` does the same in the terminal.

Append a snapshot of those numbers to the metrics history, to see how they move
between runs:

```bash
scripts/cleat metrics ../some-repo
scripts/cleat metrics ../some-repo --history /path/to/metrics.yml
```

Feed it a hook payload the way Claude Code would:

```bash
printf '%s' '{
  "hook_event_name": "PreToolUse",
  "session_id": "local",
  "tool_name": "Write",
  "tool_input": {"file_path": "/tmp/demo/CLAUDE.md", "content": "# Demo\n\nRun `just test`.\n"}
}' | python3 scripts/cleat hook
```

## Watching the hooks fire

The hooks produce no terminal output of their own. Launch with `--debug`:

```bash
claude --debug
```

Each hook run logs one line naming the event, the prefilter command, the
plugin, its exit status, and how long it took:

```text
[DEBUG] Hooks: PostToolUse:Read [bash ".../cleat/<version>/hooks/prefilter.sh" read] (plugin cleat@<marketplace>) finished with status 0 (135ms)
```
