defmodule Onchain.RPC.Proof do
  @moduledoc """
  EIP-1186 account proof. Quantities are integers; addresses, hashes and RLP
  proof nodes are raw bytes. Storage keys are integers, accepting either padded
  DATA or QUANTITY encodings from clients. Proofs are not verified locally.
  """

  alias Onchain.Hex

  defmodule StorageProof do
    @moduledoc "A storage key, value and its RLP-encoded Merkle proof nodes."
    @enforce_keys [:key, :value, :proof]
    defstruct @enforce_keys
    @type t :: %__MODULE__{key: non_neg_integer(), value: non_neg_integer(), proof: [binary()]}
  end

  @enforce_keys [:address, :balance, :nonce, :code_hash, :storage_hash, :account_proof, :storage_proof]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          address: <<_::160>>,
          balance: non_neg_integer(),
          nonce: non_neg_integer(),
          code_hash: <<_::256>>,
          storage_hash: <<_::256>>,
          account_proof: [binary()],
          storage_proof: [StorageProof.t()]
        }

  @typedoc """
  An `eth_getProof` result as the node returns it: hex strings under
  `"address"`, `"balance"`, `"nonce"`, `"codeHash"`, `"storageHash"`, a hex list
  under `"accountProof"`, and `"storageProof"` entries.
  """
  @type raw :: %{required(String.t()) => String.t() | [String.t()] | [raw_storage()]}

  @typedoc ~s(One `storageProof` entry: hex `"key"` and `"value"`, hex list `"proof"`.)
  @type raw_storage :: %{required(String.t()) => String.t() | [String.t()]}

  @doc "Decodes all required EIP-1186 fields, raising on missing or malformed data."
  @spec deserialize(raw()) :: t()
  def deserialize(params) do
    %__MODULE__{
      address: Hex.decode_address!(Map.fetch!(params, "address")),
      balance: Hex.decode_hex_number!(Map.fetch!(params, "balance")),
      nonce: Hex.decode_hex_number!(Map.fetch!(params, "nonce")),
      code_hash: Hex.decode_word!(Map.fetch!(params, "codeHash")),
      storage_hash: Hex.decode_word!(Map.fetch!(params, "storageHash")),
      account_proof: Enum.map(Map.fetch!(params, "accountProof"), &Hex.decode_hex!/1),
      storage_proof: Enum.map(Map.fetch!(params, "storageProof"), &deserialize_storage/1)
    }
  end

  @spec deserialize_storage(raw_storage()) :: StorageProof.t()
  defp deserialize_storage(entry) do
    %StorageProof{
      key: Hex.decode_hex_number!(Map.fetch!(entry, "key")),
      value: Hex.decode_hex_number!(Map.fetch!(entry, "value")),
      proof: Enum.map(Map.fetch!(entry, "proof"), &Hex.decode_hex!/1)
    }
  end
end
