defmodule Onchain.RPC.NodeRefusalIntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.RPC

  @moduletag :integration

  @unknown_method "eth_thisMethodDoesNotExistAnywhere"
  @historical_block 20_000_000

  # Observed live on Alchemy mainnet, 2026-08-25. eth_blockNumber succeeded on
  # the same URL in the same session, so these are method/capability refusals,
  # not transport failures.
  @alchemy_unsupported_access_list "Unsupported method: eth_getBlockAccessList on ETH_MAINNET"
  @alchemy_base_fee_unavailable "eth_baseFee is not available on the ETH_MAINNET. For more information see our docs: https://docs.alchemy.com/alchemy/documentation/apis/ethereum"
  @alchemy_trace_tier "trace_block is not available on the Free tier - upgrade to Pay As You Go, or Enterprise for access."
  @alchemy_unable "Unable to complete request at this time."

  describe "standard method-not-found on the configured node" do
    test "an unimplemented method returns {:method_not_found, map} with -32601" do
      opts = [rpc_url: Onchain.RPCCase.rpc_url!()]

      assert {:error, {:method_not_found, %{code: -32_601, message: message}}} =
               RPC.call(@unknown_method, [], opts)

      assert message == "Method not found"
    end
  end

  describe "hosted-provider refusals" do
    test "Alchemy refuses eth_getBlockAccessList as {:method_not_found, map}" do
      opts = limited_opts()
      assert {:ok, block} = RPC.block_number(opts)
      assert is_integer(block) and block > 0

      assert {:error, {:method_not_found, %{code: -32_600, message: @alchemy_unsupported_access_list}}} =
               RPC.get_block_access_list(@historical_block, opts)

      assert {:error, {:method_not_found, %{code: -32_600, message: @alchemy_unsupported_access_list}}} =
               RPC.call("eth_getBlockAccessList", [Onchain.Hex.from_integer(@historical_block)], opts)
    end

    test "Alchemy refuses eth_baseFee as {:method_not_found, map}" do
      opts = limited_opts()

      assert {:error, {:method_not_found, %{code: -32_600, message: @alchemy_base_fee_unavailable}}} =
               RPC.call("eth_baseFee", [], opts)
    end

    test "Alchemy Free-tier trace_block is {:namespace_unavailable, map}" do
      opts = limited_opts()

      assert {:error, {:namespace_unavailable, %{code: -32_600, message: @alchemy_trace_tier}}} =
               RPC.call("trace_block", [Onchain.Hex.from_integer(@historical_block)], opts)
    end

    test "historical eth_feeHistory is {:unavailable, map}; latest feeHistory succeeds" do
      opts = limited_opts()

      assert {:ok, %Cartouche.FeeHistory{}} =
               RPC.fee_history(1, Keyword.put(opts, :newest_block, "latest"))

      assert {:error, {:unavailable, %{code: -32_001, message: @alchemy_unable}}} =
               RPC.fee_history(1, Keyword.put(opts, :newest_block, @historical_block))
    end

    test "erigon_getHeaderByNumber produces the same {:unavailable, map} as pruned feeHistory" do
      # Pinning the collision: Alchemy answers HTTP 503 / -32001
      # "Unable to complete request at this time." for this unimplemented
      # Erigon method, identical at the wire to historical eth_feeHistory.
      # The classifier does not invent a pruned-vs-unimplemented distinction
      # the node does not make.
      opts = limited_opts()

      assert {:error, {:unavailable, %{code: -32_001, message: @alchemy_unable}}} =
               RPC.call("erigon_getHeaderByNumber", ["0x1"], opts)
    end
  end

  describe "call mode changes the provider's wire response" do
    # The classifier is uniform across call modes; the provider is not. Observed
    # live on Alchemy mainnet 2026-08-25 — the byte-identical eth_feeHistory
    # request answers -32001 as a single call and a generic -32000 "Internal
    # error" inside a JSON-RPC array batch, alone or alongside a healthy call.
    # -32000 "Internal error" stays unclassified on purpose: it is
    # indistinguishable from a genuine internal failure, and the classifier does
    # not invent a distinction the node declines to make.
    test "pruned eth_feeHistory is {:unavailable, map} single but unclassified batched" do
      opts = limited_opts()
      params = ["0x1", Onchain.Hex.from_integer(@historical_block), [50]]

      assert {:error, {:unavailable, %{code: -32_001, message: @alchemy_unable}}} =
               RPC.call("eth_feeHistory", params, opts)

      assert {:error, {:rpc_error, %{code: -32_000, message: "Internal error"}}} =
               RPC.batch([{"eth_feeHistory", params}], opts)

      assert {:error, {:rpc_error, %{code: -32_000, message: "Internal error"}}} =
               RPC.batch([{"eth_blockNumber", []}, {"eth_feeHistory", params}], opts)
    end

    test "a batched capability refusal the provider reports identically still classifies" do
      opts = limited_opts()

      assert {:error, {:method_not_found, %{code: -32_600, message: @alchemy_base_fee_unavailable}}} =
               RPC.batch([{"eth_blockNumber", []}, {"eth_baseFee", []}], opts)

      assert {:error, {:namespace_unavailable, %{code: -32_600, message: @alchemy_trace_tier}}} =
               RPC.batch([{"trace_block", [Onchain.Hex.from_integer(@historical_block)]}], opts)
    end
  end

  defp limited_opts, do: [rpc_url: Onchain.RPCCase.limited_rpc_url!()]
end
