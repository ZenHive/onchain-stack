#!/usr/bin/env python3
"""Draw a fixed, reproducible sample of the campaign's KILLED mutations.

Re-grading survivors cannot see a false kill: it only looks at mutants the
campaign already spared. The restore defect (ledger §7.2d) manufactures kills,
and muex's own runner restores between mutants exactly as the first version of
the re-grade harness did -- so the campaign's kill count is subject to a
mechanism nothing in this campaign otherwise checks.

This draws a sample of them so the false-kill rate can be BOUNDED by
measurement instead of argued about. The seed is fixed so the sample is part of
the record rather than a number that changes on re-run.

  ./.mutation/sample-kills.py [n]
  MIX_ENV=test mix run .mutation/verify-survivors.exs \\
      .mutation/results/killsample-input.json --status killed
"""
import json
import pathlib
import random
import sys

RESULTS = pathlib.Path(__file__).resolve().parent / "results"
SEED = 46  # the roadmap task number, so the choice is not a knob


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    raw = (RESULTS / "campaign.json").read_text()
    doc = json.JSONDecoder().raw_decode(raw, raw.index("{"))[0]
    killed = [m for m in doc["mutations"] if m["status"] == "killed"]

    # verify-survivors.exs selects on `status`; the sample is re-graded as a
    # "killed" cohort, and its output records `reported: killed`.
    sample = random.Random(SEED).sample(killed, min(n, len(killed)))
    out = RESULTS / "killsample-input.json"
    out.write_text(json.dumps({"summary": doc["summary"], "mutations": sample}))
    print(f"{len(killed)} killed in campaign; sampled {len(sample)} "
          f"(seed {SEED}) -> {out}")


if __name__ == "__main__":
    main()
