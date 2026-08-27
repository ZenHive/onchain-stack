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

  # The root project ships no runtime code, so this is analyzer-only. `.credo.exs`
  # here is cartouche's policy verbatim — Phase 2 promotes it to the family-wide
  # root policy; it already governs the root's own `lib/mix/tasks/`.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.15", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.12", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
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
