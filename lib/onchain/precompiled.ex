defmodule Onchain.Precompiled do
  @moduledoc """
  Shared `RustlerPrecompiled` options for both NIF crates.

  The `:targets` list is the set `scripts/build-precompiled.sh` actually
  produces. Windows is omitted on purpose — `cargo-zigbuild` cannot produce
  `x86_64-pc-windows-msvc`, so Windows consumers source-build.

  A missing `checksum-*.exs` source-builds in this repo's checkout so `mix ci`
  is green before the first GitHub Release. The same missing file fails the
  load for a Hex-installed package, where `files:` guarantees the checksum
  ships. A checksum mismatch always fails; it never falls back to source.
  """

  @targets ~w(
    aarch64-apple-darwin
    x86_64-apple-darwin
    x86_64-unknown-linux-gnu
    aarch64-unknown-linux-gnu
    x86_64-unknown-linux-musl
  )

  @nif_versions ~w(2.15)

  @typedoc "Whether `checksum-Elixir.<Module>.exs` exists on disk."
  @type checksum_presence :: :missing | :present

  @typedoc "Hex tarball vs this repo (or a git/path dep)."
  @type install_source :: :hex | :checkout

  @doc "Shipped Rust target triples. Must match `scripts/build-precompiled.sh`."
  @spec targets() :: [String.t()]
  def targets, do: @targets

  @doc "Shipped OTP NIF versions. Must match `RUSTLER_NIF_VERSION` in the build script."
  @spec nif_versions() :: [String.t()]
  def nif_versions, do: @nif_versions

  @doc """
  Keyword options for `use RustlerPrecompiled`.

  Omits `:force_build` when the host should download, so the library's
  application-env `put_new` still applies. Sets it to `true` for an
  unsupported host, `ONCHAIN_EVM_BUILD=1`, or a missing checksum in this
  checkout.
  """
  @spec opts(String.t()) :: keyword()
  def opts(crate) when is_binary(crate) do
    version = Mix.Project.config()[:version]

    maybe_force_build(
      otp_app: :onchain_evm,
      crate: crate,
      base_url: "https://github.com/ZenHive/onchain_evm/releases/download/v#{version}",
      version: version,
      targets: @targets,
      nif_versions: @nif_versions
    )
  end

  @doc """
  True when the NIF should compile from source instead of downloading.

  `checksum` `:missing` source-builds only for `:checkout`. A Hex install
  with a missing checksum must not source-build — rustler_precompiled then
  fails the load. A mismatch is never a reason to force-build.
  """
  @spec force_build?(String.t() | nil, String.t() | nil, checksum_presence(), install_source()) ::
          boolean()
  def force_build?(target, env, checksum, source) do
    env in ["1", "true"] or target not in @targets or
      (checksum == :missing and source != :hex)
  end

  @doc "Artifact filename rustler_precompiled downloads for a crate/target."
  @spec artifact_filename(String.t(), String.t(), String.t()) :: String.t()
  def artifact_filename(crate, version, target) when is_binary(crate) and is_binary(version) and is_binary(target) do
    nif = hd(@nif_versions)
    "lib#{crate}-v#{version}-nif-#{nif}-#{target}.so.tar.gz"
  end

  @spec current_target() :: String.t() | nil
  defp current_target do
    nif_version = :nif_version |> :erlang.system_info() |> List.to_string()

    with {:ok, _compatible} <-
           RustlerPrecompiled.find_compatible_nif_version(nif_version, @nif_versions),
         {:ok, nif_target} <- RustlerPrecompiled.target(),
         ["nif", _nif_version, target] <- String.split(nif_target, "-", parts: 3) do
      target
    else
      _error -> nil
    end
  end

  @spec maybe_force_build(keyword()) :: keyword()
  defp maybe_force_build(opts) do
    crate = Keyword.fetch!(opts, :crate)

    if force_build?(
         current_target(),
         System.get_env("ONCHAIN_EVM_BUILD"),
         checksum_presence(crate),
         install_source()
       ) do
      Keyword.put(opts, :force_build, true)
    else
      opts
    end
  end

  @spec checksum_presence(String.t()) :: checksum_presence()
  defp checksum_presence(crate) do
    path = Path.join(File.cwd!(), "checksum-#{crate_module(crate)}.exs")
    if File.exists?(path), do: :present, else: :missing
  end

  @spec crate_module(String.t()) :: module()
  defp crate_module("onchain_evm"), do: Onchain.EVM
  defp crate_module("onchain_solidity"), do: Onchain.Solidity

  # Mix sets `:build_scm` to `Hex.SCM` when compiling a Hex dep via
  # `Mix.Project.in_project/4`. This checkout (and git/path deps) is
  # `Mix.SCM.Path` / `Mix.SCM.Git`.
  @spec install_source() :: install_source()
  defp install_source do
    if inspect(Mix.Project.config()[:build_scm]) == "Hex.SCM", do: :hex, else: :checkout
  end
end
