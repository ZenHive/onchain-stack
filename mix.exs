defmodule OnchainJs.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/ZenHive/onchain_js"

  def project do
    [
      app: :onchain_js,
      version: @version,
      # 1.18 floor inherited transitively from hieroglyph 1.6.0, whose encode
      # path uses `Enum.sum_by/2` (Elixir 1.18+).
      elixir: "~> 1.18",
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
      extra_applications: [:logger],
      mod: {OnchainJs.Application, []}
    ]
  end

  defp deps do
    [
      # Floor raised 0.11 -> 0.12: onchain 0.12.0 is the release that raises
      # `zen_websocket` to `~> 0.6.0`, which *requires* the gun version carrying
      # the GHSA-w4f7-4cxr-rv3c fix rather than merely permitting it. `~> 0.11`
      # admits 0.12.0 but does not require it, so this lock would keep resolving
      # onchain 0.11.0 -> zen_websocket 0.4.2, whose looser gun bound only
      # happens to have landed on a fixed 2.5.0. onchain 0.12.0 also narrows
      # `descripex` to `~> 0.12.0`, matching what this package declares below.
      {:onchain, "~> 0.12"},
      {:quickbeam, "~> 0.10.4"},
      {:npm, "~> 0.7"},
      # Three-segment on purpose (caps at < 0.13.0): descripex 0.12.0 changed
      # `short_name` in describe/1 output from atom to string at a *minor*
      # bump, which the previous `~> 0.11` would have absorbed silently. A 0.x
      # package that breaks on minor earns the tighter form; raise the cap
      # deliberately after reading its CHANGELOG.
      {:descripex, "~> 0.12.0"},

      # Dev/test tooling
      {:tidewave, "~> 0.6", only: :dev},
      {:bandit, "~> 1.0", only: :dev},
      {:ex_unit_json, "~> 0.4", only: [:dev, :test], runtime: false},
      {:dialyzer_json, "~> 0.2", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_ast, "~> 0.12", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.8", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "JavaScript bridge for Ethereum — run npm packages (solc-js, Uniswap SDK, DeFiSaver) on the BEAM via QuickBEAM. Built on onchain."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "OnchainJs",
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp aliases do
    [
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4028) end)'"
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
      # target. Coverage floor is 25 against a 27.78% measured baseline
      # (2026-08-01) — this repo's lib/ surface is a thin 4-module bridge; most
      # behavior is only exercised by the (excluded-by-default) QuickBEAM
      # integration tests.
      "precommit.full": [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME",
        "doctor --raise",
        "ex_dna --max-clones 0",
        "reach.check --arch --smells",
        "sobelow --skip",
        "deps.audit.gated",
        "cmd env MIX_ENV=test mix test.json --cover --cover-threshold 25 --summary-only --exclude integration",
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
      # mix_audit discards its sync exit status (mirego/mix_audit#61), so a frozen
      # advisory DB still reports green. Prove freshness first, then audit.
      "deps.audit.gated": [
        &advisory_freshness/1,
        "deps.audit --ignore-file .mix_audit_ignore"
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
      plt_add_apps: [:mix],
      plt_local_path: "priv/plts",
      plt_core_path: "priv/plts",
      ignore_warnings: ".dialyzer_ignore.exs"
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
