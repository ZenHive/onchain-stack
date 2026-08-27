defmodule Onchain.ContractTest do
  # async: false — EthCallStub mutates global :cartouche, Cartouche.RPC config
  use ExUnit.Case, async: false
  use Onchain.EthCallStub

  alias Onchain.Contract

  @valid_addr "0x" <> String.duplicate("ab", 20)
  @stub_opts [rpc_url: "http://stub.invalid"]
  @dirty_hex Onchain.Hex.encode(<<1>> <> :binary.copy(<<0>>, 30) <> <<1>>)

  describe "call/5" do
    test "returns error for invalid address" do
      assert {:error, {:invalid_address, "not_an_address"}} =
               Contract.call("not_an_address", "balanceOf(address)", [], "(uint256)")
    end

    test "returns error for empty string address" do
      assert {:error, {:invalid_address, ""}} =
               Contract.call("", "balanceOf(address)", [], "(uint256)")
    end

    test "returns error for malformed ABI signature" do
      valid_addr = "0x" <> String.duplicate("ab", 20)

      assert {:error, {:encode_error, _}} =
               Contract.call(valid_addr, "not a valid signature!!!", [], "(uint256)")
    end
  end

  describe "call!/5" do
    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/contract call failed.*invalid_address/, fn ->
        Contract.call!("bad_address", "balanceOf(address)", [], "(uint256)")
      end
    end
  end

  describe "call/5 decode opts" do
    test "forwards strict: true and surfaces {:decode_error, {:strict_violation, _}}" do
      Onchain.EthCallStub.queue_hex(@dirty_hex)
      padding = {:non_canonical_padding, %{type: {:uint, 8}}}

      assert {:error, {:decode_error, {:strict_violation, ^padding}}} =
               Contract.call(@valid_addr, "decimals()", [], "(uint8)", [{:strict, true} | @stub_opts])
    end

    test "without strict, dirty padding still decodes (permissive default)" do
      Onchain.EthCallStub.queue_hex(@dirty_hex)

      assert {:ok, [n]} = Contract.call(@valid_addr, "decimals()", [], "(uint8)", @stub_opts)
      assert is_integer(n) and n > 1
    end

    test "call!/5 returns decoded values for a canonical payload under strict: true" do
      Onchain.EthCallStub.queue_response("uint8", 6)

      assert [6] =
               Contract.call!(
                 @valid_addr,
                 "decimals()",
                 [],
                 "(uint8)",
                 [{:strict, true} | @stub_opts]
               )
    end

    test "call!/5 raises on strict_violation" do
      Onchain.EthCallStub.queue_hex(@dirty_hex)

      assert_raise RuntimeError, ~r/strict_violation/, fn ->
        Contract.call!(@valid_addr, "decimals()", [], "(uint8)", [{:strict, true} | @stub_opts])
      end
    end
  end
end
