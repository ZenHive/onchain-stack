defmodule Onchain.RPCCodegenTest do
  use ExUnit.Case, async: true

  @rpc_source Path.expand("../../lib/onchain/rpc.ex", __DIR__)
  @uniform_wrappers [
    :eth_send_raw_transaction,
    :get_balance,
    :block_number,
    :syncing,
    :chain_id,
    :get_transaction_count,
    :eth_get_code,
    :blob_base_fee
  ]
  @block_wrappers [
    :get_block_receipts,
    :get_block_transaction_count_by_hash,
    :get_block_transaction_count_by_number,
    :get_transaction_by_block_hash_and_index,
    :get_transaction_by_block_number_and_index,
    :get_block_access_list
  ]

  test "uniform and block RPC wrappers are declared through defrpc codegen" do
    ast =
      @rpc_source
      |> File.read!()
      |> Code.string_to_quoted!()

    wrappers = @uniform_wrappers ++ @block_wrappers

    assert imports_rpc_codegen?(ast)
    assert Enum.sort(wrappers) == Enum.sort(macro_call_names(ast, :defrpc))
    assert Enum.sort(wrappers) == Enum.sort(macro_call_names(ast, :defrpc_bang))
  end

  defp imports_rpc_codegen?(ast) do
    {_ast, imported?} =
      Macro.prewalk(ast, false, fn
        {:import, _meta, [{:__aliases__, _alias_meta, [:Onchain, :RPC, :Codegen]} | _]} = node, _acc ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    imported?
  end

  defp macro_call_names(ast, macro_name) do
    {_ast, names} =
      Macro.prewalk(ast, [], fn
        {^macro_name, _meta, [name | _]} = node, acc when is_atom(name) ->
          {node, [name | acc]}

        node, acc ->
          {node, acc}
      end)

    names
  end
end
