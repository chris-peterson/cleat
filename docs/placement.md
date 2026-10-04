[Where new content goes](guides/placement.md ':include')

## Behind the guide

The guide above is what cleat hands the agent when it asks where new guidance
belongs. This section is the background for people. Each kind of guidance in
its table is a layer of a harness, and
[Harness engineering](/harness-engineering) shows each one as a toddler at a hot
stove, with what it costs and why a block can't do the job alone.

### cleat follows its own advice

Nothing of cleat loads at launch. Its gate stops a write before it lands, and
its nudge reports right after one. That's also why it asks where new guidance
belongs at the write rather than earlier: a hook sees what the agent does, not
what it suggests in chat, so the question arrives when the agent acts on a
preference instead of when it recommends one. The session that answers pays one
round trip; every later session that would have carried the misplaced line is
the one that benefits.

### How to tell whether it's working

Each kind fails differently, so each has its own measure:

- **Always-on feedforward**: whether the mistake it exists to prevent still
  happens. If the matching feedback keeps firing, the instruction isn't working.
  Its effect only shows when you remove it and compare (an ablation test).
- **Just-in-time feedforward**: how often it loads where it doesn't apply. A
  rule whose globs match too much turns into always-on feedforward at a higher
  price. When it does fire, the agent's next action either follows it or
  doesn't, so it can be measured directly.
- **Feedback**: how often it fires, and how often the agent acts on it. A deny
  that's re-issued unchanged every time is noise, and the rule behind it belongs
  in a narrower place or nowhere.

### Further reading

Birgitta Böckeler's
[Harness engineering for coding agent users](https://martinfowler.com/articles/exploring-gen-ai/harness-engineering.html)
frames the harness as feedforward guides and feedback sensors, and the
Thoughtworks Technology Radar's
[Feedback sensors for coding agents](https://www.thoughtworks.com/radar/techniques/feedback-sensors-for-coding-agents)
recommends running those sensors in the session, before a commit.
