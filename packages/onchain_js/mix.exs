defmodule OnchainJs.MixProject do
  use Mix.Project

  @version "0.3.1"
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

  # In the monorepo checkout this resolves to an in-repo path dep; everywhere
  # else the declared Hex requirement below wins. The predicate is the root
  # marker `.onchain-monorepo-root` — NEVER the existence of the sibling: in a
  # consumer's `deps/` layout every Hex package is unpacked side by side, so
  # `../cartouche/mix.exs` exists there too and an existence check would fire
  # exactly at the stranger. `ONCHAIN_PUBLISH=1` forces the Hex branch, because
  # `mix hex.publish` rejects path deps (precedent: onchain_aave 0.3.0 shipped
  # `{:onchain_evm, path: "../onchain_evm", only: [:dev, :test]}` and was
  # unbuildable for everyone else — `only:` does not save you).
  #
  # Convention, parsed by `mix onchain.bounds` at the monorepo root: the call is
  # a literal `sibling(:name, "<requirement>")` or
  # `sibling(:name, "<requirement>", opts)`; name and requirement are literals.
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
      # Floor raised 0.11 -> 0.12: onchain 0.12.0 is the release that raises
      # `zen_websocket` to `~> 0.6.0`, which *requires* the gun version carrying
      # the GHSA-w4f7-4cxr-rv3c fix rather than merely permitting it. `~> 0.11`
      # admits 0.12.0 but does not require it, so this lock would keep resolving
      # onchain 0.11.0 -> zen_websocket 0.4.2, whose looser gun bound only
      # happens to have landed on a fixed 2.5.0. Two-segment, so onchain 0.13.0
      # resolves here without a bound edit.
      sibling(:onchain, "~> 0.12"),
      # Three-segment on purpose: QuickBEAM is a 0.x native runtime dependency,
      # so each minor line is reviewed and tested before this cap moves.
      {:quickbeam, "~> 0.11.0"},
      {:npm, "~> 0.7"},
      # Two-segment on purpose: the three-segment cap turned every descripex
      # minor into a forced nine-repo release cascade, while the committed
      # `mix.lock` already blocks a silent in-family upgrade — a new descripex
      # lands only through a deliberate `mix deps.update` behind `mix ci`. The
      # break-on-minor history that earned the cap (0.12.0 turned `short_name`
      # from atom to string) is being retired at descripex, not paid for here.
      {:descripex, "~> 0.12"},

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
      # `override: true` on purpose: reach 2.8.2 declares `ex_ast ~> 0.12.0`,
      # which would otherwise hold this repo at 0.12.10. Measured on onchain
      # 2026-08-22: `mix reach.check --dead-code --arch --smells` produces
      # identical output over identical scope under 0.12.10 and 0.13.1.
      {:ex_ast, "~> 0.13", override: true, only: [:dev, :test], runtime: false},
      {:reach, "~> 2.8", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "JavaScript bridge for Ethereum — run npm packages (solc-js, Uniswap SDK, DeFiSaver) on the BEAM via QuickBEAM. Built on onchain."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      # Explicit list because hex's default `files` ships all of `priv/`, and
      # `priv/` here holds nothing but the dialyzer PLTs that `dialyzer/0`
      # pins there (`plt_local_path`). .gitignore does not apply to
      # `mix hex.build`, so 0.2.0 shipped an 11 MB tarball that was two whole
      # generations of PLT (OTP 27 and OTP 29-rc) and ~40 KB of package. The
      # Zig NIFs come from the `quickbeam` dep, not from this repo, so
      # nothing under `priv/` needs to ship.
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
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
      # Harness reviewer target — `harness_dev.projects` registers this repo with
      # `check_command: "mix check.dispatch"`, and until 2026-08-23 the alias did
      # not exist, so every reviewer booked a failed check against a task that was
      # fine. It is `precommit.full` minus four steps a reviewer worktree cannot
      # or should not run: `agents.check` (harness appends an ephemeral preamble
      # to AGENTS.md in the worktree, so the render never matches),
      # `deps.audit.gated` (all ten family repos share one advisory clone and
      # concurrent worktrees interleave its fetch), the cold-PLT dialyzer, and the
      # coverage pass. `--smells` is off for the reach #36 reason documented
      # below, exactly as in `precommit.full`.
      "check.dispatch": [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME",
        "doctor --raise",
        "ex_dna --max-clones 0",
        "reach.check --arch",
        "sobelow --skip --exit low",
        "cmd env MIX_ENV=test mix test.json --exclude integration"
      ],
      "precommit.full": [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME",
        "doctor --raise",
        "ex_dna --max-clones 0",
        # `--smells` is OFF here, and only here in the family. reach 2.8.2
        # aborts the whole smell pass with `KeyError key :module` on any
        # JavaScript function node (elixir-vibe/reach#36): non-Elixir meta
        # carries no `:module`, and three sites read it with dot access. This
        # repo pulls the QuickBEAM plugin in via its `quickbeam` dep, so the JS
        # nodes are unavoidable — unlike hieroglyph's generated Erlang, they
        # have no source path to exclude, and `plugins:` is not a `.reach.exs`
        # key. Restore `--smells` (and drop this comment) as soon as a reach
        # release carries the bracket-access fix; `.reach.exs` still sets
        # `smells: [strict: true]` so it gates again the moment it is back.
        "reach.check --arch",
        "sobelow --skip --exit low",
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
