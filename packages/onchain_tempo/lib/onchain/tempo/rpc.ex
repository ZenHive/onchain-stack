defmodule Onchain.Tempo.RPC do
  @moduledoc """
  Tempo-specific JSON-RPC operations — transaction broadcast and receipt fetching.

  Provides both async (`eth_sendRawTransaction`) and sync
  (`eth_sendRawTransactionSync`) broadcast methods. The sync variant is
  Tempo-specific — it waits for block inclusion (~500ms on Tempo) and returns
  the receipt inline, eliminating the race condition of separate receipt polling.

  ## Usage

      {:ok, tx_hash} = Onchain.Tempo.RPC.broadcast_async(signed_hex, rpc_url)

      {:ok, tx_hash, receipt} = Onchain.Tempo.RPC.broadcast_sync(signed_hex, rpc_url)

      {:ok, receipt} = Onchain.Tempo.RPC.fetch_receipt(tx_hash, rpc_url)

  ## Options

  All functions accept an `opts` keyword list with:

    * `:req_options` — keyword list passed to `Req.request/2` (timeouts, adapters, etc.)
  """
  alias Onchain.Tempo.Transaction
  # Jason, Req are transitive deps via onchain — not resolved in PLT with path deps
  @dialyzer [:no_unknown]

  @doc """
  Broadcast a signed transaction via async `eth_sendRawTransaction`.

  Returns the transaction hash immediately without waiting for block inclusion.
  """
  @spec broadcast_async(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def broadcast_async(raw_hex, rpc_url, opts \\ []) do
    case rpc_request("eth_sendRawTransaction", [raw_hex], rpc_url, opts) do
      {:ok, tx_hash} when is_binary(tx_hash) ->
        {:ok, tx_hash}

      {:ok, other} ->
        {:error, "Unexpected broadcast response: #{inspect(other)}"}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Broadcast a signed transaction via Tempo's synchronous `eth_sendRawTransactionSync`.

  Waits for block inclusion and returns the full receipt inline. Returns
  `{:ok, tx_hash, receipt}` on success.
  """
  @spec broadcast_sync(String.t(), String.t(), keyword()) :: {:ok, String.t(), map()} | {:error, String.t()}
  def broadcast_sync(raw_hex, rpc_url, opts \\ []) do
    case rpc_request("eth_sendRawTransactionSync", [raw_hex], rpc_url, opts) do
      {:ok, receipt} when is_map(receipt) ->
        tx_hash = receipt["transactionHash"]
        {:ok, tx_hash, parse_receipt(receipt)}

      {:ok, other} ->
        {:error, "Unexpected sync broadcast response: #{inspect(other)}"}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Fetch a transaction receipt via `eth_getTransactionReceipt`.
  """
  @spec fetch_receipt(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def fetch_receipt(tx_hash, rpc_url, opts \\ []) do
    case rpc_request("eth_getTransactionReceipt", [tx_hash], rpc_url, opts) do
      {:ok, nil} ->
        {:error, "Transaction not found on-chain"}

      {:ok, receipt} when is_map(receipt) ->
        {:ok, parse_receipt(receipt)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Simulate a co-signed Tempo 0x76 transaction via `eth_simulateV1` before
  broadcasting, so a fee payer can confirm the transaction would SUCCEED before
  paying its gas.

  Reconstructs a `TempoTransactionRequest` from the decoded envelope (recovering
  the sender for `from` and folding the tail call into `to`/`input`), runs the
  simulation against latest state with `validation: false` (no signature checks),
  and reports the execution outcome:

    * `{:ok, :success}` — the transaction would succeed (call status `0x1`)
    * `{:ok, {:revert, detail}}` — the transaction would fail on-chain: either the
      call status is `0x0` (revert / out-of-gas, the gas-draining DoS this guards
      against) or the node rejected the transaction as invalid (an `eth_simulateV1`
      execution error such as `-38013` "intrinsic gas too low"). `detail` carries
      the node's error message / revert data. A fail-open caller MUST still reject
      on this result — it means the transaction is bad, not the node.
    * `{:ok, :unsupported}` — the node does not implement `eth_simulateV1`
      (JSON-RPC error `-32601`); the caller decides whether to fail open or closed
    * `{:error, reason}` — the transaction could not be decoded, or the RPC failed
      for an operational reason (transport error, or a non-execution RPC error)

  `raw_hex` is an already co-signed 0x76 transaction hex string.

  > #### Method note {: .info}
  > The Tempo node exposes the EVM-standard `eth_simulateV1` (AA-aware: it accepts
  > the 0x76 `type`, `feeToken`, and the folded AA call). `tempo_simulateV1` —
  > used by the mpp-rs reference — is not deployed on Tempo mainnet (4217) or
  > Moderato testnet (42431); both return `-32601`. Verified empirically against
  > both networks.
  """
  @spec simulate(String.t(), String.t(), keyword()) ::
          {:ok, :success} | {:ok, {:revert, String.t()}} | {:ok, :unsupported} | {:error, String.t()}
  def simulate(raw_hex, rpc_url, opts \\ []) do
    with {:ok, tx} <- Transaction.deserialize(raw_hex),
         {:ok, call_request} <- Transaction.simulate_request(tx) do
      payload = %{
        "blockStateCalls" => [%{"calls" => [call_request]}],
        "traceTransfers" => false,
        "validation" => false,
        "returnFullTransactions" => false
      }

      case do_rpc_request("eth_simulateV1", [payload], rpc_url, opts) do
        {:ok, result} -> interpret_simulation(result)
        {:error, {:rpc_error, error}} -> classify_simulate_error(error)
        {:error, {:transport, message}} -> {:error, message}
      end
    end
  end

  @doc """
  Parse a raw JSON-RPC receipt map into atom-keyed format.

  The output is compatible with `Onchain.Transfer.parse_logs/1` and
  `Onchain.Tempo.Transfer.parse_transfer_with_memo_logs/1`.
  """
  @spec parse_receipt(map()) :: map()
  def parse_receipt(raw) when is_map(raw) do
    %{
      status: parse_hex_integer(raw["status"]),
      logs: Enum.map(raw["logs"] || [], &parse_log/1)
    }
  end

  # --- Private ---

  # Executes a JSON-RPC request via Req, flattening structured errors to strings
  # for the broadcast/receipt callers.
  defp rpc_request(method, params, rpc_url, opts) do
    case do_rpc_request(method, params, rpc_url, opts) do
      {:ok, value} -> {:ok, value}
      {:error, {:rpc_error, error}} -> {:error, "RPC error: #{inspect(error)}"}
      {:error, {:transport, message}} -> {:error, message}
    end
  end

  # Executes a JSON-RPC request and preserves the structured error so callers
  # that need the JSON-RPC error code (e.g. -32601 method-not-found) can inspect it.
  defp do_rpc_request(method, params, rpc_url, opts) do
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
          body: body
        ],
        req_options
      )

    case result do
      {:ok, %Req.Response{status: status, body: %{"result" => value}}} when status in 200..299 ->
        {:ok, value}

      {:ok, %Req.Response{body: %{"error" => error}}} ->
        {:error, {:rpc_error, error}}

      {:error, exception} ->
        {:error, {:transport, "RPC request failed: #{Exception.message(exception)}"}}

      {:ok, %Req.Response{} = response} ->
        {:error, {:transport, "Unexpected RPC response (status #{response.status})"}}
    end
  end

  # Reads the first block's first call result from an eth_simulateV1 response.
  # `result` is a list of block results (eth_simulateV1); a map with a "blocks"
  # key is also tolerated for forward-compatibility with other node shapes.
  defp interpret_simulation(result) do
    blocks = if is_list(result), do: result, else: Map.get(result, "blocks", [])

    call =
      case List.first(blocks) do
        %{"calls" => [call | _]} -> call
        _ -> nil
      end

    case call do
      %{"status" => "0x1"} -> {:ok, :success}
      %{"status" => "0x0"} -> {:ok, {:revert, revert_detail(call)}}
      %{"status" => other} -> {:error, "Unexpected simulation status: #{inspect(other)}"}
      nil -> {:error, "Simulation returned no call results"}
      other -> {:error, "Malformed simulation call result: #{inspect(other)}"}
    end
  end

  # Classifies a top-level JSON-RPC error from eth_simulateV1.
  #   * -32601               → the method is not implemented (let the caller decide)
  #   * -38000..-38999       → eth_simulateV1 execution/validity errors (e.g. -38013
  #                            "intrinsic gas too low"): the transaction would fail,
  #                            so report a revert (NOT an ambiguous error a fail-open
  #                            caller could leak the DoS through)
  #   * anything else        → operational RPC error
  defp classify_simulate_error(%{"code" => -32_601}), do: {:ok, :unsupported}

  defp classify_simulate_error(%{"code" => code} = error) when code <= -38_000 and code > -39_000 do
    {:ok, {:revert, simulate_error_detail(error)}}
  end

  defp classify_simulate_error(error), do: {:error, "Simulation RPC error: #{inspect(error)}"}

  defp simulate_error_detail(%{"message" => message, "code" => code}), do: "#{message} (code #{code})"
  defp simulate_error_detail(error), do: inspect(error)

  # Builds a human-readable revert reason from a failed simulation call result.
  defp revert_detail(call) do
    gas = gas_suffix(call["gasUsed"])

    case call do
      %{"error" => %{"message" => message} = error} ->
        "#{message} (code #{error["code"]})" <> gas

      %{"returnData" => data} when is_binary(data) and data not in ["", "0x"] ->
        "revert data #{data}" <> gas

      _ ->
        "no revert reason returned" <> gas
    end
  end

  defp gas_suffix(nil), do: ""
  defp gas_suffix(gas) when is_binary(gas), do: " (gasUsed #{gas})"

  # Converts a raw JSON-RPC log entry to atom-keyed map.
  defp parse_log(log) do
    %{
      address: log["address"],
      topics: log["topics"] || [],
      data: log["data"],
      block_number: parse_hex_integer(log["blockNumber"]) || 0,
      transaction_hash: log["transactionHash"],
      log_index: parse_hex_integer(log["logIndex"]) || 0
    }
  end

  # Parses a hex string like "0x1" into an integer.
  defp parse_hex_integer(nil), do: nil
  defp parse_hex_integer("0x" <> hex), do: String.to_integer(hex, 16)
  defp parse_hex_integer(_), do: nil
end
