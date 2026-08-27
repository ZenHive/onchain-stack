# Gate helpers shared by every package `mix.exs` in this monorepo.
#
# Until 2026-08-27 `agents_check/1`, `advisory_freshness/1` and `host_script/3`
# were copy-pasted into all eight `packages/*/mix.exs` — near-identical, but
# already drifting (only hieroglyph's copy carried the executable? guard). They
# live here now; each package loads this file behind a `File.exists?` guard.
#
# The guard is load-bearing, not defensive style: `mix hex.publish` packages a
# package's `mix.exs`, never this file, so a consumer evaluates a `mix.exs`
# whose sibling root marker AND this file are both absent. Anything unguarded
# here breaks every downstream build. See `sibling/3` in any package `mix.exs`
# for the other half of the same rule.
#
# Deliberately an `.exs` loaded with `Code.require_file/1` rather than a module
# under `<root>/lib/`: a package's Mix project does not see the root project's
# code paths, and a tarball sees neither.
defmodule OnchainMonorepo.MixHelpers do
  @moduledoc false

  # Both gates shell out to scripts that live OUTSIDE this repo, on the
  # developer host: the AGENTS.md renderer needs the claude-marketplace checkout
  # plus ~/.claude/includes, and the advisory-freshness prover needs the local
  # mix_audit mirror. Neither exists on a CI runner or in a harness worktree, and
  # `mix cmd` with an absent path exits non-zero — which aborted the whole
  # `mix ci` alias, and since these steps precede test.json/dialyzer it took the
  # test, coverage and dialyzer signal down with it. Skip loudly when the script
  # is absent so the run keeps making the checks it CAN make; the developer host
  # and the harness reviewer still get the full gate.
  @spec agents_check([String.t()]) :: :ok
  def agents_check(_args) do
    host_script(
      "~/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh",
      ["--check"],
      "AGENTS.md freshness check"
    )
  end

  @spec advisory_freshness([String.t()]) :: :ok
  def advisory_freshness(_args) do
    host_script(
      "~/_DATA/code/onchain-stack/bin/advisory-freshness.sh",
      [],
      "advisory-mirror freshness check"
    )
  end

  @spec host_script(String.t(), [String.t()], String.t()) :: :ok
  def host_script(path, args, label) do
    expanded = Path.expand(path)

    cond do
      not File.regular?(expanded) ->
        Mix.shell().info("[skip] #{label}: #{expanded} not found (developer-host script, absent in CI).")

      # Present but not runnable is a broken host setup, not a CI runner — say
      # so instead of letting System.cmd/3 blow up with a raw :eacces.
      not executable?(expanded) ->
        Mix.raise("#{label}: #{expanded} exists but is not executable (chmod +x it).")

      true ->
        {_out, status} =
          System.cmd(expanded, args, into: IO.stream(:stdio, :line), stderr_to_stdout: true)

        if status != 0 do
          Mix.raise("#{label} failed (#{expanded} exited #{status})")
        end
    end

    :ok
  end

  @spec executable?(String.t()) :: boolean()
  defp executable?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{mode: mode}} -> Bitwise.band(mode, 0o111) != 0
      _error -> false
    end
  end
end
