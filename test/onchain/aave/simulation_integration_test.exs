defmodule Onchain.Aave.SimulationIntegrationTest do
  @moduledoc """
  Pins the local-fork simulation surface documented in README's
  "Local simulation against forked state".

  The three claims under test are the ones a reader relies on: the fork's
  `BlockEnv` mirrors the forked block header, a `"storage"` override amends an
  account rather than replacing it, and Aave's *write* paths — not just reads —
  execute end to end on the fork.

  Everything runs at a pinned block so the expected values are fixed rather
  than "whatever the chain says today".
  """

  use ExUnit.Case, async: false

  alias Onchain.Aave.Oracle
  alias Onchain.Aave.Types.UserAccountData
  alias Onchain.ABI
  alias Onchain.EVM
  alias Onchain.Hex
  alias Onchain.RPC
  alias Onchain.RPCCase

  @moduletag :integration

  @pool "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2"
  @weth "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
  @multicall3 "0xcA11bde05977b3631167028862bE2a173976CA11"

  # An address with no history on mainnet, so its state is exactly what the
  # overrides put there.
  @user "0x1111111111111111111111111111111111111111"

  @block 21_000_000
  @supply_amount 10 * 1_000_000_000_000_000_000

  # WETH keeps its balanceOf mapping at storage slot 3.
  @weth_balance_slot 3

  # Multicall3 block-introspection selectors.
  @get_block_number "0x42cbb15c"
  @get_block_timestamp "0x0f28c97d"
  @get_basefee "0x3e64a696"
  @get_gas_limit "0x86d516e8"
  @get_coinbase "0xa8b0574e"

  # ERC-20 decimals().
  @decimals "0x313ce567"

  describe "fork block environment" do
    test "number, timestamp, basefee, gas limit and coinbase come from the forked header" do
      {:ok, header} = RPC.get_block_by_number(@block, rpc_opts())

      assert read_uint(@get_block_number) == header.number
      assert read_uint(@get_block_timestamp) == header.timestamp
      assert read_uint(@get_basefee) == header.base_fee_per_gas
      assert read_uint(@get_gas_limit) == header.gas_limit
      assert read_address(@get_coinbase) == String.downcase(header.miner)
    end

    test "an Aave read that accrues interest against block.timestamp does not revert" do
      # getReserveNormalizedIncome runs MathUtils.calculateLinearInterest, which
      # subtracts the reserve's lastUpdateTimestamp from block.timestamp. A fork
      # left at a 1970 clock underflows here instead of returning an index.
      {:ok, data} = ABI.encode_call("getReserveNormalizedIncome(address)", [address_bin(@weth)])
      {:ok, out} = EVM.simulate_call(@pool, data, [block: @block] ++ rpc_opts())
      {:ok, [index]} = ABI.decode_types("(uint256)", out)

      # Liquidity indices start at 1 ray and only grow.
      assert index >= 1_000_000_000_000_000_000_000_000_000
    end
  end

  describe "state overrides" do
    test "a storage override amends the account and leaves its deployed code intact" do
      overrides = %{@weth => %{"storage" => weth_balance_override(@supply_amount)}}
      opts = [block: @block, state_overrides: overrides] ++ rpc_opts()

      {:ok, balance_data} = ABI.encode_call("balanceOf(address)", [address_bin(@user)])
      {:ok, balance_out} = EVM.simulate_call(@weth, balance_data, opts)
      {:ok, [balance]} = ABI.decode_types("(uint256)", balance_out)

      assert balance == @supply_amount

      # The account still answers as WETH rather than as a code-less EOA.
      {:ok, decimals_out} = EVM.simulate_call(@weth, @decimals, opts)
      {:ok, [decimals]} = ABI.decode_types("(uint8)", decimals_out)

      assert decimals == 18
    end
  end

  describe "Aave write paths on a fork" do
    test "approve, supply and read back the position on one fork" do
      {:ok, approve} = ABI.encode_call("approve(address,uint256)", [address_bin(@pool), @supply_amount])

      {:ok, supply} =
        ABI.encode_call("supply(address,uint256,address,uint16)", [
          address_bin(@weth),
          @supply_amount,
          address_bin(@user),
          0
        ])

      {:ok, query} = ABI.encode_call("getUserAccountData(address)", [address_bin(@user)])

      {:ok, [approve_result, supply_result, query_result]} =
        EVM.simulate_batch(
          [{@weth, approve}, {@pool, supply}, {@pool, query}],
          [
            block: @block,
            from: @user,
            state_overrides: %{
              @user => %{"balance" => hex_uint(@supply_amount)},
              @weth => %{"storage" => weth_balance_override(@supply_amount)}
            }
          ] ++ rpc_opts()
        )

      assert approve_result.success
      assert supply_result.success

      # Aave mints aWETH to the supplier — the marker that the deposit landed
      # rather than merely not reverting.
      assert Enum.any?(supply_result.logs, &mint_to_user?/1)

      {:ok, raw} =
        ABI.decode_types("(uint256,uint256,uint256,uint256,uint256,uint256)", query_result.output)

      account = UserAccountData.from_raw(raw)

      # The position is worth exactly what the Aave oracle prices it at, at the
      # same block: 10 WETH * price. Both sides are in the pool's 8-decimal base
      # currency, so this cross-checks the whole path against an independent read.
      {:ok, price} = Oracle.get_asset_price(@weth, [block: @block] ++ rpc_opts())
      expected = price |> Decimal.new() |> Decimal.mult(Decimal.new(10)) |> Decimal.div(Decimal.new(100_000_000))

      assert Decimal.equal?(account.total_collateral_base, expected)
      assert Decimal.equal?(account.total_debt_base, Decimal.new(0))
      assert Decimal.positive?(account.ltv)
      assert Decimal.compare(account.current_liquidation_threshold, account.ltv) in [:gt, :eq]
    end
  end

  defp rpc_opts, do: RPCCase.rpc_opts!()

  defp address_bin(address), do: Hex.decode!(address)

  defp hex_uint(value), do: "0x" <> Integer.to_string(value, 16)

  defp weth_balance_override(amount) do
    slot =
      (<<0::96>> <> address_bin(@user) <> <<@weth_balance_slot::256>>)
      |> Cartouche.Hash.keccak()
      |> Hex.encode()

    JSON.encode!(%{slot => hex_uint(amount)})
  end

  defp read_uint(selector) do
    {:ok, out} = EVM.simulate_call(@multicall3, selector, [block: @block] ++ rpc_opts())
    {:ok, [value]} = ABI.decode_types("(uint256)", out)
    value
  end

  defp read_address(selector) do
    {:ok, out} = EVM.simulate_call(@multicall3, selector, [block: @block] ++ rpc_opts())
    {:ok, [value]} = ABI.decode_types("(address)", out)
    value |> Hex.encode() |> String.downcase()
  end

  # --- helpers ---

  # ERC-20 Transfer(address,address,uint256) from the zero address is a mint.
  @transfer_topic "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
  @zero_topic "0x0000000000000000000000000000000000000000000000000000000000000000"

  defp mint_to_user?(%{topics: [@transfer_topic, @zero_topic, to]}) do
    String.ends_with?(String.downcase(to), String.downcase(String.replace_prefix(@user, "0x", "")))
  end

  defp mint_to_user?(_log), do: false
end
