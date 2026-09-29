defmodule Onchain.CorePrecompiledTest do
  use ExUnit.Case, async: false

  alias Onchain.Precompiled

  setup do
    names = ~w(ONCHAIN_BUILD ONCHAIN_EVM_BUILD ONCHAIN_PUBLISH)
    previous = Map.new(names, &{&1, System.get_env(&1)})
    Enum.each(names, &System.delete_env/1)
    on_exit(fn -> Enum.each(previous, fn {name, value} -> restore_env(name, value) end) end)
    :ok
  end

  test "core source-builds with committed checksums in the monorepo" do
    assert File.exists?("checksum-Elixir.ABI.Native.exs")
    assert Precompiled.opts("onchain_abi")[:force_build]
    assert {:rustler, "~> 0.38", options} = List.keyfind(Onchain.MixProject.project()[:deps], :rustler, 0)
    refute options[:optional]
    refute options[:runtime]
  end

  test "publish mode keeps Rustler optional and downloads" do
    System.put_env("ONCHAIN_PUBLISH", "1")
    refute Keyword.has_key?(Precompiled.opts("onchain_abi"), :force_build)
    assert {:rustler, "~> 0.38", [optional: true, runtime: false]} in Onchain.MixProject.project()[:deps]
  end

  @tag :tmp_dir
  test "an unpacked package keeps Rustler optional without the monorepo marker", %{tmp_dir: dir} do
    File.cp!("mix.exs", Path.join(dir, "mix.exs"))

    code = """
    Mix.start()
    Code.compile_file("mix.exs")
    IO.inspect(List.keyfind(Mix.Project.config()[:deps], :rustler, 0))
    """

    assert {output, 0} = System.cmd("elixir", ["-e", code], cd: dir, stderr_to_stdout: true)
    assert output =~ "{:rustler, \"~> 0.38\", [optional: true, runtime: false]}"
  end

  test "build overrides are scoped to their crates" do
    System.put_env("ONCHAIN_PUBLISH", "1")
    System.put_env("ONCHAIN_EVM_BUILD", "1")
    refute Keyword.has_key?(Precompiled.opts("onchain_abi"), :force_build)

    assert Precompiled.opts("onchain_evm")[:force_build]
    assert Precompiled.opts("onchain_solidity")[:force_build]
    System.delete_env("ONCHAIN_EVM_BUILD")

    for value <- ["1", "true"] do
      System.put_env("ONCHAIN_BUILD", value)
      assert Precompiled.opts("onchain_abi")[:force_build]
      refute Keyword.has_key?(Precompiled.opts("onchain_evm"), :force_build)
      refute Keyword.has_key?(Precompiled.opts("onchain_solidity"), :force_build)
    end
  end

  test "mode table preserves core and EVM policies on every supported target" do
    for target <- Precompiled.targets(), checksum <- [:present, :missing] do
      assert Precompiled.force_build?(target, nil, checksum, :monorepo, "onchain_abi")
      refute Precompiled.force_build?(target, nil, checksum, :hex, "onchain_abi")

      assert Precompiled.force_build?(target, nil, checksum, :checkout, "onchain_abi") ==
               (checksum == :missing)

      for crate <- ["onchain_abi", "onchain_evm", "onchain_solidity"], env <- ["1", "true"] do
        assert Precompiled.force_build?(target, env, checksum, :hex, crate)
      end

      for crate <- ["onchain_evm", "onchain_solidity"], source <- [:checkout, :monorepo, :hex] do
        assert Precompiled.force_build?(target, nil, checksum, source, crate) ==
                 (checksum == :missing and source != :hex)
      end
    end

    for env <- [nil, "0", "false", ""] do
      refute Precompiled.force_build?("aarch64-apple-darwin", env, :present, :hex, "onchain_abi")
    end
  end

  test "unsupported hosts reject core even with an override and keep EVM source builds" do
    for target <- [nil, "x86_64-pc-windows-msvc", "aarch64-unknown-linux-musl"],
        source <- [:hex, :checkout, :monorepo],
        env <- [nil, "1"] do
      assert_raise RuntimeError, ~r/no precompiled artifact for this platform/, fn ->
        Precompiled.force_build?(target, env, :present, source, "onchain_abi")
      end

      assert Precompiled.force_build?(target, env, :present, source, "onchain_evm")
    end
  end

  @tag :tmp_dir
  test "missing and mismatched ABI checksums fail integrity checks", %{tmp_dir: dir} do
    path = Path.join(dir, Precompiled.artifact_filename("onchain_abi", "0.15.0", "aarch64-apple-darwin"))
    File.write!(path, "tampered")

    assert {:error, missing} = RustlerPrecompiled.check_integrity_from_map(%{}, path, ABI.Native)
    assert missing =~ "does not exist in the checksum file"

    checksums = %{Path.basename(path) => "sha256:#{String.duplicate("0", 64)}"}
    assert {:error, mismatch} = RustlerPrecompiled.check_integrity_from_map(checksums, path, ABI.Native)
    assert mismatch =~ "checksum of files does not match"
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
