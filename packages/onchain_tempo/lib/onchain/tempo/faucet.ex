defmodule Onchain.Tempo.Faucet do
  @moduledoc """
  Moderato testnet faucet — wraps the non-standard `tempo_fundAddress` JSON-RPC.

  Moderato exposes a custom JSON-RPC method, `tempo_fundAddress`, that funds an
  address with native gas + pathUSD in a single call. This module provides a
  thin wrapper plus a convenience helper for spinning up a fresh, funded
  keypair — useful for writing integration tests against Moderato without
  re-deriving the recipe.

  Only Moderato (chain `42_431`) supports this RPC. Mainnet (`4_217`) does not.

  ## Usage

      # Fund an existing address.
      {:ok, [tx_hash | _]} = Onchain.Tempo.Faucet.fund_address("0xabc...")

      # Generate + fund a fresh keypair (polls for confirmation before returning).
      {:ok, %{private_key: priv, address_hex: hex, address_bin: bin}} =
        Onchain.Tempo.Faucet.fresh_funded_wallet()

      # Override the endpoint (defaults to https://rpc.moderato.tempo.xyz, or
      # the TEMPO_RPC_URL env var if set).
      Onchain.Tempo.Faucet.fund_address("0xabc...", rpc_url: "https://my-mirror")

  ## Options

  Both `fund_address/2` and `fresh_funded_wallet/1` accept:

    * `:rpc_url` — RPC endpoint URL. Defaults to `rpc_url/0`.
    * `:req_options` — keyword list passed to `Req.request/2` (timeouts,
      adapters, `Req.Test` plug, etc.)

  `fresh_funded_wallet/1` additionally accepts:

    * `:settle_ms` — maximum milliseconds to wait for the funding transaction
      to confirm. Defaults to `10_000`. Set to `0` to skip the wait entirely
      (used by unit tests that mock the RPC layer).
    * `:poll_interval_ms` — interval between balance polls. Defaults to `200`.
    * `:fee_token` — hex address of the fee token to poll for funding (via an
      `eth_call` of `balanceOf`). Defaults to Moderato's pathUSD. The faucet
      funds native gas *and* the fee token, but gas can land first; polling the
      fee token confirms the balance the caller actually needs has arrived.
  """
  alias Onchain.Tempo.TIP20

  # Jason, Req are transitive deps via onchain — not resolved in PLT with path deps
  @dialyzer [:no_unknown]

  @default_rpc_url "https://rpc.moderato.tempo.xyz"
  @default_wait_timeout_ms 10_000
  @default_poll_interval_ms 200

  # Canonical pathUSD TIP-20 stablecoin on Moderato — the fee token the faucet
  # funds alongside native gas. Override with the `:fee_token` option.
  @default_fee_token "0x20c0000000000000000000000000000000000000"

  @doc """
  RPC URL used by the faucet by default — `TEMPO_RPC_URL` env var if set,
  otherwise `https://rpc.moderato.tempo.xyz`.
  """
  @spec rpc_url() :: String.t()
  def rpc_url, do: System.get_env("TEMPO_RPC_URL") || @default_rpc_url

  @doc """
  Fund an existing address via Moderato's `tempo_fundAddress` RPC.

  Returns `{:ok, hashes}` where `hashes` is the list of funding transaction
  hashes returned by the node.
  """
  @spec fund_address(String.t(), keyword()) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def fund_address(address_hex, opts \\ []) do
    {url, opts} = Keyword.pop(opts, :rpc_url, rpc_url())

    case rpc_request("tempo_fundAddress", [address_hex], url, opts) do
      {:ok, hashes} when is_list(hashes) -> {:ok, hashes}
      {:ok, other} -> {:error, "unexpected faucet result: #{inspect(other)}"}
      {:error, _} = err -> err
    end
  end

  @doc """
  Generate a fresh 32-byte keypair, fund it via `tempo_fundAddress`, and poll
  the fee token's `balanceOf` (via `eth_call`) until the funding lands on-chain.
  The faucet credits native gas *and* the fee token, but gas can confirm first;
  polling the fee token (pathUSD by default) confirms the balance callers
  actually need has arrived. Override the token with `:fee_token`.

  Returns the wallet as a map with `:private_key` (32 bytes), `:address_hex`
  (`"0x"` + 40 hex), and `:address_bin` (20 bytes).

  Polling is bounded by `:settle_ms` (default `10_000` ms); pass `0` to skip
  the wait entirely. The interval between polls is controlled by
  `:poll_interval_ms` (default `200` ms).
  """
  @spec fresh_funded_wallet(keyword()) ::
          {:ok, %{private_key: binary(), address_hex: String.t(), address_bin: binary()}}
          | {:error, String.t()}
  def fresh_funded_wallet(opts \\ []) do
    with :ok <- validate_wait_opts(opts) do
      priv = :crypto.strong_rand_bytes(32)
      {:ok, addr_hex} = Onchain.Signer.address_from_key(priv)
      addr_bin = addr_hex |> String.trim_leading("0x") |> Base.decode16!(case: :mixed)

      with {:ok, _hashes} <- fund_address(addr_hex, opts),
           :ok <- wait_for_funding(addr_hex, opts) do
        {:ok, %{private_key: priv, address_hex: addr_hex, address_bin: addr_bin}}
      end
    end
  end

  # --- Private ---

  @spec validate_wait_opts(keyword()) :: :ok | {:error, String.t()}
  defp validate_wait_opts(opts) do
    timeout_ms = Keyword.get(opts, :settle_ms, @default_wait_timeout_ms)
    interval_ms = Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms)

    cond do
      not (is_integer(timeout_ms) and timeout_ms >= 0) ->
        {:error, ":settle_ms must be a non-negative integer, got: #{inspect(timeout_ms)}"}

      timeout_ms > 0 and not (is_integer(interval_ms) and interval_ms > 0) ->
        {:error, ":poll_interval_ms must be a positive integer, got: #{inspect(interval_ms)}"}

      true ->
        :ok
    end
  end

  @spec wait_for_funding(String.t(), keyword()) :: :ok | {:error, String.t()}
  defp wait_for_funding(addr_hex, opts) do
    timeout_ms = Keyword.get(opts, :settle_ms, @default_wait_timeout_ms)

    if timeout_ms == 0 do
      :ok
    else
      interval_ms = Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms)
      {url, opts} = Keyword.pop(opts, :rpc_url, rpc_url())
      {fee_token, rpc_opts} = Keyword.pop(opts, :fee_token, @default_fee_token)
      data_hex = balance_of_data(addr_hex)
      deadline = System.monotonic_time(:millisecond) + timeout_ms
      poll_balance(fee_token, data_hex, url, rpc_opts, deadline, interval_ms, timeout_ms)
    end
  end

  # Build the `balanceOf(owner)` calldata (hex) for the address being funded.
  @spec balance_of_data(String.t()) :: String.t()
  defp balance_of_data(addr_hex) do
    addr_bin = addr_hex |> String.trim_leading("0x") |> Base.decode16!(case: :mixed)
    "0x" <> Base.encode16(TIP20.balance_of_calldata(addr_bin), case: :lower)
  end

  @spec poll_balance(String.t(), String.t(), String.t(), keyword(), integer(), pos_integer(), pos_integer()) ::
          :ok | {:error, String.t()}
  defp poll_balance(fee_token, data_hex, url, opts, deadline, interval_ms, timeout_ms) do
    params = [%{to: fee_token, data: data_hex}, "latest"]

    with {:ok, balance_hex} <- rpc_request("eth_call", params, url, opts),
         {:ok, balance} <- parse_balance_hex(balance_hex) do
      now = System.monotonic_time(:millisecond)

      cond do
        balance > 0 ->
          :ok

        now >= deadline ->
          {:error, "timeout waiting for funding to confirm after #{timeout_ms}ms"}

        true ->
          # Cap the inter-poll sleep so a large :poll_interval_ms can't overshoot
          # the deadline by almost a full interval. Floor at 1 ms so we still
          # yield to the scheduler when budget is nearly exhausted.
          remaining = deadline - now
          Process.sleep(max(min(interval_ms, remaining), 1))
          poll_balance(fee_token, data_hex, url, opts, deadline, interval_ms, timeout_ms)
      end
    end
  end

  @spec parse_balance_hex(term()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  defp parse_balance_hex("0x" <> hex) do
    case Integer.parse(hex, 16) do
      {n, ""} when n >= 0 -> {:ok, n}
      _ -> {:error, "unexpected eth_call result: #{inspect("0x" <> hex)}"}
    end
  end

  defp parse_balance_hex(other), do: {:error, "unexpected eth_call result: #{inspect(other)}"}

  @spec rpc_request(String.t(), list(), String.t(), keyword()) ::
          {:ok, term()} | {:error, String.t()}
  defp rpc_request(method, params, rpc_url, opts) do
    req_options = Keyword.get(opts, :req_options, [])

    body =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => method,
        "params" => params,
        "id" => 1
      })

    result =
      Req.request(
        [
          url: rpc_url,
          method: :post,
          headers: [{"content-type", "application/json"}],
          body: body,
          receive_timeout: 15_000
        ],
        req_options
      )

    case result do
      {:ok, %Req.Response{status: status, body: %{"result" => value}}} when status in 200..299 ->
        {:ok, value}

      {:ok, %Req.Response{body: %{"error" => error}}} ->
        {:error, "faucet error: #{inspect(error)}"}

      {:error, exception} ->
        {:error, "faucet HTTP error: #{Exception.message(exception)}"}

      {:ok, %Req.Response{} = response} ->
        {:error, "unexpected faucet response: status #{response.status}, body #{inspect(response.body)}"}
    end
  end
end
