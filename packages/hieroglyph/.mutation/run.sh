#!/bin/zsh
# Roadmap task 46 -- mutation-adequacy campaign over the ABI surface.
#
# READ .mutation/gate-muex20.sh FIRST. It is the known-answer test for the
# measuring tool, and until it passes on the installed muex, nothing this
# script prints means anything.
#
# SCOPE. `lib/abi.ex` plus `lib/abi/*.ex`. The task scopes the campaign at
# "lib/abi/*.ex", but `method_id/1` -- one of the eight planted-corpus sites
# the known-answer check reads -- lives in the top-level `lib/abi.ex`, so a
# glob that excluded it would make criterion 2 unanswerable. `lib/mix/tasks/`
# is out of scope per the task, and `src/` is yecc/leex output: a mutant in
# generated Erlang is unfixable by definition, the same reason `.reach.exs`
# had to be scoped away from it.
#
# ONE invocation over the whole surface, deliberately. Per-module invocations
# are not equivalent in cost -- muex rebuilds its per-file indexes from
# scratch on every invocation, which is what exhausted a harness run's
# lifetime budget in cartouche.
#
# NO --coverage-guided, deviating from cartouche's campaign on purpose. That
# flag narrows which EXISTING tests run per mutant; cartouche needed it
# because its suite was slow. This suite is 460 tests in ~0.5s, so the saving
# is noise and the flag only adds a failure mode -- a coverage index that
# narrows too far turns a killed mutant into a false survivor, silently. Every
# mutant here is graded against the FULL suite, which is the stricter reading.
#
# --concurrency 8, against the cartouche precedent, and only because the
# precedent's reason was measured away rather than assumed away. cartouche had
# to run serial: muex 0.8.x could only isolate a worker's `_build` when it
# could name the app, its `detect_app_from_build/2` glob resolved on a single
# match, and any project with dependencies got `nil` -- so every sandbox shared
# one ebin and one compile manifest and a mutant could be graded against
# unmutated code (Oeditus/muex#23). 0.9.0 reads the app name from `mix.exs`
# instead (#26), which resolves deterministically here because `mix.exs` states
# `app: :hieroglyph` as a literal, and each sandbox then gets its own copied
# `_build/test/lib/hieroglyph`.
#
# That is the mechanism. The check is a paired run: the 49 `literal` mutations
# in `lib/abi/parser.ex` at --concurrency 1 and again at --concurrency 8 gave
# killed=33 survived=12 invalid=4 both times, zero per-mutation disagreements.
# Read that for what it is -- a consistency check that found nothing, not proof
# of isolation. False survivors turn up at ~0.5%, so a 49-mutation sample
# expects 0.25 of them and would look identical either way; and the same
# nondeterminism has since been reproduced upstream at --concurrency 1, so the
# flag is not the variable that would have to change. What holds regardless is
# the direction: a worker reading unmutated code corrupts toward a false
# SURVIVOR, never a false kill. So kills are trustworthy at any concurrency,
# survivors are not, and every survivor is re-graded serially by
# .mutation/verify-survivors.exs before it is dispositioned.
#
# Exhaustive: --no-filter (no file filtering), --no-optimize (no per-function
# caps, no complexity floor), all 18 mutators, no --max-mutations sampling.
# Two deliberate non-opt-outs, both recorded in the ledger rather than
# silently taken:
#   * mutations reported at `line: 0` are dropped unless
#     --keep-metadata-mutations is passed; muex documents those as
#     compile-time/invalid mutants and they cannot be dispositioned by line.
#   * --tce (Trivial Compiler Equivalence) is turned OFF, against its default.
#     TCE is meant to drop mutants that compile to identical bytecode, and on
#     a single-module file it is sound. It is NOT sound when the file's
#     top-level module contains a nested `defmodule`: Muex.Tce.compile_binary
#     keeps only the FIRST module the compiler returns (`[{module, binary} | _]`
#     in deps/muex/lib/muex/tce.ex), which for a nested module is the INNER
#     one, so both sides of the comparison fingerprint the inner module and
#     every mutation outside it compares equal. `lib/abi/type_decoder.ex`
#     nests ABI.TypeDecoder.StrictViolation at line 17 and was the only file
#     in the tree that tripped this. Measured on the 2026-08-26 TCE-on run:
#     672 of its 867 mutations were declared "equivalent", dropped from the
#     denominator and never executed -- including `@word_size_bytes 32 -> 33`,
#     which plainly changes behaviour. Reproduced minimally in
#     .mutation/tce-nested-module.exs. A dropped mutant is worse than a
#     survivor here: it is invisible to criterion 4, which requires every
#     mutation to be dispositioned. With TCE off, genuinely equivalent mutants
#     resurface as survivors and get an explicit written argument instead.
set -u
cd "${0:A:h}/.." || exit 1
export MIX_ENV=test

MUTATORS=arithmetic,boolean,case_clause,comparison,cond_clause,conditional,enum_semantics,extended_math,function_call,guard,invert_negatives,literal,map_semantics,negate_conditionals,pipe,return_value,statement_deletion,with_clause

FILES='lib/abi.ex,lib/abi/*.ex'

OUT=.mutation/results
mkdir -p "$OUT"

echo "=== muex $(sed -n 's/.*"muex": {:hex, :muex, "\([^"]*\)".*/\1/p' mix.lock), $(elixir --version | tail -1)"
echo "=== CAMPAIGN START $(date +%H:%M:%S)"
t0=$(date +%s)
mix muex --files "$FILES" --test-paths test \
  --mutators "$MUTATORS" \
  --no-filter --no-optimize --no-tce \
  --concurrency 8 --timeout 60000 --fail-at 0 --format json \
  > "$OUT/campaign.raw" 2> "$OUT/campaign.err"
rc=$?
t1=$(date +%s)
python3 - "$OUT/campaign.raw" "$OUT/campaign.json" <<'PY'
import sys
raw = open(sys.argv[1]).read()
i = raw.find('{')
open(sys.argv[2], 'w').write(raw[i:] if i >= 0 else '')
PY
echo "=== CAMPAIGN DONE rc=$rc $(( t1 - t0 ))s $(date +%H:%M:%S)"

# A zero exit status is NOT evidence of a campaign. Observed 2026-08-27: muex
# took a SIGTERM at minute 38, wrote nothing but the shutdown notice, and still
# exited 0 -- which the old `exit $rc` reported as a clean run over an empty
# file. Grade the artifact, not the status: no parsable summary means no
# campaign, whatever muex claimed on the way out.
if ! python3 -c 'import json,sys
raw=open(sys.argv[1]).read()
i=raw.find("{")
sys.exit(1) if i < 0 else None
d=json.JSONDecoder().raw_decode(raw,i)[0]
sys.exit(0 if d.get("summary",{}).get("total") else 1)' "$OUT/campaign.json" 2>/dev/null; then
  echo "=== CAMPAIGN INVALID: no parsable summary in campaign.json" >&2
  echo "=== last bytes of campaign.raw:" >&2
  tail -c 400 "$OUT/campaign.raw" >&2
  exit 1
fi

# Propagate muex's status: post-processing succeeding must not make a crashed
# campaign look like a clean one to a caller reading $?.
exit $rc
