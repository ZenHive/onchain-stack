# credo:disable-for-this-file Credo.Check.Readability.ModuleNames
defmodule Cartouche.Transaction.V_2930 do
  @moduledoc ~S"""
  Represents a type-1 EIP-2930 access-list transaction.

  ## Examples

      iex> tx =
      ...>   Cartouche.Transaction.V_2930.new(
      ...>     1,
      ...>     {1, :gwei},
      ...>     100_000,
      ...>     <<1::160>>,
      ...>     {2, :wei},
      ...>     <<1, 2, 3>>,
      ...>     [],
      ...>     :goerli
      ...>   )
      ...> tx = Cartouche.Transaction.V_2930.add_signature(tx, true, <<0x01::256>>, <<0x02::256>>)
      iex> {:ok, decoded} = tx |> Cartouche.Transaction.V_2930.encode() |> Cartouche.Transaction.V_2930.decode()
      iex> decoded == tx
      true
  """

  alias Cartouche.Signer.Default
  alias Cartouche.Transaction.JsonField
  alias Cartouche.Transaction.Signature
  alias Cartouche.Transaction.TypedDecode

  @type access_list :: [{<<_::160>>, [<<_::256>>]}]

  @type t :: %__MODULE__{
          chain_id: non_neg_integer(),
          nonce: non_neg_integer(),
          gas_price: non_neg_integer(),
          gas_limit: non_neg_integer(),
          destination: <<_::160>> | nil,
          amount: non_neg_integer(),
          data: binary(),
          access_list: access_list(),
          signature_y_parity: boolean() | nil,
          signature_r: <<_::256>> | nil,
          signature_s: <<_::256>> | nil
        }

  defstruct [
    :chain_id,
    :nonce,
    :gas_price,
    :gas_limit,
    :destination,
    :amount,
    :data,
    :access_list,
    :signature_y_parity,
    :signature_r,
    :signature_s
  ]

  @tx_type 0x01
  @invalid "invalid v2930 transaction"

  @doc """
  Constructs an unsigned EIP-2930 access-list transaction.
  """
  @spec new(
          non_neg_integer(),
          non_neg_integer() | {non_neg_integer(), :wei | :gwei},
          non_neg_integer(),
          <<_::160>>,
          non_neg_integer() | {non_neg_integer(), :wei | :gwei},
          binary(),
          access_list(),
          atom() | integer() | nil
        ) :: t()
  def new(nonce, gas_price, gas_limit, destination, amount, data, access_list, chain_id \\ nil) do
    %__MODULE__{
      chain_id: Cartouche.Chain.chain_id_value(chain_id),
      nonce: nonce,
      gas_price: Cartouche.Wei.to_wei(gas_price),
      gas_limit: gas_limit,
      destination: destination,
      amount: Cartouche.Wei.to_wei(amount),
      data: data,
      access_list: access_list,
      signature_y_parity: nil,
      signature_r: nil,
      signature_s: nil
    }
  end

  @doc """
  Build an EIP-2718 typed RLP-encoded access-list transaction.

  Signed payloads are `0x01 || rlp([chainId, nonce, gasPrice, gasLimit, to,
  value, data, accessList, yParity, r, s])` per EIP-2930. If any signature
  field is `nil`, the encoded payload omits `yParity`, `r`, and `s` and is the
  signing preimage `0x01 || rlp([chainId, nonce, gasPrice, gasLimit, to, value,
  data, accessList])`.
  """
  @spec encode(t()) :: binary()
  def encode(%__MODULE__{} = transaction) do
    <<@tx_type>> <> ExRLP.encode(encoded_fields(transaction))
  end

  @doc """
  Decodes an EIP-2930 typed RLP transaction.
  """
  @spec decode(binary()) :: {:ok, t()} | {:error, String.t()}
  def decode(input), do: TypedDecode.decode(input, @tx_type, @invalid, &decode_fields/1)

  @doc ~S"""
  Decodes an EIP-2930 (type 1) transaction object from block JSON-RPC.
  """
  @spec from_json(map()) :: t() | no_return()
  def from_json(%{} = params) do
    %__MODULE__{
      chain_id: Cartouche.Hex.decode_hex_number!(params["chainId"]),
      nonce: Cartouche.Hex.decode_hex_number!(params["nonce"]),
      gas_price: Cartouche.Hex.decode_hex_number!(params["gasPrice"]),
      gas_limit: Cartouche.Hex.decode_hex_number!(params["gas"]),
      destination: JsonField.decode_destination(params["to"]),
      amount: Cartouche.Hex.decode_hex_number!(params["value"]),
      data: Cartouche.Hex.decode_hex!(params["input"]),
      access_list: JsonField.decode_access_list(params["accessList"]),
      signature_y_parity: JsonField.decode_y_parity(params),
      signature_r: JsonField.decode_signature_word(params["r"]),
      signature_s: JsonField.decode_signature_word(params["s"])
    }
  end

  @spec decode_fields(term()) :: {:ok, t()} | {:error, String.t()}
  defp decode_fields([_, _, _, _, _, _, _, _] = fields) do
    decode_payload(fields, {nil, nil, nil})
  end

  defp decode_fields([
         chain_id,
         nonce,
         gas_price,
         gas_limit,
         destination,
         amount,
         data,
         access_list,
         signature_y_parity,
         signature_r,
         signature_s
       ]) do
    with {:ok, signature_y_parity} <- TypedDecode.decode_y_parity(signature_y_parity, @invalid),
         {:ok, signature_r} <- TypedDecode.decode_word(signature_r, @invalid),
         {:ok, signature_s} <- TypedDecode.decode_word(signature_s, @invalid) do
      decode_payload(
        [chain_id, nonce, gas_price, gas_limit, destination, amount, data, access_list],
        {signature_y_parity, signature_r, signature_s}
      )
    else
      _ -> {:error, @invalid}
    end
  end

  defp decode_fields(_), do: {:error, @invalid}

  @doc """
  Signs a type-1 transaction with the given signer process.
  """
  @spec sign(t(), GenServer.server()) :: {:ok, t()} | {:error, String.t()}
  def sign(%__MODULE__{} = transaction, signer \\ Default) do
    payload = encode(%{transaction | signature_y_parity: nil, signature_r: nil, signature_s: nil})

    with {:ok, signature} <- Cartouche.Signer.sign(payload, signer, chain_id: transaction.chain_id) do
      {:ok, add_signature(transaction, signature)}
    end
  end

  @doc """
  Hashes the typed transaction bytes.
  """
  @spec hash(t()) :: <<_::256>>
  def hash(%__MODULE__{} = transaction), do: Cartouche.Hash.keccak(encode(transaction))

  @doc """
  Adds explicit signature fields to a transaction.
  """
  @spec add_signature(t(), boolean(), <<_::256>>, <<_::256>>) :: t()
  def add_signature(%__MODULE__{} = transaction, v, r, s) when is_boolean(v) do
    Signature.add(transaction, v, r, s)
  end

  @doc """
  Adds a signature to a transaction from a packed binary (`r <> s <> v`).
  """
  @spec add_signature(t(), <<_::512, _::_*8>>) :: t()
  def add_signature(%__MODULE__{} = transaction, signature) when is_binary(signature) do
    Signature.add_packed(transaction, signature)
  end

  @doc """
  Recovers a signature from a transaction, if it has been signed.
  """
  @spec get_signature(t()) :: {:ok, binary()} | {:error, String.t()}
  def get_signature(%__MODULE__{signature_y_parity: _, signature_r: _, signature_s: _} = transaction) do
    Signature.get(transaction)
  end

  @doc """
  Recovers the signer from a signed type-1 transaction.
  """
  @spec recover_signer(t()) :: {:ok, <<_::160>>} | {:error, String.t()}
  def recover_signer(%__MODULE__{} = transaction) do
    payload = encode(%{transaction | signature_y_parity: nil, signature_r: nil, signature_s: nil})

    with {:ok, signature} <- get_signature(transaction) do
      {:ok, Cartouche.Recover.recover_eth(payload, signature)}
    end
  end

  @spec decode_payload(
          [term()],
          {boolean() | nil, <<_::256>> | nil, <<_::256>> | nil}
        ) :: {:ok, t()} | {:error, String.t()}
  defp decode_payload(
         [chain_id, nonce, gas_price, gas_limit, destination, amount, data, access_list],
         {signature_y_parity, signature_r, signature_s}
       )
       when is_binary(data) do
    with true <- byte_size(destination) == 20,
         {:ok, access_list} <- TypedDecode.decode_access_list(access_list, @invalid) do
      {:ok,
       %__MODULE__{
         chain_id: :binary.decode_unsigned(chain_id),
         nonce: :binary.decode_unsigned(nonce),
         gas_price: :binary.decode_unsigned(gas_price),
         gas_limit: :binary.decode_unsigned(gas_limit),
         destination: destination,
         amount: :binary.decode_unsigned(amount),
         data: data,
         access_list: access_list,
         signature_y_parity: signature_y_parity,
         signature_r: signature_r,
         signature_s: signature_s
       }}
    else
      _ -> {:error, @invalid}
    end
  rescue
    # `:binary.decode_unsigned/1` and `byte_size/1` raise ArgumentError on the
    # non-binary terms a malformed RLP payload can yield; helpers return
    # `{:error, …}` rather than raising.
    ArgumentError -> {:error, @invalid}
  end

  defp decode_payload(_, _), do: {:error, @invalid}

  @spec encoded_fields(t()) :: list()
  defp encoded_fields(%__MODULE__{} = tx) do
    [
      tx.chain_id,
      tx.nonce,
      tx.gas_price,
      tx.gas_limit,
      tx.destination,
      tx.amount,
      tx.data,
      TypedDecode.encode_access_list(tx.access_list)
    ] ++ maybe_signature_rlp(tx)
  end

  @spec maybe_signature_rlp(t()) :: list()
  defp maybe_signature_rlp(%__MODULE__{signature_y_parity: y_parity, signature_r: r, signature_s: s})
       when is_nil(y_parity) or is_nil(r) or is_nil(s) do
    []
  end

  defp maybe_signature_rlp(%__MODULE__{signature_y_parity: y_parity, signature_r: r, signature_s: s}) do
    [if(y_parity, do: 1, else: 0), String.trim_leading(r, <<0>>), String.trim_leading(s, <<0>>)]
  end
end
