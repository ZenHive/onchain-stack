defmodule Onchain.ERC1155 do
  @moduledoc """
  ERC-1155 (Multi Token) read operations.

  Thin wrappers around `Onchain.Contract.call/5` for standard ERC-1155 queries.
  ERC-1155 is semi-fungible: the same token ID can have multiple owners with
  different balances.

  ## Error Format

  Errors pass through from underlying modules:

  | Source | Error Shape |
  |--------|-------------|
  | `Onchain.Address.validate/1` | `{:error, {:invalid_address, input}}` |
  | `Onchain.Contract.call/5` | `{:error, {:encode_error, ...}}`, `{:error, {:rpc_error, ...}}`, `{:error, {:decode_error, ...}}` |

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `balance_of/4` | Balance of a specific token ID for an owner |
  | `balance_of!/4` | Same, raises on error |
  | `balance_of_batch/4` | Batch balance query for multiple owner/token pairs |
  | `balance_of_batch!/4` | Same, raises on error |
  | `uri/3` | Metadata URI for a token ID |
  | `uri!/3` | Same, raises on error |
  | `approved_for_all?/4` | Whether an operator is approved for all tokens |
  | `approved_for_all!/4` | Same, raises on error |
  """

  use Descripex, namespace: "/erc1155"

  alias Onchain.Address
  alias Onchain.Contract
  alias Onchain.ERC.Helpers

  # --- balance_of ---

  api(:balance_of, "Get the balance of a specific token ID for an owner.",
    params: [
      contract: [kind: :value, description: "ERC-1155 contract address"],
      owner: [kind: :value, description: "Address to check balance for"],
      token_id: [kind: :value, description: "Token ID (non-negative integer)"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, non_neg_integer()} | {:error, term()}",
      description: "Balance of the token ID for the owner",
      example: "10"
    }
  )

  @spec balance_of(String.t() | binary(), String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def balance_of(contract, owner, token_id, opts \\ []) do
    with {:ok, owner_bin} <- Address.validate(owner),
         {:ok, [balance]} <-
           Contract.call(
             contract,
             "balanceOf(address,uint256)",
             [owner_bin, token_id],
             "(uint256)",
             opts
           ) do
      {:ok, balance}
    end
  end

  # --- balance_of! ---

  api(:balance_of!, "Get the balance of a specific token ID for an owner. Raises on error.",
    params: [
      contract: [kind: :value, description: "ERC-1155 contract address"],
      owner: [kind: :value, description: "Address to check balance for"],
      token_id: [kind: :value, description: "Token ID (non-negative integer)"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :non_neg_integer, description: "Balance of the token ID"}
  )

  @spec balance_of!(String.t() | binary(), String.t() | binary(), non_neg_integer(), keyword()) ::
          non_neg_integer()
  def balance_of!(contract, owner, token_id, opts \\ []) do
    case balance_of(contract, owner, token_id, opts) do
      {:ok, balance} -> balance
      {:error, reason} -> raise "balance_of failed: #{inspect(reason)}"
    end
  end

  # --- balance_of_batch ---

  api(:balance_of_batch, "Batch query balances for multiple owner/token ID pairs.",
    params: [
      contract: [kind: :value, description: "ERC-1155 contract address"],
      owners: [kind: :value, description: "List of owner addresses (must match token_ids length)"],
      token_ids: [kind: :value, description: "List of token IDs (must match owners length)"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, [non_neg_integer()]} | {:error, term()}",
      description: "List of balances corresponding to each owner/token_id pair",
      example: "[10, 0, 5]"
    }
  )

  @spec balance_of_batch(
          String.t() | binary(),
          [String.t() | binary()],
          [non_neg_integer()],
          keyword()
        ) :: {:ok, [non_neg_integer()]} | {:error, term()}
  def balance_of_batch(contract, owners, token_ids, opts \\ [])

  def balance_of_batch(_contract, owners, _token_ids, _opts) when not is_list(owners) do
    {:error, {:invalid_input, "owners must be a list"}}
  end

  def balance_of_batch(_contract, _owners, token_ids, _opts) when not is_list(token_ids) do
    {:error, {:invalid_input, "token_ids must be a list"}}
  end

  def balance_of_batch(_contract, owners, token_ids, _opts) when length(owners) != length(token_ids) do
    {:error, {:length_mismatch, %{owners: length(owners), token_ids: length(token_ids)}}}
  end

  def balance_of_batch(contract, owners, token_ids, opts) do
    with {:ok, owner_bins} <- validate_addresses(owners),
         {:ok, [balances]} <-
           Contract.call(
             contract,
             "balanceOfBatch(address[],uint256[])",
             [owner_bins, token_ids],
             "(uint256[])",
             opts
           ) do
      {:ok, balances}
    end
  end

  # --- balance_of_batch! ---

  api(:balance_of_batch!, "Batch query balances. Raises on error.",
    params: [
      contract: [kind: :value, description: "ERC-1155 contract address"],
      owners: [kind: :value, description: "List of owner addresses (must match token_ids length)"],
      token_ids: [kind: :value, description: "List of token IDs (must match owners length)"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: "[non_neg_integer()]", description: "List of balances"}
  )

  @spec balance_of_batch!(
          String.t() | binary(),
          [String.t() | binary()],
          [non_neg_integer()],
          keyword()
        ) :: [non_neg_integer()]
  def balance_of_batch!(contract, owners, token_ids, opts \\ []) do
    case balance_of_batch(contract, owners, token_ids, opts) do
      {:ok, balances} -> balances
      {:error, reason} -> raise "balance_of_batch failed: #{inspect(reason)}"
    end
  end

  # --- uri ---

  api(:uri, "Get the metadata URI for a token ID.",
    params: [
      contract: [kind: :value, description: "ERC-1155 contract address"],
      token_id: [kind: :value, description: "Token ID (non-negative integer)"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Token metadata URI (may contain {id} placeholder per ERC-1155 spec)",
      example: ~s("https://token-cdn-domain/{id}.json")
    }
  )

  @spec uri(String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def uri(contract, token_id, opts \\ []) do
    with {:ok, [value]} <- Contract.call(contract, "uri(uint256)", [token_id], "(string)", opts) do
      {:ok, value}
    end
  end

  # --- uri! ---

  api(:uri!, "Get the metadata URI for a token ID. Raises on error.",
    params: [
      contract: [kind: :value, description: "ERC-1155 contract address"],
      token_id: [kind: :value, description: "Token ID (non-negative integer)"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :string, description: "Token metadata URI"}
  )

  @spec uri!(String.t() | binary(), non_neg_integer(), keyword()) :: String.t()
  def uri!(contract, token_id, opts \\ []) do
    case uri(contract, token_id, opts) do
      {:ok, value} -> value
      {:error, reason} -> raise "uri failed: #{inspect(reason)}"
    end
  end

  # --- approved_for_all? ---

  api(:approved_for_all?, "Check if an operator is approved for all tokens of an owner.",
    params: [
      contract: [kind: :value, description: "ERC-1155 contract address"],
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
      contract: [kind: :value, description: "ERC-1155 contract address"],
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

  # Validates a list of addresses, returning all as binaries or the first error.
  @spec validate_addresses([String.t() | binary()]) :: {:ok, [binary()]} | {:error, term()}
  defp validate_addresses(addresses) do
    addresses
    |> Enum.reduce_while({:ok, []}, fn addr, {:ok, acc} ->
      case Address.validate(addr) do
        {:ok, bin} -> {:cont, {:ok, [bin | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, bins} -> {:ok, Enum.reverse(bins)}
      error -> error
    end
  end
end
