defmodule Cartouche.Transaction.V3 do
  @moduledoc ~S"""
  Represents a V3 or EIP-4844 blob transaction.

  This module encodes the execution-layer transaction envelope only. Blob
  sidecars (blobs, KZG commitments, and KZG proofs) are propagated separately
  and are not part of the canonical signed transaction bytes.

  ## Examples

      iex> tx =
      ...>   Cartouche.Transaction.V3.new(
      ...>     1,
      ...>     {1, :gwei},
      ...>     {100, :gwei},
      ...>     100_000,
      ...>     <<1::160>>,
      ...>     {2, :wei},
      ...>     <<1, 2, 3>>,
      ...>     [],
      ...>     {1, :wei},
      ...>     [<<1, 0::248>>],
      ...>     :goerli
      ...>   )
      ...> tx = Cartouche.Transaction.V3.add_signature(tx, true, <<0x01::256>>, <<0x02::256>>)
      iex> {:ok, decoded} = tx |> Cartouche.Transaction.V3.encode() |> Cartouche.Transaction.V3.decode()
      iex> decoded == tx
      true
  """

  alias Cartouche.Signer.Default
  alias Cartouche.Transaction.JsonField
  alias Cartouche.Transaction.Signature
  alias Cartouche.Transaction.TypedDecode

  @tx_type 0x03
  @invalid "invalid v3 transaction"
  @invalid_blob_versioned_hashes "blob_versioned_hashes must be a non-empty list of 32-byte hashes prefixed with 0x01"
  @versioned_hash_version_kzg <<0x01>>

  @type access_list :: [{<<_::160>>, [<<_::256>>]}]
  @type blob_versioned_hashes :: list(<<_::256>>)
  @type encodable_blob_versioned_hashes :: nonempty_list(<<_::256>>)

  @type t :: %__MODULE__{
          chain_id: integer(),
          nonce: integer(),
          max_priority_fee_per_gas: integer(),
          max_fee_per_gas: integer(),
          gas_limit: integer(),
          # Wire `to` is `null` for contract creation; the RLP `decode/1`
          # path enforces a 20-byte address, but `from_json/1` (which
          # mirrors the JSON-RPC envelope verbatim) preserves `nil`.
          destination: <<_::160>> | nil,
          amount: integer(),
          data: binary(),
          access_list: access_list(),
          max_fee_per_blob_gas: integer(),
          blob_versioned_hashes: blob_versioned_hashes(),
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
    :max_fee_per_blob_gas,
    :blob_versioned_hashes,
    :signature_y_parity,
    :signature_r,
    :signature_s
  ]

  @doc ~S"""
  Constructs a new V3 (EIP-4844) Ethereum transaction.
  """
  @spec new(
          integer(),
          integer() | {integer(), :wei | :gwei} | nil,
          integer() | {integer(), :wei | :gwei} | nil,
          integer(),
          <<_::160>>,
          integer() | {integer(), :wei | :gwei},
          binary(),
          access_list(),
          integer() | {integer(), :wei | :gwei} | nil,
          blob_versioned_hashes(),
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
        max_fee_per_blob_gas,
        blob_versioned_hashes,
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
      max_fee_per_blob_gas: Cartouche.Wei.maybe_to_wei(max_fee_per_blob_gas),
      blob_versioned_hashes: blob_versioned_hashes,
      signature_y_parity: nil,
      signature_r: nil,
      signature_s: nil
    }
  end

  @doc ~S"""
  Build an EIP-2718 typed RLP-encoded blob transaction.

  If any signature field is `nil`, the encoded payload omits
  `signature_y_parity`, `signature_r`, and `signature_s` and can be used as the
  signing preimage.
  """
  @spec encode(t()) :: binary()
  def encode(%__MODULE__{} = transaction) do
    <<0x03>> <>
      (transaction
       |> rlp_payload()
       |> ExRLP.encode())
  end

  @doc """
  Decode an EIP-4844 blob transaction envelope.

  Accepts both signed transaction bytes and unsigned signing preimages. Unsigned
  payloads omit `signature_y_parity`, `signature_r`, and `signature_s`; the
  decoded struct sets those fields to `nil`.
  """
  @spec decode(binary()) :: {:ok, t()} | {:error, String.t()}
  def decode(input), do: TypedDecode.decode(input, @tx_type, @invalid, &decode_fields/1)

  @spec decode_fields(term()) :: {:ok, t()} | {:error, String.t()}
  defp decode_fields([_, _, _, _, _, _, _, _, _, _, _] = fields) do
    decode_payload(fields, {nil, nil, nil})
  end

  defp decode_fields([
         chain_id,
         nonce,
         max_priority_fee_per_gas,
         max_fee_per_gas,
         gas_limit,
         destination,
         amount,
         data,
         access_list,
         max_fee_per_blob_gas,
         blob_versioned_hashes,
         signature_y_parity,
         signature_r,
         signature_s
       ]) do
    fields = [
      chain_id,
      nonce,
      max_priority_fee_per_gas,
      max_fee_per_gas,
      gas_limit,
      destination,
      amount,
      data,
      access_list,
      max_fee_per_blob_gas,
      blob_versioned_hashes
    ]

    with {:ok, signature_y_parity} <- TypedDecode.decode_y_parity(signature_y_parity, @invalid),
         {:ok, signature_r} <- TypedDecode.decode_word(signature_r, @invalid),
         {:ok, signature_s} <- TypedDecode.decode_word(signature_s, @invalid) do
      decode_payload(fields, {signature_y_parity, signature_r, signature_s})
    else
      _ -> {:error, @invalid}
    end
  end

  defp decode_fields(_), do: {:error, @invalid}

  @doc """
  Signs a V3 transaction with the given signer process.
  """
  @spec sign(t(), GenServer.server()) :: {:ok, t()} | {:error, String.t()}
  def sign(%__MODULE__{} = transaction, signer \\ Default) do
    unsigned = %{transaction | signature_y_parity: nil, signature_r: nil, signature_s: nil}

    with {:ok, signature} <- Cartouche.Signer.sign(encode(unsigned), signer, chain_id: transaction.chain_id) do
      {:ok, add_signature(transaction, signature)}
    end
  end

  @doc """
  Hashes the typed transaction bytes.
  """
  @spec hash(t()) :: <<_::256>>
  def hash(%__MODULE__{} = transaction), do: transaction |> encode() |> Cartouche.Hash.keccak()

  @doc """
  Adds explicit signature fields to a transaction.
  """
  @spec add_signature(t(), boolean(), <<_::256>>, <<_::256>>) :: t()
  def add_signature(%__MODULE__{} = transaction, v, r, s), do: Signature.add(transaction, v, r, s)

  @doc """
  Adds a signature to a transaction from a packed binary (`r <> s <> v`).
  """
  @spec add_signature(t(), <<_::512, _::_*8>>) :: t()
  def add_signature(%__MODULE__{} = transaction, signature), do: Signature.add_packed(transaction, signature)

  @doc """
  Recovers a signature from a transaction, if it has been signed.
  """
  @spec get_signature(t()) :: {:ok, binary()} | {:error, String.t()}
  def get_signature(%__MODULE__{} = transaction), do: Signature.get(transaction)

  @doc """
  Recovers the signer from a signed V3 transaction.
  """
  @spec recover_signer(t()) :: {:ok, <<_::160>>} | {:error, String.t()}
  def recover_signer(%__MODULE__{} = transaction) do
    unsigned = %{transaction | signature_y_parity: nil, signature_r: nil, signature_s: nil}

    with {:ok, signature} <- get_signature(transaction) do
      {:ok, Cartouche.Recover.recover_eth(encode(unsigned), signature)}
    end
  end

  @doc ~S"""
  Decodes an EIP-4844 (type 3) blob transaction object as returned in the
  `transactions` array of `eth_getBlockByNumber` / `eth_getBlockByHash`
  when `include_transaction_details: true` is requested.

  Mirrors `Cartouche.Transaction.V2.from_json/1` plus `maxFeePerBlobGas`
  and `blobVersionedHashes` (the blob sidecar — blobs/commitments/proofs —
  is propagated separately and is not part of the block JSON).

  ## Examples

      iex> use Cartouche.Hex
      iex> %{
      ...>   "type" => "0x3",
      ...>   "chainId" => "0x1",
      ...>   "nonce" => "0x1",
      ...>   "maxPriorityFeePerGas" => "0x3b9aca00",
      ...>   "maxFeePerGas" => "0x174876e800",
      ...>   "gas" => "0x186a0",
      ...>   "to" => "0x0000000000000000000000000000000000000001",
      ...>   "value" => "0x2",
      ...>   "input" => "0x010203",
      ...>   "accessList" => [],
      ...>   "maxFeePerBlobGas" => "0x1",
      ...>   "blobVersionedHashes" => [
      ...>     "0x0100000000000000000000000000000000000000000000000000000000000000"
      ...>   ],
      ...>   "yParity" => "0x1",
      ...>   "r" => "0x1",
      ...>   "s" => "0x2"
      ...> }
      ...> |> Cartouche.Transaction.V3.from_json()
      ...> |> Map.take([:chain_id, :destination, :max_fee_per_blob_gas, :blob_versioned_hashes, :signature_y_parity])
      %{
        chain_id: 1,
        destination: ~h[0x0000000000000000000000000000000000000001],
        max_fee_per_blob_gas: 1,
        blob_versioned_hashes: [
          ~h[0x0100000000000000000000000000000000000000000000000000000000000000]
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
      max_fee_per_blob_gas: Cartouche.Hex.decode_hex_number!(params["maxFeePerBlobGas"]),
      blob_versioned_hashes: JsonField.decode_blob_versioned_hashes(params["blobVersionedHashes"]),
      signature_y_parity: JsonField.decode_y_parity(params),
      signature_r: JsonField.decode_signature_word(params["r"]),
      signature_s: JsonField.decode_signature_word(params["s"])
    }
  end

  @spec rlp_payload(t()) :: list()
  defp rlp_payload(%__MODULE__{} = transaction) do
    base_payload(transaction) ++ signature_payload(transaction)
  end

  @spec base_payload(t()) :: list()
  defp base_payload(%__MODULE__{} = transaction) do
    [
      transaction.chain_id,
      transaction.nonce,
      transaction.max_priority_fee_per_gas,
      transaction.max_fee_per_gas,
      transaction.gas_limit,
      transaction.destination,
      transaction.amount,
      transaction.data,
      TypedDecode.encode_access_list(transaction.access_list),
      transaction.max_fee_per_blob_gas,
      encode_blob_versioned_hashes(transaction.blob_versioned_hashes)
    ]
  end

  @spec signature_payload(t()) :: list()
  defp signature_payload(%__MODULE__{signature_y_parity: v, signature_r: r, signature_s: s})
       when is_nil(v) or is_nil(r) or is_nil(s), do: []

  defp signature_payload(%__MODULE__{signature_y_parity: v, signature_r: r, signature_s: s}) do
    [if(v, do: 1, else: 0), trim_signature_word(r), trim_signature_word(s)]
  end

  @spec encode_blob_versioned_hashes(term()) :: encodable_blob_versioned_hashes()
  defp encode_blob_versioned_hashes(blob_versioned_hashes) do
    if valid_blob_versioned_hashes?(blob_versioned_hashes) do
      blob_versioned_hashes
    else
      raise ArgumentError, @invalid_blob_versioned_hashes
    end
  end

  @spec trim_signature_word(<<_::256>>) :: binary()
  defp trim_signature_word(signature_word), do: String.trim_leading(signature_word, <<0>>)

  @spec decode_payload(
          [term()],
          {boolean() | nil, <<_::256>> | nil, <<_::256>> | nil}
        ) :: {:ok, t()} | {:error, String.t()}
  defp decode_payload(
         [
           chain_id,
           nonce,
           max_priority_fee_per_gas,
           max_fee_per_gas,
           gas_limit,
           destination,
           amount,
           data,
           access_list,
           max_fee_per_blob_gas,
           blob_versioned_hashes
         ],
         {signature_y_parity, signature_r, signature_s}
       )
       when is_binary(data) do
    with true <- byte_size(destination) == 20,
         {:ok, access_list} <- TypedDecode.decode_access_list(access_list, @invalid),
         {:ok, blob_versioned_hashes} <- decode_blob_versioned_hashes(blob_versioned_hashes) do
      {:ok,
       %__MODULE__{
         chain_id: :binary.decode_unsigned(chain_id),
         nonce: :binary.decode_unsigned(nonce),
         max_priority_fee_per_gas: :binary.decode_unsigned(max_priority_fee_per_gas),
         max_fee_per_gas: :binary.decode_unsigned(max_fee_per_gas),
         gas_limit: :binary.decode_unsigned(gas_limit),
         destination: destination,
         amount: :binary.decode_unsigned(amount),
         data: data,
         access_list: access_list,
         max_fee_per_blob_gas: :binary.decode_unsigned(max_fee_per_blob_gas),
         blob_versioned_hashes: blob_versioned_hashes,
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

  @spec decode_blob_versioned_hashes(term()) :: {:ok, encodable_blob_versioned_hashes()} | {:error, String.t()}
  defp decode_blob_versioned_hashes(blob_versioned_hashes) do
    if valid_blob_versioned_hashes?(blob_versioned_hashes) do
      {:ok, blob_versioned_hashes}
    else
      {:error, @invalid}
    end
  end

  @spec valid_blob_versioned_hashes?(term()) :: boolean()
  defp valid_blob_versioned_hashes?([_hash | _rest] = blob_versioned_hashes) do
    Enum.all?(blob_versioned_hashes, fn hash ->
      is_binary(hash) and byte_size(hash) == 32 and binary_part(hash, 0, 1) == @versioned_hash_version_kzg
    end)
  end

  defp valid_blob_versioned_hashes?(_), do: false
end
