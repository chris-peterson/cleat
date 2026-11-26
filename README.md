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

The CLI is the whole implementation; the hooks are registrations pointing at
it. Both halves run standalone.

Report a directory's findings:

```bash
scripts/cleat check ../some-repo
scripts/cleat check ../some-repo --json
```

Report what a session there loads at launch, against the budget:

```bash
scripts/cleat cost ../some-repo
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

## Checking the masthead subscription live

cleat subscribes to `codes.bridgeai.masthead/content.routed`, which masthead
announces when it turns content away from its end-user docs hub. The synthetic
test (`scripts/tests/routed.test.sh`) proves the matcher; only a live session
proves the line arrives. Load this checkout, have the agent print an
announcement, and ask what came back:

```bash
claude -p --plugin-dir . --allowedTools='Bash(printf:*)' \
  "Run exactly this Bash command: printf 'codes.bridgeai.masthead/content.routed {\"tier\":\"maintainer\",\"path\":\"docs/build.md\",\"title\":\"Building\",\"reason\":\"Needs a checkout.\"}\n'. Then quote any hook context that arrived after it, or reply NONE."
```

A working subscription quotes a note that begins `cleat — masthead turned content
away`. `NONE` proves nothing until you've confirmed the hook ran: launch with
`--debug` and look for the `PostToolUse:Bash` line below. Each session notes a
piece of content once, so run a fresh session for each try.

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
