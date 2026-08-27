defmodule Onchain.ERC721 do
  @moduledoc """
  ERC-721 (NFT) read operations.

  Thin wrappers around `Onchain.Contract.call/5` for standard ERC-721 queries.
  Returns checksummed hex addresses for `owner_of/3` and `get_approved/3`.

  ## Error Format

  Errors pass through from underlying modules:

  | Source | Error Shape |
  |--------|-------------|
  | `Onchain.Address.validate/1` | `{:error, {:invalid_address, input}}` |
  | `Onchain.Contract.call/5` | `{:error, {:encode_error, ...}}`, `{:error, {:rpc_error, ...}}`, `{:error, {:decode_error, ...}}` |

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `balance_of/3` | Number of NFTs owned by an address |
  | `balance_of!/3` | Same, raises on error |
  | `owner_of/3` | Owner address of a specific token ID |
  | `owner_of!/3` | Same, raises on error |
  | `token_uri/3` | Metadata URI for a token ID |
  | `token_uri!/3` | Same, raises on error |
  | `name/2` | Collection name |
  | `name!/2` | Same, raises on error |
  | `symbol/2` | Collection symbol |
  | `symbol!/2` | Same, raises on error |
  | `get_approved/3` | Approved operator for a token ID |
  | `get_approved!/3` | Same, raises on error |
  | `approved_for_all?/4` | Whether an operator is approved for all tokens |
  | `approved_for_all!/4` | Same, raises on error |
  """

  use Descripex, namespace: "/erc721"

  alias Onchain.Address
  alias Onchain.Contract
  alias Onchain.ERC.Helpers

  # --- balance_of ---

  api(:balance_of, "Get the number of NFTs owned by an address.",
    params: [
      contract: [kind: :value, description: "ERC-721 contract address"],
      owner: [kind: :value, description: "Address to check balance for"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, non_neg_integer()} | {:error, term()}",
      description: "Number of NFTs owned",
      example: "3"
    }
  )

  @spec balance_of(String.t() | binary(), String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def balance_of(contract, owner, opts \\ []), do: Helpers.balance_of(contract, owner, opts)

  # --- balance_of! ---

  api(:balance_of!, "Get the number of NFTs owned by an address. Raises on error.",
    params: [
      contract: [kind: :value, description: "ERC-721 contract address"],
      owner: [kind: :value, description: "Address to check balance for"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :non_neg_integer, description: "Number of NFTs owned"}
  )

  @spec balance_of!(String.t() | binary(), String.t() | binary(), keyword()) :: non_neg_integer()
  def balance_of!(contract, owner, opts \\ []), do: Helpers.unwrap!(balance_of(contract, owner, opts), "balance_of")

  # --- owner_of ---

  api(:owner_of, "Get the owner of a specific token ID.",
    params: [
      contract: [kind: :value, description: "ERC-721 contract address"],
      token_id: [kind: :value, description: "Token ID (non-negative integer)"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Owner address as EIP-55 checksummed hex string",
      example: ~s("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
    }
  )

  @spec owner_of(String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def owner_of(contract, token_id, opts \\ []) do
    with {:ok, [addr_bin]} <- Contract.call(contract, "ownerOf(uint256)", [token_id], "(address)", opts) do
      Address.checksum(addr_bin)
    end
  end

  # --- owner_of! ---

  api(:owner_of!, "Get the owner of a specific token ID. Raises on error.",
    params: [
      contract: [kind: :value, description: "ERC-721 contract address"],
      token_id: [kind: :value, description: "Token ID (non-negative integer)"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :string, description: "Owner address as EIP-55 checksummed hex string"}
  )

  @spec owner_of!(String.t() | binary(), non_neg_integer(), keyword()) :: String.t()
  def owner_of!(contract, token_id, opts \\ []) do
    case owner_of(contract, token_id, opts) do
      {:ok, address} -> address
      {:error, reason} -> raise "owner_of failed: #{inspect(reason)}"
    end
  end

  # --- token_uri ---

  api(:token_uri, "Get the metadata URI for a token ID.",
    params: [
      contract: [kind: :value, description: "ERC-721 contract address"],
      token_id: [kind: :value, description: "Token ID (non-negative integer)"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Token metadata URI",
      example: ~s("ipfs://QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq/1")
    }
  )

  @spec token_uri(String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def token_uri(contract, token_id, opts \\ []) do
    with {:ok, [uri]} <- Contract.call(contract, "tokenURI(uint256)", [token_id], "(string)", opts) do
      {:ok, uri}
    end
  end

  # --- token_uri! ---

  api(:token_uri!, "Get the metadata URI for a token ID. Raises on error.",
    params: [
      contract: [kind: :value, description: "ERC-721 contract address"],
      token_id: [kind: :value, description: "Token ID (non-negative integer)"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :string, description: "Token metadata URI"}
  )

  @spec token_uri!(String.t() | binary(), non_neg_integer(), keyword()) :: String.t()
  def token_uri!(contract, token_id, opts \\ []) do
    case token_uri(contract, token_id, opts) do
      {:ok, uri} -> uri
      {:error, reason} -> raise "token_uri failed: #{inspect(reason)}"
    end
  end

  # --- name ---

  api(:name, "Get the collection name.",
    params: [
      contract: [kind: :value, description: "ERC-721 contract address"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Collection name",
      example: ~s("BoredApeYachtClub")
    }
  )

  @spec name(String.t() | binary(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def name(contract, opts \\ []) do
    with {:ok, [value]} <- Contract.call(contract, "name()", [], "(string)", opts) do
      {:ok, value}
    end
  end

  # --- name! ---

  api(:name!, "Get the collection name. Raises on error.",
    params: [
      contract: [kind: :value, description: "ERC-721 contract address"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :string, description: "Collection name"}
  )

  @spec name!(String.t() | binary(), keyword()) :: String.t()
  def name!(contract, opts \\ []) do
    case name(contract, opts) do
      {:ok, value} -> value
      {:error, reason} -> raise "name failed: #{inspect(reason)}"
    end
  end

  # --- symbol ---

  api(:symbol, "Get the collection symbol.",
    params: [
      contract: [kind: :value, description: "ERC-721 contract address"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Collection symbol",
      example: ~s("BAYC")
    }
  )

  @spec symbol(String.t() | binary(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def symbol(contract, opts \\ []) do
    with {:ok, [value]} <- Contract.call(contract, "symbol()", [], "(string)", opts) do
      {:ok, value}
    end
  end

  # --- symbol! ---

  api(:symbol!, "Get the collection symbol. Raises on error.",
    params: [
      contract: [kind: :value, description: "ERC-721 contract address"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :string, description: "Collection symbol"}
  )

  @spec symbol!(String.t() | binary(), keyword()) :: String.t()
  def symbol!(contract, opts \\ []), do: Helpers.unwrap!(symbol(contract, opts), "symbol")

  # --- get_approved ---

  api(:get_approved, "Get the approved address for a specific token ID.",
    params: [
      contract: [kind: :value, description: "ERC-721 contract address"],
      token_id: [kind: :value, description: "Token ID (non-negative integer)"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Approved address as EIP-55 checksummed hex string (zero address if none)",
      example: ~s("0x0000000000000000000000000000000000000000")
    }
  )

  @spec get_approved(String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def get_approved(contract, token_id, opts \\ []) do
    with {:ok, [addr_bin]} <-
           Contract.call(contract, "getApproved(uint256)", [token_id], "(address)", opts) do
      Address.checksum(addr_bin)
    end
  end

  # --- get_approved! ---

  api(:get_approved!, "Get the approved address for a specific token ID. Raises on error.",
    params: [
      contract: [kind: :value, description: "ERC-721 contract address"],
      token_id: [kind: :value, description: "Token ID (non-negative integer)"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :string, description: "Approved address as EIP-55 checksummed hex string"}
  )

  @spec get_approved!(String.t() | binary(), non_neg_integer(), keyword()) :: String.t()
  def get_approved!(contract, token_id, opts \\ []) do
    case get_approved(contract, token_id, opts) do
      {:ok, address} -> address
      {:error, reason} -> raise "get_approved failed: #{inspect(reason)}"
    end
  end

  # --- approved_for_all? ---

  api(:approved_for_all?, "Check if an operator is approved for all tokens of an owner.",
    params: [
      contract: [kind: :value, description: "ERC-721 contract address"],
      owner: [kind: :value, description: "Token owner address"],
      operator: [kind: :value, description: "Operator address to check"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, boolean()} | {:error, term()}",
      description: "Whether the operator is approved for all tokens",
      example: "false"
    }
  )

  @spec approved_for_all?(
          String.t() | binary(),
          String.t() | binary(),
          String.t() | binary(),
          keyword()
        ) :: {:ok, boolean()} | {:error, term()}
  def approved_for_all?(contract, owner, operator, opts \\ []),
    do: Helpers.approved_for_all?(contract, owner, operator, opts)

  # --- approved_for_all! ---

  api(:approved_for_all!, "Check if an operator is approved for all tokens. Raises on error.",
    params: [
      contract: [kind: :value, description: "ERC-721 contract address"],
      owner: [kind: :value, description: "Token owner address"],
      operator: [kind: :value, description: "Operator address to check"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :boolean, description: "Whether the operator is approved for all tokens"}
  )

  @spec approved_for_all!(
          String.t() | binary(),
          String.t() | binary(),
          String.t() | binary(),
          keyword()
        ) :: boolean()
  def approved_for_all!(contract, owner, operator, opts \\ []),
    do: Helpers.unwrap!(approved_for_all?(contract, owner, operator, opts), "approved_for_all?")
end
