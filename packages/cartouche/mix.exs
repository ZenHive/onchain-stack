defmodule Cartouche.MixProject do
  use Mix.Project

  def project do
    [
      app: :cartouche,
      version: "0.8.0",
      # 1.18 floor inherited from hieroglyph 1.6.0, whose encode path uses
      # `Enum.sum_by/2` (Elixir 1.18+). Declaring less would let cartouche
      # resolve on 1.17 and then fail compiling its own dependency.
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "Cartouche",
      description: "Lightweight Ethereum and Solana RPC client for Elixir",
      source_url: "https://github.com/zenhive/cartouche",
      docs: [
        main: "readme",
        extras: ["README.md", "CHANGELOG.md"],
        # CHANGELOG entries reference hidden generated modules (e.g.
        # `Cartouche.Contract.IConsole`, which has `@moduledoc false`) as
        # historical narrative — not as API documentation. ex_doc otherwise
        # warns and `mix docs --warnings-as-errors` (the pre-commit hook)
        # blocks the commit. Skip on CHANGELOG.md only; README and source
        # docstrings remain strict.
        skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
      ],
      # plt_*_path pin keeps the PLT outside _build/ so CI can cache it
      # independently of the deps cache (which invalidates on mix.lock).
      #
      # plt_add_deps: :apps_direct skips transitive dep recursion (default is
      # :app_tree). Tidewave/bandit's dev-only HTTP stack (plug, finch, mint,
      # gun, cowlib, etc.) is not in lib/'s call graph and bloats the PLT.
      #
      # plt_ignore_apps strips two clusters on top of :apps_direct:
      #   1. Goth — optional runtime auth dependency for the CloudKMS signer.
      #      The signer now calls KMS via Req directly; Goth only mints the
      #      bearer token.
      #   2. Dev-only direct deps (bandit, tidewave) — pulled in via the
      #      `tidewave` mix alias, never called from lib/. Including them
      #      means every Tidewave or Bandit minor bump invalidates the
      #      cartouche PLT, dragging incremental rebuilds back into the
      #      20+ minute range.
      dialyzer: [
        plt_add_deps: :apps_direct,
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts",
        plt_add_apps: [:mix, :ex_unit],
        plt_ignore_apps: [
          :goth,
          :bandit,
          :tidewave
        ]
      ],
      test_coverage: [ignore_modules: [Cartouche.Contract.IConsole]],
      package: package()
    ]
  end

  # ZenHive dev-branch only: preferred envs for our tooling.
  #
  # ci / precommit / precommit.full / check.dispatch pin :test so every step
  # (compile, credo, test.json, dialyzer) runs in one consistent env — dialyzer
  # then builds a `priv/plts/*_deps-test.plt`. The MIX_ENV=dev dialyzer pass
  # against the cached `priv/plts` PLT lived in `.github/workflows/harness.yml`,
  # removed family-wide on 2026-08-22 and never replaced: the :test view is the
  # only one anything checks now, so a clean `mix dialyzer` (dev) does not imply
  # a clean gate. Reproduce the gate's view with `MIX_ENV=test mix dialyzer`.
  def cli do
    [
      preferred_envs: [
        "test.json": :test,
        "dialyzer.json": :dev,
        integration: :test,
        ci: :test,
        precommit: :test,
        "precommit.full": :test,
        "check.dispatch": :test
      ]
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*", "CHANGELOG*"],
      maintainers: ["ZenHive"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/zenhive/cartouche",
        "Changelog" => "https://hexdocs.pm/cartouche/changelog.html"
      }
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Cartouche.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # zenhive/dev override: bumped from upstream's ~> 0.31.1 so :reach (needs
      # makeup_elixir ~> 1.0) can resolve. Never cherry-picked into PR branches
      # (they fork from `main` and keep upstream's pin).
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false},
      {:jason, "~> 1.4.5"},
      # Bumped to ~> 3.1 (2026-05-08). Decimal 3.0 tightens IEEE 754 decimal128
      # bounds (precision 28 → 34, exponent capped at ±6_144, CVE-2026-32686
      # DoS-bounded parsing) and fixes `to_integer("0.0")` infinite loop. No
      # changes to rounding modes, comparison, or normalization semantics —
      # safe for wei/fee token math (uint256 max ~78 digits << 6_178 string
      # cap). See https://github.com/ericmj/decimal/blob/main/CHANGELOG.md.
      {:decimal, "~> 3.1"},
      {:req, "~> 0.6.2 or ~> 0.7"},
      # Test-only intent: Req.Test builds `Plug.Conn`s for the stub plugs that
      # mock cartouche's outbound RPC calls. Req lists plug as optional. Scoped
      # `only: [:dev, :test]` (not `:test`) because the dev-only `tidewave` dep
      # already pulls plug `only: :dev` — a narrower `:only` here fails the
      # env-match check. Still excluded from prod (PLT + published deps).
      {:plug, "~> 1.16", only: [:dev, :test]},
      {:ex_sha3, "~> 0.1.5"},
      {:curvy, "~> 0.3.1"},
      {:goth, "~> 1.4.5", optional: true},
      {:ex_rlp, "~> 0.6.0"},
      # Promoted from transitive (via :hieroglyph) to direct so consumer
      # mix.exs files don't need to add it to use Cartouche.describe/0,1,2.
      # Floor is 0.9.1, not 0.9.0: 0.9.0's runtime @spec→JSON-Schema enrichment
      # crashed (CaseClauseError in json_spec) on the `%{non_neg_integer() =>
      # <<_::256>>}` spec of Solana.Transaction.sign_partial/2, taking down
      # Cartouche.describe/0 and __api__/1. Fixed in descripex 0.9.1.
      # Floor tracks what actually resolves: hieroglyph 1.6.0 requires
      # `descripex ~> 0.12.0`, so 0.11.x has been unreachable since that bump.
      # Declaring `~> 0.11` advertised a range cartouche can no longer be built
      # against — a consumer pinning 0.11.x hit a resolution conflict from
      # hieroglyph instead of a clear bound here.
      # Two-segment on purpose: the three-segment cap turned every descripex
      # minor into a forced nine-repo release cascade, while the committed
      # `mix.lock` already blocks a silent in-family upgrade — a new descripex
      # lands only through a deliberate `mix deps.update` behind `mix ci`. The
      # break-on-minor history that earned the cap (0.12.0 turned `short_name`
      # from atom to string) is being retired at descripex, not paid for here.
      {:descripex, "~> 0.12"},
      # Formerly `{:abi, path: "../abi"}`. The fork has been renamed and
      # published on hex.pm as `hieroglyph` 1.0.0 (hex package name only;
      # module namespace remains `ABI`). Switching to hex unblocks
      # `mix hex.publish` here (which rejects path/git deps).
      # `override: true` dropped at publish time — no transitive dep
      # pulls `hieroglyph` or `:abi`, so nothing needs overriding, and
      # hex rejects overrides on published packages.
      {:hieroglyph, "~> 1.6"},
      {:junit_formatter, "~> 3.4.0", only: [:test]},
      {:stream_data, "~> 1.4", only: :test, runtime: false}
    ] ++ zenhive_dev_deps()
  end

  # ZenHive dev-branch only. Never merged back to main (tracks upstream).
  # PR branches fork from `main` so these never appear in any upstream diff.
  defp zenhive_dev_deps do
    [
      {:styler, "~> 1.12.0", only: [:dev, :test], runtime: false},
      {:ex_unit_json, "~> 0.6.0", only: [:dev, :test], runtime: false},
      {:dialyzer_json, "~> 0.2.0", only: [:dev, :test], runtime: false},
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
      # Mutation-adequacy measurement (ROADMAP task 114). Not a CI gate —
      # campaigns are run on demand; the record lives in
      # docs/verification-ledger.md.
      #
      # muex 0.8.3 carries the fix for Oeditus/muex#20: 0.8.2's
      # `Muex.TestRunner.Port.count_failures/2` matched only the pre-1.20 ExUnit
      # summary wording (`N tests, M failures`), so on Elixir 1.20 —
      # `Result: N passed` / `Failed: N test` — the regex missed, the fallback
      # returned 1 failure, every survivor was reported `killed`, and the score
      # was a constant 100%. 0.8.3 adds a `^Failed: (\d+) tests?` pattern
      # alongside the old one.
      #
      # That fix is necessary but not sufficient, and 0.8.3 still cannot produce
      # a usable score here — a 2026-08-24 campaign was run on it and discarded.
      # Two upstream defects remain open. Oeditus/muex#23: sandboxes share the
      # project's real `_build` in any project with dependencies, so a mutant
      # can be compiled away by a sibling worker and graded on unmutated code —
      # verified here against a survivor that the suite in fact kills.
      # Oeditus/muex#24: mutations are keyed by their reported line, so
      # `StatementDeletion` never applies at all and bare-boolean flips mostly
      # do not, regardless of scheduling. ROADMAP task 119 is blocked on a
      # release carrying both; its first acceptance criterion is a per-defect
      # gate, not #20's reproduction alone.
      #
      # `no_coverage` is decided before any mutation is applied and its task 114
      # result stands. `equivalent` does NOT: Trivial Compiler Equivalence runs
      # after the line-keyed application #24 breaks, so a no-op mutation compiles
      # to identical bytecode and is classified `equivalent` without reaching a
      # sandbox. Those counts are an upper bound, not a measurement — see
      # docs/verification-ledger.md.
      {:muex, "~> 0.8.3", only: [:dev, :test], runtime: false},
      {:tidewave, "~> 0.6", only: :dev},
      {:bandit, "~> 1.12", only: :dev}
      # :boxart intentionally omitted — conflicts with upstream ex_doc 0.31.1
      # (needs makeup_elixir ~> 1.0, ex_doc pulls ~> 0.14). Terminal --graph
      # rendering is optional; text/json output still works for all reach.* tasks.
    ]
  end

  # ZenHive dev-branch only. Tidewave alias — port registered in
  # ~/.claude/tidewave-ports.md. Never merged back to main.
  defp aliases do
    [
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4013) end)'"
      ],
      integration: ["test.json --only integration"],
      manifest: ["descripex.manifest --pretty --output api_manifest.json --app cartouche"],
      # Fast local pre-commit loop — skips the cold-PLT dialyzer and full coverage
      # pass so it stays sub-minute on incremental edits.
      precommit: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME",
        "ex_dna --max-clones 0",
        "test.json --exclude integration --exclude dev_node"
      ],
      # Dispatch-scale gate — the harness reviewer's `check_command`. Deliberately
      # lighter than `precommit.full`: no dialyzer (cold PLT dominates a fresh run
      # worktree) and no coverage pass. It also omits `agents.check`, because
      # harness prepends an ephemeral "do not commit" preamble to AGENTS.md inside
      # the reviewer worktree, which that check correctly reports as drift — a red
      # the reviewer can neither fix nor ignore. Freshness stays enforced by
      # `precommit.full`, which runs on the landed base where no preamble exists.
      "check.dispatch": [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME",
        "doctor --raise",
        "ex_dna --max-clones 0",
        "reach.check --arch --smells",
        "sobelow --config",
        "test.json --exclude integration --exclude dev_node"
      ],
      # Comprehensive gate — the landed-base Architect/QA pass and the `mix ci`
      # target. The GitHub Actions workflows were removed family-wide on
      # 2026-08-22, so a local green here is the only green there is.
      "precommit.full": [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME",
        "doctor --raise",
        "ex_dna --max-clones 0",
        "reach.check --arch --smells",
        "sobelow --config",
        "deps.audit.gated",
        "test.json --cover --cover-threshold 85 --summary-only --exclude integration --exclude dev_node",
        "dialyzer",
        "agents.check"
      ],
      # Fails when AGENTS.md has drifted from CLAUDE.md. Compares rendered output,
      # not mtimes, so drift in a transitive @-import is caught too.
      "agents.check": [&agents_check/1],
      # mix_audit discards its own sync exit status (mirego/mix_audit#61), so a
      # frozen advisory DB still reports "No vulnerabilities found" and exits 0.
      # Prove freshness first, then audit. cartouche's dep tree carries no gun
      # (no `.mix_audit_ignore` needed — audits clean).
      "deps.audit.gated": [&advisory_freshness/1, "deps.audit"],
      ci: ["precommit.full"]
    ]
  end

  # Both gates below shell out to scripts that live OUTSIDE this repo, on the
  # developer host: the AGENTS.md renderer needs the claude-marketplace checkout
  # plus ~/.claude/includes, and the advisory-freshness prover needs the local
  # mix_audit mirror. Neither exists on a CI runner, and `mix cmd` with an
  # absent path dies with `:enoent` — which used to abort the whole `mix ci`
  # alias (and, since these steps precede `test.json`/`dialyzer`, took the test,
  # coverage, and test-env dialyzer signal down with it). Skip loudly when the
  # script is absent so CI keeps running the checks it CAN run; the developer
  # host and the harness reviewer still get the full gate.
  defp agents_check(_args) do
    host_script("~/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh", ["--check"], "AGENTS.md freshness check")
  end

  defp advisory_freshness(_args) do
    host_script("~/_DATA/code/onchain-stack/bin/advisory-freshness.sh", [], "advisory-mirror freshness check")
  end

  defp host_script(path, args, label) do
    expanded = Path.expand(path)

    if File.exists?(expanded) do
      {_out, status} = System.cmd(expanded, args, into: IO.stream(:stdio, :line), stderr_to_stdout: true)

      if status != 0 do
        Mix.raise("#{label} failed (#{expanded} exited #{status})")
      end
    else
      Mix.shell().info("[skip] #{label}: #{expanded} not found (developer-host script, absent in CI).")
    end
  end
end
