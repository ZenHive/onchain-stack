defmodule Onchain.Transaction.Info do
  @moduledoc """
  Inclusion metadata for an execution-apis transaction object, plus the typed
  transaction.

  `from_json/1` on each envelope drops `blockHash`, `blockNumber`,
  `blockTimestamp`, `from`, `hash`, and `transactionIndex` (TransactionInfo in
  execution-apis v1.0.0-beta.7, `src/schemas/transaction.yaml`). Those fields
  live here. Block fields are `nil` when the transaction is pending.
  `block_timestamp` is also `nil` when the node omits `blockTimestamp`.
  Alchemy mainnet sometimes does that for mined transactions (observed
  2026-10-01), even though the beta.7 schema lists the field as required.
  """

  alias Onchain.Hex
  alias Onchain.Transaction
  alias Onchain.Transaction.V1
  alias Onchain.Transaction.V2
  alias Onchain.Transaction.V3
  alias Onchain.Transaction.V4
  alias Onchain.Transaction.V_2930

  @type transaction :: V1.t() | V_2930.t() | V2.t() | V3.t() | V4.t()

  @type t :: %__MODULE__{
          hash: <<_::256>>,
          from: <<_::160>>,
          block_hash: <<_::256>> | nil,
          block_number: non_neg_integer() | nil,
          block_timestamp: non_neg_integer() | nil,
          transaction_index: non_neg_integer() | nil,
          transaction: transaction()
        }

  defstruct [
    :hash,
    :from,
    :block_hash,
    :block_number,
    :block_timestamp,
    :transaction_index,
    :transaction
  ]

  @doc """
  Decodes a JSON-RPC transaction object into an envelope.

  Returns `{:error, reason}` for a missing required field, an unknown `type`,
  or a field the envelope decoder cannot read. Does not raise.
  """
  @spec decode(term()) :: {:ok, t()} | {:error, term()}
  def decode(%{} = params) do
    with {:ok, hash} <- required_bytes(params, "hash", 32),
         {:ok, from} <- required_bytes(params, "from", 20),
         {:ok, module} <- Transaction.from_json_module(params["type"]),
         :ok <- require_fields(params, required_fields(module)),
         :ok <- require_signature(params, module),
         {:ok, transaction} <- decode_body(module, params),
         {:ok, block_hash} <- optional_word(params, "blockHash"),
         {:ok, block_number} <- optional_quantity(params, "blockNumber"),
         {:ok, block_timestamp} <- optional_quantity(params, "blockTimestamp"),
         {:ok, transaction_index} <- optional_quantity(params, "transactionIndex") do
      {:ok,
       %__MODULE__{
         hash: hash,
         from: from,
         block_hash: block_hash,
         block_number: block_number,
         block_timestamp: block_timestamp,
         transaction_index: transaction_index,
         transaction: transaction
       }}
    end
  end

  def decode(other), do: {:error, {:unexpected_transaction, other}}

  @spec required_fields(module()) :: [String.t()]
  defp required_fields(V1), do: ~w(nonce gasPrice gas value input v r s)
  defp required_fields(V_2930), do: ~w(chainId nonce gasPrice gas value input r s)
  defp required_fields(V2), do: ~w(chainId nonce maxPriorityFeePerGas maxFeePerGas gas value input r s)
  defp required_fields(V3), do: ~w(chainId nonce maxPriorityFeePerGas maxFeePerGas gas value input maxFeePerBlobGas r s)
  defp required_fields(V4), do: required_fields(V2)

  # V1 reads `v` only. Typed envelopes accept `yParity` or, failing that, `v`.
  @spec require_signature(map(), module()) :: :ok | {:error, {:missing_field, String.t()}}
  defp require_signature(_params, V1), do: :ok

  defp require_signature(params, _module) do
    if present?(params, "yParity") or present?(params, "v") do
      :ok
    else
      {:error, {:missing_field, "yParity"}}
    end
  end

  @spec require_fields(map(), [String.t()]) :: :ok | {:error, {:missing_field, String.t()}}
  defp require_fields(params, fields) do
    case Enum.find(fields, &(not present?(params, &1))) do
      nil -> :ok
      field -> {:error, {:missing_field, field}}
    end
  end

  @spec present?(map(), String.t()) :: boolean()
  defp present?(params, field) do
    case Map.fetch(params, field) do
      {:ok, value} when not is_nil(value) -> true
      _ -> false
    end
  end

  # `from_json/1` raises. The envelope is the boundary that turns that into
  # `{:error, reason}`; callers of the transaction reads must not see a raise.
  @spec decode_body(module(), map()) :: {:ok, transaction()} | {:error, {:invalid_transaction, String.t()}}
  defp decode_body(module, params) do
    {:ok, module.from_json(params)}
  rescue
    e in [
      Hex.InvalidHex,
      ArgumentError,
      KeyError,
      FunctionClauseError,
      MatchError,
      Protocol.UndefinedError
    ] ->
      {:error, {:invalid_transaction, Exception.message(e)}}
  end

  @spec required_bytes(map(), String.t(), pos_integer()) ::
          {:ok, binary()} | {:error, {:missing_field, String.t()} | {:invalid_field, String.t()}}
  defp required_bytes(params, field, size) do
    case Map.get(params, field) do
      nil -> {:error, {:missing_field, field}}
      value -> decode_sized(value, size, field)
    end
  end

  @spec optional_word(map(), String.t()) ::
          {:ok, <<_::256>> | nil} | {:error, {:invalid_field, String.t()}}
  defp optional_word(params, field) do
    case Map.get(params, field) do
      nil -> {:ok, nil}
      value -> decode_sized(value, 32, field)
    end
  end

  @spec optional_quantity(map(), String.t()) ::
          {:ok, non_neg_integer() | nil} | {:error, {:invalid_field, String.t()}}
  defp optional_quantity(params, field) do
    case Map.get(params, field) do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        case Hex.decode_hex_number(value) do
          {:ok, number} -> {:ok, number}
          :invalid_hex -> {:error, {:invalid_field, field}}
        end

      _other ->
        {:error, {:invalid_field, field}}
    end
  end

  @spec decode_sized(term(), pos_integer(), String.t()) ::
          {:ok, binary()} | {:error, {:invalid_field, String.t()}}
  defp decode_sized(value, size, field) when is_binary(value) do
    case Hex.decode_hex(value) do
      {:ok, bin} when byte_size(bin) == size -> {:ok, bin}
      _ -> {:error, {:invalid_field, field}}
    end
  end

  defp decode_sized(_value, _size, field), do: {:error, {:invalid_field, field}}
end
