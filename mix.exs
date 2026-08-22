defmodule OnchainEvm.MixProject do
  use Mix.Project

  @version "0.5.0"
  @source_url "https://github.com/ZenHive/onchain_evm"

  def project do
    [
      app: :onchain_evm,
      version: @version,
      # 1.18 floor inherited transitively from hieroglyph 1.6.0, whose encode
      # path uses `Enum.sum_by/2` (Elixir 1.18+).
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
      dialyzer: dialyzer(),
      test_coverage: test_coverage(),
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
        "dialyzer.json": :dev,
        integration: :test,
        ci: :test,
        precommit: :test,
        "precommit.full": :test
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
      # Floor raised 0.11 -> 0.12: onchain 0.12.0 is the release that raises
      # `zen_websocket` to `~> 0.6.0`, which *requires* the gun version carrying
      # the GHSA-w4f7-4cxr-rv3c fix rather than merely permitting it. `~> 0.11`
      # admits 0.12.0 but does not require it, so this lock would keep resolving
      # onchain 0.11.0 -> zen_websocket 0.4.2, whose looser gun bound only
      # happens to have landed on a fixed 2.5.0. onchain 0.12.0 also narrows
      # `descripex` to `~> 0.12.0`, matching what this package declares below.
      {:onchain, "~> 0.12"},
      # Two-segment on purpose: the three-segment cap turned every descripex
      # minor into a forced nine-repo release cascade, while the committed
      # `mix.lock` already blocks a silent in-family upgrade — a new descripex
      # lands only through a deliberate `mix deps.update` behind `mix ci`. The
      # break-on-minor history that earned the cap (0.12.0 turned `short_name`
      # from atom to string) is being retired at descripex, not paid for here.
      {:descripex, "~> 0.12"},
      {:rustler, "~> 0.38", runtime: false},

      # Dev/test tooling
      {:tidewave, "~> 0.9", only: :dev},
      {:bandit, "~> 1.12", only: :dev},
      {:ex_unit_json, "~> 0.4", only: [:dev, :test], runtime: false},
      {:dialyzer_json, "~> 0.1", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      # ex_doc >= 0.40 pulls makeup_elixir ~> 1.0, which :reach also requires;
      # the older ~> 0.39 pin holds makeup_elixir < 1.0 and conflicts with reach.
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},

      # Vibe analyzer stack (matches the onchain family — cartouche/onchain)
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_ast, "~> 0.12", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.7", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "EVM simulation, Solidity parsing, debug/trace APIs, and contract codegen for Elixir via Rust NIFs. Built on onchain."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      # Rust NIFs compile from source on the consumer — the `native/` crate
      # sources MUST ship (src + Cargo.toml + Cargo.lock per crate). All of
      # `priv/` is test fixtures + build artifacts (.so / PLTs / vendored
      # Solidity) — nothing in `lib/` reads it at runtime, so it is excluded.
      files: ~w(
          lib
          native/onchain_evm/src
          native/onchain_evm/Cargo.toml
          native/onchain_evm/Cargo.lock
          native/onchain_solidity/src
          native/onchain_solidity/Cargo.toml
          native/onchain_solidity/Cargo.lock
          .formatter.exs
          mix.exs
          README.md
          LICENSE
          CHANGELOG.md
        )
    ]
  end

  defp docs do
    [
      main: "OnchainEvm",
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp aliases do
    [
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4009) end)'"
      ],
      integration: ["test.json --only integration"],
      # Fast local pre-commit loop — skips the cold-PLT dialyzer and full coverage
      # pass so it stays quick on incremental edits.
      precommit: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME",
        "ex_dna --max-clones 0",
        "test.json --exclude integration"
      ],
      # Comprehensive gate — the harness reviewer's `check_command` and `mix ci` target.
      "precommit.full": [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME",
        "doctor --raise",
        "ex_dna --max-clones 0",
        "reach.check --arch --smells",
        "sobelow --skip --exit low",
        "deps.audit.gated",
        "test.json --cover --cover-threshold 85 --summary-only --exclude integration",
        "dialyzer",
        "agents.check"
      ],
      # Fails when AGENTS.md has drifted from CLAUDE.md. Compares rendered output,
      # not mtimes, so drift in a transitive @-import is caught too.
      "agents.check": [
        &agents_check/1
      ],
      # mix_audit discards its own sync exit status (mirego/mix_audit#61), so a
      # frozen advisory DB still reports "No vulnerabilities found" and exits 0.
      # Prove freshness first, then audit. `.mix_audit_ignore` carries the one
      # verified false positive (GHSA-w4f7-4cxr-rv3c on gun — see the file).
      "deps.audit.gated": [
        &advisory_freshness/1,
        "deps.audit --ignore-file .mix_audit_ignore"
      ],
      ci: ["precommit.full"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # `cover` recompiles each instrumented module's .beam, which re-triggers a
  # Rustler NIF's `on_load` as an unsupported "upgrade" — so the two NIF-backed
  # modules cannot be cover-instrumented (it fails non-deterministically based
  # on load order). Their pure-Elixir logic lives in cover-able sibling modules
  # (`Onchain.EVM.Params`, `Onchain.Solidity.Resolver`); only the thin NIF stub
  # shells are excluded. The modules stay fully exercised by the test suite.
  defp test_coverage do
    [ignore_modules: [Onchain.EVM, Onchain.Solidity]]
  end

  defp dialyzer do
    [
      # OOM mitigation: skip transitive deps (default is :app_tree).
      # The HTTP stack (req → finch → mint; tidewave/bandit → plug, gun, cowlib)
      # is not in lib/ call graph and bloats PLT to ~800 modules.
      plt_add_deps: :apps_direct,
      # :ex_unit so test/support/*.ex (ExUnit.Assertions.flunk/1) resolves in the PLT.
      plt_add_apps: [:mix, :ex_unit],
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
