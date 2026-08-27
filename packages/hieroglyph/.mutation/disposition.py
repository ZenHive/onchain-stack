#!/usr/bin/env python3
"""Assign every surviving mutant exactly one disposition class, and fail if any
is left unclassified.

Criterion 4 of roadmap task 46 requires each survivor to be dispositioned in
writing as one of: killed by a new test added in this task, provably equivalent
with the argument, or an accepted gap with the reason -- none left
unclassified. At this scale that is done by CLASS: each survivor is mapped to
exactly one class by the rules below, each class carries its argument in
docs/abi-verification-ledger.md, and this script is the coverage gate proving
no survivor fell through.

Verdicts come from the campaign as corrected by ONE serial re-grade against the
full suite -- results/verified-authoritative.json. Not a union of passes; see
surviving_mutations() for why that rule was retracted.

  ./.mutation/disposition.py            # summary + coverage gate
  ./.mutation/disposition.py --write    # also write results/dispositions.md
  ./.mutation/disposition.py --class X  # list one class
  ./.mutation/disposition.py --emit-input F.json --classes a,b
                                        # re-grade input for those classes
"""
import collections
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RESULTS = ROOT / ".mutation/results"


def load_json_document(path):
    raw = pathlib.Path(path).read_text()
    return json.JSONDecoder().raw_decode(raw, raw.index("{"))[0]


def key(m):
    return (m["location"]["file"], m["location"]["line"], m["mutator"],
            m["description"])


def surviving_mutations():
    """Campaign survivors minus anything the authoritative re-grade killed.

    ONE run decides, not a union of runs. The earlier merge rule -- a kill in
    any pass wins, on the reasoning that a kill is positive evidence while a
    survival is only its absence -- was falsified by measurement:
    Muex.Sandbox.restore/2 leaves the mutated .beam in the sandbox, so a
    mutant can be graded against its PREDECESSOR's code and reported killed
    when nothing it did could fail a test. Under a union rule one such false
    kill is permanent, because no later pass can retract it.
    .mutation/verify-survivors.exs now forces a recompile after every restore;
    verified-authoritative.json is the run made with that fix, and the earlier
    verified-pass*.json files are kept only as the evidence trail for the bug.
    """
    doc = load_json_document(RESULTS / "campaign.json")
    path = RESULTS / "verified-authoritative.json"
    if not path.exists():
        raise SystemExit("missing results/verified-authoritative.json -- run "
                         ".mutation/verify-survivors.exs over "
                         "results/authoritative-input.json first")
    killed = {(r["file"], r["line"], r["mutator"], r["description"])
              for r in load_json_document(path)["results"]
              if r["verified"] == "killed"}
    survivors = [m for m in doc["mutations"]
                 if m["status"] == "survived" and key(m) not in killed]
    return doc, survivors, killed, 1


def provably_equivalent():
    """Mutants that compile to byte-identical BEAM, per .mutation/equivalence.exs.

    Sound in one direction only: an `equivalent` verdict is a proof that no
    test can kill the mutant, while `distinguishable` means only that the
    bytecode differs -- evaluation order of a pure expression differs in the
    instruction stream without being observable. So this promotes mutants OUT
    of the argued classes, never into them.
    """
    path = RESULTS / "equivalent.json"
    if not path.exists():
        return set()
    return {(r["file"], r["line"], r["mutator"], r["description"])
            for r in load_json_document(path)["results"]
            if r["equivalence"] == "equivalent"}


def argued_equivalent(survivors):
    """Survivors carrying a written equivalence argument in argued-equivalent.json.

    Returns (keys, stale). A selector that matches no surviving mutant is
    STALE -- the argument has outlived its mutant, which is exactly how a
    disposition file rots into fiction -- and main() fails on it.
    """
    path = ROOT / ".mutation/argued-equivalent.json"
    if not path.exists():
        return set(), []
    doc = json.loads(path.read_text())
    index = collections.defaultdict(list)
    for m in survivors:
        mutator = m["mutator"].rsplit(".", 1)[-1]
        index[(m["location"]["file"], m["location"]["line"], mutator)].append(m)

    keys, stale = set(), []
    for group in doc["groups"]:
        for sel in group["selectors"]:
            hit = [m for m in index[(sel["file"], sel["line"], sel["mutator"])]
                   if "description" not in sel
                   or m["description"] == sel["description"]]
            if not hit:
                stale.append(f"{group['id']}: {sel['file']}:{sel['line']} "
                             f"{sel['mutator']}")
                continue
            keys.update(key(m) for m in hit)
    return keys, stale


