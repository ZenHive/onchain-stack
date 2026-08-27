#!/usr/bin/env python3
"""Regenerate the vendored ethers.js vector subset in this directory.

Usage:  python3 test/support/fixtures/ethers/vendor.py

Downloads @ethersproject/testcases from the npm registry, slims each corpus to
the fields the Elixir assertions consume, and applies the filter criteria
recorded in PROVENANCE.md. Output is byte-stable for a given upstream tarball,
so a re-run on an unchanged corpus leaves the working tree clean.
"""

import base64
import gzip
import hashlib
import io
import json
import os
import tarfile
import urllib.request

TARBALL = "https://registry.npmjs.org/@ethersproject/testcases/-/testcases-5.8.0.tgz"
# npm registry `dist.integrity` for testcases 5.8.0, re-derived from the
# downloaded bytes. The corpus is only usable as an INDEPENDENT ORACLE if the
# bytes it came from are the bytes upstream published, so the download is
# verified rather than trusted: a registry compromise, a proxy rewrite or a
# truncated transfer would otherwise regenerate a corpus that silently
# redefines what "correct" means for the whole wire-format suite.
TARBALL_INTEGRITY = "sha512-Jx/g2GoLwW0nv3/QpB9/Yfla1TPaqTop2lfa4HTOSGHKk4Q++aGoMUkZG/KrsuNdbHnROrXogjLTMqq6TauQNQ=="
CORPORA = (
    "contract-interface",
    "contract-interface-abi2",
    "contract-signatures",
    "contract-events",
)
MAX_RECORD_BYTES = 4096
RANDOM_STRIDE = 5
OUT_DIR = os.path.dirname(os.path.abspath(__file__))


def verify(raw: bytes) -> None:
    """Abort unless the downloaded tarball matches the pinned npm integrity."""
    digest = "sha512-" + base64.b64encode(hashlib.sha512(raw).digest()).decode()
    if digest != TARBALL_INTEGRITY:
        raise SystemExit(
            "tarball integrity mismatch\n  expected %s\n  got      %s"
            % (TARBALL_INTEGRITY, digest)
        )


def fetch() -> dict:
    with urllib.request.urlopen(TARBALL) as response:
        raw = response.read()

    verify(raw)

    corpora = {}
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz") as tar:
        for name in CORPORA:
            member = tar.extractfile("package/testcases/%s.json.gz" % name)
            corpora[name] = json.loads(gzip.decompress(member.read()))

    return corpora


def as_json(value):
    """Several corpus fields are JSON encoded inside a JSON string."""
    return json.loads(value) if isinstance(value, str) else value


def unwrap(value):
    """Flatten ethers {type, value} descriptors into plain JSON.

    Integers keep their upstream spelling (decimal in contract-interface,
    BigNumber hex in contract-events); the Elixir loader coerces both.
    """
    if isinstance(value, list):
        return [unwrap(item) for item in value]

    if isinstance(value, dict):
        kind, inner = value["type"], value["value"]
        if kind == "number":
            return str(inner)
        if kind in ("buffer", "string"):
            return inner
        if kind == "boolean":
            return bool(inner)
        if kind == "tuple":
            return [unwrap(item) for item in inner]
        raise SystemExit("unknown value descriptor: " + kind)

    return value


def utf8_clean(value) -> bool:
    """Reject the handful of vectors carrying unpaired UTF-16 surrogates."""
    try:
        json.dumps(value, ensure_ascii=False).encode("utf-8")
        return True
    except (UnicodeEncodeError, UnicodeDecodeError):
        return False


def slim(name, corpus):
    records = []

    for case in corpus:
        if name == "contract-signatures":
            records.append(
                {"name": case["name"], "signature": case["signature"], "sigHash": case["sigHash"]}
            )
            continue

        if name == "contract-events":
            # `values`, not `normalizedValues`: the latter substitutes the topic
            # hash for hashed indexed reference types, so it is the decode
            # side's expectation rather than an encodable input.
            values = [unwrap(v) for v in as_json(case["values"])]
            event = next(
                item
                for item in json.loads(case["interface"])
                if item.get("type") == "event" and item["name"] == "testEvent"
            )
            record = {
                "name": case["name"],
                "types": as_json(case["types"]),
                "values": values,
                "topics": case["topics"],
                "data": case["data"],
                "indexed": case["indexed"],
                "hashed": case["hashed"],
                "abi": event,
            }
        else:
            # `normalizedValues` where present: the generator feeds values that
            # the contract then truncates to the declared width, and `result`
            # records the truncated encoding.
            values = [
                unwrap(v) for v in as_json(case.get("normalizedValues") or case["values"])
            ]
            record = {
                "name": case["name"],
                "types": as_json(case["types"]),
                "values": values,
                "result": case["result"],
            }

        if not utf8_clean(record["values"]):
            continue

        records.append(record)

    return records


def apply_filter(records):
    """See PROVENANCE.md — order matters and is part of the criterion."""
    kept, seen_random = [], 0

    for record in records:
        if len(json.dumps(record, ensure_ascii=False).encode("utf-8")) > MAX_RECORD_BYTES:
            continue

        if record["name"].startswith("random-"):
            keep = seen_random % RANDOM_STRIDE == 0
            seen_random += 1
            if not keep:
                continue

        kept.append(record)

    return kept


def main():
    corpora = fetch()

    for name in CORPORA:
        records = apply_filter(slim(name, corpora[name]))
        path = os.path.join(OUT_DIR, name + ".json")

        with open(path, "w", encoding="utf-8") as handle:
            json.dump(records, handle, ensure_ascii=False, indent=0, separators=(",", ":"))
            handle.write("\n")

        print("%-26s %5d vectors  %8d bytes" % (name, len(records), os.path.getsize(path)))


if __name__ == "__main__":
    main()
