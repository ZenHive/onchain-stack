defmodule Onchain.Aerodrome.Integration.PortabilityTest do
  use ExUnit.Case, async: false

  alias Onchain.ABI
  alias Onchain.Aerodrome.Bindings.Abi
  alias Onchain.Aerodrome.Contracts
  alias Onchain.Aerodrome.RPCCase
  alias Onchain.RPC

  @moduletag :integration
  # Two 180s RPC calls plus blockNumber exceed ExUnit's 60s default.
  @moduletag timeout: 600_000

  # Encodes all(uint256,uint256,uint256) directly so endpoint agreement does
  # not depend on Bindings.LpSugar.all/4 wrapping the same call.
  @limit 500
  @offset 0
  @filter 0
  @timeout 180_000

  test "LpSugar.all(500, 0, 0) decodes identically on both unprivileged endpoints" do
    address = Contracts.address!(:lp_sugar)
    {:ok, signature} = Abi.signature("lp_sugar.json", "all")
    {:ok, return_type} = Abi.return_type("lp_sugar.json", "all")
    {:ok, calldata} = ABI.encode_call(signature, [@limit, @offset, @filter])

    # Pin both calls to one block so a latest-block race cannot look like
    # endpoint disagreement. The second unprivileged endpoint is what the
    # portability claim rests on — not our archive node.
    block = pinned_block!()

    {primary, secondary} =
      RPCCase.run_on_both_endpoints(fn ->
        lp_sugar_all(address, calldata, return_type, block)
      end)

    assert primary == secondary
    assert [rows] = primary
    assert length(rows) == @limit
  end

  @spec pinned_block!() :: non_neg_integer()
  defp pinned_block! do
    opts = Keyword.put(RPCCase.rpc_opts!(), :timeout, @timeout)

    case RPC.block_number(opts) do
      # Two blocks behind latest so a lagging secondary cannot miss the pin.
      {:ok, block} -> max(block - 2, 0)
      {:error, reason} -> flunk("eth_blockNumber failed: #{inspect(reason)}")
    end
  end

  @spec lp_sugar_all(String.t(), String.t(), String.t(), non_neg_integer()) :: [term()]
  defp lp_sugar_all(address, calldata, return_type, block) do
    opts = Keyword.merge(RPCCase.rpc_opts!(), timeout: @timeout, block: block, retry: [max_retries: 2, backoff_ms: 500])

    case RPC.eth_call(address, calldata, opts) do
      {:ok, hex} ->
        case ABI.decode_response(return_type, hex) do
          {:ok, decoded} -> decoded
          {:error, reason} -> flunk("LpSugar.all(500, 0, 0) decode failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        flunk("LpSugar.all(500, 0, 0) eth_call failed: #{inspect(reason)}")
    end
  end
end
