defmodule Onchain.Aave.PoolTest do
  # async: false — :dbg tracing sets a process-global tracer, can't run concurrently
  use ExUnit.Case, async: false

  alias Onchain.Aave.Contracts
  alias Onchain.Aave.Pool
  alias Onchain.Aave.Types.UserAccountData
  alias Onchain.RPCStub

  # Valid addresses for param validation tests (don't need to be real contracts)
  @valid_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @valid_address_2 "0xF380B8F1e63e2BEd7CA329CA1FdDbC39B52cC0d3"
  @test_amount 1_000_000

  # Expected Pool contract address (ethereum mainnet, checksummed)
  @pool_address "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2"

  # ABI function selectors (first 4 bytes of keccak256 of the signature)
  @supply_selector <<0x61, 0x7B, 0xA0, 0x37>>
  @withdraw_selector <<0x69, 0x32, 0x8D, 0xEC>>
  @borrow_selector <<0xA4, 0x15, 0xBC, 0xAD>>
  @repay_selector <<0x57, 0x3A, 0xDE, 0x81>>

  # Canned getUserAccountData response, in the contract's own raw units:
  # base-currency values at 10^8, LTV/threshold in basis points (10^4),
  # health factor at 10^18. UserAccountData.from_raw/1 scales them down, so
  # these are the pre-image of the Decimals asserted below.
  @collateral_raw 500_000_000_000
  @debt_raw 100_000_000_000
  @available_borrows_raw 200_000_000_000
  @liquidation_threshold_raw 8_250
  @ltv_raw 8_000
  @health_factor_raw 1_500_000_000_000_000_000
  @low_health_raw 900_000_000_000_000_000

  # Canned eth_sendRawTransaction result for the offline write path.
  @tx_hash "0x1111111111111111111111111111111111111111111111111111111111111111"

  @account_data_response "(uint256,uint256,uint256,uint256,uint256,uint256)"
  @multicall_response "((bool,bytes)[])"
  @multicall_signature "aggregate3((address,bool,bytes)[])"

  # --- Read operations ---

  describe "get_user_account_data/2" do
    test "returns error for invalid address" do
      assert {:error, {:invalid_address, "not_an_address"}} =
               Pool.get_user_account_data("not_an_address")
    end

    test "returns error for unsupported network" do
      assert {:error, {:unsupported_network, :solana}} =
               Pool.get_user_account_data(@valid_address, network: :solana)
    end
  end

  describe "get_user_account_data!/2" do
    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/get_user_account_data failed.*invalid_address/, fn ->
        Pool.get_user_account_data!("bad_address")
      end
    end

    test "raises on unsupported network" do
      assert_raise RuntimeError, ~r/get_user_account_data failed.*unsupported_network/, fn ->
        Pool.get_user_account_data!(@valid_address, network: :solana)
      end
    end
  end

  describe "get_user_account_data_many/2" do
    test "short-circuits to {:ok, []} on empty input (no RPC)" do
      assert {:ok, []} = Pool.get_user_account_data_many([])
    end

    test "returns error for an invalid address in the list" do
      assert {:error, {:invalid_address, "not_an_address"}} =
               Pool.get_user_account_data_many([@valid_address, "not_an_address"])
    end

    test "returns error for unsupported network" do
      assert {:error, {:unsupported_network, :solana}} =
               Pool.get_user_account_data_many([@valid_address], network: :solana)
    end
  end

  describe "get_user_account_data_many!/2" do
    test "returns [] on empty input" do
      assert [] = Pool.get_user_account_data_many!([])
    end

    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/get_user_account_data_many failed.*invalid_address/, fn ->
        Pool.get_user_account_data_many!([@valid_address, "bad_address"])
      end
    end

    test "raises on unsupported network" do
      assert_raise RuntimeError, ~r/get_user_account_data_many failed.*unsupported_network/, fn ->
        Pool.get_user_account_data_many!([@valid_address], network: :solana)
      end
    end
  end

  # --- Write operations: input validation ---

  describe "supply/4" do
    test "returns error for invalid asset address" do
      assert {:error, {:invalid_address, "bad_asset"}} =
               Pool.supply("bad_asset", @test_amount, @valid_address, [])
    end

    test "returns error for invalid on_behalf_of address" do
      assert {:error, {:invalid_address, "bad_obo"}} =
               Pool.supply(@valid_address, @test_amount, "bad_obo", [])
    end

    test "returns error for unsupported network" do
      assert {:error, {:unsupported_network, :solana}} =
               Pool.supply(@valid_address, @test_amount, @valid_address_2, network: :solana)
    end
  end

  describe "supply!/4" do
    test "raises on invalid asset address" do
      assert_raise RuntimeError, ~r/supply failed.*invalid_address/, fn ->
        Pool.supply!("bad_asset", @test_amount, @valid_address, [])
      end
    end
  end

  describe "withdraw/4" do
    test "returns error for invalid asset address" do
      assert {:error, {:invalid_address, "bad_asset"}} =
               Pool.withdraw("bad_asset", @test_amount, @valid_address, [])
    end

    test "returns error for invalid to address" do
      assert {:error, {:invalid_address, "bad_to"}} =
               Pool.withdraw(@valid_address, @test_amount, "bad_to", [])
    end

    test "returns error for unsupported network" do
      assert {:error, {:unsupported_network, :solana}} =
               Pool.withdraw(@valid_address, @test_amount, @valid_address_2, network: :solana)
    end
  end

  describe "withdraw!/4" do
    test "raises on invalid asset address" do
      assert_raise RuntimeError, ~r/withdraw failed.*invalid_address/, fn ->
        Pool.withdraw!("bad_asset", @test_amount, @valid_address, [])
      end
    end
  end

  describe "borrow/4" do
    test "returns error for invalid asset address" do
      assert {:error, {:invalid_address, "bad_asset"}} =
               Pool.borrow("bad_asset", @test_amount, @valid_address, [])
    end

    test "returns error for invalid on_behalf_of address" do
      assert {:error, {:invalid_address, "bad_obo"}} =
               Pool.borrow(@valid_address, @test_amount, "bad_obo", [])
    end

    test "returns error for unsupported network" do
      assert {:error, {:unsupported_network, :solana}} =
               Pool.borrow(@valid_address, @test_amount, @valid_address_2, network: :solana)
    end

    test "returns error for invalid interest_rate_mode" do
      assert {:error, {:invalid_interest_rate_mode, :fixed}} =
               Pool.borrow(@valid_address, @test_amount, @valid_address_2, interest_rate_mode: :fixed)
    end
  end

  describe "borrow!/4" do
    test "raises on invalid asset address" do
      assert_raise RuntimeError, ~r/borrow failed.*invalid_address/, fn ->
        Pool.borrow!("bad_asset", @test_amount, @valid_address, [])
      end
    end

    test "raises on invalid interest_rate_mode" do
      assert_raise RuntimeError, ~r/borrow failed.*invalid_interest_rate_mode/, fn ->
        Pool.borrow!(@valid_address, @test_amount, @valid_address_2, interest_rate_mode: :fixed)
      end
    end
  end

  describe "repay/4" do
    test "returns error for invalid asset address" do
      assert {:error, {:invalid_address, "bad_asset"}} =
               Pool.repay("bad_asset", @test_amount, @valid_address, [])
    end

    test "returns error for invalid on_behalf_of address" do
      assert {:error, {:invalid_address, "bad_obo"}} =
               Pool.repay(@valid_address, @test_amount, "bad_obo", [])
    end

    test "returns error for unsupported network" do
      assert {:error, {:unsupported_network, :solana}} =
               Pool.repay(@valid_address, @test_amount, @valid_address_2, network: :solana)
    end

    test "returns error for invalid interest_rate_mode" do
      assert {:error, {:invalid_interest_rate_mode, :fixed}} =
               Pool.repay(@valid_address, @test_amount, @valid_address_2, interest_rate_mode: :fixed)
    end
  end

  describe "repay!/4" do
    test "raises on invalid asset address" do
      assert_raise RuntimeError, ~r/repay failed.*invalid_address/, fn ->
        Pool.repay!("bad_asset", @test_amount, @valid_address, [])
      end
    end

    test "raises on invalid interest_rate_mode" do
      assert_raise RuntimeError, ~r/repay failed.*invalid_interest_rate_mode/, fn ->
        Pool.repay!(@valid_address, @test_amount, @valid_address_2, interest_rate_mode: :fixed)
      end
    end
  end

  # --- Full calldata + destination verification via :dbg trace ---

  describe "supply calldata verification" do
    test "sends to Pool address with correct selector and arguments" do
      {to, calldata} =
        capture_signer_args(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   Pool.supply(@valid_address, @test_amount, @valid_address_2, [])
        end)

      assert to == @pool_address

      <<selector::binary-size(4), args::binary>> = calldata
      assert selector == @supply_selector

      # supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
      <<asset::binary-size(32), amt::binary-size(32), obo::binary-size(32), ref::binary-size(32)>> = args

      {:ok, asset_bin} = Onchain.Address.validate(@valid_address)
      {:ok, obo_bin} = Onchain.Address.validate(@valid_address_2)

      assert :binary.decode_unsigned(asset) == :binary.decode_unsigned(pad_left(asset_bin))
      assert :binary.decode_unsigned(amt) == @test_amount
      assert :binary.decode_unsigned(obo) == :binary.decode_unsigned(pad_left(obo_bin))
      assert :binary.decode_unsigned(ref) == 0
    end
  end

  describe "withdraw calldata verification" do
    test "sends to Pool address with correct selector and arguments" do
      {to, calldata} =
        capture_signer_args(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   Pool.withdraw(@valid_address, @test_amount, @valid_address_2, [])
        end)

      assert to == @pool_address

      <<selector::binary-size(4), args::binary>> = calldata
      assert selector == @withdraw_selector

      # withdraw(address asset, uint256 amount, address to)
      <<asset_arg::binary-size(32), amount_arg::binary-size(32), to_arg::binary-size(32)>> = args

      {:ok, asset_bin} = Onchain.Address.validate(@valid_address)
      {:ok, to_bin} = Onchain.Address.validate(@valid_address_2)

      assert :binary.decode_unsigned(asset_arg) == :binary.decode_unsigned(pad_left(asset_bin))
      assert :binary.decode_unsigned(amount_arg) == @test_amount
      assert :binary.decode_unsigned(to_arg) == :binary.decode_unsigned(pad_left(to_bin))
    end
  end

  describe "borrow calldata verification" do
    test "sends to Pool address with correct selector and arguments (variable rate)" do
      {to, calldata} =
        capture_signer_args(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   Pool.borrow(@valid_address, @test_amount, @valid_address_2, [])
        end)

      assert to == @pool_address

      <<selector::binary-size(4), args::binary>> = calldata
      assert selector == @borrow_selector

      # borrow(address, amount, interestRateMode, referralCode, onBehalfOf)
      <<a::binary-size(32), b::binary-size(32), c::binary-size(32), d::binary-size(32), e::binary-size(32)>> = args

      {:ok, asset_bin} = Onchain.Address.validate(@valid_address)
      {:ok, obo_bin} = Onchain.Address.validate(@valid_address_2)

      assert :binary.decode_unsigned(a) == :binary.decode_unsigned(pad_left(asset_bin))
      assert :binary.decode_unsigned(b) == @test_amount
      assert :binary.decode_unsigned(c) == 2
      assert :binary.decode_unsigned(d) == 0
      assert :binary.decode_unsigned(e) == :binary.decode_unsigned(pad_left(obo_bin))
    end

    test "encodes stable rate mode when specified" do
      {_to, calldata} =
        capture_signer_args(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   Pool.borrow(@valid_address, @test_amount, @valid_address_2, interest_rate_mode: :stable)
        end)

      <<_selector::binary-size(4), _asset::binary-size(32), _amount::binary-size(32), rate_arg::binary-size(32),
        _referral::binary-size(32), _obo::binary-size(32)>> = calldata

      assert :binary.decode_unsigned(rate_arg) == 1
    end
  end

  describe "repay calldata verification" do
    test "sends to Pool address with correct selector and arguments (variable rate)" do
      {to, calldata} =
        capture_signer_args(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   Pool.repay(@valid_address, @test_amount, @valid_address_2, [])
        end)

      assert to == @pool_address

      <<selector::binary-size(4), args::binary>> = calldata
      assert selector == @repay_selector

      # repay(address asset, uint256 amount, uint256 interestRateMode, address onBehalfOf)
      <<asset_arg::binary-size(32), amount_arg::binary-size(32), rate_arg::binary-size(32), obo_arg::binary-size(32)>> =
        args

      {:ok, asset_bin} = Onchain.Address.validate(@valid_address)
      {:ok, obo_bin} = Onchain.Address.validate(@valid_address_2)

      assert :binary.decode_unsigned(asset_arg) == :binary.decode_unsigned(pad_left(asset_bin))
      assert :binary.decode_unsigned(amount_arg) == @test_amount
      assert :binary.decode_unsigned(rate_arg) == 2
      assert :binary.decode_unsigned(obo_arg) == :binary.decode_unsigned(pad_left(obo_bin))
    end

    test "encodes stable rate mode when specified" do
      {_to, calldata} =
        capture_signer_args(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   Pool.repay(@valid_address, @test_amount, @valid_address_2, interest_rate_mode: :stable)
        end)

      <<_selector::binary-size(4), _asset::binary-size(32), _amount::binary-size(32), rate_arg::binary-size(32),
        _obo::binary-size(32)>> = calldata

      assert :binary.decode_unsigned(rate_arg) == 1
    end
  end

  describe "write selectors are distinct" do
    test "all four operations have unique selectors" do
      selectors =
        Enum.map(
          [
            fn -> Pool.supply(@valid_address, @test_amount, @valid_address_2, []) end,
            fn -> Pool.withdraw(@valid_address, @test_amount, @valid_address_2, []) end,
            fn -> Pool.borrow(@valid_address, @test_amount, @valid_address_2, []) end,
            fn -> Pool.repay(@valid_address, @test_amount, @valid_address_2, []) end
          ],
          fn fun ->
            {_to, calldata} = capture_signer_args(fn -> fun.() end)
            <<selector::binary-size(4), _rest::binary>> = calldata
            selector
          end
        )

      assert [_, _, _, _] = Enum.uniq(selectors)
    end
  end

  describe "network option routing" do
    test "sends to correct Pool address for non-default network" do
      {to, _calldata} =
        capture_signer_args(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   Pool.supply(@valid_address, @test_amount, @valid_address_2, network: :arbitrum)
        end)

      {:ok, arb_pool} = Contracts.address(:pool, network: :arbitrum)
      assert to == arb_pool
    end
  end

  # --- Read decode paths (loopback JSON-RPC stub, no live node) ---

  describe "get_user_account_data/2 decode path" do
    test "decodes the six raw uint256 values into scaled Decimal fields" do
      seen = start_supervised!({Agent, fn -> [] end})
      url = start_stub(%{account_data_selector() => account_data_payload()}, seen)

      assert {:ok, data} = Pool.get_user_account_data(@valid_address, RPCStub.rpc_opts(url))

      assert Decimal.equal?(data.total_collateral_base, Decimal.new("5000"))
      assert Decimal.equal?(data.total_debt_base, Decimal.new("1000"))
      assert Decimal.equal?(data.available_borrows_base, Decimal.new("2000"))
      assert Decimal.equal?(data.current_liquidation_threshold, Decimal.new("0.825"))
      assert Decimal.equal?(data.ltv, Decimal.new("0.8"))
      assert Decimal.equal?(data.health_factor, Decimal.new("1.5"))

      assert [to] = Agent.get(seen, & &1)
      assert String.downcase(to) == String.downcase(@pool_address)
    end

    test "propagates a JSON-RPC error instead of decoding it" do
      url = start_error_stub(%{"code" => -32_000, "message" => "execution reverted"})

      assert {:error, _reason} = Pool.get_user_account_data(@valid_address, RPCStub.rpc_opts(url))
    end
  end

  describe "get_user_account_data!/2 decode path" do
    test "returns the struct unwrapped on success" do
      url = start_stub(%{account_data_selector() => account_data_payload()})

      assert %UserAccountData{} = data = Pool.get_user_account_data!(@valid_address, RPCStub.rpc_opts(url))
      assert Decimal.equal?(data.health_factor, Decimal.new("1.5"))
    end

    test "raises when the node returns an error" do
      url = start_error_stub(%{"code" => -32_000, "message" => "execution reverted"})

      assert_raise RuntimeError, ~r/get_user_account_data failed/, fn ->
        Pool.get_user_account_data!(@valid_address, RPCStub.rpc_opts(url))
      end
    end
  end

  describe "get_user_account_data_many/2 decode path" do
    test "returns one struct per user, in input order" do
      url =
        start_multicall_stub([{true, raw_account_data(@health_factor_raw)}, {true, raw_account_data(@low_health_raw)}])

      assert {:ok, [first, second]} =
               Pool.get_user_account_data_many([@valid_address, @valid_address_2], RPCStub.rpc_opts(url))

      assert Decimal.equal?(first.health_factor, Decimal.new("1.5"))
      assert Decimal.equal?(second.health_factor, Decimal.new("0.9"))
    end

    test "fails the whole batch loudly when one sub-call reverts" do
      revert_data = <<0xDE, 0xAD, 0xBE, 0xEF>>
      url = start_multicall_stub([{true, raw_account_data(@health_factor_raw)}, {false, revert_data}])

      assert {:error, {:multicall_call_failed, data}} =
               Pool.get_user_account_data_many([@valid_address, @valid_address_2], RPCStub.rpc_opts(url))

      assert String.downcase(data) =~ "deadbeef"
    end
  end

  describe "bang write wrappers" do
    test "supply!/withdraw!/borrow!/repay! return the broadcast tx hash on success" do
      for {fun, name} <- [
            {&Pool.supply!/4, :supply},
            {&Pool.withdraw!/4, :withdraw},
            {&Pool.borrow!/4, :borrow},
            {&Pool.repay!/4, :repay}
          ] do
        # One supervised Agent per operation — a shared child id would collide.
        seen = start_supervised!(Supervisor.child_spec({Agent, fn -> [] end}, id: name))
        url = RPCStub.start(RPCStub.send_tx_handler(@tx_hash, seen))

        assert @tx_hash == fun.(@valid_address, @test_amount, @valid_address_2, RPCStub.write_opts(url))

        assert [raw] = Agent.get(seen, & &1)
        assert String.starts_with?(raw, "0x02")
      end
    end

    test "supply!/withdraw!/borrow!/repay! raise with the operation name in the message" do
      for {fun, name} <- [
            {fn -> Pool.supply!(@valid_address, @test_amount, @valid_address_2, []) end, "supply"},
            {fn -> Pool.withdraw!(@valid_address, @test_amount, @valid_address_2, []) end, "withdraw"},
            {fn -> Pool.borrow!(@valid_address, @test_amount, @valid_address_2, []) end, "borrow"},
            {fn -> Pool.repay!(@valid_address, @test_amount, @valid_address_2, []) end, "repay"}
          ] do
        assert_raise RuntimeError, ~r/#{name} failed.*missing_option/, fun
      end
    end

    test "get_user_account_data_many!/2 raises on an invalid address in the list" do
      assert_raise RuntimeError, ~r/get_user_account_data_many failed.*invalid_address/, fn ->
        Pool.get_user_account_data_many!([@valid_address, "not_an_address"])
      end
    end
  end

  @doc false
  # Delegates to TraceCase and destructures to {to, calldata}.
  defp capture_signer_args(fun) do
    {to, calldata, _opts} = Onchain.TraceCase.capture_signer_call(fun)
    {to, calldata}
  end

  @doc false
  # Left-pads a binary to 32 bytes for ABI argument comparison.
  defp pad_left(bin) when byte_size(bin) <= 32 do
    padding_size = 32 - byte_size(bin)
    <<0::size(padding_size * 8), bin::binary>>
  end

  @doc false
  # Starts a stub answering `eth_call` from a selector-keyed payload map.
  defp start_stub(payloads, seen \\ nil) do
    RPCStub.start(RPCStub.payload_handler(payloads, seen))
  end

  @doc false
  # Starts a stub that answers every request with a JSON-RPC error object.
  defp start_error_stub(error) do
    RPCStub.start(fn _request -> {:error, error} end)
  end

  @doc false
  # Starts a stub that answers the Multicall3 aggregate3 call with the given
  # {success?, return_data} sub-results, in order.
  defp start_multicall_stub(sub_results) do
    payload = RPCStub.encode(@multicall_response, [{sub_results}])
    start_stub(%{RPCStub.selector(@multicall_signature, [[]]) => payload})
  end

  @doc false
  defp account_data_selector do
    RPCStub.selector("getUserAccountData(address)", [<<0::160>>])
  end

  @doc false
  defp account_data_payload do
    RPCStub.encode(@account_data_response, [account_data_tuple(@health_factor_raw)])
  end

  @doc false
  # Raw ABI bytes of one getUserAccountData return, for embedding as the
  # `bytes` member of a Multicall3 sub-result.
  defp raw_account_data(health_factor_raw) do
    RPCStub.encode_raw(@account_data_response, [account_data_tuple(health_factor_raw)])
  end

  @doc false
  defp account_data_tuple(health_factor_raw) do
    {@collateral_raw, @debt_raw, @available_borrows_raw, @liquidation_threshold_raw, @ltv_raw, health_factor_raw}
  end
end
