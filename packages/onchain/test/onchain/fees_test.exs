defmodule Onchain.FeesTest do
  use ExUnit.Case, async: true

  alias Cartouche.FeeHistory
  alias Onchain.Fees

  # Helper to build a deterministic FeeHistory struct.
  defp history(base_fees, reward) do
    %FeeHistory{
      oldest_block: 1,
      base_fee_per_gas: base_fees,
      gas_used_ratio: List.duplicate(0.5, length(reward)),
      reward: reward
    }
  end

  describe "suggest_fees/2" do
    test "happy path with default percentile_index and buffer" do
      h =
        history(
          [100, 110, 120, 130, 140, 150],
          [[1_000_000_000], [2_000_000_000], [1_500_000_000], [3_000_000_000], [2_500_000_000]]
        )

      {:ok, {base, prio, max_fee}} = Fees.suggest_fees(h)

      # base_fee_per_gas[last] is the projected next-block fee per the
      # eth_feeHistory spec (oldest-to-newest with the projection at index N).
      assert base == 150
      # median of [1, 2, 1.5, 3, 2.5] gwei = 2 gwei
      assert prio == 2_000_000_000
      # ceil(150 * 1.2) + 2_000_000_000 = 180 + 2_000_000_000
      assert max_fee == 180 + 2_000_000_000
    end

    test "selects column via :percentile_index" do
      h =
        history(
          [200, 210],
          [[100, 200, 300], [400, 500, 600]]
        )

      {:ok, {_, prio_0, _}} = Fees.suggest_fees(h, percentile_index: 0)
      {:ok, {_, prio_1, _}} = Fees.suggest_fees(h, percentile_index: 1)
      {:ok, {_, prio_2, _}} = Fees.suggest_fees(h, percentile_index: 2)

      # median of [100, 400] = 250; [200, 500] = 350; [300, 600] = 450
      assert prio_0 == 250
      assert prio_1 == 350
      assert prio_2 == 450
    end

    test ":buffer applied to base_fee for max_fee" do
      h = history([1_000], [[100], [100], [100]])

      {:ok, {_, _, max_12}} = Fees.suggest_fees(h, buffer: 1.2)
      {:ok, {_, _, max_20}} = Fees.suggest_fees(h, buffer: 2.0)

      # ceil(1000 * 1.2) + 100 = 1200 + 100; ceil(1000 * 2.0) + 100 = 2000 + 100
      assert max_12 == 1_300
      assert max_20 == 2_100
    end

    test "integer :buffer is accepted (regression: Float.ceil/1 rejected integers)" do
      h = history([1_000], [[100]])
      assert {:ok, {1_000, 100, 2_100}} = Fees.suggest_fees(h, buffer: 2)
    end

    test "median: odd-length list" do
      h = history([100], [[1], [3], [5]])
      {:ok, {_, prio, _}} = Fees.suggest_fees(h)
      # median of [1, 3, 5] = 3
      assert prio == 3
    end

    test "median: even-length list averages two middle values (rounded down)" do
      h = history([100], [[1], [2], [3], [4]])
      {:ok, {_, prio, _}} = Fees.suggest_fees(h)
      # median of [1, 2, 3, 4] = (2 + 3) / 2 = 2 (integer div)
      assert prio == 2
    end

    test "single-element reward list" do
      h = history([100], [[42]])
      {:ok, {_, prio, _}} = Fees.suggest_fees(h)
      assert prio == 42
    end

    test "ceil with non-integer base_fee × buffer product" do
      # 105 * 1.2 = 126.0 — already integer, no rounding
      h_no_round = history([105], [[10]])
      {:ok, {_, _, max_fee_no_round}} = Fees.suggest_fees(h_no_round, buffer: 1.2)
      assert max_fee_no_round == 126 + 10

      # 100 * 1.234 = 123.4 — must ceil to 124
      h_round = history([100], [[10]])
      {:ok, {_, _, max_fee_round}} = Fees.suggest_fees(h_round, buffer: 1.234)
      assert max_fee_round == 124 + 10
    end

    test "error: reward is nil" do
      h = %FeeHistory{
        oldest_block: 1,
        base_fee_per_gas: [100, 110],
        gas_used_ratio: [0.5],
        reward: nil
      }

      assert {:error, :no_reward_data} = Fees.suggest_fees(h)
    end

    test "error: reward is empty" do
      h = %FeeHistory{
        oldest_block: 1,
        base_fee_per_gas: [100, 110],
        gas_used_ratio: [],
        reward: []
      }

      assert {:error, :no_reward_data} = Fees.suggest_fees(h)
    end

    test "error: base_fee_per_gas is empty" do
      h = %FeeHistory{
        oldest_block: 1,
        base_fee_per_gas: [],
        gas_used_ratio: [0.5],
        reward: [[1000]]
      }

      assert {:error, :no_base_fee_data} = Fees.suggest_fees(h)
    end

    test "error: base_fee_per_gas is nil" do
      h = %FeeHistory{
        oldest_block: 1,
        base_fee_per_gas: nil,
        gas_used_ratio: [0.5],
        reward: [[1000]]
      }

      assert {:error, :no_base_fee_data} = Fees.suggest_fees(h)
    end

    test "error: last base_fee_per_gas entry is not a number" do
      h = %FeeHistory{
        oldest_block: 1,
        base_fee_per_gas: [100, "0x1a"],
        gas_used_ratio: [0.5],
        reward: [[1000]]
      }

      assert {:error, {:invalid_base_fee, "0x1a"}} = Fees.suggest_fees(h)
    end

    test "error: ragged reward rows bound the index by the narrowest row" do
      # A non-conforming node returns fewer columns for one block. The index is valid
      # for the first row but absent from the second — previously this crashed in
      # round(nil) mid-map instead of returning an error tuple.
      h = history([10, 20], [[1000, 2000], [1500]])

      assert {:error, {:percentile_index_out_of_range, 1, 1}} =
               Fees.suggest_fees(h, percentile_index: 1)
    end

    test "ragged reward rows still resolve an index every row carries" do
      h = history([10, 20], [[1000, 2000], [1500]])

      assert {:ok, {20, 1250, 1274}} = Fees.suggest_fees(h)
    end

    test "error: a reward row is not a list" do
      h = %FeeHistory{
        oldest_block: 1,
        base_fee_per_gas: [100, 110],
        gas_used_ratio: [0.5],
        reward: [[10], :garbage]
      }

      assert {:error, :no_reward_data} = Fees.suggest_fees(h)
    end

    test "error: percentile_index out of range" do
      h = history([100], [[10, 20]])

      assert {:error, {:percentile_index_out_of_range, 5, 2}} =
               Fees.suggest_fees(h, percentile_index: 5)
    end

    test "error: negative percentile_index" do
      h = history([100], [[10]])

      assert {:error, {:percentile_index_out_of_range, -1, 1}} =
               Fees.suggest_fees(h, percentile_index: -1)
    end

    test "error: invalid buffer (zero)" do
      h = history([100], [[10]])
      assert {:error, {:invalid_buffer, 0}} = Fees.suggest_fees(h, buffer: 0)
    end

    test "error: invalid buffer (negative)" do
      h = history([100], [[10]])
      assert {:error, {:invalid_buffer, -1.0}} = Fees.suggest_fees(h, buffer: -1.0)
    end

    test "error: non-numeric buffer" do
      h = history([100], [[10]])
      assert {:error, {:invalid_buffer, :nope}} = Fees.suggest_fees(h, buffer: :nope)
    end
  end

  describe "suggest_fees!/2" do
    test "returns tuple on success" do
      h = history([100, 110], [[1_000_000_000], [2_000_000_000]])
      # base_fee = List.last([100, 110]) = 110 (next-block projection per spec).
      assert {110, 1_500_000_000, _} = Fees.suggest_fees!(h)
    end

    test "raises on error" do
      h = %FeeHistory{
        oldest_block: 1,
        base_fee_per_gas: [100],
        gas_used_ratio: [],
        reward: nil
      }

      assert_raise RuntimeError, ~r/suggest_fees failed.*no_reward_data/, fn ->
        Fees.suggest_fees!(h)
      end
    end
  end
end
