# Graceful degradation for other agents

You're reading this because a repo has config under `.claude/` that no other
agent tool loads. The repair is not to move it. Most of it cannot be moved:
there is nowhere agreed to move it to, and half of it would stop working
anywhere else. The repair is to restate what it accomplishes in `AGENTS.md`, so
a tool that reads only `AGENTS.md` still gets a usable subset — full behavior
under Claude Code, something worth having everywhere else.

## Why moving it is the wrong instinct

`AGENTS.md` works because it is one file, governed, that about 30 tools read.
There is no equivalent for operational config. `.agents/skills/` is a real
convention for skills and an explicitly non-normative one; nothing at all covers
commands, hooks, or subagents. The reasoning and the citations are in
`guides/operational-config.md`.

So the question isn't *where do these files go*. It's *what can another agent
still do about them*.

## The dividing line: who consumes it

| Artifact | Consumer | What survives |
|---|---|---|
| Skills, commands, subagent prompts | the model | the file itself, if the agent will go read it |
| Hooks | the harness | the rule, restated as a rule |
| `settings.json` permissions | the harness | what is safe to run without asking |
| MCP servers | the harness | what the server provides, and how to wire it up |

Everything harness-consumed fails the same way: an agent cannot register a
lifecycle callback or spawn an MCP server because a markdown file asked it to.
The model never gets the chance, and the runtime never sees the request.

That sounds like a loss and mostly isn't. **A hook is an enforced rule.**
Restating it gives you a stated rule, which is what `AGENTS.md` is made of.
Claude Code stops you; another tool is merely told. For a policy hook that is a
real fraction of the value. For a mechanical one (format on save, telemetry)
there is nothing to say, so say nothing.

## Translating each kind

**A hook → the rule it enforces.** Write the *rule*, not the hook. A gate that
denies writes to generated files becomes "never edit a generated file; edit its
source and run `just generate`." Skip hooks with no user-visible rule.

**A permission list → what is safe to run.** An allowlist entry is a statement
about your project: these commands are cheap and reversible. Other agents ask
before running things, and this is what lets them stop asking.

**An MCP server → capability plus setup.** Two separable facts. *What it
provides* is tool-agnostic and belongs in `AGENTS.md` outright. *How to wire it
up* is a pointer at `.mcp.json` plus the note that a tool supporting MCP can
load it.

**Skills and commands → a pointer, last.** `SKILL.md` is a real multi-vendor
format, so the content is usually portable even though its location isn't. Say
where they live and how to tell when one applies.

Order the block so the parts that work unconditionally come first. Whether an
agent will actually go read a `SKILL.md` on the strength of a sentence in
`AGENTS.md` is unverified — plausible for an agentic CLI with file access, and
exactly the kind of claim that sounds true without being tested. Put it last, so
if it does nothing you have lost nothing.

## Write a map, not an index

Name directories and formats, never individual skills or commands. An index of
skill names is stale the first time one is renamed, and nothing reports it. A
map stays true.

```markdown
## For agents other than Claude Code

Tooling for this repo lives in `.claude/`. Claude Code loads it
automatically; your tool does not. These rules apply to you anyway:

- Never edit a generated file. Edit its source and run `just generate`.
- Agent guidance is canonical here in AGENTS.md; CLAUDE.md only points at it.

Claude Code enforces those with hooks. Nothing enforces them for you.

Safe to run without asking: `just test`, `just check`.

`.mcp.json` declares the MCP servers this project uses. Load it if your tool
supports MCP.

If you can read files on demand: `.claude/skills/*/SKILL.md` are Agent Skills;
each frontmatter `description` says when it applies. Read one when it matches
the task. `.claude/commands/*.md` are prompt templates for `/name`.
```

## What stops the finding

Any mention of `.claude` in `AGENTS.md`. Whether a mention degrades *well* is
judgment, and cleat decides facts — so one mention is enough to stop the report,
and the quality of it is yours. The advisory severity says the same thing: a repo
may hold Claude-only config on purpose and owe nobody an explanation.
