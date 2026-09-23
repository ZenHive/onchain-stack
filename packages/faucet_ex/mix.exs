defmodule Faucet.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/ZenHive/faucet_ex"

  # Coverage floor is a measured ratchet: set from the first full run of the
  # unit suite (`mix test.json --cover --exclude integration`), rounded down.
  # Raise it in lockstep with real coverage; never pad it.
  @cover_threshold 90

  def project do
    [
      app: :faucet_ex,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: dialyzer(),
      aliases: aliases(),
      test_coverage: [ignore_modules: [~r/^Faucet\.Test\./]],
      description: description(),
      package: package(),
      name: "FaucetEx",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: [
        main: "Faucet",
        extras: ["README.md", "CHANGELOG.md"],
        source_url: @source_url,
        source_ref: "v#{@version}"
      ]
    ]
  end

  def cli do
    [preferred_envs: ["test.json": :test, "dialyzer.json": :dev]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp deps do
    [
      # Runtime: every adapter is HTTP/JSON-RPC over Req.
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},

      # Optional: EVM signing, ABI encoding and keccak for the adapters that
      # need them (`Faucet.Source.ERC20Mint`, `Faucet.EVM.fresh_funded_wallet/3`,
      # `Faucet.ForkOverride`). Consumers funding Solana, XRPL or plain native
      # gas do not have to pull the EVM stack. Two-segment on purpose: the
      # committed lock already blocks a silent in-family upgrade.
      {:onchain, "~> 0.14", optional: true},

      # Self-describing APIs — full dep, macros expand at compile time.
      {:descripex, "~> 1.0"},

      # Req.Test needs Plug for the stub adapter.
      {:plug, "~> 1.16", only: [:dev, :test]},

      # AI-friendly reporters
      {:ex_unit_json, "~> 0.6", only: [:dev, :test], runtime: false},
      {:dialyzer_json, "~> 0.2", only: [:dev, :test], runtime: false},

      # Static analysis
      {:styler, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      # reach 2.8.x declares `ex_ast ~> 0.12.0`; it only uses APIs 0.13 retains.
      {:ex_ast, "~> 0.13", override: true, only: [:dev, :test], runtime: false},
      {:reach, "~> 2.8", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},

      # Docs
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},

      # Tidewave MCP for Claude Code (non-Phoenix: standalone Bandit)
      {:tidewave, "~> 0.9", only: :dev},
      {:bandit, "~> 1.10", only: :dev}
    ]
  end

  defp dialyzer do
    [
      # OOM mitigation: direct deps only; tidewave/bandit's HTTP stack is not in
      # lib/'s call graph.
      plt_add_deps: :apps_direct,
      plt_add_apps: [:mix, :crypto, :onchain, :cartouche],
      plt_local_path: "priv/plts",
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  defp aliases do
    [
      # Scoped verification for implementation and review; add focused tests.
      "check.fast": ["format --check-formatted", "compile --warnings-as-errors"],
      "check.dispatch": ["check.fast"],
      precommit: [
        "check.fast",
        "credo --strict --ignore TagTODO,TagFIXME",
        "doctor --raise",
        # preferred_envs is ignored inside alias steps — set MIX_ENV explicitly.
        "cmd env MIX_ENV=test mix test.json --quiet --cover --cover-threshold #{@cover_threshold} --summary-only --exclude integration",
        "sobelow --skip --exit low"
      ],
      # Full post-merge QA.
      "precommit.full": [
        "check.fast",
        "credo --strict --ignore TagTODO,TagFIXME",
        "doctor --raise",
        "ex_dna --max-clones 0",
        "reach.check --dead-code --arch --smells",
        "sobelow --skip --exit low",
        "deps.audit.gated",
        "cmd env MIX_ENV=test mix test.json --quiet --cover --cover-threshold #{@cover_threshold} --exclude integration",
        "cmd env MIX_ENV=dev mix dialyzer",
        "agents.check"
      ],
      ci: ["precommit.full"],
      "agents.check": [&agents_check/1],
      # mix_audit discards its own sync exit status (mirego/mix_audit#61); prove
      # the advisory mirror is fresh before trusting a clean audit.
      "deps.audit.gated": [&advisory_freshness/1, "deps.audit --ignore-file .mix_audit_ignore"],
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4038) end)'"
      ]
    ]
  end

  defp description do
    "Programmatic testnet funding for integration tests: one top-up loop " <>
      "(read balance, request, wait, verify) over pluggable faucet sources — " <>
      "Coinbase CDP, Tempo Moderato, Solana airdrop, XRPL testnet, ERC-20 " <>
      "mint contracts, and EVM fork state overrides."
  end

  defp package do
    [
      name: "faucet_ex",
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url, "Docs" => "https://hexdocs.pm/faucet_ex"},
      maintainers: ["ZenHive"]
    ]
  end

  @spec agents_check([String.t()]) :: :ok
  defp agents_check(_args), do: repo_script("bin/sync-agents-md.sh", ["--check"], "AGENTS.md freshness check")

  @spec advisory_freshness([String.t()]) :: :ok
  defp advisory_freshness(_args), do: repo_script("bin/advisory-freshness.sh", [], "advisory-mirror freshness check")

  # Both gates shell out to scripts tracked in this repo so any portable
  # checkout runs them; a missing script fails the step rather than skipping.
  @spec repo_script(String.t(), [String.t()], String.t()) :: :ok
  defp repo_script(relative, args, label) do
    expanded = Path.expand(relative, Path.dirname(Mix.Project.project_file()))

    cond do
      not File.regular?(expanded) ->
        Mix.raise("#{label}: #{expanded} not found (in-repo QA script required)")

      not executable?(expanded) ->
        Mix.raise("#{label}: #{expanded} exists but is not executable")

      true ->
        {_out, status} = System.cmd(expanded, args, into: IO.stream(:stdio, :line), stderr_to_stdout: true)
        if status != 0, do: Mix.raise("#{label} failed (#{expanded} exited #{status})")
    end

    :ok
  end

  @spec executable?(String.t()) :: boolean()
  defp executable?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{mode: mode}} -> Bitwise.band(mode, 0o111) != 0
      _ -> false
    end
  end
end
