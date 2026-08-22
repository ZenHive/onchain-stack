defmodule Onchain.PrecompiledTest do
  use ExUnit.Case, async: true

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

  describe "opts/2" do
    test "points both crates at the GitHub Release for this package version" do
      version = Mix.Project.config()[:version]
      evm = Precompiled.opts("onchain_evm", Onchain.EVM)
      sol = Precompiled.opts("onchain_solidity", Onchain.Solidity)

      assert evm[:otp_app] == :onchain_evm
      assert evm[:crate] == "onchain_evm"
      assert evm[:version] == version
      assert evm[:targets] == Precompiled.targets()
      assert evm[:nif_versions] == ["2.15"]

      assert evm[:base_url] ==
               "https://github.com/ZenHive/onchain_evm/releases/download/v#{version}"

      assert sol[:crate] == "onchain_solidity"
      assert sol[:base_url] == evm[:base_url]
    end

    test "force_build is set while checksum files are absent" do
      refute File.exists?(Precompiled.checksum_path(Onchain.EVM))
      refute File.exists?(Precompiled.checksum_path(Onchain.Solidity))
      assert Keyword.get(Precompiled.opts("onchain_evm", Onchain.EVM), :force_build) == true
    end
  end

  describe "force_build?/3" do
    test "is true when the checksum file is missing" do
      dummy = :onchain_precompiled_dummy_missing
      refute File.exists?(Precompiled.checksum_path(dummy))
      assert Precompiled.force_build?(dummy, {:unix, :darwin}, nil)
    end

    test "is true on Windows even with a checksum file present" do
      dummy = :onchain_precompiled_dummy_win
      path = Precompiled.checksum_path(dummy)
      File.write!(path, "%{}\n")

      try do
        assert Precompiled.force_build?(dummy, {:win32, :nt}, nil)
      after
        File.rm(path)
      end
    end

    test "is true when ONCHAIN_EVM_BUILD is 1 or true" do
      dummy = :onchain_precompiled_dummy_env
      path = Precompiled.checksum_path(dummy)
      File.write!(path, "%{}\n")

      try do
        assert Precompiled.force_build?(dummy, {:unix, :darwin}, "1")
        assert Precompiled.force_build?(dummy, {:unix, :darwin}, "true")
        refute Precompiled.force_build?(dummy, {:unix, :darwin}, nil)
      after
        File.rm(path)
      end
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

      case Onchain.EVM.nif_simulate_call(%{}) do
        {:error, _} ->
          :ok

        other ->
          flunk("expected a NIF error tuple, got: #{inspect(other)}")
      end
    end
  end
end
