#!/usr/bin/env python3
"""Partition survivors into documentation vs behaviour, so criterion 4's
written disposition can treat the documentation classes as classes and spend
the individual attention on the mutants that encode behaviour.

  ./.mutation/triage.py .mutation/results/campaign.json [--class behaviour]

Classes:
  api   -- inside a Descripex `api(...)` metadata block: prose and option
           atoms rendered into api_manifest.json, not encoder behaviour.
  doc   -- inside @moduledoc/@doc/@typedoc.
  behaviour -- everything else. These get individual dispositions.

Spans come from .mutation/results/spans.json (see .mutation/spans.exs).
"""
import json, sys, collections, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent


def load_json_document(path):
    raw = pathlib.Path(path).read_text()
    return json.JSONDecoder().raw_decode(raw, raw.index("{"))[0]


def classify(spans, file, line):
    for s in spans.get(file, []):
        if s["line"] <= line <= s["last"]:
            return s["kind"]
    return "behaviour"


def main():
    doc = load_json_document(sys.argv[1])
    spans = load_json_document(ROOT / ".mutation/results/spans.json")
    want = None
    if "--class" in sys.argv:
        want = sys.argv[sys.argv.index("--class") + 1]

    survivors = [m for m in (doc.get("mutations") or []) if m["status"] == "survived"]

    # Fold in the full-suite re-grade when it exists. muex graded lib/abi.ex
    # against 2 of 15 test files (see the ledger, campaign section), so its raw
    # `survived` verdicts are not trustworthy; verified.json carries the
    # verdict from a serial run of the whole suite and wins wherever it exists.
    verified_path = ROOT / ".mutation/results/verified.json"
    if verified_path.exists():
        verified = {
            (v["file"], v["line"], v["mutator"], v["description"]): v["verified"]
            for v in load_json_document(verified_path)["results"]
        }
        if verified:
            before = len(survivors)
            survivors = [
                m for m in survivors
                if verified.get((m["location"]["file"], m["location"]["line"],
                                 m["mutator"], m["description"]), "survived") == "survived"
            ]
            print(f"re-graded against the full suite: {before - len(survivors)} of "
                  f"{before} reported survivors were actually killed\n")
    tagged = [(classify(spans, m["location"]["file"], m["location"]["line"]), m)
              for m in survivors]

    counts = collections.Counter(k for k, _ in tagged)
    print(f"survivors: {len(survivors)}")
    for k in ("api", "doc", "behaviour"):
        print(f"  {k:<10} {counts.get(k, 0)}")

    per_file = collections.defaultdict(collections.Counter)
    for k, m in tagged:
        per_file[m["location"]["file"]][k] += 1
    print("\nper module (survivors)")
    print(f"  {'file':<32}{'api':>6}{'doc':>6}{'behaviour':>11}")
    for f in sorted(per_file):
        c = per_file[f]
        print(f"  {f:<32}{c['api']:>6}{c['doc']:>6}{c['behaviour']:>11}")

    if want:
        src_cache = {}
        sel = [m for k, m in tagged if k == want]
        print(f"\n## {want} survivors ({len(sel)})")
        for m in sorted(sel, key=lambda m: (m["location"]["file"], m["location"]["line"])):
            f, ln = m["location"]["file"], m["location"]["line"]
            src = src_cache.setdefault(f, (ROOT / f).read_text().split("\n"))
            line = src[ln - 1].strip() if 0 < ln <= len(src) else "?"
            print(f"\n{f}:{ln}  {m['mutator'].split('.')[-1]}")
            print(f"    {m['description']}")
            print(f"    src: {line[:120]}")


if __name__ == "__main__":
    main()
