# Gate helpers shared by all eight packages (`agents_check/1`,
# `advisory_freshness/1`, `host_script/3`) live at the monorepo root in
# `shared/mix_helpers.exs`. That file is NOT part of the published tarball, so
# the load is guarded and every call site degrades to a loud skip: nothing in
# this file may assume the monorepo checkout. (hieroglyph declares no in-repo
# sibling — descripex is its only first-party dep and stays a Hex dep — so it
# carries no `sibling/3`.)
# `Code.ensure_loaded?/1` keeps the load idempotent (a re-require of the same
# path would redefine the module and warn).
shared_mix_helpers = Path.expand("../../shared/mix_helpers.exs", __DIR__)

if not Code.ensure_loaded?(OnchainMonorepo.MixHelpers) and File.exists?(shared_mix_helpers) do
  Code.require_file(shared_mix_helpers)
end

defmodule ABI.Mixfile do
  use Mix.Project

  @spec project() :: keyword()
  def project do
    [
      app: :hieroglyph,
      version: "1.8.0",
      # 1.18 floor: `lib/` uses `Enum.sum_by/2` (added in Elixir 1.18) on the
      # tuple/array encode path, so a lower floor would compile with only a
      # warning and then die at runtime in a consumer's first encode call.
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      description:
        "Solidity ABI encoder/decoder for Elixir. Maintained fork of exthereum/abi with bugfixes and Elixir 1.19+ support.",
      source_url: "https://github.com/ZenHive/hieroglyph",
      homepage_url: "https://github.com/ZenHive/hieroglyph",
      docs: [
        main: "ABI",
        extras: ["README.md", "CHANGELOG.md"],
        skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
      ],
      package: package(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      compilers: [:yecc, :leex] ++ Mix.compilers(),
      aliases: aliases(),
      # OOM mitigation: :apps_direct skips transitive dep recursion (default
      # :app_tree). Tidewave/bandit's HTTP stack (plug, finch, mint, gun,
      # cowlib, etc.) is not in lib/'s call graph. priv/plts/ survives `mix
      # clean` / _build wipes.
      dialyzer: [
        plt_add_deps: :apps_direct,
        plt_add_apps: [:mix, :descripex],
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts"
      ],
      deps: deps()
    ]
  end

  @spec package() :: keyword()
  defp package do
    [
      name: "hieroglyph",
      maintainers: ["ZenHive"],
      licenses: ["MIT"],
      files: ~w(lib src skills mix.exs README.md CHANGELOG.md LICENSE.md .formatter.exs),
      links: %{
        "GitHub" => "https://github.com/ZenHive/hieroglyph",
        "Changelog" => "https://github.com/ZenHive/hieroglyph/blob/main/CHANGELOG.md",
        "Upstream (fork-of)" => "https://github.com/exthereum/abi"
      }
    ]
  end

  @spec cli() :: keyword()
  def cli do
    [
      preferred_envs: [
        "test.json": :test,
        "dialyzer.json": :dev,
        "check.dispatch": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  @spec application() :: keyword()
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  @spec elixirc_paths(atom()) :: [String.t()]
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  @spec aliases() :: keyword()
  defp aliases do
    [
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4006) end)'"
      ],
      # TagTODO/TagFIXME stay on in .credo.exs for visibility; the gate excludes
      # them so it fails only on real regressions, not tracked debt.
      "check.fast": [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict --ignore TagTODO,TagFIXME"
      ],
      # Manual / CI gate (NOT run by the commit hook). Drops dialyzer; keeps
      # tests + sobelow + doctor. 95% coverage — this is a wire-format/crypto
      # encoder (critical business logic).
      precommit: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict --ignore TagTODO,TagFIXME",
        "doctor --raise",
        # `preferred_envs` (cli/0) is ignored for alias steps, and `mix cmd`
        # runs args via `System.cmd` with no shell (so a `MIX_ENV=test` prefix
        # is treated as the binary name). Spawn a fresh `mix` in :test instead.
        &cover_gate/1,
        "sobelow --skip --exit low"
      ],
      # Dispatch-scale gate handed to the harness reviewer as `check_command`.
      # Deliberately omits `agents.check`: harness prepends an ephemeral
      # instruction preamble to AGENTS.md inside the reviewer worktree, which
      # that check correctly reports as drift — a red the reviewer can neither
      # fix nor ignore. Freshness stays enforced by `precommit.full`, which
      # runs on the landed base where no preamble exists. Also omits the
      # coverage gate and dialyzer, which are landed-base concerns.
      "check.dispatch": [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --ignore TagTODO,TagFIXME",
        "doctor --raise",
        "ex_dna --max-clones 0",
        "sobelow --skip --exit low",
        "test.json --exclude integration"
      ],
      # CI mirror — adds ex_dna clone detection, reach PDG arch/smell gates,
      # the security-advisory audit, dialyzer, AGENTS.md freshness, and
      # api_manifest.json freshness. Matches the onchain-family canonical
      # gate (see onchain-stack/CLAUDE.md). Order is append-after-`precommit`,
      # not the family's canonical step order — this repo's `cover_gate/1`
      # mechanism (below) predates and supersedes the family's
      # `cmd env MIX_ENV=test mix ...` step form.
      "precommit.full": [
        "precommit",
        # After `precommit` so the project is compiled. Mix.Task.rerun/2
        # because Mix runs a given task name at most once per VM.
        &manifest_check/1,
        "ex_dna --max-clones 0",
        "reach.check --arch --smells",
        "deps.audit.gated",
        "dialyzer.json --quiet",
        "agents.check"
      ],
      # mix_audit discards its sync exit status (mirego/mix_audit#61), so a
      # frozen advisory DB still reports green. Prove freshness first, then
      # audit. This repo's `deps.audit` reports clean — no ignore file needed.
      "deps.audit.gated": [
        &advisory_freshness/1,
        "deps.audit"
      ],
      # Fails when AGENTS.md has drifted from CLAUDE.md. Compares rendered
      # output, not mtimes, so drift in a transitive @-import is caught too.
      "agents.check": [
        &agents_check/1
      ],
      ci: ["precommit.full"]
    ]
  end

  # 95% coverage gate. Spawns a child `mix` in :test (alias steps ignore
  # `cli/0` preferred_envs); a non-zero exit — test failure or sub-threshold
  # coverage — aborts the precommit run.
  @spec cover_gate([String.t()]) :: nil
  defp cover_gate(_args) do
    args =
      ~w(test.json --quiet --cover --cover-threshold 95 --summary-only --exclude integration)

    {_out, status} =
      System.cmd("mix", args, env: [{"MIX_ENV", "test"}], into: IO.stream())

    if status != 0, do: Mix.raise("coverage gate failed (mix test exit #{status})")
  end

  # Run "mix help deps" to learn about dependencies.
  @spec deps() :: [{atom(), String.t()} | {atom(), String.t(), keyword()}]
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:ex_sha3, "~> 0.1.4"},
      # Two-segment on purpose: the three-segment cap turned every descripex
      # minor into a forced nine-repo release cascade, while the committed
      # `mix.lock` already blocks a silent in-family upgrade — a new descripex
      # lands only through a deliberate `mix deps.update` behind `mix ci`.
      # descripex 1.0.0 (2026-08-26) is the stable major this cap was always
      # meant to reach for; the break-on-minor history that earned the cap
      # on 0.x (0.12.0 turned `short_name` from atom to string) does not
      # apply post-1.0 under semver.
      {:descripex, "~> 1.0"},
      {:ex_unit_json, "~> 0.4", only: [:dev, :test], runtime: false},
      {:dialyzer_json, "~> 0.2", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:doctor, "~> 0.23", only: [:dev, :test], runtime: false},
      {:tidewave, "~> 0.5", only: :dev},
      {:bandit, "~> 1.10", only: :dev},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      # Reach 2.8.2 caps ex_ast at ~> 0.12.0; Reach uses APIs retained
      # by ex_ast 0.13.
      {:ex_ast, "~> 0.13", override: true, only: [:dev, :test], runtime: false},
      {:reach, "~> 2.8", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      # Mutation-adequacy measurement (roadmap task 46), on demand only —
      # never a `mix ci` gate. 0.9.0 floor is not cosmetic: 0.8.2 could not
      # report a surviving mutant on Elixir 1.20 at all (Oeditus/muex#20),
      # and 0.9.0 carries the sandbox fix (#25) that symlinks `test/`
      # subdirectories into worker sandboxes — without it the vendored
      # ethers vector corpus under test/support/fixtures/ is invisible to
      # a narrowed run.
      {:muex, "~> 0.9", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.1", only: :test}
    ]
  end

  @spec manifest_check([String.t()]) :: :ok
  defp manifest_check(_args) do
    Mix.Task.rerun("hieroglyph.manifest", ["--check"])
    :ok
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
