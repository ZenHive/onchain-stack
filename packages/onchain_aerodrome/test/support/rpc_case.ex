defmodule Onchain.Aerodrome.RPCCase do
  @moduledoc """
  Two-endpoint RPC test seam for Base portability claims.

  `Onchain.RPCCase` in onchain core exposes a single URL. This module does
  not exist upstream, and upstreaming it is a deliberate non-goal here: the
  family-wide gap named in `node-portability.md` is closed locally so every
  Aerodrome read/write integration test can assert portability instead of
  re-running the suite by hand.

  Authorities are the public `https://mainnet.base.org` endpoint (primary,
  `BASE_RPC_URL` with that fallback) and a genuinely separate hosted
  provider of Alchemy or Infura class (secondary, `BASE_SECONDARY_RPC_URL`,
  no fallback). Agreement between those two — not agreement with our own
  archive node — is what portable means. Our node's ok result is not
  evidence; a hosted endpoint's real refusal is.

  A missing endpoint flunks with the exact env var and an export command.
  Never skip: a suite that reports zero failures from zero tests is a lie.
  The identical green run on both endpoints is what the portability claim
  rests on.
  """

  @primary_env "BASE_RPC_URL"
  @secondary_env "BASE_SECONDARY_RPC_URL"
  @primary_fallback "https://mainnet.base.org"
  @secondary_example "https://base-mainnet.g.alchemy.com/v2/YOUR_KEY"
  @rpc_url_key {__MODULE__, :rpc_url}

  @doc """
  Primary Base RPC URL.

  Reads `BASE_RPC_URL`. When unset or empty, falls back to
  `https://mainnet.base.org`. Empty is treated as unset so a blank export
  cannot silently disable the public endpoint.
  """
  @spec primary_rpc_url!() :: String.t()
  def primary_rpc_url! do
    case env_url(@primary_env) do
      url when is_binary(url) -> url
      nil -> @primary_fallback
    end
  end

  @doc """
  Secondary unprivileged Base RPC URL.

  Reads `BASE_SECONDARY_RPC_URL`. There is no fallback: the second
  authority must be a genuinely different hosted provider. Flunks with the
  exact env var and an export command when unset or empty — never skips.
  """
  @spec secondary_rpc_url!() :: String.t()
  def secondary_rpc_url! do
    case env_url(@secondary_env) do
      url when is_binary(url) -> url
      nil -> flunk_missing(@secondary_env, @secondary_example)
    end
  end

  @doc """
  RPC URL for the closure currently running under `run_on_both_endpoints/1`.

  Outside that helper this is the primary URL, matching how later single-endpoint
  integration tests will resolve a Base node.
  """
  @spec rpc_url!() :: String.t()
  def rpc_url! do
    Process.get(@rpc_url_key) || primary_rpc_url!()
  end

  @doc "Keyword options for `Onchain.RPC` against the current endpoint."
  @spec rpc_opts!() :: keyword()
  def rpc_opts!, do: [rpc_url: rpc_url!()]

  @doc """
  Runs a zero-arity eth_call-shaped action against both endpoints.

  The closure should read `rpc_url!/0` or `rpc_opts!/0` so each invocation
  hits a different node. Returns `{primary_result, secondary_result}`.
  Flunks — never skips — when the secondary URL is missing or when both
  accessors resolve to the same URL.
  """
  @spec run_on_both_endpoints((-> result)) :: {result, result} when result: term()
  def run_on_both_endpoints(fun) when is_function(fun, 0) do
    primary = primary_rpc_url!()
    secondary = secondary_rpc_url!()
    assert_distinct!(primary, secondary)

    {with_rpc_url(primary, fun), with_rpc_url(secondary, fun)}
  end

  @spec env_url(String.t()) :: String.t() | nil
  defp env_url(var) do
    case System.get_env(var) do
      url when is_binary(url) and url != "" -> url
      _unset -> nil
    end
  end

  @spec with_rpc_url(String.t(), (-> result)) :: result when result: term()
  defp with_rpc_url(url, fun) do
    previous = Process.put(@rpc_url_key, url)

    try do
      fun.()
    after
      restore_rpc_url(previous)
    end
  end

  @spec restore_rpc_url(String.t() | nil) :: term()
  defp restore_rpc_url(previous) when is_binary(previous), do: Process.put(@rpc_url_key, previous)
  defp restore_rpc_url(nil), do: Process.delete(@rpc_url_key)

  @spec assert_distinct!(String.t(), String.t()) :: :ok | no_return()
  defp assert_distinct!(primary, secondary) when primary != secondary, do: :ok

  defp assert_distinct!(_primary, _secondary) do
    ExUnit.Assertions.flunk("""
    BASE_RPC_URL and BASE_SECONDARY_RPC_URL resolve to the same URL.

    The consumer's node — not ours — as the case that matters.
    Secondary must be a genuinely different unprivileged provider
    (Alchemy, Infura, or similar), not the public Base endpoint again.

    A real result or its real refusal, never a skip.

      export #{@secondary_env}="#{@secondary_example}"
    """)
  end

  @spec flunk_missing(String.t(), String.t()) :: no_return()
  defp flunk_missing(var, example) do
    ExUnit.Assertions.flunk("""
    Missing #{var}!

    A real result or its real refusal, never a skip.
    The consumer's node — not ours — as the case that matters;
    the identical green run on both endpoints is what the portability claim rests on.

      export #{var}="#{example}"
    """)
  end
end
