%{
  "mix.exs" => %{
    "check.dispatch" => [
      "fn _ ->\n  Mix.raise(\n    \"check.dispatch runs per package, not at the monorepo root — \" <>\n      \"cd packages/<name> && mix check.dispatch for each package the task touches.\"\n  )\nend"
    ],
    "ci" => ["\"onchain.bounds\"", "&packages_ci/1"],
    "tidewave" => ["\"run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4037) end)'\""]
  },
  "packages/cartouche/mix.exs" => %{
    "agents.check" => ["&agents_check/1"],
    "check.dispatch" => [
      "\"compile --warnings-as-errors\"",
      "\"format --check-formatted\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"doctor --raise\"",
      "\"ex_dna --max-clones 0\"",
      "\"reach.check --arch --smells\"",
      "\"sobelow --config\"",
      "\"test.json --exclude integration --exclude dev_node\""
    ],
    "ci" => ["\"precommit.full\""],
    "deps.audit.gated" => ["&advisory_freshness/1", "\"deps.audit\""],
    "integration" => ["\"test.json --only integration\""],
    "manifest" => ["\"descripex.manifest --pretty --output api_manifest.json --app cartouche\""],
    "precommit" => [
      "\"compile --warnings-as-errors\"",
      "\"format --check-formatted\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"ex_dna --max-clones 0\"",
      "\"test.json --exclude integration --exclude dev_node\""
    ],
    "precommit.full" => [
      "\"compile --warnings-as-errors\"",
      "\"format --check-formatted\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"doctor --raise\"",
      "\"ex_dna --max-clones 0\"",
      "\"reach.check --arch --smells\"",
      "\"sobelow --config\"",
      "\"deps.audit.gated\"",
      "\"test.json --cover --cover-threshold 85 --exclude integration --exclude dev_node\"",
      "\"dialyzer\"",
      "\"agents.check\""
    ],
    "tidewave" => ["\"run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4013) end)'\""]
  },
  "packages/hieroglyph/mix.exs" => %{
    "agents.check" => ["&agents_check/1"],
    "check.dispatch" => [
      "\"compile --warnings-as-errors\"",
      "\"format --check-formatted\"",
      "\"credo --strict --ignore TagTODO,TagFIXME\"",
      "\"doctor --raise\"",
      "\"ex_dna --max-clones 0\"",
      "\"sobelow --skip --exit low\"",
      "\"test.json --exclude integration\""
    ],
    "check.fast" => [
      "\"format --check-formatted\"",
      "\"compile --warnings-as-errors\"",
      "\"credo --strict --ignore TagTODO,TagFIXME\""
    ],
    "ci" => ["\"precommit.full\""],
    "deps.audit.gated" => ["&advisory_freshness/1", "\"deps.audit\""],
    "precommit" => [
      "\"format --check-formatted\"",
      "\"compile --warnings-as-errors\"",
      "\"credo --strict --ignore TagTODO,TagFIXME\"",
      "\"doctor --raise\"",
      "&cover_gate/1",
      "\"sobelow --skip --exit low\""
    ],
    "precommit.full" => [
      "\"precommit\"",
      "&manifest_check/1",
      "\"ex_dna --max-clones 0\"",
      "\"reach.check --dead-code --arch --smells\"",
      "\"deps.audit.gated\"",
      "\"dialyzer.json --quiet\"",
      "\"agents.check\""
    ],
    "tidewave" => ["\"run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4006) end)'\""]
  },
  "packages/onchain/mix.exs" => %{
    "agents.check" => ["&agents_check/1"],
    "check.dispatch" => [
      "\"compile --warnings-as-errors\"",
      "\"format --check-formatted\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"doctor --raise\"",
      "\"ex_dna --max-clones 0\"",
      "\"reach.check --dead-code --arch --smells\"",
      "\"sobelow --skip --exit low\"",
      "\"cmd env MIX_ENV=test mix test.json --exclude integration\""
    ],
    "ci" => ["\"precommit.full\""],
    "deps.audit.gated" => ["&advisory_freshness/1", "\"deps.audit --ignore-file .mix_audit_ignore\""],
    "precommit" => [
      "\"compile --warnings-as-errors\"",
      "\"format --check-formatted\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"ex_dna --max-clones 0\"",
      "\"cmd env MIX_ENV=test mix test.json --exclude integration\""
    ],
    "precommit.full" => [
      "\"compile --warnings-as-errors\"",
      "\"format --check-formatted\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"doctor --raise\"",
      "\"ex_dna --max-clones 0\"",
      "\"reach.check --dead-code --arch --smells\"",
      "\"sobelow --skip --exit low\"",
      "\"deps.audit.gated\"",
      "\"cmd env MIX_ENV=test mix test.json --cover --cover-threshold 70 --exclude integration\"",
      "\"dialyzer\"",
      "\"agents.check\""
    ],
    "tidewave" => ["\"run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4007) end)'\""]
  },
  "packages/onchain_aave/mix.exs" => %{
    "agents.check" => ["&agents_check/1"],
    "check.dispatch" => [
      "\"format --check-formatted\"",
      "\"compile --warnings-as-errors\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"doctor --raise\"",
      "\"ex_dna --max-clones 0\"",
      "\"reach.check --dead-code --arch --smells\"",
      "\"sobelow --skip --exit low\"",
      "\"cmd env MIX_ENV=test mix test.json --exclude integration\""
    ],
    "ci" => ["\"precommit.full\""],
    "deps.audit" => ["\"deps.audit --ignore-file .mix_audit_ignore\""],
    "deps.audit.gated" => ["&advisory_freshness/1", "\"deps.audit\""],
    "precommit" => [
      "\"compile --warnings-as-errors\"",
      "\"format --check-formatted\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"cmd env MIX_ENV=test mix test.json --exclude integration\""
    ],
    "precommit.full" => [
      "\"compile --warnings-as-errors\"",
      "\"format --check-formatted\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"doctor --raise\"",
      "\"ex_dna --max-clones 0\"",
      "\"reach.check --dead-code --arch --smells\"",
      "\"sobelow --skip --exit low\"",
      "\"deps.audit.gated\"",
      "\"cmd env MIX_ENV=test mix test.json --cover --cover-threshold 65 --exclude integration\"",
      "\"dialyzer\"",
      "\"agents.check\""
    ],
    "tidewave" => ["\"run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4012) end)'\""]
  },
  "packages/onchain_aerodrome/mix.exs" => %{
    "agents.check" => ["&agents_check/1"],
    "check.dispatch" => [
      "\"format --check-formatted\"",
      "\"compile --warnings-as-errors\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"doctor --raise\"",
      "\"ex_dna --max-clones 0\"",
      "\"reach.check --dead-code --arch --smells\"",
      "\"sobelow --skip --exit low\"",
      "~s(cmd env MIX_ENV=test sh -c 'PATH=\"$HOME/.foundry/bin:$PATH\" exec mix test.json --exclude integration')"
    ],
    "ci" => ["\"precommit.full\""],
    "deps.audit" => ["\"deps.audit --ignore-file .mix_audit_ignore\""],
    "deps.audit.gated" => ["&advisory_freshness/1", "\"deps.audit\""],
    "precommit" => [
      "\"compile --warnings-as-errors\"",
      "\"format --check-formatted\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"cmd env MIX_ENV=test mix test.json --exclude integration\""
    ],
    "precommit.full" => [
      "\"compile --warnings-as-errors\"",
      "\"format --check-formatted\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"doctor --raise\"",
      "\"ex_dna --max-clones 0\"",
      "\"reach.check --dead-code --arch --smells\"",
      "\"sobelow --skip --exit low\"",
      "\"deps.audit.gated\"",
      "\"cmd env MIX_ENV=test mix test.json --cover --cover-threshold 65 --exclude integration\"",
      "\"dialyzer\"",
      "\"agents.check\""
    ],
    "tidewave" => ["\"run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4035) end)'\""]
  },
  "packages/onchain_evm/mix.exs" => %{
    "agents.check" => ["&agents_check/1"],
    "check.dispatch" => [
      "\"format --check-formatted\"",
      "\"compile --warnings-as-errors\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"doctor --raise\"",
      "\"ex_dna --max-clones 0\"",
      "\"reach.check --dead-code --arch --smells\"",
      "\"sobelow --skip --exit low\"",
      "\"cmd env MIX_ENV=test mix test.json --exclude integration\""
    ],
    "ci" => ["\"precommit.full\""],
    "deps.audit" => ["\"deps.audit --ignore-file .mix_audit_ignore\""],
    "deps.audit.gated" => ["&advisory_freshness/1", "\"deps.audit\""],
    "integration" => ["\"test.json --only integration\""],
    "precommit" => [
      "\"compile --warnings-as-errors\"",
      "\"format --check-formatted\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"ex_dna --max-clones 0\"",
      "\"test.json --exclude integration\""
    ],
    "precommit.full" => [
      "\"compile --warnings-as-errors\"",
      "\"format --check-formatted\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"doctor --raise\"",
      "\"ex_dna --max-clones 0\"",
      "\"reach.check --dead-code --arch --smells\"",
      "\"sobelow --skip --exit low\"",
      "\"deps.audit.gated\"",
      "\"test.json --cover --cover-threshold 85 --exclude integration\"",
      "&cargo_test/1",
      "&cargo_clippy/1",
      "\"dialyzer\"",
      "\"agents.check\""
    ],
    "tidewave" => ["\"run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4009) end)'\""]
  },
  "packages/onchain_js/mix.exs" => %{
    "agents.check" => ["&agents_check/1"],
    "check.dispatch" => [
      "\"compile --warnings-as-errors\"",
      "\"format --check-formatted\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"doctor --raise\"",
      "\"ex_dna --max-clones 0\"",
      "\"reach.check --dead-code --arch --smells\"",
      "\"sobelow --skip --exit low\"",
      "\"cmd env MIX_ENV=test mix test.json --exclude integration\""
    ],
    "ci" => ["\"precommit.full\""],
    "deps.audit.gated" => ["&advisory_freshness/1", "\"deps.audit --ignore-file .mix_audit_ignore\""],
    "precommit" => [
      "\"compile --warnings-as-errors\"",
      "\"format --check-formatted\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"cmd env MIX_ENV=test mix test.json --exclude integration\""
    ],
    "precommit.full" => [
      "\"compile --warnings-as-errors\"",
      "\"format --check-formatted\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"doctor --raise\"",
      "\"ex_dna --max-clones 0\"",
      "\"reach.check --dead-code --arch --smells\"",
      "\"sobelow --skip --exit low\"",
      "\"deps.audit.gated\"",
      "\"cmd env MIX_ENV=test mix test.json --cover --cover-threshold 25 --exclude integration\"",
      "\"dialyzer\"",
      "\"agents.check\""
    ],
    "tidewave" => ["\"run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4028) end)'\""]
  },
  "packages/onchain_tempo/mix.exs" => %{
    "agents.check" => ["&agents_check/1"],
    "check.dispatch" => [
      "\"compile --warnings-as-errors\"",
      "\"format --check-formatted\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"doctor --raise\"",
      "\"ex_dna --max-clones 0\"",
      "\"reach.check --dead-code --arch --smells\"",
      "\"sobelow --skip --exit low\"",
      "\"cmd env MIX_ENV=test mix test.json --exclude integration\""
    ],
    "ci" => ["\"precommit.full\""],
    "deps.audit.gated" => ["&advisory_freshness/1", "\"deps.audit --ignore-file .mix_audit_ignore\""],
    "integration" => ["\"test.json --only integration\""],
    "precommit" => [
      "\"compile --warnings-as-errors\"",
      "\"format --check-formatted\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"ex_dna --max-clones 0\"",
      "\"cmd env MIX_ENV=test mix test.json --exclude integration\""
    ],
    "precommit.full" => [
      "\"compile --warnings-as-errors\"",
      "\"format --check-formatted\"",
      "\"credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME\"",
      "\"doctor --raise\"",
      "\"ex_dna --max-clones 0\"",
      "\"reach.check --dead-code --arch --smells\"",
      "\"sobelow --skip --exit low\"",
      "\"deps.audit.gated\"",
      "\"cmd env MIX_ENV=test mix test.json --cover --cover-threshold 90 --exclude integration\"",
      "\"dialyzer\"",
      "\"agents.check\""
    ],
    "tidewave" => ["\"run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4010) end)'\""]
  }
}
