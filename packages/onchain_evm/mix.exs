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

defmodule OnchainEvm.MixProject do
  use Mix.Project

  @version "0.7.0"
  @source_url "https://github.com/ZenHive/onchain-stack"

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
      # happens to have landed on a fixed 2.5.0. onchain 0.12.0 also narrows
      # `descripex` to `~> 0.12.0`, matching what this package declares below.
      sibling(:onchain, "~> 0.12"),
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
      {:rustler_precompiled, "~> 0.9.0"},
      # Optional so Hex consumers with a matching artifact don't need a Rust
      # toolchain. Required when `force_build` is set (Windows, unmatched
      # targets, `RUSTLER_PRECOMPILED_FORCE_BUILD_ALL=1`, `ONCHAIN_EVM_BUILD=1`).
      {:rustler, "~> 0.38", optional: true, runtime: false},

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
      {:ex_ast, "~> 0.13", override: true, only: [:dev, :test], runtime: false},
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
      links: %{
        "GitHub" => "https://github.com/ZenHive/onchain-stack/tree/main/packages/onchain_evm",
        "Changelog" => "https://github.com/ZenHive/onchain-stack/blob/main/packages/onchain_evm/CHANGELOG.md"
      },
      # Matching hosts load a GitHub-Release artifact. Unmatched hosts
      # (Windows, or `RUSTLER_PRECOMPILED_FORCE_BUILD_ALL=1`) still compile
      # from source, so the `native/` crate sources MUST ship. `checksum-*.exs`
      # is generated after upload by `mix rustler_precompiled.download` — if it
      # is missing from the package, every consumer silently loses checksum
      # verification. `native/.cargo` carries the musl rustflags the source
      # build needs. All of `priv/` is test fixtures + build artifacts
      # (.so / PLTs / vendored Solidity) — nothing in `lib/` reads it at
      # runtime, so it is excluded.
      files: ~w(
          lib
          native/onchain_evm/src
          native/onchain_evm/Cargo.toml
          native/onchain_evm/Cargo.lock
          native/onchain_solidity/src
          native/onchain_solidity/Cargo.toml
          native/onchain_solidity/Cargo.lock
          native/.cargo
          checksum-*.exs
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
      source_ref: "onchain_evm-v#{@version}",
      source_url: @source_url,
      # ExDoc builds file links relative to the package root, but the
      # monorepo puts the package two levels below the repo root — without
      # this pattern every generated doc link 404s against
      # packages/onchain_evm/lib/… instead of the repo-root-relative path
      # GitHub actually serves.
      source_url_pattern:
        "https://github.com/ZenHive/onchain-stack/blob/onchain_evm-v#{@version}/packages/onchain_evm/%{path}#L%{line}"
    ]
  end

  defp aliases do
    [
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4009) end)'"
      ],
      integration: ["test.json --only integration"],
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
      # Fast local pre-commit loop — skips the cold-PLT dialyzer and full coverage
      # pass so it stays quick on incremental edits.
      precommit: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME",
        "ex_dna --max-clones 0",
        "test.json --exclude integration"
      ],
      # Comprehensive gate — landed-base Architect/QA pass and `mix ci` target.
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
        &cargo_test/1,
        &cargo_clippy/1,
        "dialyzer",
        "agents.check"
      ],
      # Fails when AGENTS.md has drifted from CLAUDE.md. Compares rendered output,
      # not mtimes, so drift in a transitive @-import is caught too.
      "agents.check": [
        &agents_check/1
      ],
      # Keep the reviewed advisory baseline active for direct invocations and
      # host hooks, not only for the comprehensive gate below.
      "deps.audit": "deps.audit --ignore-file .mix_audit_ignore",
      # mix_audit discards its own sync exit status (mirego/mix_audit#61), so a
      # frozen advisory DB still reports "No vulnerabilities found" and exits 0.
      # Prove freshness first, then audit. `.mix_audit_ignore` carries the one
      # verified false positive (GHSA-w4f7-4cxr-rv3c on gun — see the file).
      "deps.audit.gated": [
        &advisory_freshness/1,
        "deps.audit"
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

  # Rust crate gate. Lives in `Onchain.Cargo` so the skip/fail paths are
  # unit-testable; these captures are the `precommit.full` steps.
  @spec cargo_test([String.t()]) :: :ok
  defp cargo_test(_args), do: Onchain.Cargo.run(:test)

  @spec cargo_clippy([String.t()]) :: :ok
  defp cargo_clippy(_args), do: Onchain.Cargo.run(:clippy)

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
