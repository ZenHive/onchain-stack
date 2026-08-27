defmodule Onchain.Aave.Pool.IntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.Aave.Pool
  alias Onchain.Aave.Types.UserAccountData

  @moduletag :integration

  # Active Aave V3 borrower — same address used in math/contracts integration tests
  @known_borrower "0xF380B8F1e63e2BEd7CA329CA1FdDbC39B52cC0d3"

  describe "get_user_account_data/2 with known borrower" do
    test "returns {:ok, %UserAccountData{}} struct" do
      {:ok, data} = Pool.get_user_account_data(@known_borrower, Onchain.RPCCase.rpc_opts!())

      assert %UserAccountData{} = data
    end

    test "all values are Decimal structs" do
      {:ok, data} = Pool.get_user_account_data(@known_borrower, Onchain.RPCCase.rpc_opts!())

      assert %Decimal{} = data.total_collateral_base
      assert %Decimal{} = data.total_debt_base
      assert %Decimal{} = data.available_borrows_base
      assert %Decimal{} = data.current_liquidation_threshold
      assert %Decimal{} = data.ltv
      assert %Decimal{} = data.health_factor
    end

    test "active borrower has collateral > 0 and debt > 0" do
      {:ok, data} = Pool.get_user_account_data(@known_borrower, Onchain.RPCCase.rpc_opts!())

      assert Decimal.gt?(data.total_collateral_base, Decimal.new(0)),
             "Expected collateral > 0, got #{data.total_collateral_base}"

      assert Decimal.gt?(data.total_debt_base, Decimal.new(0)),
             "Expected debt > 0, got #{data.total_debt_base}"
    end

    test "health factor in sane range (1 to 100)" do
      {:ok, data} = Pool.get_user_account_data(@known_borrower, Onchain.RPCCase.rpc_opts!())

      assert Decimal.gt?(data.health_factor, Decimal.new(1)),
             "Expected health factor > 1, got #{data.health_factor}"

      assert Decimal.lt?(data.health_factor, Decimal.new(100)),
             "Expected health factor < 100, got #{data.health_factor}"
    end

    test "ltv and liquidation threshold between 0 and 1" do
      {:ok, data} = Pool.get_user_account_data(@known_borrower, Onchain.RPCCase.rpc_opts!())

      assert Decimal.gt?(data.ltv, Decimal.new(0)),
             "Expected ltv > 0, got #{data.ltv}"

      assert Decimal.lt?(data.ltv, Decimal.new(1)),
             "Expected ltv < 1, got #{data.ltv}"

      assert Decimal.gt?(data.current_liquidation_threshold, Decimal.new(0)),
             "Expected liq_threshold > 0, got #{data.current_liquidation_threshold}"

      assert Decimal.lte?(data.current_liquidation_threshold, Decimal.new(1)),
             "Expected liq_threshold <= 1, got #{data.current_liquidation_threshold}"
    end

    test "Aave invariant: liquidation threshold >= ltv" do
      {:ok, data} = Pool.get_user_account_data(@known_borrower, Onchain.RPCCase.rpc_opts!())

      assert Decimal.gte?(data.current_liquidation_threshold, data.ltv),
             "Expected liq_threshold (#{data.current_liquidation_threshold}) >= ltv (#{data.ltv})"
    end
  end

  describe "get_user_account_data/2 with binary address" do
    test "accepts 20-byte binary address" do
      {:ok, user_bin} = Onchain.Address.validate(@known_borrower)
      {:ok, data} = Pool.get_user_account_data(user_bin, Onchain.RPCCase.rpc_opts!())

      assert %UserAccountData{} = data
      assert Decimal.gt?(data.total_collateral_base, Decimal.new(0))
    end
  end

  describe "get_user_account_data/2 with zero-position address" do
    test "returns zero Decimals for address with no Aave position" do
      # Ethereum genesis address — extremely unlikely to have an Aave position
      zero_position = "0x0000000000000000000000000000000000000001"
      {:ok, data} = Pool.get_user_account_data(zero_position, Onchain.RPCCase.rpc_opts!())

      assert Decimal.eq?(data.total_collateral_base, Decimal.new(0)),
             "Expected collateral = 0, got #{data.total_collateral_base}"

      assert Decimal.eq?(data.total_debt_base, Decimal.new(0)),
             "Expected debt = 0, got #{data.total_debt_base}"

      assert Decimal.eq?(data.ltv, Decimal.new(0)),
             "Expected ltv = 0, got #{data.ltv}"
    end
  end

  describe "get_user_account_data!/2" do
    test "returns UserAccountData struct directly for known borrower" do
      data = Pool.get_user_account_data!(@known_borrower, Onchain.RPCCase.rpc_opts!())

      assert %UserAccountData{} = data
      assert %Decimal{} = data.health_factor
    end
  end

  describe "get_user_account_data_many/2" do
    # Ethereum address with no Aave position — all-zero result
    @zero_position "0x0000000000000000000000000000000000000001"

    test "returns one struct per input, aligned positionally" do
      {:ok, [borrower, zero]} =
        Pool.get_user_account_data_many([@known_borrower, @zero_position], Onchain.RPCCase.rpc_opts!())

      assert %UserAccountData{} = borrower
      assert %UserAccountData{} = zero

      # The active borrower has a real position; the empty address is all zeros.
      assert Decimal.gt?(borrower.total_collateral_base, Decimal.new(0))
      assert Decimal.eq?(zero.total_collateral_base, Decimal.new(0))
      assert Decimal.eq?(zero.total_debt_base, Decimal.new(0))
    end

    test "accepts 20-byte binary addresses" do
      {:ok, borrower_bin} = Onchain.Address.validate(@known_borrower)

      {:ok, [data]} = Pool.get_user_account_data_many([borrower_bin], Onchain.RPCCase.rpc_opts!())

      assert %UserAccountData{} = data
      assert Decimal.gt?(data.total_collateral_base, Decimal.new(0))
    end

    test "batched result matches the single-call result for the same user" do
      opts = Onchain.RPCCase.rpc_opts!()

      {:ok, single} = Pool.get_user_account_data(@known_borrower, opts)
      {:ok, [batched]} = Pool.get_user_account_data_many([@known_borrower], opts)

      assert Decimal.eq?(batched.total_collateral_base, single.total_collateral_base)
      assert Decimal.eq?(batched.total_debt_base, single.total_debt_base)
      assert Decimal.eq?(batched.ltv, single.ltv)
    end

    test "empty input short-circuits without an RPC call" do
      assert {:ok, []} = Pool.get_user_account_data_many([], Onchain.RPCCase.rpc_opts!())
    end
  end
end
