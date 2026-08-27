defmodule OnchainAerodrome.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/ZenHive/onchain_aerodrome"

  def project do
    [
      app: :onchain_aerodrome,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
      dialyzer: dialyzer(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  def cli do
    [
      preferred_envs: [
        "test.json": :test,
        "dialyzer.json": :dev
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:onchain, "~> 0.13"},
      {:descripex, "~> 0.13"},
      {:decimal, "~> 3.1"},

      # Dev/test tooling
      {:onchain_evm, "~> 0.6", only: [:dev, :test]},
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:tidewave, "~> 0.5", only: :dev},
      {:bandit, "~> 1.0", only: :dev},
      {:ex_unit_json, "~> 0.6.0", only: [:dev, :test], runtime: false},
      {:dialyzer_json, "~> 0.1", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7.18", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      # No Plug/web surface here, but the elixir plugin's post-edit hook aborts its
      # whole check stack (format/compile/credo/doctor/dialyzer) when sobelow is
      # absent, so it stays declared and stays in the gate.
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.39", only: :dev, runtime: false},

      # Reach 2.8.2 caps ex_ast at ~> 0.12.0; Reach uses APIs retained by ex_ast 0.13.
      {:ex_ast, "~> 0.13", override: true, only: [:dev, :test], runtime: false},
      {:reach, "~> 2.8", only: [:dev, :test], runtime: false},
      # Clone detection (vibe_kit baseline) — matches sibling repos.
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Typed bindings and a high-level read/analytics API for Aerodrome Finance on Base (chain 8453)."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      # Explicit list because hex's default `files` ships all of `priv/`, and
      # `priv/plts/` holds the dialyzer PLTs this project pins there
      # (`dialyzer/0` sets `plt_local_path`). .gitignore does not apply to
      # `mix hex.build`, so an implicit files list would ship dev-only PLT.
      # Ship `priv/abis` and nothing else under `priv`.
      files: ~w(lib priv/abis .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  defp aliases do
    [
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4035) end)'"
      ],
      # Dispatch-scale gate — what the harness reviewer runs per run (registered
      # as the project's `check_command`). Static checks only: no dialyzer (cold
      # PLT dominates a fresh worktree), no coverage, no test run — the reviewer
      # picks focused `mix test.json` invocations for the behavior it touched.
      # `mix ci` stays the landed-base gate.
      "check.dispatch": [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME",
        "doctor --raise",
        "ex_dna --max-clones 0",
        "reach.check --arch --smells",
        "sobelow --skip --exit low"
      ],
      # Fast local pre-commit loop — skips the cold-PLT dialyzer and the coverage
      # pass so it stays quick on incremental edits.
      precommit: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME",
        # `preferred_envs` (cli/0) is ignored for alias steps — set MIX_ENV via
        # `env` (Elixir 1.20's `mix cmd` no longer parses a leading VAR=val prefix).
        "cmd env MIX_ENV=test mix test.json --exclude integration"
      ],
      # Comprehensive gate — the harness reviewer's `check_command` and `mix ci`
      # target.
      # Coverage floor 65 against an 88.57% measured baseline (2026-08-26,
      # registry + tests only). The floor is a conservative family-wide value,
      # not a per-module target: Analytics.* and Math.* are pure and critical
      # path (95%), read/binding layers 80% — see critical-rules coverage tiers.
      #
      # `--summary-only` is deliberately OMITTED here: the flag is in
      # ex_unit_json's `retry_disqualified_opts?/1` list, so it silently
      # disables the tool's own automatic retry-on-flaky (see
      # `deps/ex_unit_json/lib/mix/tasks/test_json.ex`). Dropping it restores
      # both: real flakes retry and heal (exit 0, named in a `flaky` array
      # instead of blocking), and a confirmed failure prints full assertion
      # detail on stdout instead of a bare summary line. The default output
      # mode (no `--summary-only`, no `--all`) is already CI-quiet on a green
      # run — an empty `tests` array — so this costs nothing when nothing fails.
      "precommit.full": [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME",
        "doctor --raise",
        "ex_dna --max-clones 0",
        "reach.check --arch --smells",
        "sobelow --skip --exit low",
        "deps.audit.gated",
        "cmd env MIX_ENV=test mix test.json --cover --cover-threshold 65 --exclude integration",
        "dialyzer",
        # AGENTS.md is what the cross-family (codex/cursor/grok) reviewers read;
        # a stale render makes them gate against rules that already changed.
        "agents.check"
      ],
      # Fails when AGENTS.md has drifted from CLAUDE.md. Compares rendered output,
      # not mtimes, so drift in a transitive @-import is caught too.
      "agents.check": [
        &agents_check/1
      ],
      # Every caller uses the reviewed ignore file, including generic commit
      # hooks that invoke `mix deps.audit` directly.
      "deps.audit": ["deps.audit --ignore-file .mix_audit_ignore"],
      # mix_audit discards its sync exit status (mirego/mix_audit#61), so a frozen
      # advisory DB still reports green. Prove freshness first, then audit.
      "deps.audit.gated": [
        &advisory_freshness/1,
        "deps.audit"
      ],
      ci: ["precommit.full"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp dialyzer do
    [
      # OOM mitigation: skip transitive deps (default is :app_tree).
      # Tidewave/bandit's HTTP stack (plug, finch, mint, gun, cowlib, etc.)
      # is not in lib/'s call graph and bloats PLT to ~800 modules.
      plt_add_deps: :apps_direct,
      # `:ex_unit` is required because elixirc_paths/1 compiles test/support in
      # :test, so the case modules there are analyzed — without it every
      # `flunk/1` callsite reads as `unknown_function` (5 errors, exit 2).
      plt_add_apps: [:mix, :ex_unit],
      plt_local_path: "priv/plts",
      plt_core_path: "priv/plts"
    ]
  end

  # Both gates below shell out to scripts that live OUTSIDE this repo, on the
  # developer host: the AGENTS.md renderer needs the claude-marketplace
  # checkout plus ~/.claude/includes, and the advisory-freshness prover needs
  # the local mix_audit mirror. Neither exists on a CI runner, and `mix cmd`
  # with an absent path exits non-zero — which aborted the whole `mix ci`
  # alias, and since these steps precede test.json/dialyzer it took the test,
  # coverage and dialyzer signal down with it. Skip loudly when the script is
  # absent so CI keeps running the checks it CAN run; the developer host and
  # the harness reviewer still get the full gate.
  @spec agents_check([String.t()]) :: :ok
  defp agents_check(_args) do
    host_script(
      "~/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh",
      ["--check"],
      "AGENTS.md freshness check"
    )
  end

  @spec advisory_freshness([String.t()]) :: :ok
  defp advisory_freshness(_args) do
    host_script(
      "~/_DATA/code/onchain-stack/bin/advisory-freshness.sh",
      [],
      "advisory-mirror freshness check"
    )
  end

  @spec host_script(String.t(), [String.t()], String.t()) :: :ok
  defp host_script(path, args, label) do
    expanded = Path.expand(path)

    if File.exists?(expanded) do
      {_out, status} =
        System.cmd(expanded, args, into: IO.stream(:stdio, :line), stderr_to_stdout: true)

      if status != 0 do
        Mix.raise("#{label} failed (#{expanded} exited #{status})")
      end
    else
      Mix.shell().info("[skip] #{label}: #{expanded} not found (developer-host script, absent in CI).")
    end

    :ok
  end
end
