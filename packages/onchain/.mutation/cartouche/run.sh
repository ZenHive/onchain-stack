#!/bin/zsh
# Task 114 mutation-adequacy campaign.
#
# ONE invocation over the whole surface, deliberately: --coverage-guided builds
# its line index by running `mix test.json <file> --cover` once per test file,
# serially, with no cache (deps/muex/lib/muex/coverage.ex Coverage.collect/3).
# Per-module invocations therefore pay that full-suite cost 13 times over —
# which is what exhausted the harness run's lifetime budget.
#
# Exhaustive: --no-filter --no-optimize, all 18 mutators. --coverage-guided
# only narrows which EXISTING tests run per mutant; it never drops a mutant.
# One exception, deliberately not opted out of: muex drops mutations reported at
# `line: 0` unless --keep-metadata-mutations is passed (Muex.maybe_drop_unlocatable/2).
# muex documents those as compile-time/invalid mutants, and keeping them would
# make the run non-comparable with the recorded baseline -- so "exhaustive" here
# means every LOCATABLE mutation the 18 mutators generate.
#
# --concurrency 1 is REQUIRED for a valid measurement, not a throughput choice.
# muex's per-worker sandbox only isolates _build when it can name the app:
# Sandbox.detect_app_from_build/2 globs `_build/<env>/lib/*/.mix/compile.elixir`
# and resolves only on a SINGLE match. cartouche has 45 (one per dep), so it
# returns nil, ensure_build_copy_for_file/2 no-ops, and every sandbox's
# _build/test/lib/cartouche stays a symlink into the real project build dir --
# one shared ebin and one shared compile manifest for all workers. Concurrent
# workers then race: if worker B's `mix test` recompiles (from its own
# unmutated symlink) after worker A wrote its mutant but before A's own test
# run, the manifest is newer than A's source, Mix considers it up to date, and
# A's mutation NEVER TAKES EFFECT -- scored `survived` on unmutated code.
# Task 114's baseline and task 119's first run both used --concurrency 8 and
# are invalid for that reason. Serial execution removes the interleaving.
set -u
cd "${0:A:h}/.." || exit 1
export MIX_ENV=test

MUTATORS=arithmetic,boolean,case_clause,comparison,cond_clause,conditional,enum_semantics,extended_math,function_call,guard,invert_negatives,literal,map_semantics,negate_conditionals,pipe,return_value,statement_deletion,with_clause

FILES='lib/cartouche/transaction.ex,lib/cartouche/transaction/*.ex,lib/cartouche/signer.ex,lib/cartouche/signer/*.ex,lib/cartouche/recover.ex,lib/cartouche/recovery_bit.ex'

OUT=.mutation/results
mkdir -p "$OUT"

echo "=== CAMPAIGN START $(date +%H:%M:%S)"
t0=$(date +%s)
mix muex --files "$FILES" --test-paths test \
  --mutators "$MUTATORS" \
  --no-filter --no-optimize --coverage-guided \
  --concurrency 1 --timeout 60000 --fail-at 0 --format json \
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
# Propagate muex's status: post-processing succeeding must not make a crashed
# campaign look like a clean one to a caller reading $?.
exit $rc
