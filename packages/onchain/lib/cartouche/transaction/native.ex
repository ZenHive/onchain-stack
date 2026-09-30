defmodule Cartouche.Transaction.Native do
  @moduledoc false
  alias Cartouche.Transaction.TypedDecode
  alias Cartouche.Transaction.V1
  alias Cartouche.Transaction.V2
  alias Cartouche.Transaction.V3
  alias Cartouche.Transaction.V4
  alias Cartouche.Transaction.V_2930

  @modules [V1, V_2930, V2, V3, V4]
  @fields [
    chain_id: "chainId",
    nonce: "nonce",
    gas_price: "gasPrice",
    gas_limit: "gas",
    max_priority_fee_per_gas: "maxPriorityFeePerGas",
    max_fee_per_gas: "maxFeePerGas",
    max_fee_per_blob_gas: "maxFeePerBlobGas",
    amount: "value"
  ]

  @doc false
  @spec encode(struct()) :: binary()
  def encode(transaction), do: run!("encode", transaction)

  @doc false
  @spec signing_hash(struct()) :: binary()
  def signing_hash(transaction), do: run!("signing_hash", transaction)

  @doc false
  @spec sign(struct(), GenServer.server(), Keyword.t()) :: {:ok, binary()} | {:error, term()}
  def sign(transaction, signer, opts) do
    Cartouche.Signer.sign_digest(signing_hash(transaction), run!("signing_payload", transaction), signer, opts)
  end

  @doc false
  @spec decode(term(), module(), String.t()) :: {:ok, struct()} | {:error, String.t()}
  def decode(input, module, invalid) when is_binary(input) do
    with {:ok, params} <- ABI.Native.consensus("transaction", "decode", input),
         true <- params["type"] == type(module),
         true <- is_binary(params["to"]),
         transaction = from_rpc(module, params),
         :ok <- validate(transaction) do
      {:ok, transaction}
    else
      {:error, "authorization_list must not be empty"} = error -> error
      _ -> {:error, invalid}
    end
  end

  def decode(_, _, invalid), do: {:error, invalid}

  @spec from_rpc(module(), map()) :: struct()
  defp from_rpc(module, params) do
    if module != V1 and not Map.has_key?(params, "r") do
      params = Map.merge(params, %{"r" => "0x0", "s" => "0x0", "yParity" => "0x0"})
      transaction = module.from_json(params)
      %{transaction | signature_y_parity: nil, signature_r: nil, signature_s: nil}
    else
      module.from_json(params)
    end
  end

  @doc false
  @spec authorization(String.t(), tuple()) :: binary()
  def authorization(operation, authorization) do
    [chain_id, address, nonce | _] = Tuple.to_list(authorization)
    validate_uint!(chain_id, :authorization_chain_id, 256)
    validate_uint!(nonce, :authorization_nonce, 64)
    request!(operation, %{"chainId" => quantity(chain_id), "address" => hex(address), "nonce" => quantity(nonce)})
  end

  @spec validate_widths!(map()) :: :ok
  defp validate_widths!(transaction) do
    widths = [
      nonce: 64,
      gas_limit: 64,
      chain_id: 64,
      gas_price: 128,
      max_priority_fee_per_gas: 128,
      max_fee_per_gas: 128,
      max_fee_per_blob_gas: 128,
      amount: 256,
      value: 256
    ]

    Enum.each(widths, fn {field, width} ->
      case Map.fetch(transaction, field) do
        {:ok, value} -> validate_uint!(value, field, width)
        :error -> :ok
      end
    end)

    :ok
  end

  @spec validate_uint!(term(), atom(), pos_integer()) :: :ok
  defp validate_uint!(value, field, width) do
    if not is_integer(value) or value < 0 or value >= Integer.pow(2, width),
      do: raise(ArgumentError, "#{field} must be in 0..2^#{width}-1")

    :ok
  end

  @spec run!(String.t(), struct()) :: binary()
  defp run!(operation, transaction) do
    validate_widths!(transaction)

    case validate(transaction) do
      :ok -> request!(operation, to_rpc(transaction))
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @spec request!(String.t(), map()) :: binary()
  defp request!(operation, params) do
    case ABI.Native.consensus("transaction", operation, params) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, "invalid transaction: #{reason}"
    end
  end

  @spec to_rpc(struct()) :: map()
  defp to_rpc(%V1{} = tx) do
    validate_uint!(tx.r, :r, 256)
    validate_uint!(tx.s, :s, 256)
    unsigned = tx.r == 0 and tx.s == 0

    if not unsigned and tx.v not in [27, 28] and tx.v < 35,
      do: raise(ArgumentError, "v must be 27, 28 or an EIP-155 value >= 35")

    chain_id = if unsigned, do: tx.v, else: if(tx.v >= 35, do: div(tx.v - 35, 2))
    validate_uint!(chain_id || 0, :chain_id, 64)

    base = %{
      "type" => "0x0",
      "chainId" => quantity(chain_id),
      "nonce" => quantity(tx.nonce),
      "gasPrice" => quantity(tx.gas_price),
      "gas" => quantity(tx.gas_limit),
      "to" => hex(tx.to),
      "value" => quantity(tx.value),
      "input" => hex(tx.data)
    }

    if unsigned,
      do: base,
      else: Map.merge(base, %{"r" => quantity(tx.r), "s" => quantity(tx.s), "yParity" => quantity(rem(tx.v + 1, 2))})
  end

  defp to_rpc(tx) do
    params = for {field, key} <- @fields, Map.has_key?(tx, field), into: %{}, do: {key, quantity(Map.fetch!(tx, field))}
    # Retain the existing validation error at the public struct boundary.
    access_list = TypedDecode.encode_access_list(access_list(tx))

    params
    |> Map.merge(%{
      "type" => type(tx.__struct__),
      "to" => hex(tx.destination),
      "input" => hex(tx.data),
      "accessList" => access_list_rpc(access_list)
    })
    |> put_type_fields(tx)
    |> put_signature(tx)
  end

  @spec access_list(struct()) :: list()
  defp access_list(%V4{access_list: nil}), do: []
  defp access_list(tx), do: tx.access_list

  @spec access_list_rpc(list()) :: [map()]
  defp access_list_rpc(access_list) do
    Enum.map(access_list, fn [address, keys] ->
      %{"address" => hex(address), "storageKeys" => Enum.map(keys, &hex/1)}
    end)
  end

  @spec put_type_fields(map(), struct()) :: map()
  defp put_type_fields(params, %V3{blob_versioned_hashes: hashes}) do
    Map.put(params, "blobVersionedHashes", Enum.map(hashes, &hex/1))
  end

  defp put_type_fields(params, %V4{authorization_list: list}) do
    Map.put(params, "authorizationList", Enum.map(list, &authorization_rpc/1))
  end

  defp put_type_fields(params, _tx), do: params

  @spec put_signature(map(), struct()) :: map()
  defp put_signature(params, %{signature_y_parity: nil}), do: params
  defp put_signature(params, %{signature_r: nil}), do: params
  defp put_signature(params, %{signature_s: nil}), do: params

  defp put_signature(params, tx) do
    Map.merge(params, %{
      "yParity" => quantity(if(tx.signature_y_parity, do: 1, else: 0)),
      "r" => quantity(:binary.decode_unsigned(tx.signature_r)),
      "s" => quantity(:binary.decode_unsigned(tx.signature_s))
    })
  end

  @spec authorization_rpc(tuple()) :: map()
  defp authorization_rpc({chain_id, address, nonce, parity, r, s}) do
    validate_uint!(chain_id, :authorization_chain_id, 256)
    validate_uint!(nonce, :authorization_nonce, 64)

    %{
      "chainId" => quantity(chain_id),
      "address" => hex(address),
      "nonce" => quantity(nonce),
      "yParity" => quantity(if(parity, do: 1, else: 0)),
      "r" => quantity(:binary.decode_unsigned(r)),
      "s" => quantity(:binary.decode_unsigned(s))
    }
  end

  @spec validate(struct()) :: :ok | {:error, String.t()}
  defp validate(%V1{r: 0, s: 0, v: chain_id}) when chain_id > 0xFFFFFFFFFFFFFFFF,
    do: {:error, "chain_id must be in 0..2^64-1"}

  defp validate(%V4{authorization_list: list}) when list in [nil, []],
    do: {:error, "authorization_list must not be empty"}

  defp validate(%V3{blob_versioned_hashes: hashes}) do
    if is_list(hashes) and hashes != [] and Enum.all?(hashes, &match?(<<1, _::248>>, &1)),
      do: :ok,
      else: {:error, "blob_versioned_hashes must be a non-empty list of 32-byte hashes prefixed with 0x01"}
  end

  defp validate(_), do: :ok

  @spec type(module()) :: String.t()
  defp type(module), do: "0x#{Enum.find_index(@modules, &(&1 == module))}"

  @spec quantity(integer() | nil) :: String.t() | nil
  defp quantity(nil), do: nil
  defp quantity(value) when is_integer(value) and value >= 0, do: "0x" <> Integer.to_string(value, 16)

  @spec hex(binary() | nil) :: String.t() | nil
  defp hex(nil), do: nil
  defp hex(value), do: Cartouche.Hex.encode_hex(value)
end
