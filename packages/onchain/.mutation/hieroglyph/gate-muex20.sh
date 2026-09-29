#!/bin/zsh
# Known-answer test for the MEASURING TOOL, not for this library.
#
# muex 0.8.2 could not report a surviving mutant on Elixir 1.20 at all:
# Muex.TestRunner.Port.count_failures/2 matched the pre-1.20 ExUnit summary
# wording ("N tests, M failures"), 1.20 prints "Result: N passed / Failed: N
# test", the regex missed, the fallback returned 1 failure, and the :survived
# path was unreachable -- so every survivor was reported killed and a 100%
# score was the bug's signature rather than a result. Filed as
# Oeditus/muex#20, fixed in #21.
#
# Run this BEFORE reading any campaign number, against whatever muex the
# project has actually resolved. It builds the four-file reproduction from
# issue #20 in a temp dir and asserts BOTH directions:
#
#   weak test (type-only assertion)   -> survived=2, score 0.0
#   value-asserting test              -> killed=2,   score 100.0
#
# The converse half is not decoration: without it, "survived=2" is also what a
# tool that calls everything survived would print.
set -u
cd "${0:A:h}/.." || exit 1

MUEX_REQ=$(sed -n 's/.*{:muex, "\([^"]*\)".*/\1/p' mix.exs)
MUEX_LOCKED=$(sed -n 's/.*"muex": {:hex, :muex, "\([^"]*\)".*/\1/p' mix.lock)
echo "=== gate: muex $MUEX_LOCKED (requirement $MUEX_REQ), $(elixir --version | tail -1)"

WORK=$(mktemp -d -t muex-gate) || exit 1
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/lib" "$WORK/test"

cat > "$WORK/mix.exs" <<EOF
defmodule Demo.MixProject do
  use Mix.Project

  def project do
    [app: :demo, version: "0.1.0", elixir: "~> 1.18", deps: deps()]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps, do: [{:muex, "$MUEX_REQ", only: [:dev, :test], runtime: false}]
end
EOF

cat > "$WORK/lib/demo.ex" <<'EOF'
defmodule Demo do
  def add(a, b), do: a + b
end
EOF

echo 'ExUnit.start()' > "$WORK/test/test_helper.exs"

# Pin the same muex build the project resolved, so the gate cannot silently
# grade a different version than the campaign runs on.
cp mix.lock "$WORK/mix.lock"

# And the same TOOLCHAIN. The bug this gate tests for is an Elixir-version
# dependent one -- muex parsed the pre-1.20 ExUnit summary wording -- so a
# gate that runs under the host's default Elixir while the campaign runs under
# the project's pinned one is grading a different question. Without this the
# temp project sits outside the repo and asdf resolves the global default
# (1.20.3 here, against the project's 1.20.2).
[[ -f .tool-versions ]] && cp .tool-versions "$WORK/.tool-versions"
echo "=== gate toolchain: $(cd "$WORK" && elixir --version | tail -1)"

run_case() {  # $1 = label, $2 = expected killed, $3 = expected survived
  ( cd "$WORK" && mix deps.get >/dev/null 2>&1
    MIX_ENV=test mix muex --files lib --test-paths test \
      --mutators arithmetic --no-filter --no-optimize \
      --concurrency 1 --fail-at 0 --format json 2>/dev/null ) \
  | python3 -c '
import json, sys
raw = sys.stdin.read()
i = raw.find("{")
d = json.loads(raw[i:])
s = d.get("summary", d)
print(json.dumps({k: s.get(k) for k in ("total", "killed", "survived", "mutation_score_high")}))
' > "$WORK/out.json"
  local got_k=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["killed"])' "$WORK/out.json")
  local got_s=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["survived"])' "$WORK/out.json")
  echo "--- $1: $(cat "$WORK/out.json")"
  if [[ "$got_k" != "$2" || "$got_s" != "$3" ]]; then
    echo "GATE FAILS: $1 expected killed=$2 survived=$3"
    return 1
  fi
}

# 1. Weak assertion: the tool MUST be able to say "survived".
cat > "$WORK/test/demo_test.exs" <<'EOF'
defmodule DemoTest do
  use ExUnit.Case

  test "add returns an integer" do
    assert is_integer(Demo.add(1, 2))
  end
end
EOF
run_case "weak assertion" 0 2 || exit 1

# 2. Value assertion: and it MUST NOT just say "survived" for everything.
cat > "$WORK/test/demo_test.exs" <<'EOF'
defmodule DemoTest do
  use ExUnit.Case

  test "add returns the sum" do
    assert Demo.add(1, 2) == 3
  end
end
EOF
run_case "value assertion" 2 0 || exit 1

echo "=== GATE PASSES: muex $MUEX_LOCKED reports both verdicts on this host"
