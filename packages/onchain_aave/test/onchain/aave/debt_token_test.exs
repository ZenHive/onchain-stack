defmodule Onchain.Aave.DebtTokenTest do
  use ExUnit.Case, async: false

  alias Onchain.Aave.DebtToken
  alias Onchain.RPCStub

  @valid_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @valid_address_2 "0xF380B8F1e63e2BEd7CA329CA1FdDbC39B52cC0d3"
  @test_amount 1_000_000

  @approve_delegation_selector <<0xC0, 0x4A, 0x8A, 0x10>>

  # Pool contract address (ethereum mainnet, checksummed) — mirrors the
  # constant DebtToken resolves via Contracts.address(:pool, ...).
  @pool_address "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2"

  # Mirrors the private @reserve_data_return in lib/onchain/aave/debt_token.ex
  # (getReserveData return tuple). Field order/index is load-bearing for the
  # variable-vs-stable debt token index assertions below.
  @reserve_data_return "((uint256),uint128,uint128,uint128,uint128,uint128,uint40,uint16,address,address,address,address,uint128,uint128,uint128)"

  # Two DISTINCT, recognisable 20-byte addresses placed at the variable and
  # stable debt token slots of the canned getReserveData response, so a test
  # proves the *right* field was picked for each rate mode.
  @variable_debt_token_hex "0x" <> String.duplicate("11", 18) <> "AAAA"
  @stable_debt_token_hex "0x" <> String.duplicate("22", 18) <> "BBBB"

  @borrow_allowance_raw 42_000_000

  @tx_hash "0x2222222222222222222222222222222222222222222222222222222222222222"

  describe "debt_token_address/3" do
    test "returns error for invalid asset address" do
      assert {:error, {:invalid_address, "bad_asset"}} =
               DebtToken.debt_token_address("bad_asset", :variable)
    end

    test "returns error for unsupported network" do
      assert {:error, {:unsupported_network, :solana}} =
               DebtToken.debt_token_address(@valid_address, :variable, network: :solana)
    end

    test "returns error for unsupported network with stable rate mode" do
      assert {:error, {:unsupported_network, :solana}} =
               DebtToken.debt_token_address(@valid_address, :stable, network: :solana)
    end

    test "returns error for invalid interest_rate_mode" do
      assert {:error, {:invalid_interest_rate_mode, :fixed}} =
               DebtToken.debt_token_address(@valid_address, :fixed)
    end
  end

  describe "approve_delegation/4" do
    test "returns error for invalid debt_token address" do
      assert {:error, {:invalid_address, "bad_token"}} =
               DebtToken.approve_delegation("bad_token", @valid_address_2, @test_amount, [])
    end

    test "returns error for invalid delegatee address" do
      assert {:error, {:invalid_address, "bad_delegatee"}} =
               DebtToken.approve_delegation(@valid_address, "bad_delegatee", @test_amount, [])
    end
  end

  describe "borrow_allowance/3" do
    test "returns error for invalid debt_token address" do
      assert {:error, {:invalid_address, "bad_token"}} =
               DebtToken.borrow_allowance("bad_token", @valid_address, @valid_address_2)
    end

    test "returns error for invalid from_user address" do
      assert {:error, {:invalid_address, "bad_from"}} =
               DebtToken.borrow_allowance(@valid_address, "bad_from", @valid_address_2)
    end

    test "returns error for invalid to_user address" do
      assert {:error, {:invalid_address, "bad_to"}} =
               DebtToken.borrow_allowance(@valid_address, @valid_address_2, "bad_to")
    end
  end

  describe "approve_delegation calldata verification" do
    test "sends to debt token with correct selector and arguments" do
      {to, calldata} =
        capture_signer_args(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   DebtToken.approve_delegation(
                     @valid_address,
                     @valid_address_2,
                     @test_amount,
                     []
                   )
        end)

      assert to == @valid_address

      <<selector::binary-size(4), args::binary>> = calldata
      assert selector == @approve_delegation_selector

      <<delegatee_arg::binary-size(32), amount_arg::binary-size(32)>> = args

      {:ok, delegatee_bin} = Onchain.Address.validate(@valid_address_2)

      assert :binary.decode_unsigned(delegatee_arg) ==
               :binary.decode_unsigned(pad_left(delegatee_bin))

      assert :binary.decode_unsigned(amount_arg) == @test_amount
    end

    test "encodes zero amount for revocation" do
      {_to, calldata} =
        capture_signer_args(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   DebtToken.approve_delegation(@valid_address, @valid_address_2, 0, [])
        end)

      <<_selector::binary-size(4), _delegatee::binary-size(32), amount_arg::binary-size(32)>> =
        calldata

      assert :binary.decode_unsigned(amount_arg) == 0
    end
  end

  describe "debt_token_address/3 decode path" do
    test "resolves the variable debt token address, distinct from the stable one" do
      seen = start_supervised!({Agent, fn -> [] end})
      url = start_reserve_data_stub(@valid_address, seen)

      assert {:ok, resolved} = DebtToken.debt_token_address(@valid_address, :variable, RPCStub.rpc_opts(url))

      assert resolved == checksum!(@variable_debt_token_hex)
      refute resolved == checksum!(@stable_debt_token_hex)

      assert [to] = Agent.get(seen, & &1)
      assert String.downcase(to) == String.downcase(@pool_address)
    end

    test "resolves the stable debt token address, distinct from the variable one" do
      url = start_reserve_data_stub(@valid_address)

      assert {:ok, resolved} = DebtToken.debt_token_address(@valid_address, :stable, RPCStub.rpc_opts(url))

      assert resolved == checksum!(@stable_debt_token_hex)
      refute resolved == checksum!(@variable_debt_token_hex)
    end

    test "propagates a JSON-RPC error instead of decoding it" do
      url = RPCStub.start(fn _request -> {:error, %{"code" => -32_000, "message" => "execution reverted"}} end)

      assert {:error, _reason} = DebtToken.debt_token_address(@valid_address, :variable, RPCStub.rpc_opts(url))
    end
  end

  describe "borrow_allowance/4 decode path" do
    test "decodes the raw allowance returned by the debt token" do
      seen = start_supervised!({Agent, fn -> [] end})

      {:ok, from_bin} = Onchain.Address.validate(@valid_address_2)
      {:ok, to_bin} = Onchain.Address.validate(@variable_debt_token_hex)

      selector = RPCStub.selector("borrowAllowance(address,address)", [from_bin, to_bin])
      payload = RPCStub.encode("(uint256)", [{@borrow_allowance_raw}])
      url = RPCStub.start(RPCStub.payload_handler(%{selector => payload}, seen))

      assert {:ok, @borrow_allowance_raw} =
               DebtToken.borrow_allowance(
                 @valid_address,
                 @valid_address_2,
                 @variable_debt_token_hex,
                 RPCStub.rpc_opts(url)
               )

      assert [to] = Agent.get(seen, & &1)
      assert String.downcase(to) == String.downcase(@valid_address)
    end
  end

  describe "approve_delegation/4 write path" do
    test "returns the broadcast tx hash on success" do
      seen = start_supervised!({Agent, fn -> [] end})
      url = RPCStub.start(RPCStub.send_tx_handler(@tx_hash, seen))

      assert {:ok, @tx_hash} ==
               DebtToken.approve_delegation(
                 @valid_address,
                 @valid_address_2,
                 @test_amount,
                 RPCStub.write_opts(url)
               )

      assert [raw] = Agent.get(seen, & &1)
      assert String.starts_with?(raw, "0x02")
    end
  end

  defp capture_signer_args(fun) do
    {to, calldata, _opts} = Onchain.TraceCase.capture_signer_call(fun)
    {to, calldata}
  end

  defp pad_left(bin) when byte_size(bin) <= 32 do
    padding_size = 32 - byte_size(bin)
    <<0::size(padding_size * 8), bin::binary>>
  end

  @doc false
  defp checksum!(hex) do
    {:ok, checksummed} = Onchain.Address.checksum(hex)
    checksummed
  end

  @doc false
  # Starts a stub answering getReserveData(asset) with a canned reserve tuple
  # carrying distinct addresses at the stable (index 9) and variable (index
  # 10) debt-token slots.
  defp start_reserve_data_stub(asset_hex, seen \\ nil) do
    {:ok, asset_bin} = Onchain.Address.validate(asset_hex)
    selector = RPCStub.selector("getReserveData(address)", [asset_bin])
    payload = RPCStub.encode(@reserve_data_return, [reserve_data_tuple()])
    RPCStub.start(RPCStub.payload_handler(%{selector => payload}, seen))
  end

  @doc false
  defp reserve_data_tuple do
    {:ok, a_token_bin} = Onchain.Address.validate(@valid_address_2)
    {:ok, stable_bin} = Onchain.Address.validate(@stable_debt_token_hex)
    {:ok, variable_bin} = Onchain.Address.validate(@variable_debt_token_hex)
    {:ok, strategy_bin} = Onchain.Address.validate(@valid_address)

    {
      # configuration (uint256) — nested 1-tuple per the outer ABI type
      {0},
      # liquidityIndex, currentLiquidityRate, variableBorrowIndex,
      # currentVariableBorrowRate, currentStableBorrowRate (uint128 x5)
      0,
      0,
      0,
      0,
      0,
      # lastUpdateTimestamp (uint40)
      0,
      # id (uint16)
      0,
      # aTokenAddress
      a_token_bin,
      # stableDebtTokenAddress — index 9
      stable_bin,
      # variableDebtTokenAddress — index 10
      variable_bin,
      # interestRateStrategyAddress
      strategy_bin,
      # accruedToTreasury, unbacked, isolationModeTotalDebt (uint128 x3)
      0,
      0,
      0
    }
  end
end
