defmodule Onchain.Tempo.Verification.MutationScratchTest do
  use ExUnit.Case, async: true

  alias Onchain.Tempo.Verification.Campaign

  @moduletag :verification
  @moduletag :tmp_dir

  # Exercised against a throwaway repo: dirtying the real tracked sources to
  # test the guard would itself be the hazard the guard exists to prevent.
  setup %{tmp_dir: root} do
    git!(root, ["init", "--quiet"])

    for rel <- Campaign.tracked_patch_files() do
      path = Path.join([root, "packages/onchain_tempo", rel])
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "original\n")
    end

    git!(root, ["add", "."])
    git!(root, ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "--quiet", "-m", "init"])
    :ok
  end

  test "a clean tree passes", %{tmp_dir: root} do
    assert Campaign.assert_tracked_patch_targets_clean!(root) == :ok
  end

  test "an unstaged mutation in a patch target refuses to run", %{tmp_dir: root} do
    File.write!(Path.join(root, "packages/onchain_tempo/native/onchain_tempo/src/lib.rs"), "mutant\n")

    assert_raise RuntimeError, ~r/refuses to run: .* unstaged/, fn ->
      Campaign.assert_tracked_patch_targets_clean!(root)
    end
  end

  test "a staged mutation in a patch target refuses to run", %{tmp_dir: root} do
    File.write!(Path.join(root, "packages/onchain_tempo/lib/onchain/tempo/codec.ex"), "mutant\n")
    git!(root, ["add", "."])

    assert_raise RuntimeError, ~r/refuses to run: .* staged/, fn ->
      Campaign.assert_tracked_patch_targets_clean!(root)
    end
  end

  defp git!(root, args) do
    {_, 0} = System.cmd("git", args, cd: root, stderr_to_stdout: true)
  end
end
