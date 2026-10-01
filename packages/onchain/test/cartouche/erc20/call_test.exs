defmodule Onchain.ERC20.CallTest do
  use ExUnit.Case, async: true
  use Onchain.Hex

  alias Onchain.ERC20, as: Erc20

  @token <<0xCC::160>>
  @address <<0xDD::160>>

  describe "balance_of/3" do
    test "defaults to unsigned integer decoding" do
      assert {:ok, 0x0C} = Erc20.Call.balance_of(@token, @address)
    end

    test "overrides caller decode option with unsigned integer decoding" do
      assert {:ok, 0x0C} = Erc20.Call.balance_of(@token, @address, decode: :hex)
    end
  end

  describe "transfer/4" do
    test "defaults to raw hex decoding" do
      assert {:ok, <<0x0C>>} = Erc20.Call.transfer(@token, @address, 100_000)
    end

    test "overrides caller decode option with raw hex decoding" do
      assert {:ok, <<0x0C>>} = Erc20.Call.transfer(@token, @address, 100_000, decode: :hex_unsigned)
    end
  end

  test "calldata helpers retain the binary ERC-20 encoding contract" do
    balance = Erc20.CallData.balance_of(@address)
    assert <<0x70, 0xA0, 0x82, 0x31, _::binary>> = balance
    assert {:ok, [@address]} = Onchain.ABI.decode_call("balanceOf(address)", balance)

    transfer = Erc20.CallData.transfer(@address, 100_000)
    assert <<0xA9, 0x05, 0x9C, 0xBB, _::binary>> = transfer
    assert {:ok, [@address, 100_000]} = Onchain.ABI.decode_call("transfer(address,uint256)", transfer)
  end

  test "configured signer execution remains available through exec_trx" do
    calldata = Erc20.CallData.transfer(@address, 100_000)
    hash = <<42::256>>

    plug = fn conn ->
      request = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()

      if request["method"] == "eth_sendRawTransaction" do
        [encoded] = request["params"]
        assert {:ok, transaction} = encoded |> Onchain.Hex.decode!() |> Onchain.Transaction.V2.decode()
        assert transaction.destination == @token
        assert transaction.data == calldata
        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => request["id"], "result" => Onchain.Hex.encode(hash)})
      else
        Onchain.Test.Client.call(conn)
      end
    end

    assert {:ok, ^hash} = Erc20.exec_trx(@token, calldata, req_options: [plug: plug])
  end
end
