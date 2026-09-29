# Gate helpers shared by all packages (`agents_check/1`,
# `advisory_freshness/1`, `host_script/3`) live at the monorepo root in
# `shared/mix_helpers.exs`. That file is NOT part of the published tarball, so
# the load is guarded and every call site degrades to a loud skip — same rule as
# `sibling/3` below: nothing in this file may assume the monorepo checkout.
# `Code.ensure_loaded?/1` keeps the load idempotent (a re-require of the same
# path would redefine the module and warn).
shared_mix_helpers = Path.expand("../../shared/mix_helpers.exs", __DIR__)

if not Code.ensure_loaded?(OnchainMonorepo.MixHelpers) and File.exists?(shared_mix_helpers) do
  Code.require_file(shared_mix_helpers)
end

defmodule OnchainSolana.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :onchain_solana,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "Onchain Solana",
      description: "Solana RPC, transactions, token programs, and Ed25519 signing for Elixir",
      source_url: "https://github.com/ZenHive/onchain-stack",
      docs: [
        main: "readme",
        extras: ["README.md", "CHANGELOG.md"],
        source_ref: "onchain_solana-v#{@version}",
        source_url_pattern:
          "https://github.com/ZenHive/onchain-stack/blob/onchain_solana-v#{@version}/packages/onchain_solana/%{path}#L%{line}"
      ],
      dialyzer: [
        plt_add_deps: :apps_direct,
        plt_add_apps: [:mix, :ex_unit],
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts"
      ],
      package: [
        files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md),
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/ZenHive/onchain-stack/tree/main/packages/onchain_solana"}
      ]
    ]
  end

  def application, do: [mod: {Onchain.Solana.Application, []}, extra_applications: [:logger, :crypto]]

  def cli,
    do: [
      preferred_envs: ["test.json": :test, ci: :test, precommit: :test, "precommit.full": :test, "check.dispatch": :test]
    ]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp sibling(name, req, opts \\ []) do
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
      sibling(:cartouche, "~> 0.10"),
      {:descripex, "~> 1.0"},
      {:req, "~> 0.6 or ~> 0.7"},
      {:jason, "~> 1.4"},
      {:goth, "~> 1.4", optional: true},
      {:plug, "~> 1.16", only: [:dev, :test]},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false},
      {:styler, "~> 1.12.0", only: [:dev, :test], runtime: false},
      {:ex_unit_json, "~> 0.6.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7.18", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.15", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23.0", only: [:dev, :test], runtime: false},
      {:meck, "~> 1.2.0", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5.1", only: [:dev, :test], runtime: false},
      {:ex_ast, "~> 0.13", only: [:dev, :test], runtime: false, override: true},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.7", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.4", only: :test, runtime: false}
    ]
  end

  defp aliases do
    [
      "check.dispatch": ["format --check-formatted", "compile --warnings-as-errors"],
      precommit: ["check.dispatch", "test.json"],
      "precommit.full": [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME",
        "doctor --raise",
        "ex_dna --max-clones 0",
        "reach.check --dead-code --arch --smells",
        "sobelow --config",
        "deps.audit.gated",
        "test.json --cover --cover-threshold 95",
        "dialyzer",
        "agents.check"
      ],
      "agents.check": [&agents_check/1],
      "deps.audit.gated": [&advisory_freshness/1, "deps.audit"],
      ci: ["precommit.full"]
    ]
  end

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
