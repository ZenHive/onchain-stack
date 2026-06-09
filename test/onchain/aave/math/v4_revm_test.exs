defmodule Onchain.Aave.Math.V4RevmTest do
  @moduledoc """
  Cross-validates callable Aave V4 math against deployed mainnet bytecode via revm.

  V4 does not expose a standalone deployed WadRayMath contract in the address book.
  The live public math call site available from `V4_SCOPING.md` is the external
  LiquidationLogic library.
  """

  use ExUnit.Case, async: false

  alias Onchain.Aave.Math.V4
  alias Onchain.ABI
  alias Onchain.EVM
  alias Onchain.RPCCase

  @moduletag :integration
  @moduletag :math_revm
  @moduletag timeout: :infinity

  @liquidation_logic_address "0x88dF535473C5adf1f57789734A05E555F7Deb8DB"
  @post_v4_launch_block 25_000_000

  @health_factor_liquidation_threshold 1_000_000_000_000_000_000

  setup_all do
    {:ok, opts: [rpc_url: RPCCase.rpc_url!(), block: @post_v4_launch_block]}
  end

  describe "LiquidationLogic.calculateLiquidationBonus" do
    test "deterministic vectors agree with deployed V4 bytecode", ctx do
      vectors = [
        {div(@health_factor_liquidation_threshold, 2), 5_000, div(@health_factor_liquidation_threshold, 2), 11_000},
        {div(@health_factor_liquidation_threshold, 2), 5_000, div(3 * @health_factor_liquidation_threshold, 4), 11_000},
        {900_000_000_000_000_000, 2_500, 950_000_000_000_000_000, 10_800}
      ]

      for {health_factor_for_max_bonus, liquidation_bonus_factor, health_factor, max_liquidation_bonus} <- vectors do
        assert_same_as_revm(
          ctx,
          [
            health_factor_for_max_bonus,
            liquidation_bonus_factor,
            health_factor,
            max_liquidation_bonus
          ],
          fn ->
            V4.calculate_liquidation_bonus(
              health_factor_for_max_bonus,
              liquidation_bonus_factor,
              health_factor,
              max_liquidation_bonus
            )
          end
        )
      end
    end
  end

  @spec assert_same_as_revm(
          %{:opts => keyword(), optional(atom()) => term()},
          [non_neg_integer()],
          (-> non_neg_integer())
        ) :: :ok
  defp assert_same_as_revm(ctx, args, elixir_fun) do
    elixir = elixir_fun.()
    revm = call_liquidation_bonus(ctx, args)

    if elixir == revm do
      :ok
    else
      flunk("""
      calculateLiquidationBonus divergence!
        args:   #{inspect(args)}
        elixir: #{elixir}
        revm:   #{revm}
      """)
    end
  end

  @spec call_liquidation_bonus(%{:opts => keyword(), optional(atom()) => term()}, [
          non_neg_integer()
        ]) :: non_neg_integer()
  defp call_liquidation_bonus(ctx, args) do
    calldata =
      ABI.encode_call!(
        "calculateLiquidationBonus(uint256,uint256,uint256,uint256)",
        args
      )

    case EVM.simulate_call(@liquidation_logic_address, calldata, ctx.opts) do
      {:ok, hex} ->
        [value] = ABI.decode_response!("(uint256)", hex)
        value

      {:error, reason} ->
        flunk("""
        revm call failed for LiquidationLogic.calculateLiquidationBonus
          block:  #{@post_v4_launch_block}
          args:   #{inspect(args)}
          reason: #{inspect(reason)}
        """)
    end
  end
end
