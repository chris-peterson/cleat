# Why cleat stops at instruction files

cleat enforces `AGENTS.md` because `AGENTS.md` is a standard someone else
governs. This page records what happened when the same question was asked one
level up — about the `.claude/` **directory**, which holds skills, slash
commands, hooks, subagent definitions, and `settings.json`, and which Codex,
Cursor, Gemini CLI, and the rest cannot see.

The short answer: `.claude/` has no tool-agnostic counterpart to point at, and
cleat does not invent one. Sources below were checked on 2026-08-09.

## What is standardized, and what isn't

| Artifact | Cross-tool standard | Enforceable |
|---|---|---|
| Instruction file | `AGENTS.md`, stewarded by the Agentic AI Foundation under the Linux Foundation | yes — this is cleat |
| Skills | [Agent Skills](https://agentskills.io/specification) — `SKILL.md` plus frontmatter, a real format spec | format yes, location no |
| Slash commands | none | no |
| Hooks | none | no |
| Subagents | none | no |
| MCP server config *location* | none — MCP standardizes the wire protocol, not the file path | no |

## `.agents/skills/` is a convention, not a rule

`.agents/skills/` is real and shipped — OpenAI Codex, Google Gemini CLI, Cursor,
and opencode all read it. But the spec that defines what goes in a skill
declines to say where a skill lives. From the [client implementation
guide](https://agentskills.io/client-implementation/adding-skills-support):

> While the Agent Skills specification does not mandate where skill directories
> live (it only defines what goes inside them), scanning `.agents/skills/` means
> skills installed by other compliant clients are automatically visible to yours.

Its verb for client authors is *consider scanning*. The spec's own reference
validator takes a skill directory as an argument and checks the frontmatter
inside it; placement is never examined. So a linter has nothing to cite that
would let it require a path.

## Claude Code does not read `.agents/skills/`

The deciding fact. Claude Code's [skills
documentation](https://code.claude.com/docs/en/skills) lists four scopes —
enterprise, `~/.claude/skills/`, project `.claude/skills/`, and plugins — and
contains no occurrence of `.agents`.

That inverts the `AGENTS.md` argument instead of extending it. With instruction
files, the pointer shape reaches every tool at once. With skills, a repo that
moved to the interoperable path would hide them from the one tool cleat plugs
into. The available repairs are two copies that drift, or a symlink — and the
argument against symlinking `CLAUDE.md` applies here unchanged.

## The vendors excluded the rest deliberately

The [Agent Plugins Specification
v1.0.0](https://github.com/agentplugins/agent-plugins-spec) (published
2026-08-06; core maintainers from Amazon, Cursor, Microsoft, OpenAI, and Vercel)
packages agent extensions for distribution. It covers exactly two component
types, skills and MCP servers, and says why it stops there:

> Other component types — such as commands, hooks, agents, rules, and LSP
> servers — remain too client-specific for a stable portable contract.

It defines no repository-local directory: not `.agents/`, not `.plugins/`. This
is stronger than an absence of evidence. The people who would write the standard
looked at these artifacts and ruled three of them out of scope.

## What isn't a standard

[dotagentsprotocol.com](https://dotagentsprotocol.com/) proposes `.agents/` as
one home for MCP config, instructions, skills, subagents, tasks, and memories.
It is a single-author draft dated 2026-02-24, names no implementing tool, and
three of its seven "converging standards" originate in the draft itself. At
least three unrelated proposals claim the same directory name. Anything asserting
a `.agents/` config convention as settled is describing this, or something like
it.

One analogy to avoid, because it is the natural one to reach for and it is
wrong: `.claude/skills/` is **not** to `.agents/skills/` as `CLAUDE.md` is to
`AGENTS.md`. No source treats the vendor path as legacy or deprecated. Cursor
reads `.claude/skills/` as a first-class location.

## A wrinkle in the rubric

The rubric lists skills under Claude-specific guidance. That was true when it was
written and is now imprecise: `SKILL.md` is a multi-vendor format, so a skill's
*content* often is portable even though its *location* is not. The rubric is left
alone until the location question resolves, since changing it changes what a deny
tells you to do.

## What would change this

[agentskills/agentskills#15](https://github.com/agentskills/agentskills/issues/15),
open since 2025-12-19, proposes a standard folder for skills. If it lands as
normative spec text, `.agents/skills/` becomes citable and a cleat rule becomes
defensible — subject to Claude Code reading the path too. Watch that issue rather
than re-surveying the ecosystem.
