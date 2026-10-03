defmodule Onchain.RPC.Simulate do
  @moduledoc """
  Request and result structs for `eth_simulateV1`.

  The method has been in the tagged `ethereum/execution-apis` spec since
  v1.0.0-beta.5 (`src/eth/execute.yaml`). Quantities are non-negative
  integers. Addresses, calldata, code and 32-byte words are raw bytes.
  `Onchain.RPC.eth_simulate_v1/2` is the call.

  A per-call revert stays inside the successful result as a `CallFailure`.
  A request rejection stays a JSON-RPC error map from `Onchain.RPC.send_rpc/3`.
  Method unsupported stays `{:method_not_found, map}` from that same
  classifier. Those three are not collapsed.

  Call logs are `Onchain.Filter.Log` structs. `blockTimestamp`, which this
  method's log schema adds, is ignored the same way receipt-log decoding
  ignores it.
  """

  alias Onchain.Block.Withdrawal
  alias Onchain.Filter.Log, as: FilterLog
  alias Onchain.Hex
  alias Onchain.Transaction.V2

  # execution-apis v1.0.0-beta.7, `eth_simulateV1` `errors`. `-32601` is not
  # in this list; `send_rpc/3` classifies that code as `:method_not_found`.
  @request_error_codes [
    -32_000,
    -32_602,
    -32_005,
    -32_015,
    -32_016,
    -32_603,
    -38_010,
    -38_011,
    -38_012,
    -38_013,
    -38_014,
    -38_015,
    -38_020,
    -38_021,
    -38_022,
    -38_023,
    -38_024,
    -38_025,
    -38_026
  ]

  defmodule CallError do
    @moduledoc """
    Per-call `error` object from a `CallResultFailure`.

    `code` `3` is an execution revert. `code` `-32015` is a VM execution
    error. `data` is the raw revert payload when the node sent it, and `nil`
    when it did not. This is not a JSON-RPC error on the request.
    """

    @enforce_keys [:code, :message]
    defstruct [:code, :message, :data]

    @type t :: %__MODULE__{code: integer(), message: String.t(), data: binary() | nil}
  end

  defmodule CallSuccess do
    @moduledoc """
    One successful call inside a simulated block. `status` is `1` (wire `0x1`).
    """

    @enforce_keys [:status, :return_data, :gas_used, :logs]
    defstruct [:status, :return_data, :gas_used, :max_used_gas, :logs]

    @type t :: %__MODULE__{
            status: 1,
            return_data: binary(),
            gas_used: non_neg_integer(),
            max_used_gas: non_neg_integer() | nil,
            logs: [FilterLog.t()]
          }
  end

  defmodule CallFailure do
    @moduledoc """
    One failed call inside a simulated block that the node still accepted.

    `status` is `0` (wire `0x0`). The block result is still `{:ok, _}`.
    `logs` is empty when the node omits them; reth sends `[]`.
    """

    alias Onchain.RPC.Simulate.CallError

    @enforce_keys [:status, :return_data, :gas_used, :error]
    defstruct [:status, :return_data, :gas_used, :max_used_gas, :logs, :error]

    @type t :: %__MODULE__{
            status: 0,
            return_data: binary(),
            gas_used: non_neg_integer(),
            max_used_gas: non_neg_integer() | nil,
            logs: [FilterLog.t()],
            error: CallError.t()
          }
  end

  defmodule Call do
    @moduledoc """
    One call in `blockStateCalls`, the spec's `GenericCallTransaction`.

    Every field is optional. Nil fields are omitted on the wire. `input` is
    raw calldata, sent as `input` (not `eth_call`'s `data`).
    """

    @type t :: %__MODULE__{
            from: <<_::160>> | nil,
            to: <<_::160>> | nil,
            gas: non_neg_integer() | nil,
            value: non_neg_integer() | nil,
            input: binary() | nil,
            nonce: non_neg_integer() | nil,
            type: non_neg_integer() | nil,
            gas_price: non_neg_integer() | nil,
            max_fee_per_gas: non_neg_integer() | nil,
            max_priority_fee_per_gas: non_neg_integer() | nil,
            max_fee_per_blob_gas: non_neg_integer() | nil,
            access_list: V2.access_list() | nil,
            blob_versioned_hashes: [<<_::256>>] | nil
          }

    defstruct [
      :from,
      :to,
      :gas,
      :value,
      :input,
      :nonce,
      :type,
      :gas_price,
      :max_fee_per_gas,
      :max_priority_fee_per_gas,
      :max_fee_per_blob_gas,
      :access_list,
      :blob_versioned_hashes
    ]
  end

  defmodule AccountOverride do
    @moduledoc """
    State override for one address.

    `state` replaces the account's storage. `stateDiff` patches slots. Setting
    both is rejected locally. Clients accept a balance-only override; neither
    storage field is required even though the spec's `oneOf` lists them.
    """

    @type storage :: %{optional(<<_::256>>) => <<_::256>>}

    @type t :: %__MODULE__{
            balance: non_neg_integer() | nil,
            nonce: non_neg_integer() | nil,
            code: binary() | nil,
            state: storage() | nil,
            state_diff: storage() | nil,
            move_precompile_to_address: <<_::160>> | nil
          }

    defstruct [:balance, :nonce, :code, :state, :state_diff, :move_precompile_to_address]
  end

  defmodule BlockOverride do
    @moduledoc """
    Block-field override for one simulated block.

    `prev_randao` is a 32-byte word. Reth rejects a short quantity here, so
    the wire value keeps its leading zeros.
    """

    @type t :: %__MODULE__{
            number: non_neg_integer() | nil,
            prev_randao: <<_::256>> | nil,
            time: non_neg_integer() | nil,
            gas_limit: non_neg_integer() | nil,
            fee_recipient: <<_::160>> | nil,
            base_fee_per_gas: non_neg_integer() | nil,
            withdrawals: [Withdrawal.t()] | nil,
            blob_base_fee: non_neg_integer() | nil
          }

    defstruct [
      :number,
      :prev_randao,
      :time,
      :gas_limit,
      :fee_recipient,
      :base_fee_per_gas,
      :withdrawals,
      :blob_base_fee
    ]
  end

  defmodule BlockStateCall do
    @moduledoc """
    One entry of `blockStateCalls`: calls plus optional state and block overrides.
    """

    alias Onchain.RPC.Simulate.AccountOverride
    alias Onchain.RPC.Simulate.BlockOverride
    alias Onchain.RPC.Simulate.Call

    @type t :: %__MODULE__{
            calls: [Call.t()] | nil,
            state_overrides: %{optional(<<_::160>>) => AccountOverride.t()} | nil,
            block_overrides: BlockOverride.t() | nil
          }

    defstruct [:calls, :state_overrides, :block_overrides]
  end

  defmodule Payload do
    @moduledoc """
    `eth_simulateV1` params object. `block_state_calls` is required.

    Nil booleans are omitted. `false` is sent, because that is the spec's
    documented default and callers set it on purpose.
    """

    alias Onchain.RPC.Simulate.BlockStateCall

    @enforce_keys [:block_state_calls]
    defstruct [:block_state_calls, :trace_transfers, :validation, :return_full_transactions]

    @type t :: %__MODULE__{
            block_state_calls: [BlockStateCall.t()],
            trace_transfers: boolean() | nil,
            validation: boolean() | nil,
            return_full_transactions: boolean() | nil
          }
  end

  defmodule BlockResult do
    @moduledoc """
    One simulated block: the header `Onchain.Block` already decodes, plus calls.

    `block_access_list_hash` is the EIP-7928 field when the node sends it.
    Transaction hashes stay hex strings. Full transactions, when
    `returnFullTransactions` is true, decode through `Onchain.Block`.
    """

    alias Onchain.RPC.Simulate.CallFailure
    alias Onchain.RPC.Simulate.CallSuccess

    @enforce_keys [:block, :calls]
    defstruct [:block, :calls, :block_access_list_hash]

    @type call_result :: CallSuccess.t() | CallFailure.t()

    @type t :: %__MODULE__{
            block: Onchain.Block.t(),
            calls: [call_result()],
            block_access_list_hash: <<_::256>> | nil
          }
  end

  @typedoc "A decoded call, either success or a per-call failure."
  @type call_result :: BlockResult.call_result()

  @doc """
  JSON-RPC error codes listed on `eth_simulateV1` in execution-apis v1.0.0-beta.7.

  `-32601` is absent. That refusal is `:method_not_found` from `send_rpc/3`.
  """
  @spec request_error_codes() :: [integer()]
  def request_error_codes, do: @request_error_codes

  @doc """
  Encodes a payload into the `eth_simulateV1` params object.
  """
  @spec encode(Payload.t()) :: {:ok, map()} | {:error, term()}
  def encode(%Payload{block_state_calls: blocks} = payload) when is_list(blocks) do
    with {:ok, block_state_calls} <- encode_list(blocks, &encode_block_state_call/1),
         {:ok, body} <- encode_payload_flags(payload) do
      {:ok, Map.put(body, "blockStateCalls", block_state_calls)}
    end
  end

  def encode(%Payload{}), do: {:error, :invalid_block_state_calls}

  @doc """
  Decodes an `eth_simulateV1` result array into block results.

  Raises on a shape the spec marks required and the decoder cannot read.
  `Onchain.RPC.send_rpc/3` turns that raise into `{:error, message}`.
  """
  @spec deserialize([map()]) :: [BlockResult.t()]
  def deserialize(blocks) when is_list(blocks), do: Enum.map(blocks, &deserialize_block/1)

  @spec encode_payload_flags(Payload.t()) :: {:ok, map()} | {:error, term()}
  defp encode_payload_flags(payload) do
    encode_fields([
      {"traceTransfers", payload.trace_transfers, &encode_boolean/1},
      {"validation", payload.validation, &encode_boolean/1},
      {"returnFullTransactions", payload.return_full_transactions, &encode_boolean/1}
    ])
  end

  @spec encode_block_state_call(BlockStateCall.t()) :: {:ok, map()} | {:error, term()}
  defp encode_block_state_call(%BlockStateCall{} = block) do
    encode_fields([
      {"calls", block.calls, &encode_calls/1},
      {"stateOverrides", block.state_overrides, &encode_state_overrides/1},
      {"blockOverrides", block.block_overrides, &encode_block_override/1}
    ])
  end

  defp encode_block_state_call(other), do: {:error, {:invalid_block_state_call, other}}

  @spec encode_calls([Call.t()]) :: {:ok, [map()]} | {:error, term()}
  defp encode_calls(calls), do: encode_list(calls, &encode_call/1)

  @spec encode_call(Call.t()) :: {:ok, map()} | {:error, term()}
  defp encode_call(%Call{} = call) do
    encode_fields([
      {"from", call.from, &encode_address/1},
      {"to", call.to, &encode_address/1},
      {"gas", call.gas, &encode_quantity/1},
      {"value", call.value, &encode_quantity/1},
      {"input", call.input, &encode_bytes/1},
      {"nonce", call.nonce, &encode_quantity/1},
      {"type", call.type, &encode_tx_type/1},
      {"gasPrice", call.gas_price, &encode_quantity/1},
      {"maxFeePerGas", call.max_fee_per_gas, &encode_quantity/1},
      {"maxPriorityFeePerGas", call.max_priority_fee_per_gas, &encode_quantity/1},
      {"maxFeePerBlobGas", call.max_fee_per_blob_gas, &encode_quantity/1},
      {"accessList", call.access_list, &encode_access_list/1},
      {"blobVersionedHashes", call.blob_versioned_hashes, &encode_blob_hashes/1}
    ])
  end

  defp encode_call(other), do: {:error, {:invalid_call, other}}

  @spec encode_state_overrides(%{optional(<<_::160>>) => AccountOverride.t()}) ::
          {:ok, map()} | {:error, term()}
  defp encode_state_overrides(overrides) when is_map(overrides) do
    Enum.reduce_while(overrides, {:ok, %{}}, fn {address, account}, {:ok, acc} ->
      case encode_state_override(address, account) do
        {:ok, key, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp encode_state_overrides(other), do: {:error, {:invalid_state_overrides, other}}

  @spec encode_state_override(<<_::160>>, AccountOverride.t()) ::
          {:ok, String.t(), map()} | {:error, term()}
  defp encode_state_override(address, %AccountOverride{state: state, state_diff: state_diff})
       when not is_nil(state) and not is_nil(state_diff) do
    {:error, {:conflicting_storage_override, address}}
  end

  defp encode_state_override(address, %AccountOverride{} = account) do
    with {:ok, key} <- encode_address(address),
         {:ok, value} <- encode_account(account) do
      {:ok, key, value}
    end
  end

  defp encode_state_override(_address, other), do: {:error, {:invalid_account_override, other}}

  @spec encode_account(AccountOverride.t()) :: {:ok, map()} | {:error, term()}
  defp encode_account(%AccountOverride{} = account) do
    encode_fields([
      {"balance", account.balance, &encode_quantity/1},
      {"nonce", account.nonce, &encode_quantity/1},
      {"code", account.code, &encode_bytes/1},
      {"movePrecompileToAddress", account.move_precompile_to_address, &encode_address/1},
      {"state", account.state, &encode_storage/1},
      {"stateDiff", account.state_diff, &encode_storage/1}
    ])
  end

  @spec encode_block_override(BlockOverride.t()) :: {:ok, map()} | {:error, term()}
  defp encode_block_override(%BlockOverride{} = override) do
    encode_fields([
      {"number", override.number, &encode_quantity/1},
      {"prevRandao", override.prev_randao, &encode_word/1},
      {"time", override.time, &encode_quantity/1},
      {"gasLimit", override.gas_limit, &encode_quantity/1},
      {"feeRecipient", override.fee_recipient, &encode_address/1},
      {"baseFeePerGas", override.base_fee_per_gas, &encode_quantity/1},
      {"withdrawals", override.withdrawals, &encode_withdrawals/1},
      {"blobBaseFee", override.blob_base_fee, &encode_quantity/1}
    ])
  end

  defp encode_block_override(other), do: {:error, {:invalid_block_override, other}}

  @spec encode_withdrawals([Withdrawal.t()]) :: {:ok, [map()]} | {:error, term()}
  defp encode_withdrawals(withdrawals), do: encode_list(withdrawals, &encode_withdrawal/1)

  @spec encode_withdrawal(Withdrawal.t()) :: {:ok, map()} | {:error, term()}
  defp encode_withdrawal(%Withdrawal{} = withdrawal) do
    with {:ok, index} <- encode_quantity(withdrawal.index),
         {:ok, validator_index} <- encode_quantity(withdrawal.validator_index),
         {:ok, address} <- encode_address(withdrawal.address),
         {:ok, amount} <- encode_quantity(withdrawal.amount) do
      {:ok,
       %{
         "index" => index,
         "validatorIndex" => validator_index,
         "address" => address,
         "amount" => amount
       }}
    end
  end

  defp encode_withdrawal(other), do: {:error, {:invalid_withdrawal, other}}

  @spec encode_access_list(V2.access_list()) :: {:ok, [map()]} | {:error, term()}
  defp encode_access_list(entries), do: encode_list(entries, &encode_access_entry/1)

  @spec encode_access_entry(V2.access_list_entry()) ::
          {:ok, map()} | {:error, term()}
  defp encode_access_entry({address, keys}) when is_list(keys) do
    with {:ok, address} <- encode_address(address),
         {:ok, keys} <- encode_list(keys, &encode_word/1) do
      {:ok, %{"address" => address, "storageKeys" => keys}}
    end
  end

  defp encode_access_entry(other), do: {:error, {:invalid_access_list_entry, other}}

  @spec encode_blob_hashes([<<_::256>>]) :: {:ok, [String.t()]} | {:error, term()}
  defp encode_blob_hashes(hashes), do: encode_list(hashes, &encode_word/1)

  @spec encode_storage(AccountOverride.storage()) :: {:ok, map()} | {:error, term()}
  defp encode_storage(slots) when is_map(slots) do
    Enum.reduce_while(slots, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case encode_storage_slot(key, value) do
        {:ok, wire_key, wire_value} -> {:cont, {:ok, Map.put(acc, wire_key, wire_value)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp encode_storage(other), do: {:error, {:invalid_storage, other}}

  @spec encode_storage_slot(<<_::256>>, <<_::256>>) :: {:ok, String.t(), String.t()} | {:error, term()}
  defp encode_storage_slot(key, value) do
    with {:ok, key} <- encode_word(key),
         {:ok, value} <- encode_word(value),
         do: {:ok, key, value}
  end

  @spec encode_fields([{String.t(), term(), (term() -> {:ok, term()} | {:error, term()})}]) ::
          {:ok, map()} | {:error, term()}
  defp encode_fields(fields) do
    Enum.reduce_while(fields, {:ok, %{}}, fn
      {_key, nil, _encoder}, {:ok, acc} ->
        {:cont, {:ok, acc}}

      {key, value, encoder}, {:ok, acc} ->
        case encoder.(value) do
          {:ok, encoded} -> {:cont, {:ok, Map.put(acc, key, encoded)}}
          {:error, reason} -> {:halt, {:error, {:invalid_field, key, reason}}}
        end
    end)
  end

  @spec encode_list([term()], (term() -> {:ok, term()} | {:error, term()})) ::
          {:ok, [term()]} | {:error, term()}
  defp encode_list(items, encoder) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case encoder.(item) do
        {:ok, encoded} -> {:cont, {:ok, [encoded | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, encoded} -> {:ok, Enum.reverse(encoded)}
      error -> error
    end
  end

  defp encode_list(other, _encoder), do: {:error, {:invalid_list, other}}

  @spec encode_boolean(boolean()) :: {:ok, boolean()} | {:error, term()}
  defp encode_boolean(value) when is_boolean(value), do: {:ok, value}
  defp encode_boolean(other), do: {:error, {:invalid_boolean, other}}

  @spec encode_quantity(non_neg_integer()) :: {:ok, String.t()} | {:error, term()}
  defp encode_quantity(quantity) when is_integer(quantity) and quantity >= 0, do: {:ok, Hex.from_integer(quantity)}
  defp encode_quantity(other), do: {:error, {:invalid_quantity, other}}

  @spec encode_tx_type(non_neg_integer()) :: {:ok, String.t()} | {:error, term()}
  defp encode_tx_type(type) when is_integer(type) and type >= 0 and type <= 255, do: encode_quantity(type)
  defp encode_tx_type(other), do: {:error, {:invalid_tx_type, other}}

  @spec encode_address(<<_::160>>) :: {:ok, String.t()} | {:error, term()}
  defp encode_address(<<_::160>> = address), do: {:ok, Hex.encode_hex(address)}
  defp encode_address(other), do: {:error, {:invalid_address, other}}

  @spec encode_word(<<_::256>>) :: {:ok, String.t()} | {:error, term()}
  defp encode_word(<<_::256>> = word), do: {:ok, Hex.encode_hex(word)}
  defp encode_word(other), do: {:error, {:invalid_word, other}}

  @spec encode_bytes(binary()) :: {:ok, String.t()} | {:error, term()}
  defp encode_bytes(bytes) when is_binary(bytes), do: {:ok, Hex.encode_hex(bytes)}
  defp encode_bytes(other), do: {:error, {:invalid_bytes, other}}

  @spec deserialize_block(map()) :: BlockResult.t()
  defp deserialize_block(%{"calls" => calls} = block) when is_list(calls) do
    %BlockResult{
      block: Onchain.Block.deserialize(block),
      calls: Enum.map(calls, &deserialize_call/1),
      block_access_list_hash: decode_optional_word(block["blockAccessListHash"])
    }
  end

  @spec deserialize_call(map()) :: call_result()
  defp deserialize_call(%{"status" => status} = call) do
    case Hex.decode_hex_number!(status) do
      1 -> deserialize_success(call)
      0 -> deserialize_failure(call)
      other -> raise ArgumentError, "unexpected eth_simulateV1 call status #{other}"
    end
  end

  @spec deserialize_success(map()) :: CallSuccess.t()
  defp deserialize_success(call) do
    %CallSuccess{
      status: 1,
      return_data: Hex.decode_hex!(Map.fetch!(call, "returnData")),
      gas_used: Hex.decode_hex_number!(Map.fetch!(call, "gasUsed")),
      max_used_gas: decode_optional_quantity(call["maxUsedGas"]),
      logs: FilterLog.decode_logs(Map.fetch!(call, "logs"))
    }
  end

  @spec deserialize_failure(map()) :: CallFailure.t()
  defp deserialize_failure(call) do
    %CallFailure{
      status: 0,
      return_data: Hex.decode_hex!(Map.fetch!(call, "returnData")),
      gas_used: Hex.decode_hex_number!(Map.fetch!(call, "gasUsed")),
      max_used_gas: decode_optional_quantity(call["maxUsedGas"]),
      logs: FilterLog.decode_logs(Map.get(call, "logs") || []),
      error: deserialize_error(Map.fetch!(call, "error"))
    }
  end

  @spec deserialize_error(map()) :: CallError.t()
  defp deserialize_error(%{"code" => code, "message" => message} = error) when is_integer(code) and is_binary(message) do
    %CallError{code: code, message: message, data: decode_optional_bytes(error["data"])}
  end

  @spec decode_optional_quantity(String.t() | nil) :: non_neg_integer() | nil
  defp decode_optional_quantity(nil), do: nil
  defp decode_optional_quantity(quantity), do: Hex.decode_hex_number!(quantity)

  @spec decode_optional_bytes(String.t() | nil) :: binary() | nil
  defp decode_optional_bytes(nil), do: nil
  defp decode_optional_bytes(bytes), do: Hex.decode_hex!(bytes)

  @spec decode_optional_word(String.t() | nil) :: <<_::256>> | nil
  defp decode_optional_word(nil), do: nil
  defp decode_optional_word(word), do: Hex.decode_word!(word)
end
