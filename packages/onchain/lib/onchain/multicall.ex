defmodule Onchain.Multicall do
  @moduledoc """
  Multicall3 batched contract reads.

  Batches N arbitrary contract calls into a single RPC round-trip using the
  Multicall3 contract (`0xcA11bde05977b3631167028862bE2a173976CA11`), deployed
  identically on every EVM chain.

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `aggregate3/2` | Low-level: raw calldata tuples → raw results |
  | `aggregate3!/2` | Same, raises on error |
  | `call_many/2` | High-level: signature-based calls → decoded results |
  | `call_many!/2` | Same, raises on error |

  ## Error Format

  - Input validation: `{:error, {:invalid_address, input}}`
  - RPC/ABI errors pass through from `Contract.call/5`
  - Individual call failures in `call_many`: `{:error, raw_hex}` per failed call
  """

  use Descripex, namespace: "/multicall"

  alias Onchain.ABI
  alias Onchain.Address
  alias Onchain.Contract
  alias Onchain.Hex

  @multicall3_address "0xcA11bde05977b3631167028862bE2a173976CA11"

  # --- aggregate3 ---

  api(:aggregate3, "Batch raw contract calls via Multicall3 aggregate3.",
    params: [
      calls: [
        kind: :value,
        description: "List of {address_hex, allow_failure_bool, calldata_hex} tuples"
      ],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, [{boolean(), binary()}]} | {:error, term()}",
      description: "List of {success, return_data} tuples"
    }
  )

  @spec aggregate3([{String.t(), boolean(), String.t()}], keyword()) ::
          {:ok, [{boolean(), binary()}]} | {:error, term()}
  def aggregate3(calls, opts \\ []) when is_list(calls) do
    with {:ok, encoded_calls} <- encode_aggregate3_calls(calls),
         {:ok, [results]} <-
           Contract.call(
             @multicall3_address,
             "aggregate3((address,bool,bytes)[])",
             [encoded_calls],
             "((bool,bytes)[])",
             opts
           ) do
      parsed = Enum.map(results, fn {success, data} -> {success, Hex.encode(data)} end)
      {:ok, parsed}
    end
  end

  # --- aggregate3! ---

  api(:aggregate3!, "Batch raw contract calls. Raises on error.",
    params: [
      calls: [kind: :value, description: "List of {address, allow_failure, calldata} tuples"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: "[{boolean(), binary()}]", description: "List of {success, return_data}"}
  )

  @spec aggregate3!([{String.t(), boolean(), String.t()}], keyword()) :: [{boolean(), binary()}]
  def aggregate3!(calls, opts \\ []) do
    case aggregate3(calls, opts) do
      {:ok, results} -> results
      {:error, reason} -> raise "aggregate3 failed: #{inspect(reason)}"
    end
  end

  # --- call_many ---

  api(:call_many, "Batch contract calls with automatic ABI encoding/decoding.",
    params: [
      calls: [
        kind: :value,
        description: "List of (address, signature, params, return_type) tuples"
      ],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, [result]} | {:error, term()}",
      description: "List where each result is {:ok, decoded_values} or {:error, return_data_hex}"
    }
  )

  @spec call_many([{String.t() | binary(), String.t(), list(), String.t()}], keyword()) ::
          {:ok, [{:ok, list()} | {:error, String.t()}]} | {:error, term()}
  def call_many(calls, opts \\ []) when is_list(calls) do
    with {:ok, raw_calls} <- encode_call_many(calls),
         {:ok, results} <- aggregate3(raw_calls, opts) do
      decoded =
        calls
        |> Enum.zip(results)
        |> Enum.map(fn {call, result} -> decode_result(call, result) end)

      {:ok, decoded}
    end
  end

  # --- call_many! ---

  api(:call_many!, "Batch contract calls with encoding/decoding. Raises on error.",
    params: [
      calls: [kind: :value, description: "List of {address, signature, params, return_type} tuples"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: "[result]", description: "List of {:ok, values} or {:error, data}"}
  )

  @spec call_many!([{String.t() | binary(), String.t(), list(), String.t()}], keyword()) ::
          [{:ok, list()} | {:error, String.t()}]
  def call_many!(calls, opts \\ []) do
    case call_many(calls, opts) do
      {:ok, results} -> results
      {:error, reason} -> raise "call_many failed: #{inspect(reason)}"
    end
  end

  # --- Private helpers ---

  @doc false
  # Decodes a single multicall result against its call spec.
  @spec decode_result(tuple(), {boolean(), String.t()}) :: {:ok, list()} | {:error, term()}
  defp decode_result({_addr, _sig, _params, return_type}, {true, data_hex}) do
    ABI.decode_response(return_type, data_hex)
  end

  defp decode_result(_call, {false, data_hex}), do: {:error, data_hex}

  @doc false
  # Encodes aggregate3 call tuples into the format expected by the ABI encoder.
  @spec encode_aggregate3_calls([{String.t(), boolean(), String.t()}]) ::
          {:ok, [{binary(), boolean(), binary()}]} | {:error, term()}
  defp encode_aggregate3_calls(calls) do
    calls
    |> Enum.reduce_while({:ok, []}, fn {addr, allow_failure, calldata}, {:ok, acc} ->
      with {:ok, addr_bin} <- Address.validate(addr),
           {:ok, data_bin} <- decode_calldata(calldata) do
        {:cont, {:ok, [{addr_bin, allow_failure, data_bin} | acc]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, encoded} -> {:ok, Enum.reverse(encoded)}
      error -> error
    end
  end

  @doc false
  # Encodes high-level call_many tuples into aggregate3 format.
  @spec encode_call_many([{String.t() | binary(), String.t(), list(), String.t()}]) ::
          {:ok, [{String.t(), boolean(), String.t()}]} | {:error, term()}
  defp encode_call_many(calls) do
    calls
    |> Enum.reduce_while({:ok, []}, fn {addr, signature, params, _return_type}, {:ok, acc} ->
      with {:ok, hex_addr} <- validate_and_hex(addr),
           {:ok, calldata} <- ABI.encode_call(signature, params) do
        {:cont, {:ok, [{hex_addr, true, calldata} | acc]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, encoded} -> {:ok, Enum.reverse(encoded)}
      error -> error
    end
  end

  @doc false
  # Validates an address and returns it as a hex string.
  @spec validate_and_hex(String.t() | binary()) :: {:ok, String.t()} | {:error, term()}
  defp validate_and_hex(addr) do
    case Address.validate(addr) do
      {:ok, bin} -> {:ok, Hex.encode(bin)}
      error -> error
    end
  end

  @doc false
  # Decodes 0x-prefixed calldata hex to binary.
  @spec decode_calldata(String.t()) :: {:ok, binary()} | {:error, term()}
  defp decode_calldata(hex) do
    Hex.decode(hex)
  end
end
