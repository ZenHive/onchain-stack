defmodule Faucet.ForkOverride do
  @moduledoc """
  The faucet for fork simulations: no provider, just the `state_overrides`
  map `Onchain.EVM.simulate_call/3` (and its siblings) accept.

  Funding a forked account means overriding its native balance and, for an
  ERC-20, the storage slot that holds `balances[holder]`. Solidity lays a
  `mapping(address => uint256)` at `keccak256(pad32(holder) ++ pad32(slot))`,
  where `slot` is the mapping's declaration index in the contract. WETH9 uses
  slot 3; most OpenZeppelin ERC-20s use slot 0 — check the contract.

  Needs the optional `onchain` dependency for keccak (`Onchain.Hash`).

  ## Example

      overrides =
        Faucet.ForkOverride.new()
        |> Faucet.ForkOverride.native(user, 10 ** 18)
        |> Faucet.ForkOverride.erc20(weth, user, 3, 5 * 10 ** 18)

      Onchain.EVM.simulate_call(pool, calldata, rpc_url: url, from: user, state_overrides: overrides)
  """

  use Descripex, namespace: "/faucet/fork_override"

  @typedoc ~s{Address → override map, as `Onchain.EVM` expects (`"balance"`, `"storage"` JSON string).}
  @type t :: %{optional(String.t()) => %{optional(String.t()) => String.t()}}

  api(:new, "Empty override map.", params: [], returns: %{type: :map, description: "`%{}`"})

  @spec new() :: t()
  def new, do: %{}

  api(:native, "Set `holder`'s native balance to `wei`.",
    params: [
      overrides: [kind: :value, description: "Override map to extend"],
      holder: [kind: :value, description: "0x-prefixed address"],
      wei: [kind: :value, description: "Balance in wei"]
    ],
    returns: %{type: :map, description: "Extended override map"}
  )

  @spec native(t(), String.t(), non_neg_integer()) :: t()
  def native(overrides, holder, wei) when is_map(overrides) and is_integer(wei) and wei >= 0 do
    Map.update(overrides, holder, %{"balance" => hex_quantity(wei)}, &Map.put(&1, "balance", hex_quantity(wei)))
  end

  api(:erc20, "Set `holder`'s balance in an ERC-20 whose `balances` mapping sits at declaration `slot`.",
    params: [
      overrides: [kind: :value, description: "Override map to extend"],
      token: [kind: :value, description: "0x-prefixed token contract address"],
      holder: [kind: :value, description: "0x-prefixed holder address"],
      slot: [kind: :value, description: "Declaration index of the balances mapping (WETH9: 3, OpenZeppelin: 0)"],
      amount: [kind: :value, description: "Balance in token base units"]
    ],
    returns: %{type: :map, description: "Extended override map; raises `ArgumentError` without `onchain`"}
  )

  @spec erc20(t(), String.t(), String.t(), non_neg_integer(), non_neg_integer()) :: t()
  def erc20(overrides, token, holder, slot, amount) when is_map(overrides) do
    entry = %{mapping_slot(holder, slot) => hex_quantity(amount)}

    Map.update(overrides, token, %{"storage" => Jason.encode!(entry)}, fn existing ->
      merged = existing |> Map.get("storage", "{}") |> Jason.decode!() |> Map.merge(entry)
      Map.put(existing, "storage", Jason.encode!(merged))
    end)
  end

  api(:mapping_slot, "Storage key of `mapping(address => _)[holder]` for a mapping declared at `slot`.",
    params: [
      holder: [kind: :value, description: "0x-prefixed address key"],
      slot: [kind: :value, description: "Declaration index of the mapping"]
    ],
    returns: %{type: :string, description: "0x-prefixed 32-byte hex storage key"}
  )

  @spec mapping_slot(String.t(), non_neg_integer()) :: String.t()
  def mapping_slot("0x" <> hex, slot) when byte_size(hex) == 40 and is_integer(slot) and slot >= 0 do
    if !Code.ensure_loaded?(Onchain.Hash) do
      raise ArgumentError, "Faucet.ForkOverride needs the optional :onchain dependency for keccak256"
    end

    holder_bin = Base.decode16!(hex, case: :mixed)
    digest = Onchain.Hash.keccak(<<0::96>> <> holder_bin <> <<slot::256>>)
    "0x" <> Base.encode16(digest, case: :lower)
  end

  api(:hex_quantity, "Encode an integer as a minimal 0x hex quantity.",
    params: [value: [kind: :value, description: "Non-negative integer"]],
    returns: %{type: :string, description: "`\"0x\"` + hex without leading zeros"}
  )

  @spec hex_quantity(non_neg_integer()) :: String.t()
  def hex_quantity(value) when is_integer(value) and value >= 0, do: "0x" <> Integer.to_string(value, 16)
end
