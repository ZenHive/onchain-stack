defmodule Onchain.ERC.Helpers do
  @moduledoc false

  # Shared helpers for ERC-standard wrapper modules (Onchain.ERC20, Onchain.ERC721,
  # Onchain.ERC1155). Extracted to satisfy `mix ex_dna --max-clones 0`:
  #
  #   * `balance_of/3` — ERC-20's `balance_of/3` (token balance) and ERC-721's
  #     `balance_of/3` (owned-NFT count) both call the identical
  #     `balanceOf(address)` selector and decode a single `uint256` — the same
  #     on-chain call; only the caller-side meaning of the integer differs.
  #     ERC-1155's `balance_of/4` is deliberately NOT folded in here: it takes an
  #     extra `token_id` argument and calls the distinct
  #     `balanceOf(address,uint256)` selector — a real arity/semantic
  #     difference, not a clone (see Onchain.ERC1155.balance_of/4).
  #   * `approved_for_all?/4` — ERC-721 and ERC-1155 share the identical
  #     `isApprovedForAll(address,address)` operator-approval check, byte for
  #     byte.
  #   * `unwrap!/2` — the generic "call the read function, raise on error"
  #     pattern behind every `*!` wrapper (`balance_of!`, `symbol!`,
  #     `approved_for_all!`, ...).

  alias Onchain.Address
  alias Onchain.Contract

  @doc false
  @spec balance_of(String.t() | binary(), String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def balance_of(contract, address, opts) do
    with {:ok, address_bin} <- Address.validate(address),
         {:ok, [value]} <-
           Contract.call(contract, "balanceOf(address)", [address_bin], "(uint256)", opts) do
      {:ok, value}
    end
  end

  @doc false
  @spec approved_for_all?(
          String.t() | binary(),
          String.t() | binary(),
          String.t() | binary(),
          keyword()
        ) :: {:ok, boolean()} | {:error, term()}
  def approved_for_all?(contract, owner, operator, opts) do
    with {:ok, owner_bin} <- Address.validate(owner),
         {:ok, operator_bin} <- Address.validate(operator),
         {:ok, [approved]} <-
           Contract.call(
             contract,
             "isApprovedForAll(address,address)",
             [owner_bin, operator_bin],
             "(bool)",
             opts
           ) do
      {:ok, approved}
    end
  end

  @doc false
  # Unwraps an {:ok, value} | {:error, reason} result, raising "<label> failed: ..."
  # on error. Shared body behind every bang wrapper in ERC20/ERC721/ERC1155.
  @spec unwrap!({:ok, value} | {:error, term()}, String.t()) :: value when value: term()
  def unwrap!({:ok, value}, _label), do: value
  def unwrap!({:error, reason}, label), do: raise("#{label} failed: #{inspect(reason)}")
end
