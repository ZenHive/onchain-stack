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

  @doc "Shipped rustc triples. Must match `scripts/build-precompiled.sh`."
  @spec targets() :: [String.t()]
  def targets, do: @targets

  @doc "Shipped OTP NIF versions. Must match `RUSTLER_NIF_VERSION` in the build script."
  @spec nif_versions() :: [String.t()]
  def nif_versions, do: @nif_versions

  @doc """
  Keyword options for `use RustlerPrecompiled`.

  Omits `:force_build` when the host should download, so the library's
  application-env `put_new` still applies. Sets it `true` when a source
  build is required: `ONCHAIN_EVM_BUILD=1`, a missing checksum file (this
  repo before the first release upload), or a Windows host.
  """
  @spec opts(String.t(), module()) :: keyword()
  def opts(crate, module) when is_binary(crate) and is_atom(module) do
    version = Mix.Project.config()[:version]

    maybe_force_build(
      [
        otp_app: :onchain_evm,
        crate: crate,
        base_url: "https://github.com/ZenHive/onchain_evm/releases/download/v#{version}",
        version: version,
        targets: @targets,
        nif_versions: @nif_versions
      ],
      module
    )
  end

  @doc """
  Whether this host should compile the NIF from source.

  The 3-arity form is for tests. `RUSTLER_PRECOMPILED_FORCE_BUILD_ALL=1`
  is handled by rustler_precompiled itself and is not duplicated here.
  """
  @spec force_build?(module()) :: boolean()
  def force_build?(module) when is_atom(module) do
    force_build?(module, :os.type(), System.get_env("ONCHAIN_EVM_BUILD"))
  end

  @spec force_build?(module(), {:unix | :win32, atom()}, String.t() | nil) :: boolean()
  @doc false
  def force_build?(module, os_type, env) when is_atom(module) do
    env in ["1", "true"] or not File.exists?(checksum_path(module)) or
      match?({:win32, _}, os_type)
  end

  @doc "Path of the checksum file rustler_precompiled reads from the project root."
  @spec checksum_path(module()) :: String.t()
  def checksum_path(module) when is_atom(module) do
    Path.join(File.cwd!(), "checksum-#{module}.exs")
  end

  @doc "Artifact filename rustler_precompiled downloads for a crate/target."
  @spec artifact_filename(String.t(), String.t(), String.t()) :: String.t()
  def artifact_filename(crate, version, target) when is_binary(crate) and is_binary(version) and is_binary(target) do
    nif = hd(@nif_versions)
    "lib#{crate}-v#{version}-nif-#{nif}-#{target}.so.tar.gz"
  end

  @spec maybe_force_build(keyword(), module()) :: keyword()
  defp maybe_force_build(opts, module) do
    if force_build?(module), do: Keyword.put(opts, :force_build, true), else: opts
  end
end
