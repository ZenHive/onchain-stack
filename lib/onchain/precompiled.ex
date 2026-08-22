defmodule Onchain.Precompiled do
  @moduledoc """
  Shared `RustlerPrecompiled` options for both NIF crates.

  The `:targets` list is the set `scripts/build-precompiled.sh` actually
  produces. Windows is omitted on purpose — `cargo-zigbuild` cannot produce
  `x86_64-pc-windows-msvc`, so Windows consumers source-build.
  """

  @targets ~w(
    aarch64-apple-darwin
    x86_64-apple-darwin
    x86_64-unknown-linux-gnu
    aarch64-unknown-linux-gnu
    x86_64-unknown-linux-musl
  )

  @nif_versions ~w(2.15)

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
  unsupported host or when `ONCHAIN_EVM_BUILD=1` requests a source build.
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

  @doc false
  @spec force_build?(String.t() | nil, String.t() | nil) :: boolean()
  def force_build?(target, env) do
    env in ["1", "true"] or target not in @targets
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
    if force_build?(current_target(), System.get_env("ONCHAIN_EVM_BUILD")) do
      Keyword.put(opts, :force_build, true)
    else
      opts
    end
  end
end
