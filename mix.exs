defmodule OnchainTempo.MixProject do
  use Mix.Project

  @version "0.8.0"
  @source_url "https://github.com/ZenHive/onchain_tempo"

  def project do
    [
      app: :onchain_tempo,
      version: @version,
      elixir: "~> 1.17",
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
      # Floor raised 0.10 -> 0.11: onchain 0.11.0 is the release that carries
      # `cartouche ~> 0.6`. A consumer locked on onchain 0.10.0 would otherwise
      # keep resolving cartouche 0.5.x and stay capped below req 0.7 — the
      # bound must *require* the fix, not merely permit it.
      {:onchain, "~> 0.11"},
      # Direct dep: lib/onchain/tempo/transaction{,/builder}.ex call Cartouche
      # (Signer, Transaction, RPC) themselves rather than only through onchain.
      # 0.6 is the floor that lifts cartouche's transitive `req < 0.7` cap.
      {:cartouche, "~> 0.6"},
      # Widened from `~> 0.5`: two-segment, so it always admitted 0.7.x, but the
      # stale floor understated what actually resolves here.
      {:req, "~> 0.6 or ~> 0.7"},
      {:jason, "~> 1.4"},
      # Floor raised 0.9 -> 0.11 to match cartouche 0.6's `descripex ~> 0.11`;
      # nothing below 0.11 was resolvable regardless of what this claimed.
      {:descripex, "~> 0.11"},

      # Req.Test needs plug for test stubs; tidewave needs it in dev
      {:plug, "~> 1.16", only: [:dev, :test]},

      # Dev/test tooling
      {:tidewave, "~> 0.5", only: :dev},
      {:bandit, "~> 1.0", only: :dev},
      {:ex_unit_json, "~> 0.4", only: [:dev, :test], runtime: false},
      {:dialyzer_json, "~> 0.1", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.39", only: :dev, runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Tempo blockchain primitives for Elixir — 0x76 transactions, TIP-20 tokens, RPC broadcasting, and event parsing. Built on onchain."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "OnchainTempo",
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp aliases do
    [
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4010) end)'"
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp dialyzer do
    [
      # OOM mitigation: skip transitive deps (default is :app_tree).
      # Tidewave/bandit's HTTP stack (plug, finch, mint, gun, cowlib, etc.)
      # is not in lib/'s call graph and bloats PLT to ~800 modules.
      # Note: Req is a runtime dep here — Req-call warnings are suppressed
      # via ~r/Function Req\./ in .dialyzer_ignore.exs.
      plt_add_deps: :apps_direct,
      plt_add_apps: [:mix],
      plt_local_path: "priv/plts",
      plt_core_path: "priv/plts",
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end
end
