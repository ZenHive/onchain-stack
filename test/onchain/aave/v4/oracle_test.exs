defmodule Onchain.Aave.V4.OracleTest do
  use ExUnit.Case, async: false

  alias Onchain.Aave.Contracts
  alias Onchain.Aave.V4.Oracle
  alias Onchain.RPCStub

  @spoke Contracts.address!(:v4_main_spoke)
  @oracle Contracts.address!(:v4_main_spoke_oracle)
  @feed "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419"
  @weth_price 250_000_000_000
  @usdc_price 100_000_000
  @round {1, @weth_price, 1_700_000_000, 1_700_000_001, 1}

  describe "input validation" do
    test "spoke-taking reads reject an invalid Spoke address before RPC" do
      Enum.each(
        [
          &Oracle.oracle_address/1,
          &Oracle.decimals/1,
          &Oracle.get_spoke/1,
          &Oracle.get_reserve_price(&1, 0),
          &Oracle.get_reserve_prices(&1, [0]),
          &Oracle.get_reserve_source(&1, 0),
          &Oracle.get_asset_price(&1, 0),
          &Oracle.get_asset_prices(&1, [0]),
          &Oracle.get_source_of_asset(&1, 0)
        ],
        fn fun ->
          assert {:error, {:invalid_address, "bad"}} = fun.("bad")
        end
      )
    end

    test "Chainlink reads reject an invalid feed address before RPC" do
      assert {:error, {:invalid_address, "bad"}} = Oracle.get_latest_round_data("bad")
      assert {:error, {:invalid_address, "bad"}} = Oracle.get_latest_answer("bad")
    end

    test "bang variants raise on invalid address" do
      assert_raise RuntimeError, ~r/oracle_address failed/, fn -> Oracle.oracle_address!("bad") end
      assert_raise RuntimeError, ~r/get_reserve_price failed/, fn -> Oracle.get_reserve_price!("bad", 0) end
      assert_raise RuntimeError, ~r/get_reserve_prices failed/, fn -> Oracle.get_reserve_prices!("bad", [0]) end
      assert_raise RuntimeError, ~r/get_reserve_source failed/, fn -> Oracle.get_reserve_source!("bad", 0) end
      assert_raise RuntimeError, ~r/decimals failed/, fn -> Oracle.decimals!("bad") end
      assert_raise RuntimeError, ~r/get_spoke failed/, fn -> Oracle.get_spoke!("bad") end
      assert_raise RuntimeError, ~r/get_reserve_price failed/, fn -> Oracle.get_asset_price!("bad", 0) end
      assert_raise RuntimeError, ~r/get_reserve_prices failed/, fn -> Oracle.get_asset_prices!("bad", [0]) end
      assert_raise RuntimeError, ~r/get_reserve_source failed/, fn -> Oracle.get_source_of_asset!("bad", 0) end
      assert_raise RuntimeError, ~r/get_latest_round_data failed/, fn -> Oracle.get_latest_round_data!("bad") end
      assert_raise RuntimeError, ~r/get_latest_answer failed/, fn -> Oracle.get_latest_answer!("bad") end
    end
  end

  describe "Spoke-scoped IAaveOracle reads" do
    setup do
      payloads = call_payloads()
      seen = start_supervised!({Agent, fn -> [] end})
      url = RPCStub.start(fn body -> handle_eth_call(body, payloads, seen) end)

      %{rpc_opts: RPCStub.rpc_opts(url), seen: seen}
    end

    test "every Task 46-selected read succeeds", %{rpc_opts: rpc_opts} do
      assert {:ok, oracle} = Oracle.oracle_address(@spoke, rpc_opts)
      assert oracle == @oracle

      assert {:ok, @weth_price} = Oracle.get_reserve_price(@spoke, 0, rpc_opts)
      assert {:ok, [@weth_price, @usdc_price]} = Oracle.get_reserve_prices(@spoke, [0, 1], rpc_opts)
      assert {:ok, []} = Oracle.get_reserve_prices(@spoke, [], rpc_opts)

      assert {:ok, source} = Oracle.get_reserve_source(@spoke, 0, rpc_opts)
      assert source == Onchain.Address.checksum!(@feed)

      assert {:ok, 8} = Oracle.decimals(@spoke, rpc_opts)

      assert {:ok, bound} = Oracle.get_spoke(@spoke, rpc_opts)
      assert bound == @spoke
    end

    test "V3-shaped aliases match the reserve-id reads", %{rpc_opts: rpc_opts} do
      assert Oracle.get_asset_price(@spoke, 0, rpc_opts) == Oracle.get_reserve_price(@spoke, 0, rpc_opts)

      assert Oracle.get_asset_prices(@spoke, [0, 1], rpc_opts) ==
               Oracle.get_reserve_prices(@spoke, [0, 1], rpc_opts)

      assert Oracle.get_source_of_asset(@spoke, 0, rpc_opts) == Oracle.get_reserve_source(@spoke, 0, rpc_opts)
    end

    test "bang variants return unwrapped values", %{rpc_opts: rpc_opts} do
      assert Oracle.oracle_address!(@spoke, rpc_opts) == @oracle
      assert Oracle.get_reserve_price!(@spoke, 0, rpc_opts) == @weth_price
      assert Oracle.get_reserve_prices!(@spoke, [0, 1], rpc_opts) == [@weth_price, @usdc_price]
      assert Oracle.get_reserve_source!(@spoke, 0, rpc_opts) == Onchain.Address.checksum!(@feed)
      assert Oracle.decimals!(@spoke, rpc_opts) == 8
      assert Oracle.get_spoke!(@spoke, rpc_opts) == @spoke
      assert Oracle.get_asset_price!(@spoke, 0, rpc_opts) == @weth_price
      assert Oracle.get_asset_prices!(@spoke, [0], rpc_opts) == [@weth_price]
      assert Oracle.get_source_of_asset!(@spoke, 0, rpc_opts) == Onchain.Address.checksum!(@feed)
    end

    test "resolves ORACLE() on the Spoke then reads the oracle contract", %{rpc_opts: rpc_opts, seen: seen} do
      assert {:ok, _} = Oracle.get_reserve_price(@spoke, 0, rpc_opts)

      tos =
        seen
        |> Agent.get(& &1)
        |> Enum.map(fn {to, _data} -> to end)
        |> Enum.reverse()

      assert tos == [String.downcase(@spoke), String.downcase(@oracle)]
    end

    test "network option is ignored because the oracle is Spoke-scoped", %{rpc_opts: rpc_opts} do
      opts = Keyword.put(rpc_opts, :network, :solana)
      assert {:ok, @weth_price} = Oracle.get_reserve_price(@spoke, 0, opts)
    end

    test "Chainlink aggregator reads succeed", %{rpc_opts: rpc_opts} do
      assert {:ok, data} = Oracle.get_latest_round_data(@feed, rpc_opts)

      assert data == %{
               round_id: 1,
               answer: @weth_price,
               started_at: 1_700_000_000,
               updated_at: 1_700_000_001,
               answered_in_round: 1
             }

      assert {:ok, @weth_price} = Oracle.get_latest_answer(@feed, rpc_opts)
      assert Oracle.get_latest_round_data!(@feed, rpc_opts) == data
      assert Oracle.get_latest_answer!(@feed, rpc_opts) == @weth_price
    end
  end

  defp call_payloads do
    {:ok, spoke_bin} = Onchain.Address.validate(@spoke)
    {:ok, oracle_bin} = Onchain.Address.validate(@oracle)
    {:ok, feed_bin} = Onchain.Address.validate(@feed)

    %{
      calldata("ORACLE()", []) => RPCStub.encode("(address)", [{oracle_bin}]),
      calldata("getReservePrice(uint256)", [0]) => RPCStub.encode("(uint256)", [{@weth_price}]),
      calldata("getReservesPrices(uint256[])", [[0, 1]]) => RPCStub.encode("(uint256[])", [{[@weth_price, @usdc_price]}]),
      calldata("getReservesPrices(uint256[])", [[]]) => RPCStub.encode("(uint256[])", [{[]}]),
      calldata("getReservesPrices(uint256[])", [[0]]) => RPCStub.encode("(uint256[])", [{[@weth_price]}]),
      calldata("getReserveSource(uint256)", [0]) => RPCStub.encode("(address)", [{feed_bin}]),
      calldata("decimals()", []) => RPCStub.encode("(uint8)", [{8}]),
      calldata("spoke()", []) => RPCStub.encode("(address)", [{spoke_bin}]),
      calldata("latestRoundData()", []) => RPCStub.encode("(uint80,int256,uint256,uint256,uint80)", [@round]),
      calldata("latestAnswer()", []) => RPCStub.encode("(int256)", [{@weth_price}])
    }
  end

  defp calldata(signature, params) do
    {:ok, hex} = Onchain.ABI.encode_call(signature, params)
    String.downcase(hex)
  end

  defp handle_eth_call(%{"method" => "eth_call", "params" => [%{"data" => data, "to" => to} | _]}, payloads, seen) do
    Agent.update(seen, &[{String.downcase(to), String.downcase(data)} | &1])

    Map.get_lazy(payloads, String.downcase(data), fn ->
      flunk("stub has no payload for data=#{data} to=#{to}")
    end)
  end
end
