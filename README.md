# cleat

📖 **[Read the docs →](https://chris-peterson.github.io/cleat/)**

Keep a repo's agent instructions in one `AGENTS.md` — the file about 30 coding
tools read — with `CLAUDE.md` reduced to a pointer that imports it. cleat is
hooks only: no slash commands, no skills, nothing resident in session context.

Repo layout, the `just` targets, and the conventions this codebase holds itself
to are in [AGENTS.md](./AGENTS.md) — the same file the agents read. Requirements
are in [SPEC.md](./SPEC.md), their coverage in [STATUS.md](./STATUS.md).

## Exercising it without a session

The CLI is the whole implementation; the hooks are three registrations pointing
at it. Both halves run standalone.

Report a directory's findings:

```bash
scripts/cleat check ../some-repo
scripts/cleat check ../some-repo --json
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

The hooks produce no terminal output of their own. Launch with `--debug` and
look for the `[DEBUG] Hook PreToolUse` / `Hook PostToolUse` lines:

```bash
claude --debug
```
