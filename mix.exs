defmodule OnchainAave.MixProject do
  use Mix.Project

  @version "0.2.1"
  @source_url "https://github.com/ZenHive/onchain_aave"

  def project do
    [
      app: :onchain_aave,
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
      # Floor raised 0.8 -> 0.11: onchain 0.11.0 carries `cartouche ~> 0.6`.
      # `~> 0.8` permitted it but did not require it, so a consumer locked on an
      # older onchain kept resolving cartouche 0.5.x and stayed capped below
      # req 0.7.
      {:onchain, "~> 0.11"},
      {:decimal, "~> 3.1"},
      # Floor raised 0.9 -> 0.11 to match what cartouche 0.6 already forces.
      {:descripex, "~> 0.11"},

      # Dev/test tooling
      {:onchain_evm, path: "../onchain_evm", only: [:dev, :test]},
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:tidewave, "~> 0.5", only: :dev},
      {:bandit, "~> 1.0", only: :dev},
      {:ex_unit_json, "~> 0.6.0", only: [:dev, :test], runtime: false},
      {:dialyzer_json, "~> 0.1", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7.18", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.39", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Aave V3 protocol wrappers for Elixir — pool reads/writes, oracle, math, and type structs. Built on onchain."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "OnchainAave",
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp aliases do
    [
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4012) end)'"
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
      plt_add_deps: :apps_direct,
      plt_add_apps: [:mix],
      plt_local_path: "priv/plts",
      plt_core_path: "priv/plts",
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end
end
