# Harness engineering

A harness is everything around a coding agent that steers its work: guidance
before each edit (feedforward) and checks on each edit once it's made
(feedback).

## A toddler and a hot stove

Picture the agent as a toddler in a kitchen with a hot stove. You can't watch
every move, so you set up help around them. Each kind of help in the kitchen is
one layer of a harness: two work before the touch (feedforward), and two work
after it (feedback).

| In the kitchen | In a coding session |
| --- | --- |
| The toddler | The agent |
| Touching the hot stove | An edit that needs correction |
| The adult, stopped from cooking | A false positive: a correct edit a check flags anyway |

Start with no help, then pick a kind of help to see what it does in the kitchen
and for the agent.

<iframe src="lab/stove.html" title="A toddler, an adult, and a hot stove, with no help or one of four kinds of help to pick" loading="lazy" style="width: 100%; height: 350px; border: 0;"></iframe>

## What it costs

| | Agent time and tokens |
| --- | --- |
| **Every edit** | **The baseline:** a turn of the agent's time and tokens. |
| **Always-on** | **Paid on every turn,** needed or not, and followed less as it grows. |
| **Just-in-time** | **Paid only when it fires** with the task it's for. |
| **Advisory** | **Cheap to run, cheap to act on:** a check on the edits it targets. A flagged edit gets a warning the agent reads and repairs. |
| **Blocking** | **Cheap to run, costly to act on:** a check on the edits it targets. A flagged edit is refused, the agent starts over, and the redo can go wrong too. |
| **Chasing perfection** | **The 80/20 rule:** most mistakes are cheap to rescue; chasing the rest brings diminishing returns. |

| | Your time |
| --- | --- |
| **Needs correction** | **The priciest:** someone finds the mistake, then fixes it or re-prompts. |
| **Building a layer** | **Up front, then a carrying cost.** Reliable triggers take the longest. |

## Why not just block everything?

Blocking is the only help in the kitchen that guarantees no burn. But a block
judges the action without its context: a stove that refuses every touch can't
tell a toddler from an adult who's cooking, so it stops the cook too. A
hook sees one action at a time: not the task, not what the person asked for, not
why the agent is doing it.

- **Can't judge:** a branch name or a chained `git push` can be matched with a
  pattern. A misread request, an edit outside what was asked, or a misleading
  comment takes judgment.
- **Can't tell look-alikes:** a list of banned words blocked the word "arm"
  where it named an experiment's arm, and the agent reworded a correct term.
  That's why listed words only warn, while em dashes, which a regex finds with
  full precision, still block.
- **Doesn't teach:** each block is a round trip, and the same trigger comes
  back. Feedforward is what makes the mistake rarer.
- **Can strand:** with no clear way around it, a person has to step in, the
  outcome the harness exists to avoid.

So block what a single action reveals precisely, especially when the mistake is
costly or hard to undo. Advise where the call needs judgment. Feed guidance
forward to make the mistake happen less often.

## Tips for building a harness

- **Earlier is cheaper:** feedforward costs context on every turn, but a mistake
  it prevents needs no fix or redo.
- **Later costs a redo:** a block sends the agent back to start the edit over,
  and the redo can go wrong too.
- **Just-in-time is the best rescue, when it fires:** making it fire on the
  right task is the hard part.
- **Feedforward leaves no trace:** to credit it, remove it and compare (an
  ablation test).
- **Layers compound:** each one rescues part of what the layers before it
  missed.

## Lab

The [lab](/lab) puts these layers together: build a harness one layer at a
time, and compare what each run rescues with what it costs.

## Further reading

Birgitta Böckeler's
[Harness engineering for coding agent users](https://martinfowler.com/articles/exploring-gen-ai/harness-engineering.html)
frames the harness as feedforward guides and feedback sensors, and the
Thoughtworks Technology Radar's
[Feedback sensors for coding agents](https://www.thoughtworks.com/radar/techniques/feedback-sensors-for-coding-agents)
recommends running those sensors in the session, before a commit.
