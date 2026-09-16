defmodule OnchainStack.MixProject do
  use Mix.Project

  # The monorepo root is NOT a Hex package and ships no runtime code. It exists
  # for two things: to hold `mix onchain.bounds` (lib/mix/tasks/), and to own the
  # `ci` alias that drives the eight packages under `packages/`.
  def project do
    [
      app: :onchain_stack,
      version: "0.0.0",
      elixir: "~> 1.18",
      elixirc_paths: ["lib"],
      start_permanent: false,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application, do: [extra_applications: [:logger]]

  # The root project ships no runtime code, so the Hex entries here are
  # analyzer-only. The root `.credo.exs` is the family-wide policy: all eight
  # `packages/<name>/.credo.exs` are symlinks to it, and it governs the root's
  # own `lib/mix/tasks/` too.
  #
  # The eight packages are pulled in as path deps for exactly one reason: the
  # `tidewave` alias below. Tidewave serves whatever is loaded in the node it
  # runs in, and an empty root project has nothing to inspect — with the path
  # deps, one server sees all eight packages' modules at once and a single
  # `project_eval` can cross package boundaries (an aerodrome binding against
  # cartouche signing, say), which no per-package server can do.
  defp deps do
    aggregate_packages() ++
      [
        {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
        {:doctor, "~> 0.22", only: [:dev, :test], runtime: false},
        {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
        {:sobelow, "~> 0.15", only: [:dev, :test], runtime: false},
        {:styler, "~> 1.12", only: [:dev, :test], runtime: false},
        {:bandit, "~> 1.0", only: :dev},
        {:tidewave, "~> 0.9", only: :dev}
      ]
  end

  # Derived from the directory listing rather than written out, so a ninth
  # package is picked up by existing here, not by being remembered.
  #
  # `only: :dev` keeps this off `MIX_ENV=test`, which is what the root `ci`
  # alias runs under — the gate must not pay to compile eight packages it only
  # ever shells into. `override: true` makes the top-level declaration win over
  # every nested `sibling/3` path branch instead of diverging against it: each
  # package resolves its in-family deps to `../<name>` relative to its own
  # directory, which lands on the same files, but Mix still wants one authority
  # per app name and the root project is the only place that can be it.
  @spec aggregate_packages() :: [tuple()]
  defp aggregate_packages do
    __DIR__
    |> Path.join("packages")
    |> File.ls!()
    |> Enum.sort()
    |> Enum.filter(&File.regular?(Path.join([__DIR__, "packages", &1, "mix.exs"])))
    |> Enum.map(&{String.to_atom(&1), path: "packages/#{&1}", only: :dev, override: true})
  end

  defp aliases do
    [
      # ADDITIVE, and deliberately not 4013. The eight per-package `tidewave`
      # aliases keep their own distinct ports (hieroglyph 4006, onchain 4007,
      # onchain_evm 4009, onchain_tempo 4010, onchain_aave 4012, cartouche 4013,
      # onchain_js 4028, onchain_aerodrome 4035) precisely so several package dev
      # servers can run at the same time — that predates the monorepo and is a
      # feature, not drift. This root server is a ninth listener that happens to
      # see all eight packages at once; it gets its own registered port (4037 in
      # ~/.claude/tidewave-ports.md). Binding 4013 here would collide with
      # cartouche's own server the moment both run.
      #
      # The Agent wrapper is the same trick the packages use: `Bandit.start_link`
      # links to the calling process, which `mix run` lets die.
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4037) end)'"
      ],
      # Bounds first: it is seconds of AST parsing and it catches the one failure
      # class the monorepo introduces — a Hex requirement that has rotted because
      # locally the path dep always wins. No point spending eight package gates
      # to discover it afterwards.
      ci: ["onchain.bounds", &packages_ci/1],
      # Harness registers `check_command: "mix check.dispatch"` free-text, and a
      # reviewer that runs it at the ROOT must not get a silent "task not found"
      # or — worse — a cheap green. Fail loudly with the actual instruction:
      # the dispatch-scale gate lives in each package.
      "check.dispatch": [
        fn _ ->
          Mix.raise(
            "check.dispatch runs per package, not at the monorepo root — " <>
              "cd packages/<name> && mix check.dispatch for each package the task touches."
          )
        end
      ]
    ]
  end

  # SERIAL, and not negotiable: all eight packages run `deps.audit.gated` against
  # ONE shared mix_audit clone at ~/.local/share/elixir-security-advisories-mirego,
  # and `advisory-freshness.sh` does a `git pull --rebase` in it. Concurrent runs
  # interleave into one FETCH_HEAD and fail with `fatal: Cannot rebase onto
  # multiple branches` — a red on a repo whose code is fine.
  defp packages_ci(args) do
    packages =
      case args do
        [] -> Mix.Tasks.Onchain.Bounds.packages()
        names -> names
      end

    total = length(packages)

    packages
    |> Enum.with_index(1)
    |> Enum.each(fn {package, index} ->
      path = Path.expand("packages/#{package}", __DIR__)

      unless File.dir?(path) do
        Mix.raise("unknown package #{inspect(package)} (no such directory: #{path})")
      end

      Mix.shell().info("\n==> [#{index}/#{total}] mix ci in packages/#{package}\n")

      # MIX_ENV/MIX_TARGET are cleared on purpose: each package's own `cli/0`
      # declares `ci: :test`, and an inherited MIX_ENV would silently override it.
      {_out, status} =
        System.cmd("mix", ["ci"],
          cd: path,
          into: IO.stream(:stdio, :line),
          stderr_to_stdout: true,
          env: [{"MIX_ENV", nil}, {"MIX_TARGET", nil}]
        )

      if status != 0 do
        Mix.raise("mix ci failed in packages/#{package} (exited #{status})")
      end
    end)

    Mix.shell().info("\n==> all #{total} packages green\n")
  end
end
