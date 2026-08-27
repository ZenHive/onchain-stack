defmodule Onchain.PrecompiledTest do
  use ExUnit.Case, async: false

  alias Onchain.Precompiled

  @script "scripts/build-precompiled.sh"

  describe "shipped targets" do
    test "match the build script TARGETS array exactly" do
      script = File.read!(@script)
      assert [_, block] = Regex.run(~r/TARGETS=\((.*?)\)/s, script)

      script_targets =
        block
        |> String.split()
        |> Enum.reject(&(&1 == ""))

      assert script_targets == Precompiled.targets()
    end

    test "does not declare a Windows target" do
      refute Enum.any?(Precompiled.targets(), &String.contains?(&1, "windows"))
      refute File.read!(@script) =~ "windows"
    end

    test "build script covers both crates and pins glibc 2.28 plus NIF 2.15" do
      script = File.read!(@script)
      assert script =~ "onchain_evm"
      assert script =~ "onchain_solidity"
      assert script =~ ~r/GLIBC_VERSION="\$\{GLIBC_VERSION:-2\.28\}"/
      assert script =~ ~r/NIF_VERSION="\$\{NIF_VERSION:-2\.15\}"/
      assert Precompiled.nif_versions() == ["2.15"]
    end

    test "artifact filenames match rustler_precompiled's lib*.so.tar.gz convention" do
      version = Mix.Project.config()[:version]

      for crate <- ["onchain_evm", "onchain_solidity"],
          target <- Precompiled.targets() do
        name = Precompiled.artifact_filename(crate, version, target)
        assert name == "lib#{crate}-v#{version}-nif-2.15-#{target}.so.tar.gz"
        refute String.contains?(name, "windows")
      end
    end
  end

  describe "opts/1" do
    test "points both crates at the GitHub Release for this package version" do
      version = Mix.Project.config()[:version]
      evm = Precompiled.opts("onchain_evm")
      sol = Precompiled.opts("onchain_solidity")

      assert evm[:otp_app] == :onchain_evm
      assert evm[:crate] == "onchain_evm"
      assert evm[:version] == version
      assert evm[:targets] == Precompiled.targets()
      assert evm[:nif_versions] == ["2.15"]

      assert evm[:base_url] ==
               "https://github.com/ZenHive/onchain-stack/releases/download/onchain_evm-v#{version}"

      assert sol[:crate] == "onchain_solidity"
      assert sol[:base_url] == evm[:base_url]
    end

    # Both checksum files are committed as of v0.6.0. `package.files` ships
    # them, and a Hex install that lacks them fails the load rather than
    # silently source-building — so their presence is the invariant, not the
    # pre-release absence the earlier tests asserted. The force-build decision
    # itself is covered exhaustively by the `force_build?/4` table below; it
    # must not be re-derived here through real files in the repository root.
    test "both crates ship a committed checksum file" do
      for crate <- ["Onchain.EVM", "Onchain.Solidity"] do
        assert File.exists?(Path.join(File.cwd!(), "checksum-Elixir.#{crate}.exs"))
      end

      assert "checksum-*.exs" in Mix.Project.config()[:package][:files]
    end

    test "ONCHAIN_EVM_BUILD sets the package force-build option" do
      previous = System.get_env("ONCHAIN_EVM_BUILD")
      System.put_env("ONCHAIN_EVM_BUILD", "1")

      try do
        assert Precompiled.opts("onchain_evm")[:force_build]
      after
        if previous,
          do: System.put_env("ONCHAIN_EVM_BUILD", previous),
          else: System.delete_env("ONCHAIN_EVM_BUILD")
      end
    end
  end

  describe "force_build?/4" do
    test "falls back to source for every unsupported target" do
      assert Precompiled.force_build?("x86_64-pc-windows-msvc", nil, :present, :hex)
      assert Precompiled.force_build?("aarch64-unknown-linux-musl", nil, :present, :hex)
      assert Precompiled.force_build?(nil, nil, :present, :hex)
    end

    test "a supported host with a present checksum downloads" do
      refute Precompiled.force_build?("aarch64-apple-darwin", nil, :present, :checkout)
      refute Precompiled.force_build?("x86_64-unknown-linux-gnu", nil, :present, :hex)
    end

    test "a missing checksum source-builds in this checkout and fails closed on Hex" do
      assert Precompiled.force_build?("aarch64-apple-darwin", nil, :missing, :checkout)
      refute Precompiled.force_build?("aarch64-apple-darwin", nil, :missing, :hex)
    end

    test "ONCHAIN_EVM_BUILD forces supported targets to build" do
      assert Precompiled.force_build?("aarch64-apple-darwin", "1", :present, :hex)
      assert Precompiled.force_build?("aarch64-apple-darwin", "true", :present, :hex)
    end
  end

  describe "checksum integrity" do
    test "a missing checksum entry fails rather than building" do
      assert {:error, msg} =
               RustlerPrecompiled.check_integrity_from_map(
                 %{},
                 "libonchain_evm-v0.0.0-nif-2.15-aarch64-apple-darwin.so.tar.gz",
                 Onchain.EVM
               )

      assert msg =~ "does not exist in the checksum file"
    end

    test "a tampered checksum fails rather than building" do
      path = Path.join(System.tmp_dir!(), "onchain-evm-tampered-nif.so.tar.gz")
      File.write!(path, "not-the-nif")

      try do
        checksum_map = %{
          Path.basename(path) => "sha256:#{String.duplicate("0", 64)}"
        }

        assert {:error, msg} =
                 RustlerPrecompiled.check_integrity_from_map(checksum_map, path, Onchain.EVM)

        assert msg =~ "checksum of files does not match"
      after
        File.rm(path)
      end
    end
  end

  describe "RUSTLER_PRECOMPILED_FORCE_BUILD_ALL" do
    test "installed rustler_precompiled treats 1 and true as force-build" do
      source =
        Mix.Project.deps_path()
        |> Path.join("rustler_precompiled/lib/rustler_precompiled.ex")
        |> File.read!()

      assert source =~ ~r/get_env\("RUSTLER_PRECOMPILED_FORCE_BUILD_ALL"\) in \["1", "true"\]/
      assert File.read!("README.md") =~ "RUSTLER_PRECOMPILED_FORCE_BUILD_ALL=1"
    end
  end

  describe "build script" do
    test "--dry-run prints every crate/target artifact name" do
      {output, 0} = System.cmd("bash", [@script, "--dry-run"], cd: File.cwd!())
      version = Mix.Project.config()[:version]

      for crate <- ["onchain_evm", "onchain_solidity"],
          target <- Precompiled.targets() do
        assert output =~ Precompiled.artifact_filename(crate, version, target)
      end

      assert output =~ "glibc=2.28"
      assert output =~ "nif=2.15"
      refute output =~ "windows"
    end
  end

  describe "NIF load via force_build" do
    test "both modules loaded from a source build on this host" do
      assert {:ok, parsed} =
               Onchain.Solidity.parse_sol("contract C { function f() external {} }")

      assert parsed.functions != []

      assert {:error, {:evm_error, "missing param: rpc_url"}} =
               Onchain.EVM.nif_simulate_call(%{})
    end
  end
end
