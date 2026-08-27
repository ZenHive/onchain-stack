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

defmodule Onchain.MixProject do
  use Mix.Project

  @version "0.13.0"
  @source_url "https://github.com/ZenHive/onchain"

  def project do
    [
      app: :onchain,
      version: @version,
      # 1.18 floor inherited transitively from hieroglyph 1.6.0 (via cartouche),
      # whose encode path uses `Enum.sum_by/2` (Elixir 1.18+).
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
      sibling(:cartouche, "~> 0.6"),
      {:decimal, "~> 3.1.1"},
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
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.0"},
      {:req, "~> 0.6"},
      {:telemetry, "~> 1.4"},
      # 0.5.0 is where `gun` rises to `~> 2.4` and thereby *requires* the fix for
      # GHSA-w4f7-4cxr-rv3c instead of merely permitting it; 0.6.0 is where
      # `descripex` narrows to `~> 0.12.0`, matching what this package now
      # declares directly. 0.7.0 widens `JsonRpc.build_request/2`'s spec to
      # accept positional lists, which is what let the `@dialyzer` suppression
      # in `Onchain.Subscription` go away. 0.8.0 is a documentation-accuracy
      # release — no runtime change reaches this package: the three defects it
      # fixes (`send_message/2` takes an encoded binary, `heartbeat_interval` is
      # not a connect option, non-`connect/2` start paths need an explicit
      # `:handler`) are all things `Onchain.Subscription` already did correctly.
      # Three-segment (caps at < 1.0.0) because zen_websocket keeps shipping
      # minors it labels breaking for consumers — a two-segment `~> 0.9` would
      # absorb the next one silently. 0.9.0 is a pure bound widening
      # (`descripex ~> 0.12` -> `~> 1.0`, "No runtime code changed"), and it is
      # *required* here: hieroglyph 1.8.0 declares `descripex ~> 1.0`, so
      # zen_websocket 0.8.0's `< 1.0.0` ceiling makes this graph unresolvable.
      {:zen_websocket, "~> 0.9.0"},

      # Dev/test tooling
      # Req.Test plug-based transport stubbing (req's :plug is optional);
      # tidewave (dev) also needs plug, so it spans :dev and :test.
      {:plug, "~> 1.17", only: [:dev, :test]},
      {:tidewave, "~> 0.6", only: :dev},
      {:bandit, "~> 1.0", only: :dev},
      {:ex_unit_json, "~> 0.6.0", only: [:dev, :test], runtime: false},
      {:dialyzer_json, "~> 0.2.0", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23.0", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.15", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false},
      {:ex_dna, "~> 1.3", only: [:dev, :test], runtime: false},
      # `override: true` on purpose: reach 2.8.2 declares `ex_ast ~> 0.12.0`,
      # which would otherwise hold this repo at 0.12.10. The override was long
      # carried as "unmeasured", on the theory that ex_ast 0.13.0's subset map
      # patterns could make reach's smell checks report fewer findings. Measured
      # 2026-08-22: `mix reach.check --dead-code --arch --smells` run here under
      # both 0.12.10 and 0.13.1 produced identical output over identical scope.
      {:ex_ast, "~> 0.13", override: true, only: [:dev, :test], runtime: false},
      # Two-segment on purpose: the previous `~> 2.7.1` was three-segment
      # (>= 2.7.1 and < 2.8.0) and blocked reach 2.8.x with no reason beyond
      # the way the bound was written.
      {:reach, "~> 2.8", only: [:dev, :test], runtime: false},
      {:boxart, "~> 0.3.3", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Shared Ethereum/blockchain library for read (eth_call) and write (transaction signing) operations using cartouche."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      # Ship only the JSON specs the lib reads at compile time — NOT the vendored
      # priv/specs/erigon-<sha>/ Go source tree (752K, dev-scraper input only,
      # regenerated by `mix onchain.scrape_erigon_methods` → erigon-methods.json).
      files: ~w(lib priv/specs/*.json .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "Onchain",
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp aliases do
    [
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4007) end)'"
      ],
      # Fast local pre-commit loop — skips the cold-PLT dialyzer and the coverage
      # pass so it stays quick on incremental edits.
      precommit: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME",
        "ex_dna --max-clones 0",
        # `preferred_envs` (cli/0) is ignored for alias steps — set MIX_ENV via
        # `env` (Elixir 1.20's `mix cmd` no longer parses a leading VAR=val prefix).
        "cmd env MIX_ENV=test mix test.json --exclude integration"
      ],
      # Harness reviewer target — `harness_dev.projects` registers this repo with
      # `check_command: "mix check.dispatch"`, and until 2026-08-23 the alias did
      # not exist, so every reviewer booked a failed check against a task that was
      # fine. It is `precommit.full` minus four steps a reviewer worktree cannot
      # or should not run: `agents.check` (harness appends an ephemeral preamble
      # to AGENTS.md in the worktree, so the render never matches),
      # `deps.audit.gated` (all ten family repos share one advisory clone and
      # concurrent worktrees interleave its fetch), the cold-PLT dialyzer, and the
      # coverage pass. Same shape as hieroglyph's and onchain_evm's.
      "check.dispatch": [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME",
        "doctor --raise",
        "ex_dna --max-clones 0",
        "reach.check --arch --smells",
        "sobelow --skip --exit low",
        "cmd env MIX_ENV=test mix test.json --exclude integration"
      ],
      # Comprehensive gate — the `mix ci` target. Coverage floor 70 matches the family convention already encoded
      # in .github/workflows/harness.yml (measured baseline: 79.04%). reach's
      # analysis scope (see .reach.exs) includes the `dev` root in addition to
      # `lib`/`src` — do not narrow it.
      "precommit.full": [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME",
        "doctor --raise",
        "ex_dna --max-clones 0",
        "reach.check --arch --smells",
        "sobelow --skip --exit low",
        "deps.audit.gated",
        "cmd env MIX_ENV=test mix test.json --cover --cover-threshold 70 --summary-only --exclude integration",
        "dialyzer",
        # AGENTS.md is what the cross-family (codex/cursor/grok) reviewers read;
        # a stale render makes them gate against rules that already changed.
        "agents.check"
      ],
      # mix_audit discards its sync exit status (mirego/mix_audit#61), so a
      # frozen advisory DB still reports green. Prove freshness first, then
      # audit. `deps.audit` reports the gun/GHSA-w4f7-4cxr-rv3c false positive
      # (see .mix_audit_ignore for the verified rationale) — ignore-file scoped.
      "deps.audit.gated": [
        &advisory_freshness/1,
        "deps.audit --ignore-file .mix_audit_ignore"
      ],
      # Fails when AGENTS.md has drifted from CLAUDE.md. Compares rendered
      # output, not mtimes, so drift in a transitive @-import is caught too.
      "agents.check": [
        &agents_check/1
      ],
      ci: ["precommit.full"]
    ]
  end

  defp elixirc_paths(:dev), do: ["lib", "dev"]
  defp elixirc_paths(:test), do: ["lib", "dev", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp dialyzer do
    [
      # OOM mitigation: skip transitive deps (default is :app_tree).
      # Tidewave/bandit's HTTP stack (plug, finch, mint, gun, cowlib, etc.)
      # is not in lib/'s call graph and bloats PLT to ~800 modules.
      plt_add_deps: :apps_direct,
      plt_add_apps: [:ex_unit, :mix, :hieroglyph, :curvy],
      plt_local_path: "priv/plts",
      plt_core_path: "priv/plts"
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
