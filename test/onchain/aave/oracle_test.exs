defmodule Onchain.Aave.OracleTest do
  # async: false — the opts-less clauses below swap the global :cartouche
  # ethereum_node config, which no concurrent case may observe.
  use ExUnit.Case, async: false

  alias Onchain.Aave.Oracle
  alias Onchain.Address
  alias Onchain.RPCStub

  @valid_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @valid_address_2 "0xF380B8F1e63e2BEd7CA329CA1FdDbC39B52cC0d3"

  # Ethereum mainnet Oracle address (lib/onchain/aave/contracts.ex).
  @oracle_address "0x54586bE62E3c3580375aE3723C145253060Ca0C2"

  # Known-good EIP-55 checksummed addresses reused verbatim from elsewhere in
  # this repo (contracts.ex / pool_test.exs) as canned decode results — their
  # correct casing is independent of anything Oracle computes, so asserting
  # against them exercises the real Address.checksum/1 output rather than
  # ratifying whatever Oracle happens to produce.
  @chainlink_source "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2"
  @base_currency_addr "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
  @fallback_oracle_addr "0x56b7A1012765C285afAC8b8F25C69Bf10ccfE978"

  @price_1 305_000_000_000
  @price_2 100_000_000
  @base_currency_unit 100_000_000

  describe "get_asset_price/2" do
    test "returns error for invalid address" do
      assert {:error, {:invalid_address, "bad"}} = Oracle.get_asset_price("bad")
    end
  end

  describe "get_asset_price!/2" do
    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/get_asset_price failed/, fn ->
        Oracle.get_asset_price!("bad")
      end
    end
  end

  describe "get_asset_prices/2" do
    test "returns error when any address is invalid" do
      assert {:error, {:invalid_address, "bad"}} =
               Oracle.get_asset_prices([@valid_address, "bad"])
    end

    test "validates all addresses before failing on an unsupported network" do
      # All addresses are valid, so validation succeeds and the call proceeds
      # to the next step (contract address lookup), which fails on the
      # unsupported network — proves the validate_addresses success path.
      assert {:error, {:unsupported_network, :solana}} =
               Oracle.get_asset_prices([@valid_address], network: :solana)
    end
  end

  describe "get_asset_prices!/2" do
    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/get_asset_prices failed/, fn ->
        Oracle.get_asset_prices!(["bad"])
      end
    end
  end

  describe "get_source_of_asset/2" do
    test "returns error for invalid address" do
      assert {:error, {:invalid_address, "bad"}} = Oracle.get_source_of_asset("bad")
    end
  end

  describe "get_source_of_asset!/2" do
    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/get_source_of_asset failed/, fn ->
        Oracle.get_source_of_asset!("bad")
      end
    end
  end

  describe "get_latest_round_data/2" do
    test "returns error for invalid aggregator address" do
      assert {:error, {:invalid_address, "bad"}} = Oracle.get_latest_round_data("bad")
    end
  end

  describe "get_latest_round_data!/2" do
    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/get_latest_round_data failed/, fn ->
        Oracle.get_latest_round_data!("bad")
      end
    end
  end

  describe "get_base_currency!/1, get_base_currency_unit!/1, get_fallback_oracle!/1 raise branch" do
    test "get_base_currency! raises when the oracle lookup fails" do
      assert_raise RuntimeError, ~r/get_base_currency failed.*unsupported_network/, fn ->
        Oracle.get_base_currency!(network: :solana)
      end
    end

    test "get_base_currency_unit! raises when the oracle lookup fails" do
      assert_raise RuntimeError, ~r/get_base_currency_unit failed.*unsupported_network/, fn ->
        Oracle.get_base_currency_unit!(network: :solana)
      end
    end

    test "get_fallback_oracle! raises when the oracle lookup fails" do
      assert_raise RuntimeError, ~r/get_fallback_oracle failed.*unsupported_network/, fn ->
        Oracle.get_fallback_oracle!(network: :solana)
      end
    end
  end

  describe "oracle read decode paths" do
    setup do
      {:ok, asset_bin} = Address.validate(@valid_address)
      {:ok, asset_2_bin} = Address.validate(@valid_address_2)
      {:ok, source_bin} = Address.validate(@chainlink_source)
      {:ok, base_currency_bin} = Address.validate(@base_currency_addr)
      {:ok, fallback_bin} = Address.validate(@fallback_oracle_addr)

      payloads = %{
        RPCStub.selector("getAssetPrice(address)", [asset_bin]) => RPCStub.encode("(uint256)", [{@price_1}]),
        RPCStub.selector("getAssetsPrices(address[])", [[asset_bin, asset_2_bin]]) =>
          RPCStub.encode("(uint256[])", [{[@price_1, @price_2]}]),
        RPCStub.selector("getSourceOfAsset(address)", [asset_bin]) => RPCStub.encode("(address)", [{source_bin}]),
        RPCStub.selector("BASE_CURRENCY()", []) => RPCStub.encode("(address)", [{base_currency_bin}]),
        RPCStub.selector("BASE_CURRENCY_UNIT()", []) => RPCStub.encode("(uint256)", [{@base_currency_unit}]),
        RPCStub.selector("getFallbackOracle()", []) => RPCStub.encode("(address)", [{fallback_bin}])
      }

      seen = start_supervised!({Agent, fn -> [] end})
      url = RPCStub.start(RPCStub.payload_handler(payloads, seen))

      %{url: url, seen: seen}
    end

    test "get_asset_price/2 decodes the exact price and addresses the oracle contract", %{
      url: url,
      seen: seen
    } do
      assert {:ok, @price_1} = Oracle.get_asset_price(@valid_address, RPCStub.rpc_opts(url))

      assert [to] = Agent.get(seen, & &1)
      assert String.downcase(to) == String.downcase(@oracle_address)
    end

    test "get_asset_price!/2 returns the unwrapped price on success", %{url: url} do
      assert @price_1 == Oracle.get_asset_price!(@valid_address, RPCStub.rpc_opts(url))
    end

    test "get_asset_prices/2 decodes prices in input order", %{url: url} do
      assert {:ok, [@price_1, @price_2]} =
               Oracle.get_asset_prices([@valid_address, @valid_address_2], RPCStub.rpc_opts(url))
    end

    test "get_asset_prices!/2 returns the unwrapped list on success", %{url: url} do
      assert [@price_1, @price_2] ==
               Oracle.get_asset_prices!([@valid_address, @valid_address_2], RPCStub.rpc_opts(url))
    end

    test "get_source_of_asset/2 returns the correctly checksummed aggregator address", %{url: url} do
      assert {:ok, @chainlink_source} =
               Oracle.get_source_of_asset(@valid_address, RPCStub.rpc_opts(url))
    end

    test "get_source_of_asset!/2 returns the unwrapped checksummed address", %{url: url} do
      assert @chainlink_source == Oracle.get_source_of_asset!(@valid_address, RPCStub.rpc_opts(url))
    end

    test "get_base_currency/1 returns the correctly checksummed base currency address", %{url: url} do
      assert {:ok, @base_currency_addr} = Oracle.get_base_currency(RPCStub.rpc_opts(url))
    end

    test "get_base_currency!/1 returns the unwrapped checksummed address", %{url: url} do
      assert @base_currency_addr == Oracle.get_base_currency!(RPCStub.rpc_opts(url))
    end

    test "get_base_currency_unit/1 returns the exact unit", %{url: url} do
      assert {:ok, @base_currency_unit} = Oracle.get_base_currency_unit(RPCStub.rpc_opts(url))
    end

    test "get_base_currency_unit!/1 returns the unwrapped unit", %{url: url} do
      assert @base_currency_unit == Oracle.get_base_currency_unit!(RPCStub.rpc_opts(url))
    end

    test "get_fallback_oracle/1 returns the correctly checksummed fallback address", %{url: url} do
      assert {:ok, @fallback_oracle_addr} = Oracle.get_fallback_oracle(RPCStub.rpc_opts(url))
    end

    test "get_fallback_oracle!/1 returns the unwrapped checksummed address", %{url: url} do
      assert @fallback_oracle_addr == Oracle.get_fallback_oracle!(RPCStub.rpc_opts(url))
    end

    test "propagates a JSON-RPC error instead of decoding it" do
      url = RPCStub.start(fn _request -> {:error, %{"code" => -32_000, "message" => "execution reverted"}} end)

      assert {:error, _reason} = Oracle.get_asset_price(@valid_address, RPCStub.rpc_opts(url))
    end
  end

  describe "get_latest_round_data/2 decode path" do
    @round_id 18_446_744_073_709_551_617
    @answered_in_round 18_446_744_073_709_551_618
    @answer -305_000_000_000
    @started_at 1_700_000_000
    @updated_at 1_700_000_100

    setup do
      payload =
        RPCStub.encode("(uint80,int256,uint256,uint256,uint80)", [
          {@round_id, @answer, @started_at, @updated_at, @answered_in_round}
        ])

      selector = RPCStub.selector("latestRoundData()", [])
      url = RPCStub.start(RPCStub.payload_handler(%{selector => payload}))

      %{url: url}
    end

    test "decodes round id, a negative signed answer, and timestamps", %{url: url} do
      assert {:ok,
              %{
                round_id: @round_id,
                answer: @answer,
                started_at: @started_at,
                updated_at: @updated_at,
                answered_in_round: @answered_in_round
              }} = Oracle.get_latest_round_data(@valid_address, RPCStub.rpc_opts(url))
    end

    test "get_latest_round_data!/2 returns the unwrapped map on success", %{url: url} do
      assert %{answer: @answer} = Oracle.get_latest_round_data!(@valid_address, RPCStub.rpc_opts(url))
    end
  end

  describe "default arguments" do
    test "the opts-less clauses fall back to the configured node and :ethereum" do
      {:ok, base_currency_bin} = Address.validate(@base_currency_addr)
      {:ok, fallback_bin} = Address.validate(@fallback_oracle_addr)

      url =
        RPCStub.start(
          RPCStub.payload_handler(%{
            RPCStub.selector("BASE_CURRENCY()", []) => RPCStub.encode("(address)", [{base_currency_bin}]),
            RPCStub.selector("BASE_CURRENCY_UNIT()", []) => RPCStub.encode("(uint256)", [{@base_currency_unit}]),
            RPCStub.selector("getFallbackOracle()", []) => RPCStub.encode("(address)", [{fallback_bin}])
          })
        )

      put_ethereum_node(url)

      assert {:ok, @base_currency_addr} = Oracle.get_base_currency()
      assert @base_currency_addr == Oracle.get_base_currency!()
      assert {:ok, @base_currency_unit} = Oracle.get_base_currency_unit()
      assert @base_currency_unit == Oracle.get_base_currency_unit!()
      assert {:ok, @fallback_oracle_addr} = Oracle.get_fallback_oracle()
      assert @fallback_oracle_addr == Oracle.get_fallback_oracle!()
    end
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
end
