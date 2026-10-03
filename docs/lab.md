# Lab

Build a harness one layer at a time and watch 100 edits fall through it: how
many land as acceptable, how many need correction, and what the harness cost in
agent time, tokens, and your time. The lab opens by running the edits with no
harness, the baseline (an ablation test of the whole harness). Each run after
that sends the same 100 edits through the layers you've added and compares the
result with the baseline. [Harness engineering](/harness-engineering) explains
the layers.

<iframe src="lab/index.html" title="Harness lab: 100 edits falling through the layers you add" style="width: 100%; height: 1000px; border: 0;"></iframe>

The rates and costs in the lab are made up to show how a harness behaves, not
measured from real sessions.
