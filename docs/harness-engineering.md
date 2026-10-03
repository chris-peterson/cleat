# Harness engineering

A harness is everything around a coding agent that steers its work: guidance
before each edit (feedforward) and checks on each edit once it's made
(feedback).

## A toddler and a hot stove

Pick a kind of help and watch what changes.

<iframe src="lab/stove.html" title="A toddler, an adult, and a hot stove, with four kinds of help to pick from" loading="lazy" style="width: 100%; height: 560px; border: 0;"></iframe>

## Why not just block everything?

A block judges the action without its context. A stove that shuts off at the
touch can't tell a toddler from an adult who's cooking, so it stops both. A hook
sees one action at a time: not the task, not what the person asked for, not why
the agent is doing it.

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

## What it costs

| | Agent time and tokens |
| --- | --- |
| **Every edit** | **The baseline:** a turn of the agent's time and tokens. |
| **Always-on** | **Paid on every turn,** needed or not, and followed less as it grows. |
| **Just-in-time** | **Paid only when it fires** with the task it's for. |
| **Advisory** | **Cheap to run, cheap to act on:** a check on the edits it targets. A catch is a warning the agent reads and repairs. |
| **Blocking** | **Cheap to run, costly to act on:** a check on the edits it targets. A catch refuses the edit, the agent starts over, and the redo can go wrong too. |
| **Chasing perfection** | **The 80/20 rule:** most mistakes are cheap to catch; chasing the rest brings diminishing returns. |

| | Your time |
| --- | --- |
| **Needs correction** | **The priciest:** someone finds the mistake, then fixes it or re-prompts. |
| **Building a layer** | **Up front, then a carrying cost.** Reliable triggers take the longest. |

## Tips for building a harness

- **Earlier is cheaper:** feedforward costs context on every turn, but a mistake
  it prevents needs no fix or redo.
- **Later costs a redo:** a block sends the agent back to start the edit over,
  and the redo can go wrong too.
- **Just-in-time is the best catch, when it fires:** making it fire on the right
  task is the hard part.
- **Feedforward leaves no trace:** to credit it, remove it and compare.
- **Layers compound:** each one catches part of what the layers before it
  missed.

## Gotchas

- **False alarms:** checks also flag fine edits, and each one costs a turn or
  talks the agent out of a right answer.
- **Carrying cost:** every rule, skill, hook and check needs more time to keep
  current as the code and the tools change.

## Lab

The [lab](/lab) puts these layers together: build a harness one layer at a
time, and compare what each run catches with what it costs.
