defmodule Onchain.ENS.CCIPTest do
  use ExUnit.Case, async: true

  alias Onchain.ENS.CCIP
  alias Onchain.Hex

  @sender "0xC1735677a60884ABbCF72295E88d47764BeDa282"
  @callback_selector <<0xAA, 0xBB, 0xCC, 0xDD>>
  @call_data <<1, 2, 3, 4>>
  @extra_data <<9, 9, 9, 9>>

  # Builds a real OffchainLookup revert payload:
  # selector 0x556f1830 ++ abi(address,string[],bytes,bytes4,bytes).
  defp offchain_lookup_revert(urls) do
    sender_bin = Hex.decode!(@sender)

    args =
      ABI.encode(
        "(address,string[],bytes,bytes4,bytes)",
        [{sender_bin, urls, @call_data, @callback_selector, @extra_data}]
      )

    CCIP.offchain_lookup_selector() <> args
  end

  describe "offchain_lookup_selector/0" do
    test "is the EIP-3668 selector 0x556f1830" do
      assert CCIP.offchain_lookup_selector() == <<0x55, 0x6F, 0x18, 0x30>>
    end
  end

  describe "parse_offchain_lookup/1" do
    test "decodes a well-formed OffchainLookup revert" do
      revert = offchain_lookup_revert(["https://gw.example/{sender}/{data}.json"])

      assert {:ok, lookup} = CCIP.parse_offchain_lookup(revert)
      assert String.downcase(lookup.sender) == String.downcase(@sender)
      assert lookup.urls == ["https://gw.example/{sender}/{data}.json"]
      assert lookup.call_data == @call_data
      assert lookup.callback_function == @callback_selector
      assert lookup.extra_data == @extra_data
    end

    test "rejects a plain revert that is not an OffchainLookup" do
      # Error(string) selector — a normal require revert, not CCIP.
      assert {:error, :not_offchain_lookup} =
               CCIP.parse_offchain_lookup(<<0x08, 0xC3, 0x79, 0xA0, 0::256>>)
    end

    test "rejects data shorter than a selector" do
      assert {:error, :not_offchain_lookup} = CCIP.parse_offchain_lookup(<<1, 2>>)
    end

    test "rejects an OffchainLookup selector with undecodable args" do
      assert {:error, :not_offchain_lookup} =
               CCIP.parse_offchain_lookup(CCIP.offchain_lookup_selector() <> <<0, 1, 2>>)
    end
  end

  describe "build_gateway_request/2" do
    setup do
      {:ok, lookup} =
        CCIP.parse_offchain_lookup(offchain_lookup_revert(["unused"]))

      %{lookup: lookup}
    end

    test "uses GET and substitutes {sender}/{data} when {data} is present", %{lookup: lookup} do
      template = "https://gw.example/{sender}/{data}.json"

      assert {:get, url, nil} = CCIP.build_gateway_request(lookup, template)
      assert url == "https://gw.example/#{String.downcase(@sender)}/#{Hex.encode(@call_data)}.json"
    end

    test "uses POST with a JSON body when {data} is absent", %{lookup: lookup} do
      template = "https://gw.example/lookup"

      assert {:post, "https://gw.example/lookup", body} =
               CCIP.build_gateway_request(lookup, template)

      assert {:ok, decoded} = Jason.decode(body)
      assert decoded == %{"data" => Hex.encode(@call_data), "sender" => String.downcase(@sender)}
    end

    test "substitutes {sender} in a POST template", %{lookup: lookup} do
      assert {:post, url, _body} =
               CCIP.build_gateway_request(lookup, "https://gw.example/{sender}")

      assert url == "https://gw.example/#{String.downcase(@sender)}"
    end
  end

  describe "build_callback_calldata/2" do
    test "prepends the callback selector and ABI-encodes (response, extraData)" do
      {:ok, lookup} = CCIP.parse_offchain_lookup(offchain_lookup_revert(["unused"]))
      response = <<0xDE, 0xAD, 0xBE, 0xEF>>

      calldata = CCIP.build_callback_calldata(lookup, response)

      assert <<selector::binary-4, args::binary>> = calldata
      assert selector == @callback_selector
      assert [^response, @extra_data] = ABI.decode("(bytes,bytes)", args)
    end
  end

  describe "fetch/5 (round-trip loop)" do
    test "returns the direct result when the first call does not revert" do
      call_fun = fn _to, _data -> {:ok, "0x2a"} end
      gateway_fun = fn _lookup -> flunk("gateway should not be called") end

      assert {:ok, "0x2a"} = CCIP.fetch(call_fun, gateway_fun, @sender, "0xabcd")
    end

    test "follows OffchainLookup -> gateway -> callback to the final answer" do
      revert = offchain_lookup_revert(["https://gw.example/lookup"])
      response = <<0x12, 0x34>>
      final_hex = "0x00000000000000000000000000000000000000000000000000000000deadbeef"

      # First eth_call (initial data) reverts with OffchainLookup; the callback
      # eth_call (carrying the gateway response) returns the final answer.
      call_fun = fn to, data ->
        if data == "0xabcd" do
          {:revert, revert}
        else
          # Callback target must be the OffchainLookup sender, and the calldata
          # must be callbackSelector ++ abi(response, extraData).
          assert String.downcase(to) == String.downcase(@sender)
          {:ok, callback_args} = Hex.decode(data)
          assert <<@callback_selector::binary, encoded::binary>> = callback_args
          assert [^response, @extra_data] = ABI.decode("(bytes,bytes)", encoded)
          {:ok, final_hex}
        end
      end

      gateway_fun = fn lookup ->
        assert lookup.urls == ["https://gw.example/lookup"]
        {:ok, response}
      end

      assert {:ok, ^final_hex} = CCIP.fetch(call_fun, gateway_fun, @sender, "0xabcd")
    end

    test "propagates a gateway error" do
      revert = offchain_lookup_revert(["https://gw.example/lookup"])
      call_fun = fn _to, _data -> {:revert, revert} end
      gateway_fun = fn _lookup -> {:error, :ccip_no_gateway} end

      assert {:error, :ccip_no_gateway} = CCIP.fetch(call_fun, gateway_fun, @sender, "0xabcd")
    end

    test "surfaces a non-OffchainLookup revert as :execution_reverted" do
      plain_revert = <<0x08, 0xC3, 0x79, 0xA0, 0::256>>
      call_fun = fn _to, _data -> {:revert, plain_revert} end
      gateway_fun = fn _lookup -> flunk("gateway should not be called") end

      assert {:error, {:execution_reverted, ^plain_revert}} =
               CCIP.fetch(call_fun, gateway_fun, @sender, "0xabcd")
    end

    test "stops after the maximum number of redirects" do
      # A gateway that always triggers another OffchainLookup must terminate.
      revert = offchain_lookup_revert(["https://gw.example/lookup"])
      call_fun = fn _to, _data -> {:revert, revert} end
      gateway_fun = fn _lookup -> {:ok, <<0>>} end

      assert {:error, :ccip_max_redirects} = CCIP.fetch(call_fun, gateway_fun, @sender, "0xabcd")
    end
  end
end
