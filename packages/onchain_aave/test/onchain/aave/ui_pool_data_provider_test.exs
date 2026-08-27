defmodule Onchain.Aave.UiPoolDataProviderTest do
  use ExUnit.Case, async: false

  alias Onchain.Aave.Types.AggregatedReserveData
  alias Onchain.Aave.Types.BaseCurrencyInfo
  alias Onchain.Aave.Types.UserReserveData
  alias Onchain.Aave.UiPoolDataProvider
  alias Onchain.RPCStub

  # Expected UiPoolDataProvider contract addresses (checksummed) per network.
  @ui_provider_ethereum "0x56b7A1012765C285afAC8b8F25C69Bf10ccfE978"
  @ui_provider_arbitrum "0x13c833256BD767da2320d727a3691BAff3770E39"

  # PoolAddressesProvider (ethereum) — passed as the first calldata argument of
  # every UiPoolDataProvider read, so its presence in `data` proves
  # `provider_address/1` resolved and ABI-encoded the right registry entry.
  @provider_ethereum_word "0000000000000000000000002f39d218133afab8f2b819b1066c7e434ad94e9e"

  # Arbitrary but canonically-checksummed mainnet addresses. Only their
  # checksum form matters here: the decode path must hand back exactly these
  # strings from the 20-byte binaries the ABI decoder produces.
  @weth "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
  @usdc "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @dai "0x6B175474E89094C44Da98b954EedeAC495271d0F"
  @wbtc "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599"
  @link "0x514910771AF9Ca656af840dff83E8264EcF986CA"
  @aave_oracle "0x54586bE62E3c3580375aE3723C145253060Ca0C2"
  @usdt "0xdAC17F958D2ee523a2206206994597C13D831ec7"
  @aave "0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9"
  @uni "0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984"
  @crv "0xD533a949740bb3306d119CC777fa900bA034cd52"

  @user "0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2"

  @weth_bin Base.decode16!("C02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", case: :mixed)
  @usdc_bin Base.decode16!("A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", case: :mixed)
  @dai_bin Base.decode16!("6B175474E89094C44Da98b954EedeAC495271d0F", case: :mixed)
  @wbtc_bin Base.decode16!("2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599", case: :mixed)
  @link_bin Base.decode16!("514910771AF9Ca656af840dff83E8264EcF986CA", case: :mixed)
  @aave_oracle_bin Base.decode16!("54586bE62E3c3580375aE3723C145253060Ca0C2", case: :mixed)
  @usdt_bin Base.decode16!("dAC17F958D2ee523a2206206994597C13D831ec7", case: :mixed)
  @aave_bin Base.decode16!("7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9", case: :mixed)
  @uni_bin Base.decode16!("1f9840a85d5aF5bf1D1762F925BDADdC4201F984", case: :mixed)
  @crv_bin Base.decode16!("D533a949740bb3306d119CC777fa900bA034cd52", case: :mixed)

  @zero_address_bin <<0::160>>

  # ABI return types, mirrored from the module under test. Mirroring rather
  # than reaching into the private attributes is deliberate: a silent edit of
  # the module's tuple shape must fail these tests, not follow along.
  @reserves_list_response "(address[])"

  @reserves_data_response "((" <>
                            "address,string,string,uint256," <>
                            "uint256,uint256,uint256,uint256," <>
                            "bool,bool,bool,bool," <>
                            "uint128,uint128,uint128,uint128," <>
                            "uint40," <>
                            "address,address,address," <>
                            "uint256,uint256,uint256," <>
                            "address," <>
                            "uint256,uint256,uint256,uint256," <>
                            "bool,bool," <>
                            "uint128,uint128," <>
                            "bool," <>
                            "uint256,uint256,uint256,uint256," <>
                            "bool," <>
                            "uint128,uint128" <>
                            ")[],(uint256,int256,int256,uint8))"

  @user_reserves_data_response "((address,uint256,bool,uint256)[],uint8)"

  # --- Canned reserve #1 (WETH-shaped) -----------------------------------
  #
  # Raw contract units. Basis points (10^4) scale to LTV Decimals and rays
  # (10^27) scale to rate Decimals; the literals below were picked so every
  # scaled result is exact and can be asserted as a Decimal literal.
  @weth_reserve {
    # underlying, name, symbol, decimals
    @weth_bin,
    "Wrapped Ether",
    "WETH",
    18,
    # base_ltv 0.8, liq_threshold 0.825, liq_bonus 1.05, reserve_factor 0.15
    8_000,
    8_250,
    10_500,
    1_500,
    # collateral?, borrowing?, active?, frozen?
    true,
    true,
    true,
    false,
    # liquidity_index 1.05, variable_borrow_index 1.1
    1_050_000_000_000_000_000_000_000_000,
    1_100_000_000_000_000_000_000_000_000,
    # liquidity_rate 0.02, variable_borrow_rate 0.03
    20_000_000_000_000_000_000_000_000,
    30_000_000_000_000_000_000_000_000,
    # last_update_timestamp
    1_700_000_000,
    # a_token, variable_debt_token, interest_rate_strategy
    @dai_bin,
    @wbtc_bin,
    @link_bin,
    # available_liquidity, total_scaled_variable_debt, price_in_market_ref
    123_456_789_000_000_000_000,
    55_000_000_000_000_000_000,
    250_000_000_000,
    # price_oracle
    @aave_oracle_bin,
    # slope1 0.04, slope2 3, base_variable_borrow_rate 0.01, optimal 0.9
    40_000_000_000_000_000_000_000_000,
    3_000_000_000_000_000_000_000_000_000,
    10_000_000_000_000_000_000_000_000,
    900_000_000_000_000_000_000_000_000,
    # paused?, siloed?
    false,
    false,
    # accrued_to_treasury, isolation_mode_total_debt
    7,
    0,
    # flash_loan_enabled?
    true,
    # debt_ceiling, debt_ceiling_decimals, borrow_cap, supply_cap
    0,
    0,
    1_400_000,
    1_800_000,
    # borrowable_in_isolation?
    false,
    # virtual_underlying_balance, deficit
    42,
    0
  }

  # --- Canned reserve #2 (USDC-shaped) — every field distinct from #1 -----
  @usdc_reserve {
    @usdc_bin,
    "USD Coin",
    "USDC",
    6,
    # base_ltv 0.75, liq_threshold 0.78, liq_bonus 1.045, reserve_factor 0.2
    7_500,
    7_800,
    10_450,
    2_000,
    true,
    true,
    true,
    true,
    # liquidity_index 1.25, variable_borrow_index 1.5
    1_250_000_000_000_000_000_000_000_000,
    1_500_000_000_000_000_000_000_000_000,
    # liquidity_rate 0.05, variable_borrow_rate 0.06
    50_000_000_000_000_000_000_000_000,
    60_000_000_000_000_000_000_000_000,
    1_700_000_500,
    @usdt_bin,
    @aave_bin,
    @uni_bin,
    777_000_000,
    444_000_000,
    99_990_000,
    @crv_bin,
    # slope1 0.07, slope2 2, base_variable_borrow_rate 0.02, optimal 0.8
    70_000_000_000_000_000_000_000_000,
    2_000_000_000_000_000_000_000_000_000,
    20_000_000_000_000_000_000_000_000,
    800_000_000_000_000_000_000_000_000,
    true,
    true,
    12,
    34,
    false,
    5_000_000,
    2,
    1_000_000,
    2_000_000,
    true,
    88,
    99
  }

  # market_ref_price 99_500_000 scales (10^8) to 0.995; network base token
  # price 250_012_345_678 scales by its own 8 decimals to 2500.12345678.
  @base_currency {100_000_000, 99_500_000, 250_012_345_678, 8}

  @e_mode_id 3

  @user_reserve_weth {@weth_bin, 1_500_000_000_000_000_000, true, 0}
  @user_reserve_usdc {@usdc_bin, 250_000_000, false, 90_000_000}

  @rpc_error %{"code" => -32_000, "message" => "execution reverted"}

  # --- get_reserves_list -------------------------------------------------

  describe "get_reserves_list/1" do
    test "decodes and checksums every address, preserving contract order" do
      seen = start_supervised!({Agent, fn -> [] end})
      url = start_stub(%{reserves_list_selector() => reserves_list_payload([@weth_bin, @usdc_bin])}, seen)

      assert {:ok, [@weth, @usdc]} = UiPoolDataProvider.get_reserves_list(RPCStub.rpc_opts(url))

      assert [{to, data}] = Agent.get(seen, & &1)
      assert String.downcase(to) == String.downcase(@ui_provider_ethereum)
      assert String.downcase(data) =~ @provider_ethereum_word
    end

    test "decodes an empty reserves list without touching the checksum path" do
      url = start_stub(%{reserves_list_selector() => reserves_list_payload([])})

      assert {:ok, []} = UiPoolDataProvider.get_reserves_list(RPCStub.rpc_opts(url))
    end

    test "addresses the network's own UiPoolDataProvider and PoolAddressesProvider" do
      seen = start_supervised!({Agent, fn -> [] end})
      url = start_stub(%{reserves_list_selector() => reserves_list_payload([@weth_bin])}, seen)

      opts = Keyword.put(RPCStub.rpc_opts(url), :network, :arbitrum)
      assert {:ok, [@weth]} = UiPoolDataProvider.get_reserves_list(opts)

      assert [{to, data}] = Agent.get(seen, & &1)
      assert String.downcase(to) == String.downcase(@ui_provider_arbitrum)
      # Arbitrum uses the canonical CREATE2 PoolAddressesProvider, not the
      # ethereum one, so the calldata argument must differ.
      refute String.downcase(data) =~ @provider_ethereum_word
      assert String.downcase(data) =~ "a97684ead0e402dc232d5a977953df7ecbab3cdb"
    end

    test "returns an error for an unsupported network" do
      assert {:error, {:unsupported_network, :solana}} =
               UiPoolDataProvider.get_reserves_list(network: :solana)
    end

    test "propagates a JSON-RPC error instead of decoding it" do
      url = start_error_stub(@rpc_error)

      assert {:error, {:rpc_error, %{code: -32_000}}} =
               UiPoolDataProvider.get_reserves_list(RPCStub.rpc_opts(url))
    end
  end

  describe "get_reserves_list!/1" do
    test "returns the address list unwrapped" do
      url = start_stub(%{reserves_list_selector() => reserves_list_payload([@weth_bin, @usdc_bin])})

      assert [@weth, @usdc] = UiPoolDataProvider.get_reserves_list!(RPCStub.rpc_opts(url))
    end

    test "raises when the node returns an error" do
      url = start_error_stub(@rpc_error)

      assert_raise RuntimeError, ~r/get_reserves_list failed.*rpc_error/, fn ->
        UiPoolDataProvider.get_reserves_list!(RPCStub.rpc_opts(url))
      end
    end

    test "raises on an unsupported network" do
      assert_raise RuntimeError, ~r/get_reserves_list failed.*unsupported_network/, fn ->
        UiPoolDataProvider.get_reserves_list!(network: :solana)
      end
    end
  end

  # --- get_reserves_data -------------------------------------------------

  describe "get_reserves_data/1" do
    test "decodes both reserves in contract order with exactly scaled fields" do
      seen = start_supervised!({Agent, fn -> [] end})
      url = start_stub(%{reserves_data_selector() => reserves_data_payload()}, seen)

      assert {:ok, {[weth, usdc], _base}} = UiPoolDataProvider.get_reserves_data(RPCStub.rpc_opts(url))

      assert %AggregatedReserveData{underlying_asset: @weth, name: "Wrapped Ether", symbol: "WETH", decimals: 18} =
               weth

      assert %AggregatedReserveData{underlying_asset: @usdc, name: "USD Coin", symbol: "USDC", decimals: 6} = usdc

      # Basis points (10^4) → ratio Decimals.
      assert_decimal(weth.base_ltv_as_collateral, "0.8")
      assert_decimal(weth.reserve_liquidation_threshold, "0.825")
      assert_decimal(weth.reserve_liquidation_bonus, "1.05")
      assert_decimal(weth.reserve_factor, "0.15")
      assert_decimal(usdc.base_ltv_as_collateral, "0.75")
      assert_decimal(usdc.reserve_liquidation_threshold, "0.78")
      assert_decimal(usdc.reserve_liquidation_bonus, "1.045")
      assert_decimal(usdc.reserve_factor, "0.2")

      # Rays (10^27) → index/rate Decimals.
      assert_decimal(weth.liquidity_index, "1.05")
      assert_decimal(weth.variable_borrow_index, "1.1")
      assert_decimal(weth.liquidity_rate, "0.02")
      assert_decimal(weth.variable_borrow_rate, "0.03")
      assert_decimal(weth.variable_rate_slope1, "0.04")
      assert_decimal(weth.variable_rate_slope2, "3")
      assert_decimal(weth.base_variable_borrow_rate, "0.01")
      assert_decimal(weth.optimal_usage_ratio, "0.9")
      assert_decimal(usdc.liquidity_index, "1.25")
      assert_decimal(usdc.variable_borrow_index, "1.5")
      assert_decimal(usdc.liquidity_rate, "0.05")
      assert_decimal(usdc.variable_borrow_rate, "0.06")
      assert_decimal(usdc.variable_rate_slope1, "0.07")
      assert_decimal(usdc.variable_rate_slope2, "2")
      assert_decimal(usdc.base_variable_borrow_rate, "0.02")
      assert_decimal(usdc.optimal_usage_ratio, "0.8")

      assert [to] = Agent.get(seen, fn calls -> Enum.map(calls, &elem(&1, 0)) end)
      assert String.downcase(to) == String.downcase(@ui_provider_ethereum)
    end

    test "keeps flags, addresses, raw amounts and caps on their own reserve" do
      url = start_stub(%{reserves_data_selector() => reserves_data_payload()})

      assert {:ok, {[weth, usdc], _base}} = UiPoolDataProvider.get_reserves_data(RPCStub.rpc_opts(url))

      assert weth.usage_as_collateral_enabled
      assert weth.borrowing_enabled
      assert weth.is_active
      refute weth.is_frozen
      refute weth.is_paused
      refute weth.is_siloed_borrowing
      assert weth.flash_loan_enabled
      refute weth.borrowable_in_isolation

      assert usdc.is_frozen
      assert usdc.is_paused
      assert usdc.is_siloed_borrowing
      refute usdc.flash_loan_enabled
      assert usdc.borrowable_in_isolation

      assert weth.a_token_address == @dai
      assert weth.variable_debt_token_address == @wbtc
      assert weth.interest_rate_strategy_address == @link
      assert weth.price_oracle == @aave_oracle
      assert usdc.a_token_address == @usdt
      assert usdc.variable_debt_token_address == @aave
      assert usdc.interest_rate_strategy_address == @uni
      assert usdc.price_oracle == @crv

      assert weth.last_update_timestamp == 1_700_000_000
      assert weth.available_liquidity == 123_456_789_000_000_000_000
      assert weth.total_scaled_variable_debt == 55_000_000_000_000_000_000
      assert weth.price_in_market_reference_currency == 250_000_000_000
      assert weth.accrued_to_treasury == 7
      assert weth.isolation_mode_total_debt == 0
      assert weth.debt_ceiling == 0
      assert weth.debt_ceiling_decimals == 0
      assert weth.borrow_cap == 1_400_000
      assert weth.supply_cap == 1_800_000
      assert weth.virtual_underlying_balance == 42
      assert weth.deficit == 0

      assert usdc.last_update_timestamp == 1_700_000_500
      assert usdc.available_liquidity == 777_000_000
      assert usdc.total_scaled_variable_debt == 444_000_000
      assert usdc.price_in_market_reference_currency == 99_990_000
      assert usdc.accrued_to_treasury == 12
      assert usdc.isolation_mode_total_debt == 34
      assert usdc.debt_ceiling == 5_000_000
      assert usdc.debt_ceiling_decimals == 2
      assert usdc.borrow_cap == 1_000_000
      assert usdc.supply_cap == 2_000_000
      assert usdc.virtual_underlying_balance == 88
      assert usdc.deficit == 99
    end

    test "decodes base currency info alongside the reserves" do
      url = start_stub(%{reserves_data_selector() => reserves_data_payload()})

      assert {:ok, {_reserves, base}} = UiPoolDataProvider.get_reserves_data(RPCStub.rpc_opts(url))

      assert %BaseCurrencyInfo{
               market_reference_currency_unit: 100_000_000,
               network_base_token_price_decimals: 8
             } = base

      assert_decimal(base.market_reference_currency_price_in_usd, "0.995")
      assert_decimal(base.network_base_token_price_in_usd, "2500.12345678")
    end

    test "decodes an empty reserves list and still returns base currency info" do
      url = start_stub(%{reserves_data_selector() => reserves_data_payload([])})

      assert {:ok, {[], %BaseCurrencyInfo{market_reference_currency_unit: 100_000_000}}} =
               UiPoolDataProvider.get_reserves_data(RPCStub.rpc_opts(url))
    end

    test "returns an error for an unsupported network" do
      assert {:error, {:unsupported_network, :solana}} =
               UiPoolDataProvider.get_reserves_data(network: :solana)
    end

    test "propagates a JSON-RPC error instead of decoding it" do
      url = start_error_stub(@rpc_error)

      assert {:error, {:rpc_error, %{code: -32_000}}} =
               UiPoolDataProvider.get_reserves_data(RPCStub.rpc_opts(url))
    end
  end

  describe "get_reserves_data!/1" do
    test "returns the {reserves, base} tuple unwrapped" do
      url = start_stub(%{reserves_data_selector() => reserves_data_payload()})

      assert {[%AggregatedReserveData{symbol: "WETH"}, %AggregatedReserveData{symbol: "USDC"}], %BaseCurrencyInfo{}} =
               UiPoolDataProvider.get_reserves_data!(RPCStub.rpc_opts(url))
    end

    test "raises when the node returns an error" do
      url = start_error_stub(@rpc_error)

      assert_raise RuntimeError, ~r/get_reserves_data failed.*rpc_error/, fn ->
        UiPoolDataProvider.get_reserves_data!(RPCStub.rpc_opts(url))
      end
    end

    test "raises on an unsupported network" do
      assert_raise RuntimeError, ~r/get_reserves_data failed.*unsupported_network/, fn ->
        UiPoolDataProvider.get_reserves_data!(network: :solana)
      end
    end
  end

  # --- get_user_reserves_data --------------------------------------------

  describe "get_user_reserves_data/2" do
    test "decodes each user reserve in contract order plus the e-mode id" do
      seen = start_supervised!({Agent, fn -> [] end})
      url = start_stub(%{user_reserves_selector() => user_reserves_payload()}, seen)

      assert {:ok, {[weth, usdc], @e_mode_id}} =
               UiPoolDataProvider.get_user_reserves_data(@user, RPCStub.rpc_opts(url))

      assert %UserReserveData{
               underlying_asset: @weth,
               scaled_a_token_balance: 1_500_000_000_000_000_000,
               usage_as_collateral_enabled_on_user: true,
               scaled_variable_debt: 0
             } = weth

      assert %UserReserveData{
               underlying_asset: @usdc,
               scaled_a_token_balance: 250_000_000,
               usage_as_collateral_enabled_on_user: false,
               scaled_variable_debt: 90_000_000
             } = usdc

      assert [{to, data}] = Agent.get(seen, & &1)
      assert String.downcase(to) == String.downcase(@ui_provider_ethereum)
      # Both the provider and the user address ride in the calldata, provider first.
      assert String.downcase(data) =~ @provider_ethereum_word
      assert String.downcase(data) =~ String.downcase(String.trim_leading(@user, "0x"))
    end

    test "decodes an empty user reserve list with a zero e-mode id" do
      url = start_stub(%{user_reserves_selector() => user_reserves_payload([], 0)})

      assert {:ok, {[], 0}} = UiPoolDataProvider.get_user_reserves_data(@user, RPCStub.rpc_opts(url))
    end

    test "returns an error for an invalid user address" do
      assert {:error, {:invalid_address, "not_an_address"}} =
               UiPoolDataProvider.get_user_reserves_data("not_an_address")
    end

    test "returns an error for an unsupported network" do
      assert {:error, {:unsupported_network, :solana}} =
               UiPoolDataProvider.get_user_reserves_data(@user, network: :solana)
    end

    test "propagates a JSON-RPC error instead of decoding it" do
      url = start_error_stub(@rpc_error)

      assert {:error, {:rpc_error, %{code: -32_000}}} =
               UiPoolDataProvider.get_user_reserves_data(@user, RPCStub.rpc_opts(url))
    end
  end

  describe "get_user_reserves_data!/2" do
    test "returns the {reserves, e_mode_id} tuple unwrapped" do
      url = start_stub(%{user_reserves_selector() => user_reserves_payload()})

      assert {[%UserReserveData{underlying_asset: @weth}, %UserReserveData{underlying_asset: @usdc}], @e_mode_id} =
               UiPoolDataProvider.get_user_reserves_data!(@user, RPCStub.rpc_opts(url))
    end

    test "raises when the node returns an error" do
      url = start_error_stub(@rpc_error)

      assert_raise RuntimeError, ~r/get_user_reserves_data failed.*rpc_error/, fn ->
        UiPoolDataProvider.get_user_reserves_data!(@user, RPCStub.rpc_opts(url))
      end
    end

    test "raises on an invalid user address" do
      assert_raise RuntimeError, ~r/get_user_reserves_data failed.*invalid_address/, fn ->
        UiPoolDataProvider.get_user_reserves_data!("bad_address")
      end
    end
  end

  # --- Default options ---------------------------------------------------

  describe "default arguments" do
    test "the opts-less clauses fall back to the configured node and :ethereum" do
      url =
        start_stub(%{
          reserves_list_selector() => reserves_list_payload([@weth_bin]),
          reserves_data_selector() => reserves_data_payload()
        })

      put_ethereum_node(url)

      assert {:ok, [@weth]} = UiPoolDataProvider.get_reserves_list()
      assert [@weth] = UiPoolDataProvider.get_reserves_list!()

      assert {:ok, {[%AggregatedReserveData{symbol: "WETH"}, %AggregatedReserveData{symbol: "USDC"}], base}} =
               UiPoolDataProvider.get_reserves_data()

      assert %BaseCurrencyInfo{market_reference_currency_unit: 100_000_000} = base

      assert {[%AggregatedReserveData{symbol: "WETH"} | _], %BaseCurrencyInfo{}} =
               UiPoolDataProvider.get_reserves_data!()
    end
  end

  # --- Helpers -----------------------------------------------------------

  # Asserts a Decimal equals the literal, independent of its exponent, so a
  # value scaled to "0.8000" still matches the intended 0.8.
  defp assert_decimal(actual, expected) do
    assert Decimal.equal?(actual, Decimal.new(expected)),
           "expected #{expected}, got #{Decimal.to_string(actual)}"
  end

  # Like `RPCStub.payload_handler/2` but records `{to, data}` per call rather
  # than only `to`, so a test can also assert what the wrapper encoded — the
  # PoolAddressesProvider argument `provider_address/1` resolves is otherwise
  # invisible. Defined here rather than in the shared stub, which is off-limits.
  defp start_stub(payloads, seen \\ nil) do
    RPCStub.start(fn
      %{"method" => "eth_call", "params" => [%{"data" => data, "to" => to} | _]} ->
        if seen, do: Agent.update(seen, &[{to, data} | &1])
        selector = String.slice(String.downcase(data), 0, 10)

        Map.get_lazy(payloads, selector, fn ->
          flunk("stub has no payload for selector #{selector} (data=#{data})")
        end)

      %{"method" => method} ->
        flunk("stub received an unexpected JSON-RPC method: #{method}")
    end)
  end

  # Points the opts-less RPC default at the stub for one test, restoring the
  # prior value afterwards. Safe because this case is `async: false`.
  defp put_ethereum_node(url) do
    previous = Application.fetch_env(:cartouche, :ethereum_node)
    Application.put_env(:cartouche, :ethereum_node, url)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:cartouche, :ethereum_node, value)
        :error -> Application.delete_env(:cartouche, :ethereum_node)
      end
    end)
  end

  defp start_error_stub(error) do
    RPCStub.start(fn _request -> {:error, error} end)
  end

  defp reserves_list_selector do
    RPCStub.selector("getReservesList(address)", [@zero_address_bin])
  end

  defp reserves_data_selector do
    RPCStub.selector("getReservesData(address)", [@zero_address_bin])
  end

  defp user_reserves_selector do
    RPCStub.selector("getUserReservesData(address,address)", [@zero_address_bin, @zero_address_bin])
  end

  defp reserves_list_payload(addresses) do
    RPCStub.encode(@reserves_list_response, [{addresses}])
  end

  defp reserves_data_payload(reserves \\ [@weth_reserve, @usdc_reserve]) do
    RPCStub.encode(@reserves_data_response, [{reserves, @base_currency}])
  end

  defp user_reserves_payload(reserves \\ [@user_reserve_weth, @user_reserve_usdc], e_mode_id \\ @e_mode_id) do
    RPCStub.encode(@user_reserves_data_response, [{reserves, e_mode_id}])
  end
end
