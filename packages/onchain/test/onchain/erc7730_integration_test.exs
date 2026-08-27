defmodule Onchain.ERC7730.IntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.ABI
  alias Onchain.ERC7730
  alias Onchain.Hex
  alias Onchain.RPCCase

  @moduletag :integration

  @fixtures "test/support/fixtures/erc7730"
  @usdc "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @recipient "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"

  # Resolves USDC decimals (6) + symbol ("USDC") live from the node, with no
  # caller-provided :tokens map — exercises the on-chain tokenAmount path.
  test "renders real ERC-20 transfer calldata, resolving token metadata over RPC" do
    rpc_url = RPCCase.rpc_url!()
    {:ok, descriptor} = ERC7730.load(Path.join(@fixtures, "erc20-transfer.json"))
    calldata = ABI.encode_call!("transfer(address,uint256)", [Hex.decode!(@recipient), 2_500_000])

    assert {:ok, fields} = ERC7730.format(descriptor, {:calldata, @usdc, 1, calldata}, rpc_url: rpc_url)

    assert [
             %{label: "To", formatted_value: @recipient},
             %{label: "Amount", formatted_value: "2.5 USDC", raw: 2_500_000}
           ] = fields
  end
end
