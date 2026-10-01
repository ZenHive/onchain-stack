# credo:disable-for-this-file Credo.Check.Readability.ModuleNames
defmodule Onchain.Transaction.V_2930 do
  @moduledoc ~S"""
  Represents a type-1 EIP-2930 access-list transaction.

  ## Examples

      iex> tx =
      ...>   Onchain.Transaction.V_2930.new(
      ...>     1,
      ...>     {1, :gwei},
      ...>     100_000,
      ...>     <<1::160>>,
      ...>     {2, :wei},
      ...>     <<1, 2, 3>>,
      ...>     [],
      ...>     :goerli
      ...>   )
      ...> tx = Onchain.Transaction.V_2930.add_signature(tx, true, <<0x01::256>>, <<0x02::256>>)
      iex> {:ok, decoded} = tx |> Onchain.Transaction.V_2930.encode() |> Onchain.Transaction.V_2930.decode()
      iex> decoded == tx
      true
  """

  alias Onchain.Signer.Default
  alias Onchain.Transaction.JsonField
  alias Onchain.Transaction.Native
  alias Onchain.Transaction.Signature

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
      chain_id: Onchain.Chain.chain_id_value(chain_id),
      nonce: nonce,
      gas_price: Onchain.Wei.to_wei(gas_price),
      gas_limit: gas_limit,
      destination: destination,
      amount: Onchain.Wei.to_wei(amount),
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
  def encode(%__MODULE__{} = transaction), do: Native.encode(transaction)

  @doc """
  Decodes an EIP-2930 typed RLP transaction.
  """
  @spec decode(binary()) :: {:ok, t()} | {:error, String.t()}
  def decode(input), do: Native.decode(input, __MODULE__, @invalid)

  @doc ~S"""
  Decodes an EIP-2930 (type 1) transaction object from block JSON-RPC.
  """
  @spec from_json(map()) :: t() | no_return()
  def from_json(%{} = params) do
    %__MODULE__{
      chain_id: Onchain.Hex.decode_hex_number!(params["chainId"]),
      nonce: Onchain.Hex.decode_hex_number!(params["nonce"]),
      gas_price: Onchain.Hex.decode_hex_number!(params["gasPrice"]),
      gas_limit: Onchain.Hex.decode_hex_number!(params["gas"]),
      destination: JsonField.decode_destination(params["to"]),
      amount: Onchain.Hex.decode_hex_number!(params["value"]),
      data: Onchain.Hex.decode_hex!(params["input"]),
      access_list: JsonField.decode_access_list(params["accessList"]),
      signature_y_parity: JsonField.decode_y_parity(params),
      signature_r: JsonField.decode_signature_word(params["r"]),
      signature_s: JsonField.decode_signature_word(params["s"])
    }
  end

  @doc """
  Signs a type-1 transaction with the given signer process.
  """
  @spec sign(t(), GenServer.server()) :: {:ok, t()} | {:error, String.t()}
  def sign(%__MODULE__{} = transaction, signer \\ Default) do
    Signature.sign(transaction, signer)
  end

  @doc """
  Hashes the typed transaction bytes.
  """
  @spec hash(t()) :: <<_::256>>
  def hash(%__MODULE__{} = transaction), do: Onchain.Hash.keccak(encode(transaction))

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
      {:ok, Onchain.Recover.recover_eth(payload, signature)}
    end
  end
end
