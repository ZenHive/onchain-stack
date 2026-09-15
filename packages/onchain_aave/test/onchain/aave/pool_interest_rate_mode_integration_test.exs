defmodule Onchain.Aave.PoolInterestRateModeIntegrationTest do
  @moduledoc """
  Independent protocol evidence that deployed ValidationLogic rejects interest
  rate mode 1 (STABLE). The public API rejects `:stable` locally; this fork
  scenario records the same rejection from the Pool itself after a borrowable
  position is established.
  """

  use ExUnit.Case, async: false

  alias Onchain.Aave.Types.UserAccountData
  alias Onchain.ABI
  alias Onchain.EVM
  alias Onchain.Hex
  alias Onchain.RPCCase

  @moduletag :integration

  @pool "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2"
  @weth "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
  @user "0x1111111111111111111111111111111111111111"
  @block 23_000_000
  @supply_amount 10 * 1_000_000_000_000_000_000
  @borrow_amount 1 * 1_000_000_000_000_000_000
  @weth_balance_slot 3

  # Errors.InvalidInterestRateModeSelected() — keccak selector independently
  # observed on this fork when borrow() is called with interestRateMode = 1.
  @invalid_interest_rate_mode_selector "0x17c5a78e"

  describe "deployed Pool rejects interest-rate mode 1" do
    test "a borrowable position reverts mode 1 and accepts mode 2 on the same fork" do
      {:ok, approve} = ABI.encode_call("approve(address,uint256)", [address_bin(@pool), @supply_amount])

      {:ok, supply} =
        ABI.encode_call("supply(address,uint256,address,uint16)", [
          address_bin(@weth),
          @supply_amount,
          address_bin(@user),
          0
        ])

      {:ok, query} = ABI.encode_call("getUserAccountData(address)", [address_bin(@user)])

      {:ok, borrow_stable} =
        ABI.encode_call("borrow(address,uint256,uint256,uint16,address)", [
          address_bin(@weth),
          @borrow_amount,
          1,
          0,
          address_bin(@user)
        ])

      {:ok, borrow_variable} =
        ABI.encode_call("borrow(address,uint256,uint256,uint16,address)", [
          address_bin(@weth),
          @borrow_amount,
          2,
          0,
          address_bin(@user)
        ])

      {:ok, results} =
        EVM.simulate_batch(
          [
            {@weth, approve},
            {@pool, supply},
            {@pool, query},
            {@pool, borrow_stable},
            {@pool, borrow_variable}
          ],
          [
            block: @block,
            from: @user,
            gas_limit: 1_000_000,
            timeout_ms: 120_000,
            state_overrides: %{
              @user => %{"balance" => hex_uint(@supply_amount)},
              @weth => %{"storage" => weth_balance_override(@supply_amount)}
            }
          ] ++ rpc_opts()
        )

      [approve_result, supply_result, query_result, stable_result, variable_result] = results

      assert approve_result.success
      assert supply_result.success
      assert query_result.success

      {:ok, raw} =
        ABI.decode_types("(uint256,uint256,uint256,uint256,uint256,uint256)", query_result.output)

      account = UserAccountData.from_raw(raw)
      assert Decimal.positive?(account.available_borrows_base)
      assert Decimal.eq?(account.total_debt_base, Decimal.new(0))

      refute stable_result.success
      assert revert_selector(stable_result) == @invalid_interest_rate_mode_selector

      assert variable_result.success
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

  defp revert_selector(%{output: output}) when is_binary(output) do
    hex = if String.starts_with?(output, "0x"), do: output, else: Hex.encode(output)
    String.slice(String.downcase(hex), 0, 10)
  end
end
