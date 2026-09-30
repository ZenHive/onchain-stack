defmodule Cartouche.Transaction.V4 do
  @moduledoc ~S"""
  Represents a V4 or EIP-7702 set-code transaction.

  EIP-7702 transactions use transaction type `0x04` and extend the EIP-1559
  field set with an authorization list. Each authorization entry is a
  `{chain_id, address, nonce, y_parity, r, s}` tuple signed over
  `0x05 || rlp([chain_id, address, nonce])`.

  ## Examples

      iex> use Cartouche.Hex
      iex> authorization = {
      ...>   1,
      ...>   ~h[0x0000000000000000000000000000000000000002],
      ...>   7,
      ...>   false,
      ...>   <<1::256>>,
      ...>   <<2::256>>
      ...> }
      iex> transaction =
      ...>   Cartouche.Transaction.V4.new(
      ...>     1,
      ...>     {1, :gwei},
      ...>     {100, :gwei},
      ...>     100_000,
      ...>     ~h[0x0000000000000000000000000000000000000001],
      ...>     {2, :wei},
      ...>     <<1, 2, 3>>,
      ...>     [],
      ...>     [authorization],
      ...>     :mainnet
      ...>   )
      ...>   |> Cartouche.Transaction.V4.add_signature(<<3::256, 4::256, 0>>)
      iex> {:ok, decoded} = transaction |> Cartouche.Transaction.V4.encode() |> Cartouche.Transaction.V4.decode()
      iex> decoded == transaction
      true
  """

  alias Cartouche.Signer.Default
  alias Cartouche.Transaction.JsonField
  alias Cartouche.Transaction.Native
  alias Cartouche.Transaction.Signature

  @type authorization :: {
          non_neg_integer(),
          <<_::160>>,
          non_neg_integer(),
          boolean(),
          <<_::256>>,
          <<_::256>>
        }

  @type unsigned_authorization :: {non_neg_integer(), <<_::160>>, non_neg_integer()}
  @type authorization_input :: authorization() | {non_neg_integer(), <<_::160>>, non_neg_integer(), nil, nil, nil}
  @type authorization_list :: nonempty_list(authorization())

  @type t :: %__MODULE__{
          chain_id: non_neg_integer(),
          nonce: non_neg_integer(),
          max_priority_fee_per_gas: non_neg_integer() | nil,
          max_fee_per_gas: non_neg_integer() | nil,
          gas_limit: non_neg_integer(),
          # Wire `to` is `null` for contract creation; the RLP `decode/1`
          # path enforces a 20-byte address, but `from_json/1` (which
          # mirrors the JSON-RPC envelope verbatim) preserves `nil`.
          destination: <<_::160>> | nil,
          amount: non_neg_integer(),
          data: binary(),
          access_list: [{<<_::160>>, [<<_::256>>]}],
          authorization_list: authorization_list(),
          signature_y_parity: boolean() | nil,
          signature_r: <<_::256>> | nil,
          signature_s: <<_::256>> | nil
        }

  defstruct [
    :chain_id,
    :nonce,
    :max_priority_fee_per_gas,
    :max_fee_per_gas,
    :gas_limit,
    :destination,
    :amount,
    :data,
    :access_list,
    :authorization_list,
    :signature_y_parity,
    :signature_r,
    :signature_s
  ]

  @type tx_input ::
          t()
          | %__MODULE__{
              chain_id: non_neg_integer() | nil,
              nonce: non_neg_integer() | nil,
              max_priority_fee_per_gas: non_neg_integer() | nil,
              max_fee_per_gas: non_neg_integer() | nil,
              gas_limit: non_neg_integer() | nil,
              destination: <<_::160>> | nil,
              amount: non_neg_integer() | nil,
              data: binary() | nil,
              access_list: list() | nil,
              authorization_list: list() | nil,
              signature_y_parity: nil,
              signature_r: nil,
              signature_s: nil
            }

  @tx_type 0x04
  @invalid "invalid v4 transaction"

  @doc """
  Constructs an unsigned EIP-7702 transaction.
  """
  @spec new(
          non_neg_integer(),
          non_neg_integer() | {non_neg_integer(), :wei | :gwei} | nil,
          non_neg_integer() | {non_neg_integer(), :wei | :gwei} | nil,
          non_neg_integer(),
          <<_::160>>,
          non_neg_integer() | {non_neg_integer(), :wei | :gwei},
          binary(),
          list(),
          authorization_list(),
          atom() | integer() | nil
        ) :: t()
  def new(
        nonce,
        max_priority_fee_per_gas,
        max_fee_per_gas,
        gas_limit,
        destination,
        amount,
        data,
        access_list,
        authorization_list,
        chain_id \\ nil
      ) do
    %__MODULE__{
      chain_id: Cartouche.Chain.chain_id_value(chain_id),
      nonce: nonce,
      max_priority_fee_per_gas: Cartouche.Wei.maybe_to_wei(max_priority_fee_per_gas),
      max_fee_per_gas: Cartouche.Wei.maybe_to_wei(max_fee_per_gas),
      gas_limit: gas_limit,
      destination: destination,
      amount: Cartouche.Wei.to_wei(amount),
      data: data,
      access_list: access_list,
      authorization_list: authorization_list,
      signature_y_parity: nil,
      signature_r: nil,
      signature_s: nil
    }
  end

  @doc """
  Build an RLP-encoded EIP-7702 transaction.
  """
  @spec encode(tx_input()) :: binary()
  def encode(%__MODULE__{} = transaction), do: Native.encode(transaction)

  @doc """
  Decode an RLP-encoded EIP-7702 transaction.
  """
  @spec decode(binary()) :: {:ok, t()} | {:error, String.t()}
  def decode(input), do: Native.decode(input, __MODULE__, @invalid)

  @doc """
  Signs the outer EIP-7702 transaction.
  """
  @spec sign(t(), GenServer.server()) :: {:ok, t()} | {:error, String.t()}
  def sign(%__MODULE__{} = transaction, signer \\ Default) do
    with {:ok, signature} <- Native.sign(transaction, signer, chain_id: transaction.chain_id) do
      {:ok, add_signature(transaction, signature)}
    end
  end

  @doc """
  Returns the transaction hash for signed or unsigned encoded bytes.
  """
  @spec hash(t() | binary()) :: <<_::256>>
  def hash(%__MODULE__{} = transaction), do: transaction |> encode() |> Cartouche.Hash.keccak()
  def hash(<<@tx_type, _::binary>> = encoded), do: Cartouche.Hash.keccak(encoded)

  @doc """
  Returns the outer transaction signing payload.
  """
  @spec signing_payload(t()) :: binary()
  def signing_payload(%__MODULE__{} = transaction) do
    encode(%{transaction | signature_y_parity: nil, signature_r: nil, signature_s: nil})
  end

  @doc """
  Adds an outer transaction signature from a packed binary (`r <> s <> v`).
  """
  @spec add_signature(t(), <<_::520, _::_*8>>) :: t()
  def add_signature(%__MODULE__{} = transaction, signature), do: Signature.add_packed(transaction, signature)

  @doc """
  Recovers the signer from a signed EIP-7702 transaction.
  """
  @spec recover_signer(t()) :: {:ok, <<_::160>>} | {:error, String.t()}
  def recover_signer(%__MODULE__{} = transaction) do
    with {:ok, signature} <- get_signature(transaction) do
      {:ok, Cartouche.Recover.recover_eth(signing_payload(transaction), signature)}
    end
  end

  @doc """
  Recovers a packed outer transaction signature (`r <> s <> y_parity`).
  """
  @spec get_signature(t()) :: {:ok, binary()} | {:error, String.t()}
  def get_signature(%__MODULE__{} = transaction), do: Signature.get(transaction)

  @doc """
  Signs an EIP-7702 authorization tuple.
  """
  @spec sign_authorization(unsigned_authorization(), GenServer.server()) ::
          {:ok, authorization()} | {:error, String.t()}
  def sign_authorization({chain_id, address, nonce} = authorization, signer \\ Default) do
    with {:ok, signature} <-
           Cartouche.Signer.sign_digest(
             authorization_hash(authorization),
             authorization_signing_payload(authorization),
             signer,
             chain_id: chain_id
           ) do
      {:ok, add_authorization_signature({chain_id, address, nonce, nil, nil, nil}, signature)}
    end
  end

  @doc """
  Returns the EIP-7702 authorization signing payload.
  """
  @spec authorization_signing_payload(unsigned_authorization() | authorization()) :: binary()
  def authorization_signing_payload(authorization) do
    Native.authorization("authorization_encode", authorization_core(authorization))
  end

  @doc """
  Returns the EIP-7702 authorization signing hash.
  """
  @spec authorization_hash(unsigned_authorization() | authorization()) :: <<_::256>>
  def authorization_hash(authorization), do: Native.authorization("authorization_hash", authorization_core(authorization))

  @doc """
  Adds an authorization signature from a packed binary (`r <> s <> v`).
  """
  @spec add_authorization_signature(authorization_input(), <<_::520, _::_*8>>) :: authorization()
  def add_authorization_signature(
        {chain_id, address, nonce, _v, _r, _s},
        <<r::binary-size(32), s::binary-size(32), v_bin::binary>>
      )
      when byte_size(v_bin) > 0 do
    {chain_id, address, nonce, Signature.y_parity_from_v(v_bin), r, s}
  end

  @doc """
  Recovers the EOA that signed an authorization tuple.
  """
  @spec recover_authority(authorization()) :: {:ok, <<_::160>>} | {:error, String.t()}
  def recover_authority(authorization) do
    with {:ok, signature} <- get_authorization_signature(authorization) do
      {:ok, Cartouche.Recover.recover_eth(authorization_signing_payload(authorization), signature)}
    end
  end

  @doc """
  Returns a packed authorization signature (`r <> s <> y_parity`).
  """
  @spec get_authorization_signature(authorization()) :: {:ok, binary()} | {:error, String.t()}
  def get_authorization_signature({_chain_id, _address, _nonce, v, r, s}) do
    case Signature.pack(v, r, s) do
      {:ok, packed} -> {:ok, packed}
      {:error, :missing} -> {:error, "authorization missing signature"}
    end
  end

  @doc ~S"""
  Decodes an EIP-7702 (type 4) set-code transaction object as returned in
  the `transactions` array of `eth_getBlockByNumber` /
  `eth_getBlockByHash` when `include_transaction_details: true` is
  requested.

  Mirrors `Cartouche.Transaction.V2.from_json/1` plus the
  `authorizationList` — each entry decoded into the
  `{chain_id, address, nonce, y_parity, r, s}` tuple shape used by
  `Cartouche.Transaction.V4`.

  ## Examples

      iex> use Cartouche.Hex
      iex> %{
      ...>   "type" => "0x4",
      ...>   "chainId" => "0x1",
      ...>   "nonce" => "0x1",
      ...>   "maxPriorityFeePerGas" => "0x3b9aca00",
      ...>   "maxFeePerGas" => "0x174876e800",
      ...>   "gas" => "0x186a0",
      ...>   "to" => "0x0000000000000000000000000000000000000001",
      ...>   "value" => "0x2",
      ...>   "input" => "0x010203",
      ...>   "accessList" => [],
      ...>   "authorizationList" => [
      ...>     %{
      ...>       "chainId" => "0x1",
      ...>       "address" => "0x0000000000000000000000000000000000000002",
      ...>       "nonce" => "0x7",
      ...>       "yParity" => "0x0",
      ...>       "r" => "0x1",
      ...>       "s" => "0x2"
      ...>     }
      ...>   ],
      ...>   "yParity" => "0x1",
      ...>   "r" => "0x1",
      ...>   "s" => "0x2"
      ...> }
      ...> |> Cartouche.Transaction.V4.from_json()
      ...> |> Map.take([:chain_id, :destination, :authorization_list, :signature_y_parity])
      %{
        chain_id: 1,
        destination: ~h[0x0000000000000000000000000000000000000001],
        authorization_list: [
          {1, ~h[0x0000000000000000000000000000000000000002], 7, false, <<1::256>>, <<2::256>>}
        ],
        signature_y_parity: true
      }
  """
  @spec from_json(map()) :: t() | no_return()
  def from_json(%{} = params) do
    %__MODULE__{
      chain_id: Cartouche.Hex.decode_hex_number!(params["chainId"]),
      nonce: Cartouche.Hex.decode_hex_number!(params["nonce"]),
      max_priority_fee_per_gas: Cartouche.Hex.decode_hex_number!(params["maxPriorityFeePerGas"]),
      max_fee_per_gas: Cartouche.Hex.decode_hex_number!(params["maxFeePerGas"]),
      gas_limit: Cartouche.Hex.decode_hex_number!(params["gas"]),
      destination: JsonField.decode_destination(params["to"]),
      amount: Cartouche.Hex.decode_hex_number!(params["value"]),
      data: Cartouche.Hex.decode_hex!(params["input"]),
      access_list: JsonField.decode_access_list(params["accessList"]),
      authorization_list: JsonField.decode_authorization_list(params["authorizationList"]),
      signature_y_parity: JsonField.decode_y_parity(params),
      signature_r: JsonField.decode_signature_word(params["r"]),
      signature_s: JsonField.decode_signature_word(params["s"])
    }
  end

  @spec authorization_core(unsigned_authorization() | authorization()) :: unsigned_authorization()
  defp authorization_core({chain_id, address, nonce}), do: {chain_id, address, nonce}
  defp authorization_core({chain_id, address, nonce, _y_parity, _r, _s}), do: {chain_id, address, nonce}
end
