defmodule Cartouche.Transaction do
  @moduledoc """
  Build, sign, and encode Ethereum transactions.

  Encode/decode invariant for every envelope (`V1`, `V_2930`, `V2`, `V3`,
  `V4`): anything `encode/1` accepts must round-trip through that envelope's
  `decode/1` to an equal struct and match the EIP wire shape. EIP-2930
  access-list items are `[address, storage_keys]`; EIP-4844 requires a
  non-empty `blob_versioned_hashes` whose entries begin with
  `VERSIONED_HASH_VERSION_KZG` `0x01`; EIP-7702 forbids an empty
  `authorization_list`.
  """

  use Descripex, namespace: "/ethereum/transaction"

  alias Cartouche.Signer.Default
  alias Cartouche.Transaction.Signature
  alias Cartouche.Transaction.V3
  alias Cartouche.Transaction.V4
  alias Cartouche.Transaction.V_2930

  defmodule V1 do
    @moduledoc """
    Represents a V1 or "Legacy" (that is, pre-EIP-1559) transaction.
    """

    use Descripex, namespace: "/ethereum/transaction/v1"

    @type t :: %__MODULE__{
            nonce: integer(),
            gas_price: integer(),
            gas_limit: integer(),
            # Wire `to` is `null` for contract creation; the RLP `decode/1`
            # path enforces a 20-byte address, but `from_json/1` (which
            # mirrors the JSON-RPC envelope verbatim) preserves `nil`.
            to: <<_::160>> | nil,
            value: integer(),
            data: binary(),
            # Non-nilable, and `v` is never "unset": until a signature replaces
            # it, `v` carries the chain id with `r`/`s` zero, which is exactly
            # EIP-155's `[chain_id, 0, 0]` signing payload. A nil here would
            # encode as the pre-EIP-155 `[0, 0, 0]` and any signature taken over
            # that payload recovers to the wrong address.
            v: integer(),
            r: integer(),
            s: integer()
          }

    defstruct [
      :nonce,
      :gas_price,
      :gas_limit,
      :to,
      :value,
      :data,
      :v,
      :r,
      :s
    ]

    api(:new, "Construct a legacy/EIP-155-style transaction struct.",
      params: [
        nonce: [
          kind: :exchange_data,
          source: "Cartouche.RPC.get_transaction_count/2",
          description: "Account nonce for the sender."
        ],
        gas_price: [
          kind: :exchange_data,
          source: "Cartouche.RPC.gas_price/1",
          description: "Legacy gas price as wei or `{amount, :wei | :gwei}`; `nil` leaves it unset."
        ],
        gas_limit: [
          kind: :exchange_data,
          source: "Cartouche.RPC.estimate_gas/2",
          description: "Maximum gas units the transaction may consume."
        ],
        to: [kind: :value, description: "20-byte destination address."],
        value: [
          kind: :value,
          description:
            "Ether value as an integer of wei or `{amount, :wei | :gwei}` (matches V1 `@spec` and the `{2, :wei}` doctest example)."
        ],
        data: [kind: :value, description: "Contract calldata or raw transaction input bytes."],
        chain_id: [
          kind: :exchange_data,
          source: "Cartouche.RPC.eth_chain_id/1",
          default: nil,
          description: "Ethereum chain id atom/integer; defaults to `Cartouche.Application.chain_id/0`."
        ]
      ],
      returns: %{
        type: :transaction_v1,
        description:
          "%Cartouche.Transaction.V1{} with legacy `gas_price` fields, the chain id in `v`, and `r`/`s` zero — EIP-155's unsigned signature triple."
      }
    )

    @doc ~S"""
    Constructs a new V1 (Legacy) Ethereum transaction.

    ## Examples

        iex> Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
        %Cartouche.Transaction.V1{
          nonce: 1,
          gas_price: 100000000000,
          gas_limit: 100000,
          to: <<1::160>>,
          value: 2,
          data: <<1, 2, 3>>,
          v: 42,
          r: 0,
          s: 0
        }
    """
    @spec new(
            integer(),
            integer() | {integer(), :wei | :gwei} | nil,
            integer(),
            <<_::160>>,
            integer() | {integer(), :wei | :gwei},
            binary(),
            atom() | integer() | nil
          ) :: t()
    def new(nonce, gas_price, gas_limit, to, value, data, chain_id \\ nil) do
      %__MODULE__{
        nonce: nonce,
        gas_price: if(is_nil(gas_price), do: nil, else: Cartouche.Wei.to_wei(gas_price)),
        gas_limit: gas_limit,
        to: to,
        value: Cartouche.Wei.to_wei(value),
        data: data,
        v:
          if(is_nil(chain_id),
            do: Cartouche.Application.chain_id(),
            else: Cartouche.Chain.parse_id(chain_id)
          ),
        r: 0,
        s: 0
      }
    end

    api(:encode, "Encode a legacy transaction as RLP bytes for signing or broadcast.",
      params: [
        transaction: [
          kind: :value,
          description: "%Cartouche.Transaction.V1{} using `gas_price`, `gas_limit`, and legacy signature fields."
        ]
      ],
      returns: %{
        type: :rlp_binary,
        description: "RLP-encoded legacy transaction binary."
      }
    )

    @doc ~S"""
    Build an RLP-encoded transaction. Note: transactions can be encoded before they are signed, which
    uses `[chain_id, 0, 0]` in the signature fields, otherwise those fields are `[v, r, s]`.

    ## Examples

        iex> Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
        ...> |> Cartouche.Transaction.V1.encode()
        ...> |> Base.encode16()
        "E80185174876E800830186A094000000000000000000000000000000000000000102830102032A8080"
    """
    @spec encode(t()) :: binary()
    def encode(%__MODULE__{
          nonce: nonce,
          gas_price: gas_price,
          gas_limit: gas_limit,
          to: to,
          value: value,
          data: data,
          v: v,
          r: r,
          s: s
        }) do
      ExRLP.encode([nonce, gas_price, gas_limit, to, value, data, v, r, s])
    end

    api(:decode, "Decode RLP bytes into a legacy transaction struct.",
      params: [
        trx_enc: [kind: :value, description: "RLP-encoded legacy transaction binary."]
      ],
      returns: %{
        type: :ok_error_tuple,
        description: "`{:ok, %Cartouche.Transaction.V1{}}` or `{:error, reason}` for invalid legacy payloads."
      }
    )

    @doc ~S"""
    Decode an RLP-encoded transaction.

    ## Examples

        iex> use Cartouche.Hex
        iex> ~h[0xE80185174876E800830186A094000000000000000000000000000000000000000102830102032A8080]
        ...> |> Cartouche.Transaction.V1.decode()
        {:ok, %Cartouche.Transaction.V1{
          nonce: 1,
          gas_price: 100000000000,
          gas_limit: 100000,
          to: <<1::160>>,
          value: 2,
          data: <<1, 2, 3>>,
          v: 42,
          r: 0,
          s: 0
        }}
    """
    @spec decode(binary()) :: {:ok, t()} | {:error, String.t()}
    def decode(trx_enc) when is_binary(trx_enc) do
      with {:ok, decoded} <- safe_rlp_decode(trx_enc) do
        decode_fields(decoded)
      end
    end

    def decode(_), do: {:error, "invalid legacy transaction"}

    @spec decode_fields(term()) :: {:ok, t()} | {:error, String.t()}
    defp decode_fields([nonce, gas_price, gas_limit, to, value, data, v, r, s])
         when is_binary(to) and byte_size(to) == 20 and is_binary(data) and byte_size(r) <= 32 and byte_size(s) <= 32 do
      {:ok,
       %__MODULE__{
         nonce: :binary.decode_unsigned(nonce),
         gas_price: :binary.decode_unsigned(gas_price),
         gas_limit: :binary.decode_unsigned(gas_limit),
         to: to,
         value: :binary.decode_unsigned(value),
         data: data,
         v: :binary.decode_unsigned(v),
         r: :binary.decode_unsigned(r),
         s: :binary.decode_unsigned(s)
       }}
    rescue
      # `:binary.decode_unsigned/1` raises ArgumentError on the non-binary
      # terms a malformed RLP body can yield.
      ArgumentError -> {:error, "invalid legacy transaction"}
    end

    defp decode_fields(_), do: {:error, "invalid legacy transaction"}

    @spec safe_rlp_decode(binary()) :: {:ok, term()} | {:error, String.t()}
    defp safe_rlp_decode(trx_enc) do
      {:ok, ExRLP.decode(trx_enc)}
    rescue
      # ExRLP raises DecodeError on most malformed input, but leaks a MatchError
      # on truncated length-prefixed binaries (an internal `<<_::size>> = tail`).
      _e in [ExRLP.DecodeError, MatchError] -> {:error, "invalid legacy transaction"}
    end

    api(:add_signature, "Attach an Ethereum signature to a legacy transaction.",
      params: [
        transaction: [kind: :value, description: "%Cartouche.Transaction.V1{} to update."],
        signature: [kind: :value, description: "Packed `r <> s <> v` Ethereum signature bytes."]
      ],
      returns: %{
        type: :transaction_v1,
        description: "%Cartouche.Transaction.V1{} with `v`, `r`, and `s` populated from the signature."
      }
    )

    @doc ~S"""
    Adds a signature to a transaction. This overwrites the `[chain_id, 0, 0]` fields, as per EIP-155.

    ## Examples

        iex> Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
        ...> |> Cartouche.Transaction.V1.add_signature(<<1::256, 2::256, 3::8>>)
        %Cartouche.Transaction.V1{
          nonce: 1,
          gas_price: 100000000000,
          gas_limit: 100000,
          to: <<1::160>>,
          value: 2,
          data: <<1, 2, 3>>,
          v: 3,
          r: 1,
          s: 2
        }
    """
    @spec add_signature(t(), <<_::512, _::_*8>>) :: t()
    def add_signature(%__MODULE__{} = transaction, <<r::binary-size(32), s::binary-size(32), v::binary>>) do
      %{
        transaction
        | v: :binary.decode_unsigned(v),
          r: :binary.decode_unsigned(r),
          s: :binary.decode_unsigned(s)
      }
    end

    api(:get_signature, "Extract the packed signature from a signed legacy transaction.",
      params: [
        transaction: [kind: :value, description: "%Cartouche.Transaction.V1{} to inspect."]
      ],
      returns: %{
        type: :ok_error_tuple,
        description: "`{:ok, r <> s <> v}` when signed, or `{:error, reason}` when signature fields are empty."
      }
    )

    @doc ~S"""
    Recovers a signature from a transaction, if it's been signed. Otherwise returns an error.

    ## Examples

        iex> Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
        ...> |> Cartouche.Transaction.V1.add_signature(<<1::256, 2::256, 3::8>>)
        ...> |> Cartouche.Transaction.V1.get_signature()
        {:ok, <<1::256, 2::256, 3::8>>}

        iex> Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
        ...> |> Cartouche.Transaction.V1.add_signature(<<1::256, 2::256, 0x05f5e0ff::32>>)
        ...> |> Cartouche.Transaction.V1.get_signature()
        {:ok, <<1::256, 2::256, 0x05f5e0ff::32>>}

        iex> Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
        ...> |> Cartouche.Transaction.V1.get_signature()
        {:error, "transaction missing signature"}
    """
    @spec get_signature(t()) :: {:ok, binary()} | {:error, String.t()}
    def get_signature(%__MODULE__{v: _v, r: 0, s: 0}), do: {:error, "transaction missing signature"}

    def get_signature(%__MODULE__{v: v, r: r, s: s}) do
      v_enc = :binary.encode_unsigned(v)
      {:ok, <<r::big-256, s::big-256, v_enc::binary>>}
    end

    api(:recover_signer, "Recover the signer address from a signed legacy transaction.",
      params: [
        transaction: [kind: :value, description: "Signed %Cartouche.Transaction.V1{}."],
        chain_id: [
          kind: :exchange_data,
          source: "Cartouche.RPC.eth_chain_id/1",
          description: "Chain id atom/integer used to reconstruct the EIP-155 signing payload."
        ]
      ],
      returns: %{
        type: :ok_error_tuple,
        description: "`{:ok, 20-byte address}` or `{:error, reason}` when the transaction is unsigned."
      }
    )

    @doc ~S"""
    Recovers the signer from a given transaction, if it's been signed.

    ## Examples

        iex> {:ok, address} =
        ...> Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
        ...> |> Cartouche.Transaction.V1.add_signature(<<1::256, 2::256, 3::8>>)
        ...> |> Cartouche.Transaction.V1.recover_signer(:kovan)
        ...> Cartouche.Hex.to_address(address)
        "0x47643AC1194d7e8C6d04dD631D456137028bBc1F"

        iex> Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
        ...> |> Cartouche.Transaction.V1.recover_signer(:kovan)
        {:error, "transaction missing signature"}
    """
    @spec recover_signer(t(), atom() | integer()) :: {:ok, <<_::160>>} | {:error, String.t()}
    def recover_signer(transaction, chain_id) do
      trx_encoded = encode(%{transaction | v: Cartouche.Chain.parse_id(chain_id), r: 0, s: 0})

      with {:ok, signature} <- get_signature(transaction) do
        {:ok, Cartouche.Recover.recover_eth(trx_encoded, signature)}
      end
    end

    api(:from_json, "Decode a legacy transaction JSON object from `eth_getBlockBy*` into a V1 struct.",
      params: [
        params: [
          kind: :exchange_data,
          source:
            "Cartouche.RPC.get_block_by_number/2 or Cartouche.RPC.get_block_by_hash/2 with `:include_transaction_details, true`",
          description:
            "JSON transaction object with `nonce`, `gasPrice`, `gas`, `to`, `value`, `input`, `v`, `r`, `s` hex fields (legacy / EIP-155 shape)."
        ]
      ],
      returns: %{
        type: :transaction_v1,
        description:
          "%Cartouche.Transaction.V1{} with integer `nonce`/`gas_price`/`gas_limit`/`value`/`v`/`r`/`s`, raw-bytes `data`, and `to` as a 20-byte address or `nil` for contract creation."
      },
      errors: [
        invalid_hex: "Raised as `Cartouche.Hex.InvalidHex` when a required hex field is missing or malformed."
      ]
    )

    @doc ~S"""
    Decodes a legacy (type 0) transaction object as returned in the
    `transactions` array of `eth_getBlockByNumber` / `eth_getBlockByHash`
    when `include_transaction_details: true` is requested.

    `to` is preserved as `nil` for contract-creation transactions per the
    wire shape (the strict RLP `decode/1` path requires an explicit 20-byte
    address; this JSON path does not).

    ## Examples

        iex> use Cartouche.Hex
        iex> %{
        ...>   "type" => "0x0",
        ...>   "nonce" => "0x1",
        ...>   "gasPrice" => "0x174876e800",
        ...>   "gas" => "0x186a0",
        ...>   "to" => "0x0000000000000000000000000000000000000001",
        ...>   "value" => "0x2",
        ...>   "input" => "0x010203",
        ...>   "v" => "0x2a",
        ...>   "r" => "0x0",
        ...>   "s" => "0x0"
        ...> }
        ...> |> Cartouche.Transaction.V1.from_json()
        %Cartouche.Transaction.V1{
          nonce: 1,
          gas_price: 100_000_000_000,
          gas_limit: 100_000,
          to: ~h[0x0000000000000000000000000000000000000001],
          value: 2,
          data: <<1, 2, 3>>,
          v: 0x2a,
          r: 0,
          s: 0
        }

    Contract creation: `"to": null` is preserved as `to: nil`.

        iex> %{
        ...>   "type" => "0x0",
        ...>   "nonce" => "0x0",
        ...>   "gasPrice" => "0x1",
        ...>   "gas" => "0x186a0",
        ...>   "to" => nil,
        ...>   "value" => "0x0",
        ...>   "input" => "0x60606040",
        ...>   "v" => "0x1c",
        ...>   "r" => "0x0",
        ...>   "s" => "0x0"
        ...> }
        ...> |> Cartouche.Transaction.V1.from_json()
        ...> |> Map.fetch!(:to)
        nil
    """
    @spec from_json(map()) :: t() | no_return()
    def from_json(%{} = params) do
      %__MODULE__{
        nonce: Cartouche.Hex.decode_hex_number!(params["nonce"]),
        gas_price: Cartouche.Hex.decode_hex_number!(params["gasPrice"]),
        gas_limit: Cartouche.Hex.decode_hex_number!(params["gas"]),
        to: decode_to(params["to"]),
        value: Cartouche.Hex.decode_hex_number!(params["value"]),
        data: Cartouche.Hex.decode_hex!(params["input"]),
        v: Cartouche.Hex.decode_hex_number!(params["v"]),
        r: Cartouche.Hex.decode_hex_number!(params["r"]),
        s: Cartouche.Hex.decode_hex_number!(params["s"])
      }
    end

    @spec decode_to(String.t() | nil) :: <<_::160>> | nil
    defp decode_to(nil), do: nil
    defp decode_to(addr) when is_binary(addr), do: Cartouche.Hex.decode_address!(addr)
  end

  defmodule V2 do
    @moduledoc """
    Represents a V2 or EIP-1559 transaction.
    """

    use Descripex, namespace: "/ethereum/transaction/v2"

    alias Cartouche.Transaction.JsonField
    alias Cartouche.Transaction.TypedDecode

    @type access_list_entry :: {<<_::160>>, [<<_::256>>]}
    @type access_list :: [access_list_entry()]
    @type access_list_input :: [access_list_entry() | <<_::160>>]

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
      :signature_y_parity,
      :signature_r,
      :signature_s
    ]

    api(:new, "Construct an EIP-1559 transaction struct.",
      params: [
        nonce: [
          kind: :exchange_data,
          source: "Cartouche.RPC.get_transaction_count/2",
          description: "Account nonce for the sender."
        ],
        max_priority_fee_per_gas: [
          kind: :exchange_data,
          source: "Cartouche.RPC.max_priority_fee_per_gas/1",
          description: "EIP-1559 priority tip per gas as wei or `{amount, :wei | :gwei}`; distinct from V1 `gas_price`."
        ],
        max_fee_per_gas: [
          kind: :exchange_data,
          source: "Cartouche.RPC.fee_history/1",
          description: "EIP-1559 max total fee per gas as wei or `{amount, :wei | :gwei}`; distinct from V1 `gas_price`."
        ],
        gas_limit: [
          kind: :exchange_data,
          source: "Cartouche.RPC.estimate_gas/2",
          description: "Maximum gas units the transaction may consume."
        ],
        destination: [kind: :value, description: "20-byte destination address."],
        amount: [kind: :value, description: "Ether value as wei or `{amount, :wei | :gwei}`."],
        data: [kind: :value, description: "Contract calldata or raw transaction input bytes."],
        access_list: [kind: :value, description: "EIP-2930/EIP-1559 access list entries."],
        chain_id: [
          kind: :exchange_data,
          source: "Cartouche.RPC.eth_chain_id/1",
          default: nil,
          description: "Ethereum chain id atom/integer; defaults to `Cartouche.Application.chain_id/0`."
        ]
      ],
      returns: %{
        type: :transaction_v2,
        description: "%Cartouche.Transaction.V2{} with EIP-1559 `max_fee_per_gas` and `max_priority_fee_per_gas` fields."
      }
    )

    @doc ~S"""
    Constructs a new V2 (EIP-1559) Ethereum transaction.

    ## Examples

        iex> Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [{<<2::160>>, [<<22::256>>]}, {<<3::160>>, []}], :goerli)
        %Cartouche.Transaction.V2{
          chain_id: 5,
          nonce: 1,
          max_priority_fee_per_gas: 1000000000,
          max_fee_per_gas: 100000000000,
          gas_limit: 100000,
          destination: <<1::160>>,
          amount: 2,
          data: <<1, 2, 3>>,
          access_list: [{<<2::160>>, [<<22::256>>]}, {<<3::160>>, []}],
          signature_y_parity: nil,
          signature_r: nil,
          signature_s: nil
        }

        iex> Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [{<<2::160>>, [<<22::256>>]}, {<<3::160>>, []}], true, <<0x01::256>>, <<0x02::256>>, :goerli)
        %Cartouche.Transaction.V2{
          chain_id: 5,
          nonce: 1,
          max_priority_fee_per_gas: 1000000000,
          max_fee_per_gas: 100000000000,
          gas_limit: 100000,
          destination: <<1::160>>,
          amount: 2,
          data: <<1, 2, 3>>,
          access_list: [{<<2::160>>, [<<22::256>>]}, {<<3::160>>, []}],
          signature_y_parity: true,
          signature_r: <<0x01::256>>,
          signature_s: <<0x02::256>>
        }
    """
    @spec new(
            integer(),
            integer() | {integer(), :wei | :gwei} | nil,
            integer() | {integer(), :wei | :gwei} | nil,
            integer(),
            <<_::160>>,
            integer() | {integer(), :wei | :gwei},
            binary(),
            access_list_input(),
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
          chain_id \\ nil
        ),
        do:
          new(
            nonce,
            max_priority_fee_per_gas,
            max_fee_per_gas,
            gas_limit,
            destination,
            amount,
            data,
            access_list,
            nil,
            nil,
            nil,
            chain_id
          )

    api(:new, "Construct an EIP-1559 transaction struct with explicit signature fields.",
      params: [
        nonce: [
          kind: :exchange_data,
          source: "Cartouche.RPC.get_transaction_count/2",
          description: "Account nonce for the sender."
        ],
        max_priority_fee_per_gas: [
          kind: :exchange_data,
          source: "Cartouche.RPC.max_priority_fee_per_gas/1",
          description: "EIP-1559 priority tip per gas as wei or `{amount, :wei | :gwei}`; distinct from V1 `gas_price`."
        ],
        max_fee_per_gas: [
          kind: :exchange_data,
          source: "Cartouche.RPC.fee_history/1",
          description: "EIP-1559 max total fee per gas as wei or `{amount, :wei | :gwei}`; distinct from V1 `gas_price`."
        ],
        gas_limit: [
          kind: :exchange_data,
          source: "Cartouche.RPC.estimate_gas/2",
          description: "Maximum gas units the transaction may consume."
        ],
        destination: [kind: :value, description: "20-byte destination address."],
        amount: [kind: :value, description: "Ether value as wei or `{amount, :wei | :gwei}`."],
        data: [kind: :value, description: "Contract calldata or raw transaction input bytes."],
        access_list: [kind: :value, description: "EIP-2930/EIP-1559 access list entries."],
        signature_y_parity: [
          kind: :value,
          description: "Typed-transaction y-parity signature bit, or `nil` for unsigned construction."
        ],
        signature_r: [kind: :value, description: "32-byte signature r value, or `nil` for unsigned construction."],
        signature_s: [kind: :value, description: "32-byte signature s value, or `nil` for unsigned construction."],
        chain_id: [
          kind: :exchange_data,
          source: "Cartouche.RPC.eth_chain_id/1",
          default: nil,
          description: "Ethereum chain id atom/integer; defaults to `Cartouche.Application.chain_id/0`."
        ]
      ],
      returns: %{
        type: :transaction_v2,
        description:
          "%Cartouche.Transaction.V2{} with EIP-1559 fee fields and explicit `signature_y_parity`, `signature_r`, and `signature_s` fields."
      }
    )

    @doc """
    Like `new/9` but also accepts explicit signature fields (`signature_y_parity`, `signature_r`, `signature_s`).
    """
    @spec new(
            integer(),
            integer() | {integer(), :wei | :gwei} | nil,
            integer() | {integer(), :wei | :gwei} | nil,
            integer(),
            <<_::160>>,
            integer() | {integer(), :wei | :gwei},
            binary(),
            access_list_input(),
            boolean() | nil,
            <<_::256>> | nil,
            <<_::256>> | nil,
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
          signature_y_parity,
          signature_r,
          signature_s,
          chain_id \\ nil
        ) do
      %__MODULE__{
        chain_id:
          if(is_nil(chain_id),
            do: Cartouche.Application.chain_id(),
            else: Cartouche.Chain.parse_id(chain_id)
          ),
        nonce: nonce,
        max_priority_fee_per_gas:
          if(is_nil(max_priority_fee_per_gas),
            do: nil,
            else: Cartouche.Wei.to_wei(max_priority_fee_per_gas)
          ),
        max_fee_per_gas: if(is_nil(max_fee_per_gas), do: nil, else: Cartouche.Wei.to_wei(max_fee_per_gas)),
        gas_limit: gas_limit,
        destination: destination,
        amount: Cartouche.Wei.to_wei(amount),
        data: data,
        access_list: canonicalize_access_list(access_list),
        signature_y_parity: signature_y_parity,
        signature_r: signature_r,
        signature_s: signature_s
      }
    end

    api(:encode, "Encode an EIP-1559 transaction as typed RLP bytes for signing or broadcast.",
      params: [
        transaction: [
          kind: :value,
          description:
            "%Cartouche.Transaction.V2{} using `max_fee_per_gas`, `max_priority_fee_per_gas`, and access-list fields."
        ]
      ],
      returns: %{
        type: :typed_rlp_binary,
        description: "`0x02`-prefixed RLP-encoded EIP-1559 transaction binary."
      }
    )

    @doc ~S"""
    Build an RLP-encoded transaction. Note: if the transaction does not have a signature
    set (that is, `signature_y_parity`, `signature_r` or `signature_s` are `nil`), then
    we will encode a partial transaction (which can be used for signing).

    ## Examples

        iex> Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [], :goerli)
        ...> |> Cartouche.Transaction.V2.encode()
        ...> |> Cartouche.Hex.encode_big_hex()
        "0x02EC0501843B9ACA0085174876E800830186A09400000000000000000000000000000000000000010283010203C0"

        iex> Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], :goerli)
        ...> |> Cartouche.Transaction.V2.encode()
        ...> |> Cartouche.Hex.encode_big_hex()
        "0x02F85A0501843B9ACA0085174876E800830186A09400000000000000000000000000000000000000010283010203EED6940000000000000000000000000000000000000002C0D6940000000000000000000000000000000000000003C0"

        iex> Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [], true, <<0x01::256>>, <<0x02::256>>, :goerli)
        ...> |> Cartouche.Transaction.V2.encode()
        ...> |> Cartouche.Hex.encode_big_hex()
        "0x02EF0501843B9ACA0085174876E800830186A09400000000000000000000000000000000000000010283010203C0010102"

        iex> Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], true, <<0x01::256>>, <<0x02::256>>, :goerli)
        ...> |> Cartouche.Transaction.V2.encode()
        ...> |> Cartouche.Hex.encode_big_hex()
        "0x02F85D0501843B9ACA0085174876E800830186A09400000000000000000000000000000000000000010283010203EED6940000000000000000000000000000000000000002C0D6940000000000000000000000000000000000000003C0010102"

        iex> Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [{<<2::160>>, [<<22::256>>]}, {<<3::160>>, []}], true, <<0x01::256>>, <<0x00, 0x02::248>>, :goerli)
        ...> |> Cartouche.Transaction.V2.encode()
        ...> |> Cartouche.Hex.encode_big_hex()
        "0x02F87F0501843B9ACA0085174876E800830186A09400000000000000000000000000000000000000010283010203F84FF7940000000000000000000000000000000000000002E1A00000000000000000000000000000000000000000000000000000000000000016D6940000000000000000000000000000000000000003C0010102"

        iex> use Cartouche.Hex
        iex> %Cartouche.Transaction.V2{
        ...>   chain_id: 8453,
        ...>   nonce: 1,
        ...>   max_priority_fee_per_gas: 1000000000,
        ...>   max_fee_per_gas: 1008963825,
        ...>   gas_limit: 300000,
        ...>   destination: ~h[0x00aea4b2242abc8bb4bb78d537a67a245a7bec64],
        ...>   amount: 0,
        ...>   data: ~h[0xdeff4b240000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000007b0000000000000000000000003b72952436d0dcacfa7d7691c0cf4de6dd5baa7e0000000000000000000000003b72952436d0dcacfa7d7691c0cf4de6dd5baa7e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b2c639c533813f4aa9d7837caf62653d097ff85000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda0291300000000000000000000000000000000000000000000000000000000000aae6000000000000000000000000000000000000000000000000000000000000aae60000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000002ada240000000000000000000000000000000000000000000000000000000067d38314000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001800000000000000000000000000000000000000000000000000000000000000000],
        ...>   access_list: [],
        ...>   signature_y_parity: false,
        ...>   signature_r: ~h[0x019c8102cb582c309b0d2ababb6aeb683a8fbc7e2044665f84669f0a73865b9a],
        ...>   signature_s: ~h[0x3732eb6644fc11e850a0fed8ebe403b4c2f5d1f1aec961eaccf1f7baa55615a6]
        ...> }
        ...> |> Cartouche.Transaction.V2.encode()
        ...> |> Cartouche.Hex.encode_big_hex()
        "0x02F9027382210501843B9ACA00843C2390F1830493E09400AEA4B2242ABC8BB4BB78D537A67A245A7BEC6480B90204DEFF4B240000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000A000000000000000000000000000000000000000000000000000000000000007B0000000000000000000000003B72952436D0DCACFA7D7691C0CF4DE6DD5BAA7E0000000000000000000000003B72952436D0DCACFA7D7691C0CF4DE6DD5BAA7E00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000B2C639C533813F4AA9D7837CAF62653D097FF85000000000000000000000000833589FCD6EDB6E08F4C7C32D4F71B54BDA0291300000000000000000000000000000000000000000000000000000000000AAE6000000000000000000000000000000000000000000000000000000000000AAE60000000000000000000000000000000000000000000000000000000000000000A00000000000000000000000000000000000000000000000000000000002ADA240000000000000000000000000000000000000000000000000000000067D38314000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001800000000000000000000000000000000000000000000000000000000000000000C080A0019C8102CB582C309B0D2ABABB6AEB683A8FBC7E2044665F84669F0A73865B9AA03732EB6644FC11E850A0FED8EBE403B4C2F5D1F1AEC961EACCF1F7BAA55615A6"
    """
    @spec encode(
            t()
            | %__MODULE__{
                chain_id: integer() | nil,
                nonce: integer() | nil,
                max_priority_fee_per_gas: integer() | nil,
                max_fee_per_gas: integer() | nil,
                gas_limit: integer() | nil,
                destination: <<_::160>> | nil,
                amount: integer() | nil,
                data: binary() | nil,
                access_list: list() | nil,
                signature_y_parity: nil,
                signature_r: nil,
                signature_s: nil
              }
          ) :: binary()
    def encode(
          %__MODULE__{signature_y_parity: signature_y_parity, signature_r: signature_r, signature_s: signature_s} =
            transaction
        )
        when is_nil(signature_y_parity) or is_nil(signature_r) or is_nil(signature_s) do
      <<0x02>> <> ExRLP.encode(unsigned_rlp_list(transaction))
    end

    def encode(
          %__MODULE__{signature_y_parity: signature_y_parity, signature_r: signature_r, signature_s: signature_s} =
            transaction
        )
        when is_boolean(signature_y_parity) and is_binary(signature_r) and is_binary(signature_s) do
      <<0x02>> <>
        (transaction
         |> unsigned_rlp_list()
         |> Kernel.++([
           signature_y_parity(signature_y_parity),
           String.trim_leading(signature_r, <<0>>),
           String.trim_leading(signature_s, <<0>>)
         ])
         |> ExRLP.encode())
    end

    @doc false
    @spec unsigned_rlp_list(%__MODULE__{}) :: [term()]
    defp unsigned_rlp_list(%__MODULE__{
           chain_id: chain_id,
           nonce: nonce,
           max_priority_fee_per_gas: max_priority_fee_per_gas,
           max_fee_per_gas: max_fee_per_gas,
           gas_limit: gas_limit,
           destination: destination,
           amount: amount,
           data: data,
           access_list: access_list
         }) do
      [
        chain_id,
        nonce,
        max_priority_fee_per_gas,
        max_fee_per_gas,
        gas_limit,
        destination,
        amount,
        data,
        normalize_access_list(access_list)
      ]
    end

    @spec canonicalize_access_list(access_list_input()) :: access_list()
    defp canonicalize_access_list(access_list) do
      Enum.map(access_list, fn
        # Lift the documented shorthand to an EIP-2930 `{address, []}` tuple so
        # encode emits `[address, []]`, never a raw 20-byte RLP string.
        <<_::160>> = address -> {address, []}
        entry -> TypedDecode.validate_access_list_entry!(entry)
      end)
    end

    @spec normalize_access_list(access_list()) :: [[<<_::160>> | [<<_::256>>]]]
    defp normalize_access_list(access_list), do: TypedDecode.encode_access_list(access_list)

    @spec signature_y_parity(boolean()) :: 0 | 1
    defp signature_y_parity(true), do: 1
    defp signature_y_parity(false), do: 0

    api(:decode, "Decode typed RLP bytes into an EIP-1559 transaction struct.",
      params: [
        trx_enc: [kind: :value, description: "`0x02`-prefixed RLP-encoded EIP-1559 transaction binary."]
      ],
      returns: %{
        type: :ok_error_tuple,
        description: "`{:ok, %Cartouche.Transaction.V2{}}` or `{:error, reason}` for invalid EIP-1559 payloads."
      }
    )

    @doc ~S"""
    Decode an RLP-encoded transaction.

    Accepts both signed payloads and unsigned signing payloads. Unsigned
    payloads omit `signature_y_parity`, `signature_r`, and `signature_s`; those
    fields decode as `nil`.

    ## Examples

        iex> use Cartouche.Hex
        iex> Cartouche.Transaction.V2.decode(~h[0x02EF0501843B9ACA0085174876E800830186A09400000000000000000000000000000000000000010283010203C0010102])
        {:ok, %Cartouche.Transaction.V2{
          chain_id: 5,
          nonce: 1,
          max_priority_fee_per_gas: 1000000000,
          max_fee_per_gas: 100000000000,
          gas_limit: 100000,
          destination: <<1::160>>,
          amount: 2,
          data: <<1, 2, 3>>,
          access_list: [],
          signature_y_parity: true,
          signature_r: <<0x01::256>>,
          signature_s: <<0x02::256>>
        }}

        iex> use Cartouche.Hex
        iex> Cartouche.Transaction.V2.decode(~h[0x02F87F0501843B9ACA0085174876E800830186A09400000000000000000000000000000000000000010283010203F84FF7940000000000000000000000000000000000000002E1A00000000000000000000000000000000000000000000000000000000000000016D6940000000000000000000000000000000000000003C0010102])
        {:ok, %Cartouche.Transaction.V2{
          chain_id: 5,
          nonce: 1,
          max_priority_fee_per_gas: 1000000000,
          max_fee_per_gas: 100000000000,
          gas_limit: 100000,
          destination: <<1::160>>,
          amount: 2,
          data: <<1, 2, 3>>,
          access_list: [{<<2::160>>, [<<22::256>>]}, {<<3::160>>, []}],
          signature_y_parity: true,
          signature_r: <<0x01::256>>,
          signature_s: <<0x02::256>>
        }}

        iex> use Cartouche.Hex
        iex> Cartouche.Transaction.V2.decode(~h[0x02F9027382210501843B9ACA00843C2390F1830493E09400AEA4B2242ABC8BB4BB78D537A67A245A7BEC6480B90204DEFF4B240000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000A000000000000000000000000000000000000000000000000000000000000007B0000000000000000000000003B72952436D0DCACFA7D7691C0CF4DE6DD5BAA7E0000000000000000000000003B72952436D0DCACFA7D7691C0CF4DE6DD5BAA7E00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000B2C639C533813F4AA9D7837CAF62653D097FF85000000000000000000000000833589FCD6EDB6E08F4C7C32D4F71B54BDA0291300000000000000000000000000000000000000000000000000000000000AAE6000000000000000000000000000000000000000000000000000000000000AAE60000000000000000000000000000000000000000000000000000000000000000A00000000000000000000000000000000000000000000000000000000002ADA240000000000000000000000000000000000000000000000000000000067D38314000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001800000000000000000000000000000000000000000000000000000000000000000C080A0019C8102CB582C309B0D2ABABB6AEB683A8FBC7E2044665F84669F0A73865B9AA03732EB6644FC11E850A0FED8EBE403B4C2F5D1F1AEC961EACCF1F7BAA55615A6])
        {:ok, %Cartouche.Transaction.V2{
          chain_id: 8453,
          nonce: 1,
          max_priority_fee_per_gas: 1000000000,
          max_fee_per_gas: 1008963825,
          gas_limit: 300000,
          destination: ~h[0x00aea4b2242abc8bb4bb78d537a67a245a7bec64],
          amount: 0,
          data: ~h[0xdeff4b240000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000007b0000000000000000000000003b72952436d0dcacfa7d7691c0cf4de6dd5baa7e0000000000000000000000003b72952436d0dcacfa7d7691c0cf4de6dd5baa7e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b2c639c533813f4aa9d7837caf62653d097ff85000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda0291300000000000000000000000000000000000000000000000000000000000aae6000000000000000000000000000000000000000000000000000000000000aae60000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000002ada240000000000000000000000000000000000000000000000000000000067d38314000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001800000000000000000000000000000000000000000000000000000000000000000],
          access_list: [],
          signature_y_parity: false,
          signature_r: ~h[0x019c8102cb582c309b0d2ababb6aeb683a8fbc7e2044665f84669f0a73865b9a],
          signature_s: ~h[0x3732eb6644fc11e850a0fed8ebe403b4c2f5d1f1aec961eaccf1f7baa55615a6]
        }}
    """
    @spec decode(binary()) :: {:ok, t()} | {:error, String.t()}
    def decode(<<0x02, trx_enc::binary>>) do
      with {:ok, fields} <- safe_rlp_decode(trx_enc) do
        decode_fields(fields)
      end
    end

    def decode(_), do: {:error, "invalid v2 transaction"}

    @spec decode_fields(term()) :: {:ok, t()} | {:error, String.t()}
    defp decode_fields([_, _, _, _, _, _, _, _, _] = fields) do
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
           signature_y_parity,
           signature_r,
           signature_s
         ]) do
      with {:ok, signature_y_parity} <- decode_y_parity(signature_y_parity),
           {:ok, signature_r} <- decode_word(signature_r),
           {:ok, signature_s} <- decode_word(signature_s) do
        decode_payload(
          [
            chain_id,
            nonce,
            max_priority_fee_per_gas,
            max_fee_per_gas,
            gas_limit,
            destination,
            amount,
            data,
            access_list
          ],
          {signature_y_parity, signature_r, signature_s}
        )
      else
        _ -> {:error, "invalid v2 transaction"}
      end
    end

    defp decode_fields(_), do: {:error, "invalid v2 transaction"}

    @spec decode_payload(
            list(),
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
             access_list
           ],
           {signature_y_parity, signature_r, signature_s}
         )
         when is_binary(data) do
      with {:ok, access_list} <- decode_access_list(access_list),
           {:ok, destination} <- decode_address(destination) do
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
           signature_y_parity: signature_y_parity,
           signature_r: signature_r,
           signature_s: signature_s
         }}
      end
    rescue
      # `:binary.decode_unsigned/1` raises ArgumentError on the non-binary
      # terms a malformed RLP payload can yield.
      ArgumentError -> {:error, "invalid v2 transaction"}
    end

    defp decode_payload(_, _), do: {:error, "invalid v2 transaction"}

    @spec decode_access_list(term()) :: {:ok, [{<<_::160>>, [<<_::256>>]}]} | {:error, String.t()}
    defp decode_access_list(access_list) when is_list(access_list) do
      {:ok,
       Enum.map(access_list, fn [address, storage] ->
         {pad_address(address), Enum.map(storage, &pad_word/1)}
       end)}
    rescue
      # A malformed access list raises when an entry isn't a 2-element list
      # (FunctionClauseError), `storage` isn't enumerable
      # (Protocol.UndefinedError), or a word/address fails its size guard.
      _e in [MatchError, FunctionClauseError, Protocol.UndefinedError, ArgumentError] ->
        {:error, "invalid v2 transaction"}
    end

    defp decode_access_list(_), do: {:error, "invalid v2 transaction"}

    @spec decode_address(binary()) :: {:ok, <<_::160>>} | {:error, String.t()}
    defp decode_address(address) when byte_size(address) == 20, do: {:ok, address}
    defp decode_address(_), do: {:error, "invalid v2 transaction"}

    @spec decode_word(binary()) :: {:ok, <<_::256>>} | {:error, String.t()}
    defp decode_word(word) when byte_size(word) <= 32, do: {:ok, Cartouche.Hex.pad(word, 32)}
    defp decode_word(_), do: {:error, "invalid v2 transaction"}

    @spec decode_y_parity(binary()) :: {:ok, boolean()} | {:error, String.t()}
    defp decode_y_parity(y_parity) do
      case :binary.decode_unsigned(y_parity) do
        0 -> {:ok, false}
        1 -> {:ok, true}
        _ -> {:error, "invalid v2 transaction"}
      end
    rescue
      # `:binary.decode_unsigned/1` raises ArgumentError on a non-binary y-parity.
      ArgumentError -> {:error, "invalid v2 transaction"}
    end

    @spec pad_address(binary()) :: <<_::160>>
    defp pad_address(address) when byte_size(address) == 20, do: address

    @spec pad_word(binary()) :: <<_::256>>
    defp pad_word(word) when byte_size(word) == 32, do: word

    @spec safe_rlp_decode(binary()) :: {:ok, term()} | {:error, String.t()}
    defp safe_rlp_decode(trx_enc) do
      {:ok, ExRLP.decode(trx_enc)}
    rescue
      # ExRLP raises DecodeError on most malformed input, but leaks a MatchError
      # on truncated length-prefixed binaries (an internal `<<_::size>> = tail`).
      _e in [ExRLP.DecodeError, MatchError] -> {:error, "invalid v2 transaction"}
    end

    api(:add_signature, "Attach an Ethereum signature to an EIP-1559 transaction.",
      params: [
        transaction: [kind: :value, description: "%Cartouche.Transaction.V2{} to update."],
        v: [
          kind: :value,
          description: "Typed-transaction y-parity boolean."
        ],
        r: [kind: :value, description: "32-byte signature r value when passing signature fields separately."],
        s: [kind: :value, description: "32-byte signature s value when passing signature fields separately."]
      ],
      returns: %{
        type: :transaction_v2,
        description: "%Cartouche.Transaction.V2{} with `signature_y_parity`, `signature_r`, and `signature_s` populated."
      }
    )

    @doc ~S"""
    Adds a signature to a transaction. This overwrites the `signature_y_parity`, `signature_r` and `signature_s` fields.

    ## Examples

        iex> Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], 1, 0x01, 0x02, :goerli)
        ...> |> Cartouche.Transaction.V2.add_signature(true, <<1::256>>, <<2::256>>)
        %Cartouche.Transaction.V2{
          chain_id: 5,
          nonce: 1,
          max_priority_fee_per_gas: 1000000000,
          max_fee_per_gas: 100000000000,
          gas_limit: 100000,
          destination: <<1::160>>,
          amount: 2,
          data: <<1, 2, 3>>,
          access_list: [{<<2::160>>, []}, {<<3::160>>, []}],
          signature_y_parity: true,
          signature_r: <<0x01::256>>,
          signature_s: <<0x02::256>>
        }

        iex> Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], 1, 0x01, 0x02, :goerli)
        ...> |> Cartouche.Transaction.V2.add_signature(<<1::256, 2::256, 1::8>>)
        %Cartouche.Transaction.V2{
          chain_id: 5,
          nonce: 1,
          max_priority_fee_per_gas: 1000000000,
          max_fee_per_gas: 100000000000,
          gas_limit: 100000,
          destination: <<1::160>>,
          amount: 2,
          data: <<1, 2, 3>>,
          access_list: [{<<2::160>>, []}, {<<3::160>>, []}],
          signature_y_parity: true,
          signature_r: <<0x01::256>>,
          signature_s: <<0x02::256>>
        }

        iex> Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], 1, 0x01, 0x02, :goerli)
        ...> |> Cartouche.Transaction.V2.add_signature(<<1::256, 2::256, 27::8>>)
        %Cartouche.Transaction.V2{
          chain_id: 5,
          nonce: 1,
          max_priority_fee_per_gas: 1000000000,
          max_fee_per_gas: 100000000000,
          gas_limit: 100000,
          destination: <<1::160>>,
          amount: 2,
          data: <<1, 2, 3>>,
          access_list: [{<<2::160>>, []}, {<<3::160>>, []}],
          signature_y_parity: false,
          signature_r: <<0x01::256>>,
          signature_s: <<0x02::256>>
        }

        iex> Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], 1, 0x01, 0x02, :goerli)
        ...> |> Cartouche.Transaction.V2.add_signature(<<1::256, 2::256, 38::8>>)
        %Cartouche.Transaction.V2{
          chain_id: 5,
          nonce: 1,
          max_priority_fee_per_gas: 1000000000,
          max_fee_per_gas: 100000000000,
          gas_limit: 100000,
          destination: <<1::160>>,
          amount: 2,
          data: <<1, 2, 3>>,
          access_list: [{<<2::160>>, []}, {<<3::160>>, []}],
          signature_y_parity: true,
          signature_r: <<0x01::256>>,
          signature_s: <<0x02::256>>
        }

        iex> Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], 1, 0x01, 0x02, :goerli)
        ...> |> Cartouche.Transaction.V2.add_signature(<<1::256, 2::256, 3838::16>>)
        %Cartouche.Transaction.V2{
          chain_id: 5,
          nonce: 1,
          max_priority_fee_per_gas: 1000000000,
          max_fee_per_gas: 100000000000,
          gas_limit: 100000,
          destination: <<1::160>>,
          amount: 2,
          data: <<1, 2, 3>>,
          access_list: [{<<2::160>>, []}, {<<3::160>>, []}],
          signature_y_parity: true,
          signature_r: <<0x01::256>>,
          signature_s: <<0x02::256>>
        }
    """
    @spec add_signature(t(), boolean(), <<_::256>>, <<_::256>>) :: t()
    def add_signature(%__MODULE__{} = transaction, v, r, s), do: Signature.add(transaction, v, r, s)

    api(:add_signature, "Attach a packed Ethereum signature to an EIP-1559 transaction.",
      params: [
        transaction: [kind: :value, description: "%Cartouche.Transaction.V2{} to update."],
        signature: [kind: :value, description: "Packed `r <> s <> v` Ethereum signature bytes."]
      ],
      returns: %{
        type: :transaction_v2,
        description: "%Cartouche.Transaction.V2{} with y-parity derived from the packed signature."
      }
    )

    @doc """
    Adds a signature to a transaction from a packed binary (`r <> s <> v`), deriving `signature_y_parity` from `v`.
    """
    @spec add_signature(t(), <<_::512, _::_*8>>) :: t()
    def add_signature(%__MODULE__{} = transaction, <<r::binary-size(32), s::binary-size(32), v_bin::binary>>) do
      v = :binary.decode_unsigned(v_bin)

      y_parity =
        if v < 2 do
          v == 1
        else
          rem(v, 2) == 0
        end

      %{transaction | signature_y_parity: y_parity, signature_r: r, signature_s: s}
    end

    api(:get_signature, "Extract the packed signature from a signed EIP-1559 transaction.",
      params: [
        transaction: [kind: :value, description: "%Cartouche.Transaction.V2{} to inspect."]
      ],
      returns: %{
        type: :ok_error_tuple,
        description: "`{:ok, r <> s <> y_parity}` when signed, or `{:error, reason}` when signature fields are empty."
      }
    )

    @doc ~S"""
    Recovers a signature from a transaction, if it's been signed. Otherwise returns an error.

    ## Examples

        iex> Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], true, <<0x01::256>>, <<0x02::256>>, :goerli)
        ...> |> Cartouche.Transaction.V2.get_signature()
        {:ok, <<1::256, 2::256, 1::8>>}

        iex> Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], :goerli)
        ...> |> Cartouche.Transaction.V2.get_signature()
        {:error, "transaction missing signature"}
    """
    @spec get_signature(t()) :: {:ok, binary()} | {:error, String.t()}
    def get_signature(%__MODULE__{} = transaction), do: Signature.get(transaction)

    api(:recover_signer, "Recover the signer address from a signed EIP-1559 transaction.",
      params: [
        transaction: [kind: :value, description: "Signed %Cartouche.Transaction.V2{}."]
      ],
      returns: %{
        type: :ok_error_tuple,
        description: "`{:ok, 20-byte address}` or `{:error, reason}` when the transaction is unsigned."
      }
    )

    @doc ~S"""
    Recovers the signer from a given transaction, if it's been signed.

    ## Examples

        iex> {:ok, address} =
        ...>   Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], true, <<0x01::256>>, <<0x02::256>>, :goerli)
        ...>   |> Cartouche.Transaction.V2.recover_signer()
        ...> Cartouche.Hex.to_address(address)
        "0xCaF1CF8ea0EBE79552A8cCFca5519ED7Db6a0F99"

        iex> Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], :goerli)
        ...> |> Cartouche.Transaction.V2.recover_signer()
        {:error, "transaction missing signature"}
    """
    @spec recover_signer(t()) :: {:ok, <<_::160>>} | {:error, String.t()}
    def recover_signer(transaction) do
      trx_encoded =
        encode(%{transaction | signature_y_parity: nil, signature_r: nil, signature_s: nil})

      with {:ok, signature} <- get_signature(transaction) do
        {:ok, Cartouche.Recover.recover_eth(trx_encoded, signature)}
      end
    end

    api(:from_json, "Decode an EIP-1559 transaction JSON object from `eth_getBlockBy*` into a V2 struct.",
      params: [
        params: [
          kind: :exchange_data,
          source:
            "Cartouche.RPC.get_block_by_number/2 or Cartouche.RPC.get_block_by_hash/2 with `:include_transaction_details, true`",
          description:
            "JSON transaction object with `chainId`, `nonce`, `maxPriorityFeePerGas`, `maxFeePerGas`, `gas`, `to`, `value`, `input`, `accessList`, and `yParity`/`v` + `r`/`s` hex fields."
        ]
      ],
      returns: %{
        type: :transaction_v2,
        description:
          "%Cartouche.Transaction.V2{} with integer fee fields, decoded `access_list` tuples, 32-byte `signature_r`/`signature_s` words, and `destination` as a 20-byte address or `nil` for contract creation."
      },
      errors: [
        invalid_hex: "Raised as `Cartouche.Hex.InvalidHex` when a required hex field is missing or malformed."
      ]
    )

    @doc ~S"""
    Decodes an EIP-1559 (type 2) transaction object as returned in the
    `transactions` array of `eth_getBlockByNumber` / `eth_getBlockByHash`
    when `include_transaction_details: true` is requested.

    `signature_y_parity` is taken from the `"yParity"` field (typed-tx
    canonical) or, when absent, derived from `"v"` (legacy backwards-compat
    field, which on typed transactions always holds the y-parity bit
    directly). `signature_r` and `signature_s` are normalised to 32-byte
    binaries even when the wire encoding strips leading zeros.

    ## Examples

        iex> use Cartouche.Hex
        iex> %{
        ...>   "type" => "0x2",
        ...>   "chainId" => "0x1",
        ...>   "nonce" => "0x1",
        ...>   "maxPriorityFeePerGas" => "0x3b9aca00",
        ...>   "maxFeePerGas" => "0x174876e800",
        ...>   "gas" => "0x186a0",
        ...>   "to" => "0x0000000000000000000000000000000000000001",
        ...>   "value" => "0x2",
        ...>   "input" => "0x010203",
        ...>   "accessList" => [],
        ...>   "yParity" => "0x1",
        ...>   "r" => "0x1",
        ...>   "s" => "0x2"
        ...> }
        ...> |> Cartouche.Transaction.V2.from_json()
        %Cartouche.Transaction.V2{
          chain_id: 1,
          nonce: 1,
          max_priority_fee_per_gas: 1_000_000_000,
          max_fee_per_gas: 100_000_000_000,
          gas_limit: 100_000,
          destination: ~h[0x0000000000000000000000000000000000000001],
          amount: 2,
          data: <<1, 2, 3>>,
          access_list: [],
          signature_y_parity: true,
          signature_r: <<1::256>>,
          signature_s: <<2::256>>
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
        signature_y_parity: JsonField.decode_y_parity(params),
        signature_r: JsonField.decode_signature_word(params["r"]),
        signature_s: JsonField.decode_signature_word(params["s"])
      }
    end
  end

  defmodule JsonField do
    @moduledoc """
    Shared JSON-field decoders used by `from_json/1` on V1/V2/V3/V4.

    Tightly mirrors the `eth_getBlockBy*` wire shape — these helpers are
    cross-module callable from each envelope's `from_json/1` and apply
    consistent decode rules (padding signature words, handling pre-Berlin
    `v` vs post-Berlin `yParity`, defensive `nil → []` for optional-on-wire
    list fields).
    """

    alias Cartouche.Hex

    @doc """
    Decode a `to` address from JSON.

    Returns `nil` for contract-creation transactions (where `to` is omitted
    or `null` on the wire) and a 20-byte binary otherwise.
    """
    @spec decode_destination(String.t() | nil) :: <<_::160>> | nil
    def decode_destination(nil), do: nil
    def decode_destination(addr) when is_binary(addr), do: Hex.decode_address!(addr)

    @doc """
    Decode a 256-bit signature word (`r` or `s`) from hex.

    Pads short hex values to a full 32 bytes — Geth and some other nodes
    strip leading zeros from signature components, so `"0x1"` is a valid
    on-wire representation of a word.
    """
    @spec decode_signature_word(String.t()) :: <<_::256>>
    def decode_signature_word(hex) when is_binary(hex), do: hex |> Hex.decode_hex!() |> Hex.pad(32)

    @doc """
    Decode `yParity` (post-Berlin) or fall back to `v` (pre-Berlin) into a
    boolean parity bit.

    Raises `Cartouche.Hex.InvalidHex` if the value decodes to anything
    other than 0 or 1.
    """
    @spec decode_y_parity(map()) :: boolean()
    def decode_y_parity(%{"yParity" => y_parity}) when not is_nil(y_parity), do: hex_to_y_parity(y_parity)
    def decode_y_parity(%{"v" => v}) when not is_nil(v), do: hex_to_y_parity(v)

    @doc """
    Decode an EIP-2930 access list (`[{address, storage_keys}]`).

    Defensive `nil → []`: although `accessList` is required on the wire
    for type 2/3/4 transactions, `from_json/1` is publicly callable and
    tolerates omission to stay symmetric with other optional-on-wire
    fields. Pass the parsed JSON value directly.
    """
    @spec decode_access_list(list() | nil) :: [{<<_::160>>, [<<_::256>>]}]
    def decode_access_list(nil), do: []

    def decode_access_list(entries) when is_list(entries) do
      Enum.map(entries, fn %{"address" => address, "storageKeys" => storage_keys} ->
        {Hex.decode_address!(address), Enum.map(storage_keys, &Hex.decode_word!/1)}
      end)
    end

    @doc """
    Decode an EIP-4844 blob-versioned-hashes list into 32-byte words.

    Defensive `nil → []` for the same reason as `decode_access_list/1`.
    """
    @spec decode_blob_versioned_hashes(list() | nil) :: [<<_::256>>]
    def decode_blob_versioned_hashes(nil), do: []
    def decode_blob_versioned_hashes(hashes) when is_list(hashes), do: Enum.map(hashes, &Hex.decode_word!/1)

    @doc """
    Decode an EIP-7702 authorization list into a tuple of
    `{chain_id, address, nonce, y_parity, r, s}` per entry.

    Defensive `nil → []` for the same reason as `decode_access_list/1`.
    """
    @spec decode_authorization_list(list() | nil) :: [
            {non_neg_integer(), <<_::160>>, non_neg_integer(), boolean(), <<_::256>>, <<_::256>>}
          ]
    def decode_authorization_list(nil), do: []

    def decode_authorization_list(entries) when is_list(entries) do
      Enum.map(entries, fn %{
                             "chainId" => chain_id,
                             "address" => address,
                             "nonce" => nonce
                           } = entry ->
        {
          Hex.decode_hex_number!(chain_id),
          Hex.decode_address!(address),
          Hex.decode_hex_number!(nonce),
          decode_y_parity(entry),
          decode_signature_word(entry["r"]),
          decode_signature_word(entry["s"])
        }
      end)
    end

    @spec hex_to_y_parity(String.t()) :: boolean()
    defp hex_to_y_parity(hex) do
      case Hex.decode_hex_number!(hex) do
        0 -> false
        1 -> true
        v -> raise Hex.InvalidHex, "invalid y_parity hex value: #{inspect(hex)} (decoded to #{v})"
      end
    end
  end

  api(
    :encode,
    "Encode a concrete transaction struct (V1/V_2930/V2/V3/V4) into raw RLP/typed-RLP transaction bytes by dispatching on struct.",
    params: [
      transaction: [
        kind: :value,
        description:
          "%Cartouche.Transaction.V1{}, %Cartouche.Transaction.V_2930{}, %Cartouche.Transaction.V2{}, %Cartouche.Transaction.V3{}, or %Cartouche.Transaction.V4{} to encode."
      ]
    ],
    returns: %{
      type: :transaction_binary,
      description:
        "Raw transaction bytes: untyped RLP for V1; EIP-2718 typed envelope (`0x01`/`0x02`/`0x03`/`0x04`) followed by RLP-encoded payload for V_2930/V2/V3/V4."
    },
    composes_with: [:decode]
  )

  @doc """
  Encodes a concrete transaction struct into raw transaction bytes, mirroring `decode/1`.

  Dispatches by struct so callers don't need to know which versioned encoder to
  invoke. The output is the same shape `decode/1` accepts:

    * `%Cartouche.Transaction.V1{}` - untyped RLP-encoded legacy/EIP-155 bytes
      (leading byte `>= 0x80`).
    * `%Cartouche.Transaction.V_2930{}` - `0x01`-prefixed EIP-2718 typed RLP
      (EIP-2930 access-list transaction).
    * `%Cartouche.Transaction.V2{}` - `0x02`-prefixed EIP-2718 typed RLP.
    * `%Cartouche.Transaction.V3{}` - `0x03`-prefixed EIP-2718 typed RLP
      (EIP-4844 blob transaction envelope).
    * `%Cartouche.Transaction.V4{}` - `0x04`-prefixed EIP-2718 typed RLP
      (EIP-7702 authorization-list transaction envelope).

  Each leaf encoder already emits the EIP-2718 envelope byte where applicable;
  this function is a pure pattern-match-and-delegate.

  ## Examples

      iex> tx = Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
      iex> {:ok, ^tx} = tx |> Cartouche.Transaction.encode() |> Cartouche.Transaction.decode()
      iex> Cartouche.Transaction.encode(tx) == Cartouche.Transaction.V1.encode(tx)
      true

      iex> tx = Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [], :goerli)
      iex> <<0x02, _::binary>> = Cartouche.Transaction.encode(tx)
      iex> {:ok, ^tx} = tx |> Cartouche.Transaction.encode() |> Cartouche.Transaction.decode()
  """
  @spec encode(V1.t() | V_2930.t() | V2.t() | V3.t() | V4.t()) :: binary()
  def encode(%V1{} = transaction), do: V1.encode(transaction)
  def encode(%V_2930{} = transaction), do: V_2930.encode(transaction)
  def encode(%V2{} = transaction), do: V2.encode(transaction)
  def encode(%V3{} = transaction), do: V3.encode(transaction)
  def encode(%V4{} = transaction), do: V4.encode(transaction)

  api(
    :decode,
    "Decode raw Ethereum transaction bytes into the matching transaction struct (V1/V_2930/V2/V3/V4 by envelope byte).",
    params: [
      encoded: [kind: :value, description: "Raw RLP/typed-RLP transaction bytes."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "Tagged union of eight dispatcher outcomes: " <>
          "`{:ok, %Cartouche.Transaction.V1{}}` for legacy/EIP-155 RLP bodies (first byte >= 0x80); " <>
          "`{:ok, %Cartouche.Transaction.V_2930{}}` for `0x01`-prefixed EIP-2930 envelopes; " <>
          "`{:ok, %Cartouche.Transaction.V2{}}` for `0x02`-prefixed EIP-1559 envelopes; " <>
          "`{:ok, %Cartouche.Transaction.V3{}}` for `0x03`-prefixed envelopes; " <>
          "`{:ok, %Cartouche.Transaction.V4{}}` for `0x04`-prefixed envelopes; " <>
          "`{:error, :empty_transaction}` for empty input; " <>
          "`{:error, :unknown_envelope_type}` for reserved envelope bytes (`< 0x80` except supported typed envelopes); " <>
          "`{:error, String.t()}` for malformed bodies delegated from `V1/V_2930/V2/V3/V4.decode/1`."
    }
  )

  @doc """
  Decodes raw Ethereum transaction bytes into the matching transaction struct.

  Dispatches typed envelopes by their first byte:

    * `0x01` - `Cartouche.Transaction.V_2930`
    * `0x02` - `Cartouche.Transaction.V2`
    * `0x03` - `Cartouche.Transaction.V3`
    * `0x04` - `Cartouche.Transaction.V4`

  Legacy transactions are untyped RLP and are decoded as
  `Cartouche.Transaction.V1` when the first byte is an RLP prefix (`>= 0x80`).
  Empty input returns `{:error, :empty_transaction}`. Unknown typed envelopes
  (`< 0x80` except supported typed envelopes) return `{:error, :unknown_envelope_type}`.

  ## Examples

      iex> tx = Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
      iex> {:ok, decoded} = Cartouche.Transaction.decode(Cartouche.Transaction.V1.encode(tx))
      iex> decoded == tx
      true

      iex> Cartouche.Transaction.decode(<<>>)
      {:error, :empty_transaction}
  """
  @spec decode(binary()) ::
          {:ok, V1.t() | V_2930.t() | V2.t() | V3.t() | V4.t()}
          | {:error, String.t() | :empty_transaction | :unknown_envelope_type}
  def decode(<<>>), do: {:error, :empty_transaction}
  def decode(<<0x01, _::binary>> = encoded), do: V_2930.decode(encoded)
  def decode(<<0x02, _::binary>> = encoded), do: V2.decode(encoded)
  def decode(<<0x03, _::binary>> = encoded), do: V3.decode(encoded)
  def decode(<<0x04, _::binary>> = encoded), do: V4.decode(encoded)
  def decode(<<type, _::binary>>) when type < 0x80, do: {:error, :unknown_envelope_type}
  def decode(encoded) when is_binary(encoded), do: V1.decode(encoded)
  def decode(_), do: {:error, :unknown_envelope_type}

  api(:build_trx, "Build a legacy transaction for a contract call or raw calldata.",
    params: [
      address: [kind: :value, description: "20-byte contract or recipient address."],
      nonce: [
        kind: :exchange_data,
        source: "Cartouche.RPC.get_transaction_count/2",
        description: "Account nonce for the sender."
      ],
      call_data: [kind: :value, description: "Raw calldata bytes or `{abi_signature, params}` to ABI encode."],
      gas_price: [
        kind: :exchange_data,
        source: "Cartouche.RPC.gas_price/1",
        description: "Legacy gas price as wei or `{amount, :wei | :gwei}`; `nil` leaves it unset."
      ],
      gas_limit: [
        kind: :exchange_data,
        source: "Cartouche.RPC.estimate_gas/2",
        description: "Maximum gas units the transaction may consume."
      ],
      value: [kind: :value, description: "Ether value as wei or `{amount, :wei | :gwei}`."],
      chain_id: [
        kind: :exchange_data,
        source: "Cartouche.RPC.eth_chain_id/1",
        default: nil,
        description: "Ethereum chain id atom/integer passed to Cartouche.Transaction.V1.new/7."
      ]
    ],
    returns: %{
      type: :transaction_v1,
      description: "%Cartouche.Transaction.V1{} ready to encode or sign."
    },
    composes_with: [:build_signed_trx]
  )

  @doc """
  Builds a v1-style call to a given contract

  ## Examples

      iex> use Cartouche.Hex
      iex> Cartouche.Transaction.build_trx(<<1::160>>, 5, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, {50, :gwei}, 100_000, 0, 5)
      %Cartouche.Transaction.V1{
        nonce: 5,
        gas_price: 50000000000,
        gas_limit: 100000,
        to: <<1::160>>,
        value: 0,
        data: ~h[0xA291ADD600000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000001],
        v: 5,
        r: 0,
        s: 0
      }

      iex> use Cartouche.Hex
      iex> call_data = ~h[0xA291ADD600000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000001]
      ...> Cartouche.Transaction.build_trx(<<1::160>>, 5, call_data, {50, :gwei}, 100_000, 0, 5)
      %Cartouche.Transaction.V1{
        nonce: 5,
        gas_price: 50000000000,
        gas_limit: 100000,
        to: <<1::160>>,
        value: 0,
        data: ~h[0xA291ADD600000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000001],
        v: 5,
        r: 0,
        s: 0
      }
  """
  @spec build_trx(
          <<_::160>>,
          integer(),
          binary() | {String.t(), [term()]},
          integer() | {integer(), :wei | :gwei} | nil,
          integer(),
          integer() | {integer(), :wei | :gwei},
          atom() | integer() | nil
        ) :: V1.t()
  def build_trx(address, nonce, call_data, gas_price, gas_limit, value, chain_id \\ nil) do
    data =
      case call_data do
        {abi, params} ->
          ABI.encode(abi, params)

        call_data when is_binary(call_data) ->
          call_data
      end

    V1.new(nonce, gas_price, gas_limit, address, value, data, chain_id)
  end

  api(:build_trx_v2, "Build an EIP-1559 transaction for a contract call or raw calldata.",
    params: [
      address: [kind: :value, description: "20-byte contract or recipient address."],
      nonce: [
        kind: :exchange_data,
        source: "Cartouche.RPC.get_transaction_count/2",
        description: "Account nonce for the sender."
      ],
      call_data: [kind: :value, description: "Raw calldata bytes or `{abi_signature, params}` to ABI encode."],
      max_priority_fee_per_gas: [
        kind: :exchange_data,
        source: "Cartouche.RPC.max_priority_fee_per_gas/1",
        description: "EIP-1559 priority tip per gas as wei or `{amount, :wei | :gwei}`; not the V1 `gas_price`."
      ],
      max_fee_per_gas: [
        kind: :exchange_data,
        source: "Cartouche.RPC.fee_history/1",
        description: "EIP-1559 max total fee per gas as wei or `{amount, :wei | :gwei}`; not the V1 `gas_price`."
      ],
      gas_limit: [
        kind: :exchange_data,
        source: "Cartouche.RPC.estimate_gas/2",
        description: "Maximum gas units the transaction may consume."
      ],
      amount: [kind: :value, description: "Ether value as wei or `{amount, :wei | :gwei}`."],
      access_list: [kind: :value, description: "EIP-2930/EIP-1559 access list entries."],
      chain_id: [
        kind: :exchange_data,
        source: "Cartouche.RPC.eth_chain_id/1",
        default: nil,
        description: "Ethereum chain id atom/integer passed to Cartouche.Transaction.V2.new/9."
      ]
    ],
    returns: %{
      type: :transaction_v2,
      description: "%Cartouche.Transaction.V2{} ready to encode or sign."
    },
    composes_with: [:build_signed_trx_v2]
  )

  @doc """
  Builds a v2 (eip-1559)-style call to a given contract

  ## Examples

      iex> use Cartouche.Hex
      iex> Cartouche.Transaction.build_trx_v2(<<1::160>>, 6, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, {50, :gwei}, {10, :gwei}, 100_000, 0, [<<1::160>>], :goerli)
      %Cartouche.Transaction.V2{
        chain_id: 5,
        nonce: 6,
        max_priority_fee_per_gas: 50000000000,
        max_fee_per_gas: 10000000000,
        gas_limit: 100000,
        destination: <<1::160>>,
        amount: 0,
        data: ~h[0xA291ADD600000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000001],
        access_list: [{<<1::160>>, []}],
        signature_y_parity: nil,
        signature_r: nil,
        signature_s: nil
      }

      iex> use Cartouche.Hex
      iex> call_data = ~h[0xA291ADD600000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000001]
      ...> Cartouche.Transaction.build_trx_v2(<<1::160>>, 5, call_data, {50, :gwei}, {10, :gwei}, 100_000, 0, [<<1::160>>], :goerli)
      %Cartouche.Transaction.V2{
        chain_id: 5,
        nonce: 5,
        max_priority_fee_per_gas: 50000000000,
        max_fee_per_gas: 10000000000,
        gas_limit: 100000,
        destination: <<1::160>>,
        amount: 0,
        data: ~h[0xA291ADD600000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000001],
        access_list: [{<<1::160>>, []}],
        signature_y_parity: nil,
        signature_r: nil,
        signature_s: nil
      }
  """
  @spec build_trx_v2(
          <<_::160>>,
          integer(),
          binary() | {String.t(), [term()]},
          integer() | {integer(), :wei | :gwei} | nil,
          integer() | {integer(), :wei | :gwei} | nil,
          integer(),
          integer() | {integer(), :wei | :gwei},
          V2.access_list_input(),
          atom() | integer() | nil
        ) :: V2.t()
  def build_trx_v2(
        address,
        nonce,
        call_data,
        max_priority_fee_per_gas,
        max_fee_per_gas,
        gas_limit,
        amount,
        access_list,
        chain_id \\ nil
      )
      when is_list(access_list) do
    data =
      case call_data do
        {abi, params} ->
          ABI.encode(abi, params)

        call_data when is_binary(call_data) ->
          call_data
      end

    V2.new(
      nonce,
      max_priority_fee_per_gas,
      max_fee_per_gas,
      gas_limit,
      address,
      amount,
      data,
      access_list,
      chain_id
    )
  end

  api(:build_signed_trx, "Build and sign a legacy transaction.",
    params: [
      address: [kind: :value, description: "20-byte contract or recipient address."],
      nonce: [
        kind: :exchange_data,
        source: "Cartouche.RPC.get_transaction_count/2",
        description: "Account nonce for the sender."
      ],
      call_data: [kind: :value, description: "Raw calldata bytes or `{abi_signature, params}` to ABI encode."],
      gas_price: [
        kind: :exchange_data,
        source: "Cartouche.RPC.gas_price/1",
        description: "Legacy gas price as wei or `{amount, :wei | :gwei}`; `nil` leaves it unset."
      ],
      gas_limit: [
        kind: :exchange_data,
        source: "Cartouche.RPC.estimate_gas/2",
        description: "Maximum gas units the transaction may consume."
      ],
      value: [kind: :value, description: "Ether value as wei or `{amount, :wei | :gwei}`."],
      opts: [kind: :value, default: [], description: "Signing options."]
    ],
    opts: [
      signer: [kind: :value, default: Default, description: "Signer process name or pid."],
      chain_id: [
        kind: :exchange_data,
        source: "Cartouche.RPC.eth_chain_id/1",
        default: nil,
        description:
          "Ethereum chain id atom/integer used for signing; the `nil` default resolves to the application-configured chain (`config :cartouche, :chain_id`)."
      ],
      callback: [
        kind: :value,
        default: nil,
        description: "Optional function that can modify the transaction before signing."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, %Cartouche.Transaction.V1{}}` with signature fields populated, or `{:error, reason}`."
    },
    composes_with: [:build_trx]
  )

  @doc ~S"""
  Builds and signs a transaction, to be ready to be passed to JSON-RPC.

  Optionally takes a callback to modify the transaction before it is signed.

  ## Examples

      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, signed_trx} = Cartouche.Transaction.build_signed_trx(<<1::160>>, 5, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, {50, :gwei}, 100_000, 0, signer: signer_proc, chain_id: :goerli)
      iex> {:ok, signer} = Cartouche.Transaction.V1.recover_signer(signed_trx, 5)
      iex> Cartouche.Hex.to_address(signer)
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
  """
  @spec build_signed_trx(
          <<_::160>>,
          integer(),
          binary() | {String.t(), [term()]},
          integer() | {integer(), :wei | :gwei} | nil,
          integer(),
          integer() | {integer(), :wei | :gwei},
          Keyword.t()
        ) :: {:ok, V1.t()} | {:error, String.t()}
  def build_signed_trx(address, nonce, call_data, gas_price, gas_limit, value, opts \\ []) do
    signer = Keyword.get(opts, :signer, Default)
    chain_id = Keyword.get(opts, :chain_id)
    callback = Keyword.get(opts, :callback)

    transaction = build_trx(address, nonce, call_data, gas_price, gas_limit, value, chain_id)
    callback = if(is_nil(callback), do: fn trx -> {:ok, trx} end, else: callback)

    with {:ok, transaction} <- callback.(transaction),
         transaction_encoded = V1.encode(transaction),
         {:ok, signature} <- Cartouche.Signer.sign(transaction_encoded, signer, chain_id: chain_id) do
      {:ok, V1.add_signature(transaction, signature)}
    end
  end

  api(:build_signed_trx_v2, "Build and sign an EIP-1559 transaction.",
    params: [
      address: [kind: :value, description: "20-byte contract or recipient address."],
      nonce: [
        kind: :exchange_data,
        source: "Cartouche.RPC.get_transaction_count/2",
        description: "Account nonce for the sender."
      ],
      call_data: [kind: :value, description: "Raw calldata bytes or `{abi_signature, params}` to ABI encode."],
      max_priority_fee_per_gas: [
        kind: :exchange_data,
        source: "Cartouche.RPC.max_priority_fee_per_gas/1",
        description: "EIP-1559 priority tip per gas as wei or `{amount, :wei | :gwei}`; not the V1 `gas_price`."
      ],
      max_fee_per_gas: [
        kind: :exchange_data,
        source: "Cartouche.RPC.fee_history/1",
        description: "EIP-1559 max total fee per gas as wei or `{amount, :wei | :gwei}`; not the V1 `gas_price`."
      ],
      gas_limit: [
        kind: :exchange_data,
        source: "Cartouche.RPC.estimate_gas/2",
        description: "Maximum gas units the transaction may consume."
      ],
      amount: [kind: :value, description: "Ether value as wei or `{amount, :wei | :gwei}`."],
      access_list: [kind: :value, description: "EIP-2930/EIP-1559 access list entries."],
      opts: [kind: :value, default: [], description: "Signing options."]
    ],
    opts: [
      signer: [kind: :value, default: Default, description: "Signer process name or pid."],
      chain_id: [
        kind: :exchange_data,
        source: "Cartouche.RPC.eth_chain_id/1",
        default: nil,
        description:
          "Ethereum chain id atom/integer used for signing; the `nil` default resolves to the application-configured chain (`config :cartouche, :chain_id`)."
      ],
      callback: [
        kind: :value,
        default: nil,
        description: "Optional function that can modify the transaction before signing."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, %Cartouche.Transaction.V2{}}` with typed signature fields populated, or `{:error, reason}`."
    },
    composes_with: [:build_trx_v2]
  )

  @doc ~S"""
  Builds and signs a V2 transaction, to be ready to be passed to JSON-RPC.

  Optionally takes a callback to modify the transaction before it is signed.

  ## Examples

      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, signed_trx} = Cartouche.Transaction.build_signed_trx_v2(<<1::160>>, 5, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, {50, :gwei}, {10, :gwei}, 100_000, 0, [], signer: signer_proc, chain_id: :goerli)
      iex> {:ok, signer} = Cartouche.Transaction.V2.recover_signer(signed_trx)
      iex> Cartouche.Hex.to_address(signer)
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
  """
  @spec build_signed_trx_v2(
          <<_::160>>,
          integer(),
          binary() | {String.t(), [term()]},
          integer() | {integer(), :wei | :gwei} | nil,
          integer() | {integer(), :wei | :gwei} | nil,
          integer(),
          integer() | {integer(), :wei | :gwei},
          V2.access_list_input(),
          Keyword.t()
        ) :: {:ok, V2.t()} | {:error, String.t()}
  def build_signed_trx_v2(
        address,
        nonce,
        call_data,
        max_priority_fee_per_gas,
        max_fee_per_gas,
        gas_limit,
        amount,
        access_list,
        opts \\ []
      )
      when is_list(access_list) do
    signer = Keyword.get(opts, :signer, Default)
    chain_id = Keyword.get(opts, :chain_id)
    callback = Keyword.get(opts, :callback)

    transaction =
      build_trx_v2(
        address,
        nonce,
        call_data,
        max_priority_fee_per_gas,
        max_fee_per_gas,
        gas_limit,
        amount,
        access_list,
        chain_id
      )

    callback = if(is_nil(callback), do: fn trx -> {:ok, trx} end, else: callback)

    with {:ok, transaction} <- callback.(transaction),
         transaction_encoded = V2.encode(transaction),
         {:ok, signature} <- Cartouche.Signer.sign(transaction_encoded, signer, chain_id: chain_id) do
      {:ok, V2.add_signature(transaction, signature)}
    end
  end
end
