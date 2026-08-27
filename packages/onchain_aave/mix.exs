# Gate helpers shared by all eight packages (`agents_check/1`,
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

defmodule OnchainAave.MixProject do
  use Mix.Project

  @version "0.4.0"
  @source_url "https://github.com/ZenHive/onchain_aave"

  def project do
    [
      app: :onchain_aave,
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
      extra_applications: [:logger]
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
      {:decimal, "~> 3.1"},
      # Two-segment on purpose: the three-segment cap turned every descripex
      # minor into a forced nine-repo release cascade, while the committed
      # `mix.lock` already blocks a silent in-family upgrade — a new descripex
      # lands only through a deliberate `mix deps.update` behind `mix ci`. The
      # break-on-minor history that earned the cap (0.12.0 turned `short_name`
      # from atom to string) is being retired at descripex, not paid for here.
      # Widened to `~> 1.0` family-wide: descripex 1.0.0 is behaviourally equal
      # to 0.13.0 (its own CHANGELOG: "No behavioural change over 0.13.0"), and
      # hieroglyph already declares `~> 1.0`. With hieroglyph in the graph as a
      # path dep a `< 1.0.0` ceiling here makes the family unresolvable.
      {:descripex, "~> 1.0"},

      # Dev/test tooling
      sibling(:onchain_evm, "~> 0.6", only: [:dev, :test]),
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
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.39", only: :dev, runtime: false},

      # Reach 2.8.2 caps ex_ast at ~> 0.12.0; Reach uses APIs retained by ex_ast 0.13.
      {:ex_ast, "~> 0.13", override: true, only: [:dev, :test], runtime: false},
      {:reach, "~> 2.8", only: [:dev, :test], runtime: false},
      # Clone detection (vibe_kit baseline) — matches sibling repos.
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Aave V3 and V4 protocol wrappers for Elixir — pool reads/writes, Hub-and-Spoke reads, Position Manager writes, oracle, math, and type structs. Built on onchain."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      # Explicit list because hex's default `files` ships all of `priv/`, and
      # `priv/plts/` holds the dialyzer PLTs this project pins there
      # (`dialyzer/0` sets `plt_local_path`). .gitignore does not apply to
      # `mix hex.build`, so 0.3.0 shipped a 5.5 MB tarball that was ~5.4 MB
      # of dev-only PLT. Ship `priv/abis` and nothing else under `priv`.
      files: ~w(lib priv/abis .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
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
      # Coverage floor is 65 against a 68.44% measured baseline (2026-08-01).
      #
      # `--summary-only` is deliberately OMITTED here (2026-08-03): the flag is
      # in ex_unit_json's `retry_disqualified_opts?/1` list, so it silently
      # disables the tool's own automatic retry-on-flaky (see
      # `deps/ex_unit_json/lib/mix/tasks/test_json.ex`). With it set, a
      # transient failure never gets the self-heal re-run AND its detail is
      # stripped from the JSON — exactly the "232 pass locally, 2 fail in CI,
      # identity unknown" shape hit in run 30742057271. Dropping it restores
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
      # `flunk/1` callsite reads as `unknown_function` (5 errors, exit 2). The
      # gate only surfaced it once the integration tests stopped failing first.
      plt_add_apps: [:mix, :ex_unit],
      plt_local_path: "priv/plts",
      plt_core_path: "priv/plts"
      # No `ignore_warnings:` — `.dialyzer_ignore.exs` was deleted once all 17 of
      # its entries reported as unnecessary skips. It carried a
      # `~r/Function Onchain\./` catch-all that would have swallowed any real
      # unknown_function on an Onchain call, and its own TODO said to remove it
      # when the upstream Signet.Hex specs were fixed. They are.
    ]
  end

  # Shared with the other seven packages — see `shared/mix_helpers.exs` at the
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