def classify(m, spans, src, equivalent, argued):
    """Ordered rules; the first match wins, so every survivor gets one class."""
    f, line = m["location"]["file"], m["location"]["line"]
    mutator = m["mutator"].rsplit(".", 1)[-1]
    kinds = {s["kind"] for s in spans.get(f, []) if s["line"] <= line <= s["last"]}

    # A machine-checked proof outranks every argued class.
    if key(m) in equivalent:
        return "provably-equivalent"
    if key(m) in argued:
        return "argued-equivalent"

    # A raise inside an api(...) block is still an error message; check the
    # narrower class first.
    if "raise" in kinds:
        return "error-message"
    if "api" in kinds:
        return "manifest-metadata"
    if "doc" in kinds:
        return "doc-attribute"
    if mutator == "Guard":
        return "guard"

    text = src[f][line - 1] if 0 < line <= len(src[f]) else ""
    if "when " in text and mutator in ("Comparison", "Boolean",
                                       "NegateConditionals"):
        return "guard"
    return "unreviewed"


def main():
    doc, survivors, killed, passes = surviving_mutations()
    spans = load_json_document(RESULTS / "spans.json")
    src = {}
    for m in survivors:
        f = m["location"]["file"]
        src.setdefault(f, (ROOT / f).read_text().split("\n"))

    equivalent = provably_equivalent()
    argued, stale = argued_equivalent(survivors)
    tagged = [(classify(m, spans, src, equivalent, argued), m)
              for m in survivors]
    counts = collections.Counter(c for c, _ in tagged)

    s = doc["summary"]
    print(f"campaign: {s['total']} mutations, {s['killed']} killed, "
          f"{s['survived']} reported survived, {s['invalid']} invalid, "
          f"{s.get('timeout', 0)} timeout")
    print(f"authoritative re-grade: {len(killed)} reported survivors proved "
          f"killable ({passes} run, restore-fix applied)")
    print(f"survivors to disposition: {len(survivors)}\n")

    for c, n in counts.most_common():
        print(f"  {n:>5}  {c}")

    want = None
    if "--class" in sys.argv:
        want = sys.argv[sys.argv.index("--class") + 1]
    if want:
        print(f"\n## {want}")
        for c, m in sorted(tagged, key=lambda t: (t[1]["location"]["file"],
                                                  t[1]["location"]["line"])):
            if c != want:
                continue
            f, line = m["location"]["file"], m["location"]["line"]
            print(f"\n{f}:{line}  {m['mutator'].rsplit('.', 1)[-1]}")
            print(f"    {m['description']}")
            print(f"    src: {src[f][line - 1].strip()[:110]}")

    if "--emit-input" in sys.argv:
        out = pathlib.Path(sys.argv[sys.argv.index("--emit-input") + 1])
        wanted = sys.argv[sys.argv.index("--classes") + 1].split(",")
        picked = [m for c, m in tagged if c in wanted]
        out.write_text(json.dumps({
            "summary": doc["summary"],
            "mutations": picked,
        }))
        print(f"\nwrote {out}: {len(picked)} mutation(s) in "
              f"{', '.join(wanted)}")
        return 0

    if "--write" in sys.argv:
        out = RESULTS / "dispositions.md"
        with out.open("w") as fh:
            fh.write("# Survivor dispositions\n\n")
            fh.write("Generated by `.mutation/disposition.py`. The argument "
                     "for each class is in\n`docs/abi-verification-ledger.md`."
                     "\n\n")
            for c, n in counts.most_common():
                fh.write(f"- **{c}** — {n}\n")
            fh.write("\n| file | line | mutator | mutation | class |\n")
            fh.write("|---|---|---|---|---|\n")
            for c, m in sorted(tagged, key=lambda t: (t[1]["location"]["file"],
                                                      t[1]["location"]["line"])):
                d = m["description"].replace("|", "\\|")
                fh.write(f"| {m['location']['file']} | {m['location']['line']} "
                         f"| {m['mutator'].rsplit('.', 1)[-1]} | {d} | {c} |\n")
        print(f"\nwrote {out}")

    if stale:
        print(f"\nSTALE ARGUMENTS: {len(stale)} selector(s) in "
              "argued-equivalent.json match no surviving mutant")
        for line in stale:
            print(f"    {line}")
        return 1

    unreviewed = counts.get("unreviewed", 0)
    if unreviewed:
        print(f"\nUNCLASSIFIED: {unreviewed} survivor(s) have no disposition "
              "class yet")
        return 1
    print("\nevery survivor carries a disposition class")
    return 0


if __name__ == "__main__":
    sys.exit(main())
