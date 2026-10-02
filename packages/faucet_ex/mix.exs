# Gate helpers shared by every package (`agents_check/1`, `advisory_freshness/1`)
# live at the monorepo root in `shared/mix_helpers.exs`. That file is NOT part
# of the published tarball, so the load is guarded and every call site degrades
# to a loud skip — same rule as `sibling/3` below: nothing in this file may
# assume the monorepo checkout.
shared_mix_helpers = Path.expand("../../shared/mix_helpers.exs", __DIR__)

if not Code.ensure_loaded?(OnchainMonorepo.MixHelpers) and File.exists?(shared_mix_helpers) do
  Code.require_file(shared_mix_helpers)
end

defmodule Faucet.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/ZenHive/onchain-stack"

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
        source_ref: "faucet_ex-v#{@version}",
        source_url_pattern: "#{@source_url}/blob/faucet_ex-v#{@version}/packages/faucet_ex/%{path}#L%{line}"
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

  # In the monorepo checkout this resolves to an in-repo path dep; everywhere
  # else the declared Hex requirement wins. The predicate is the root marker
  # `.onchain-monorepo-root`, never the sibling's existence (a consumer's
  # `deps/` unpacks every package side by side). `ONCHAIN_PUBLISH=1` forces the
  # Hex branch, because `mix hex.publish` rejects path deps.
  #
  # Convention, parsed by `mix onchain.bounds` at the monorepo root: the call is
  # a literal `sibling(:name, "<requirement>")` or
  # `sibling(:name, "<requirement>", opts)`.
  defp sibling(name, req, opts) do
    monorepo? = File.exists?(Path.expand("../../.onchain-monorepo-root", __DIR__))
    publishing? = System.get_env("ONCHAIN_PUBLISH") == "1"

    if monorepo? and not publishing? do
      {name, [path: Path.expand("../#{name}", __DIR__), override: true] ++ opts}
    else
      {name, req, opts}
    end
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
      sibling(:onchain, "~> 0.16", optional: true),

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
      plt_add_apps: [:mix, :crypto, :onchain],
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
      links: %{
        "GitHub" => "#{@source_url}/tree/main/packages/faucet_ex",
        "Docs" => "https://hexdocs.pm/faucet_ex"
      },
      maintainers: ["ZenHive"]
    ]
  end

  # Shared with the other packages — see `shared/mix_helpers.exs` at the
  # monorepo root. Resolved dynamically so a consumer evaluating this mix.exs
  # out of the tarball (where that file does not exist) gets a skip, not a
  # crash.
  defp agents_check(args), do: shared_gate(:agents_check, args)

  defp advisory_freshness(args), do: shared_gate(:advisory_freshness, args)

  defp shared_gate(fun, args) do
    mod = OnchainMonorepo.MixHelpers

    if Code.ensure_loaded?(mod) do
      apply(mod, fun, [args])
    else
      Mix.shell().info(
        "[skip] #{fun}: shared/mix_helpers.exs not found (monorepo-root file, absent in a published tarball)."
      )

      :ok
    end
  end
end
