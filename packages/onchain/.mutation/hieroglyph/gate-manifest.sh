#!/bin/zsh
# Known-answer test for the manifest-metadata survivor class (roadmap task 46).
#
# 514 of the campaign's survivors are mutations inside Descripex `api(...)`
# blocks -- agent-facing prose and option atoms rendered into
# api_manifest.json. Dispositioning them as "not the wire format, guarded
# elsewhere" is only worth writing down if the other guard demonstrably fires,
# so this asserts it in both directions, the same way .mutation/gate-muex20.sh
# grades muex itself:
#
#   unmutated tree              -> `mix hieroglyph.manifest --check` exits 0
#   one api() description edited -> exits 1, reporting a stale manifest
#
# The point of the class is not that these mutants are harmless. It is that
# `mix test` -- the only thing muex runs -- is the wrong gate for them, and the
# right one is a `mix ci` step muex never invokes.
set -u
cd "${0:A:h}/.." || exit 1

FILE=lib/abi.ex
ANCHOR='api(:encode, "Encodes the given data into the function signature or tuple signature.",'
BAK=$(mktemp -t hieroglyph-manifest-gate)
cp "$FILE" "$BAK"
restore() { cp "$BAK" "$FILE"; rm -f "$BAK"; }
trap restore EXIT INT TERM

MIX_ENV=dev mix hieroglyph.manifest --check > /dev/null 2>&1
clean=$?
echo "--- unmutated tree: exit $clean (want 0)"

python3 - "$FILE" "$ANCHOR" <<'PY'
import pathlib, sys
path, anchor = pathlib.Path(sys.argv[1]), sys.argv[2]
src = path.read_text()
if anchor not in src:
    sys.exit("gate anchor no longer present in %s -- update ANCHOR" % path)
path.write_text(src.replace(anchor, anchor.replace('signature.",', 'signature.x",'), 1))
PY
[ $? -eq 0 ] || { echo "=== GATE INCONCLUSIVE: could not apply the mutation" >&2; exit 2; }

MIX_ENV=dev mix hieroglyph.manifest --check > /dev/null 2>&1
mutated=$?
echo "--- one api() description mutated: exit $mutated (want non-zero)"

if [ "$clean" -eq 0 ] && [ "$mutated" -ne 0 ]; then
  echo "=== GATE PASSES: api() prose is gated by mix hieroglyph.manifest --check"
  exit 0
fi
echo "=== GATE FAILS: the manifest check does not separate these two trees" >&2
exit 1
