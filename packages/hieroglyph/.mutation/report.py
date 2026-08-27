#!/usr/bin/env python3
"""Turn a muex campaign JSON into the numbers the verification ledger records.

Two outputs:
  * per-module counts by verdict (the ledger's campaign table)
  * the full survivor list with each mutant's patch and its source line,
    which is the input to survivor triage -- every entry here has to end up
    dispositioned as killed-by-a-new-test, provably equivalent, or an
    accepted gap with a reason.

`equivalent` is a verdict muex assigns, not a silent drop: Trivial Compiler
Equivalence proves the mutant compiles to byte-identical BEAM code, so no test
can ever distinguish it. Those are excluded from the score denominator
(killed + survived + timeout) and are already dispositioned by construction.

Usage: report.py .mutation/results/campaign.json [--survivors-only]
"""

import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def load_json_document(path):
    """Read muex's JSON report, tolerating anything printed around it.

    muex writes the report to the same stdout its progress logs use, and a
    `mix` banner can precede it on an uncompiled project. `raw_decode` stops at
    the end of the first complete document instead of failing on trailing text
    the way `json.loads` does.
    """
    raw = Path(path).read_text()
    start = raw.index("{")
    return json.JSONDecoder().raw_decode(raw, start)[0]


ORDER = ["killed", "survived", "timeout", "equivalent", "invalid", "no_coverage"]


def source_line(file, line):
    try:
        return (ROOT / file).read_text().splitlines()[line - 1].strip()
    except (OSError, IndexError):
        return "<unreadable>"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    survivors_only = "--survivors-only" in sys.argv
    if len(args) != 1:
        raise SystemExit(__doc__)

    doc = load_json_document(args[0])
    muts = doc["mutations"]
    summary = doc["summary"]

    by_file = defaultdict(Counter)
    by_mutator = defaultdict(Counter)
    for m in muts:
        status = str(m["status"])
        by_file[m["location"]["file"]][status] += 1
        by_mutator[m["mutator"]][status] += 1

    if not survivors_only:
        print("## summary")
        for k in ("total", "killed", "survived", "timeout", "invalid",
                  "mutation_score_low", "mutation_score_high"):
            if k in summary:
                print(f"  {k}: {summary[k]}")
        equiv = sum(c["equivalent"] for c in by_file.values())
        print(f"  equivalent (TCE, excluded from denominator): {equiv}")
        print()

        cols = [c for c in ORDER if any(c in v for v in by_file.values())]
        print("## per module")
        head = f"  {'file':<32}" + "".join(f"{c:>12}" for c in cols) + f"{'total':>8}"
        print(head)
        for f in sorted(by_file):
            counts = by_file[f]
            row = f"  {f:<32}" + "".join(f"{counts.get(c, 0):>12}" for c in cols)
            print(row + f"{sum(counts.values()):>8}")
        print()

        print("## per mutator")
        for mu in sorted(by_mutator, key=lambda k: -by_mutator[k]["survived"]):
            counts = by_mutator[mu]
            print(f"  {mu:<44} survived={counts.get('survived', 0):<5} "
                  f"killed={counts.get('killed', 0):<5} "
                  f"equivalent={counts.get('equivalent', 0):<5} "
                  f"total={sum(counts.values())}")
        print()

    survivors = [m for m in muts if str(m["status"]) == "survived"]
    print(f"## survivors ({len(survivors)})")
    for i, m in enumerate(sorted(survivors, key=lambda m: (m["location"]["file"],
                                                           m["location"]["line"])), 1):
        loc = m["location"]
        patch = m.get("patch") or {}
        print(f"\n[{i}] {loc['file']}:{loc['line']}  {m['mutator']}")
        print(f"    {m['description']}")
        print(f"    source: {source_line(loc['file'], loc['line'])}")
        if patch.get("before") is not None:
            print(f"    before: {str(patch['before']).strip()[:200]}")
            print(f"    after:  {str(patch['after']).strip()[:200]}")


if __name__ == "__main__":
    main()
