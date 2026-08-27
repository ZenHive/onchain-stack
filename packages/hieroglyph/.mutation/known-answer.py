#!/usr/bin/env python3
"""Cross-reference a muex campaign against the task-44 planted-mutant corpus.

The corpus (`test/support/mutants/mutants.exs`) is a known-answer test: seven
of its eight single-site edits are killed by the existing vectors, and
`mod-negative-branch` is a recorded survivor carrying an unreachability
argument (ledger section 5). A muex run that cannot reproduce that split at
those sites is not measuring this library -- so this check is read BEFORE any
other campaign number.

The two tools do not plant the same edit at a site, so the comparison is
between VERDICTS at the site, not between mutations. A corpus `:killed` site
where every muex mutation survives is a disagreement to investigate, not a
result to record.

Usage: known-answer.py .mutation/results/campaign.json
"""

import json
import re
import sys
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


CORPUS = ROOT / "test/support/mutants/mutants.exs"


def load_corpus():
    """Resolve each corpus anchor to a current file:line, the way the runner does."""
    text = CORPUS.read_text()
    entries = []
    for block in re.findall(r"%\{(.*?)\n  \}", text, re.S):
        get = lambda k: (m.group(1) if (m := re.search(rf'{k}: "((?:[^"\\]|\\.)*)"', block, re.S)) else None)
        expect = re.search(r"expect: :(\w+)", block)
        find = get("find")
        if find is None or expect is None:
            continue
        needle = find.encode().decode("unicode_escape")
        path = ROOT / get("file")
        src = path.read_text()
        count = src.count(needle)
        entries.append({
            "id": get("id"),
            "file": get("file"),
            "expect": expect.group(1),
            "site": get("site"),
            "occurrences": count,
            # A `find:` anchor may span several source lines (a whole pipeline,
            # a clause with its guard).  muex attributes each mutation to the
            # line carrying the mutated token, which for a multi-line anchor is
            # rarely the anchor's first line -- so the site is a LINE SPAN, not
            # a single line.  Comparing against the first line only reports a
            # phantom disagreement (seen on `event-signature-annotates-indexed`,
            # whose anchor starts on the bare `function_selector` line while
            # every mutation lands on the two `|>` lines below it).
            "line": src[: src.index(needle)].count("\n") + 1 if count == 1 else None,
            "line_end": (src[: src.index(needle)].count("\n") + 1
                         + needle.rstrip("\n").count("\n")) if count == 1 else None,
        })
    return entries


def load_mutations(path):
    """muex --format json, tolerant of banner text before the document."""
    doc = load_json_document(path)
    for key in ("mutations", "results", "details", "mutants"):
        if isinstance(doc.get(key), list):
            return doc[key], doc
    raise SystemExit(f"no mutation list in {path}; top-level keys: {sorted(doc)}")


def field(mutation, *names):
    """Read a field, looking inside the nested `location` object too.

    muex's JSON reporter nests the site as {"location": {"file": ..., "line": ...}}
    while keeping status/mutator/description flat.
    """
    for n in names:
        if mutation.get(n) not in (None, ""):
            return mutation[n]
        loc = mutation.get("location") or {}
        if loc.get(n) not in (None, ""):
            return loc[n]
    return None


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    mutations, doc = load_mutations(sys.argv[1])
    corpus = load_corpus()

    by_site = {}
    for m in mutations:
        f = field(m, "file", "path")
        ln = field(m, "original_line", "line")
        if f is None or ln is None:
            continue
        by_site.setdefault(str(f).removeprefix("./"), []).append((int(ln), m))

    print(f"campaign: {sys.argv[1]}")
    summary = doc.get("summary", doc)
    print("summary:", {k: summary.get(k) for k in
                       ("total", "killed", "survived", "invalid", "no_coverage",
                        "timeout", "equivalent", "mutation_score_high", "mutation_score_low")})
    print()

    disagreements = 0
    for e in corpus:
        if e["occurrences"] != 1:
            print(f"!! {e['id']}: anchor matches {e['occurrences']}x -- corpus has drifted, "
                  "no comparison possible")
            disagreements += 1
            continue
        hits = [m for ln, m in by_site.get(e["file"], [])
                if e["line"] <= ln <= e["line_end"]]
        verdicts = sorted({str(field(m, "status", "verdict", "result")) for m in hits})
        agrees = (
            "survived" in verdicts if e["expect"] == "survivor"
            else "killed" in verdicts
        )
        if not hits:
            agrees = False
        flag = "ok " if agrees else "!! "
        if not agrees:
            disagreements += 1
        span = (f"{e['line']}" if e["line"] == e["line_end"]
                else f"{e['line']}-{e['line_end']}")
        print(f"{flag}{e['id']:<38} {e['file']}:{span:<7} "
              f"corpus={e['expect']:<9} muex={len(hits)} mutation(s) {verdicts or '[none generated]'}")
        for m in hits:
            print(f"      - {field(m, 'mutator', 'type')}: "
                  f"{field(m, 'description', 'name', 'mutation')} -> "
                  f"{field(m, 'status', 'verdict', 'result')}")

    print()
    if disagreements:
        print(f"DISAGREEMENTS: {disagreements} -- investigate and write down before "
              "reading any other campaign number")
        return 1
    print("KNOWN ANSWER REPRODUCED: every corpus site agrees with the recorded verdict")
    return 0


if __name__ == "__main__":
    sys.exit(main())
