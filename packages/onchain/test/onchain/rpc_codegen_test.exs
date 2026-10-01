defmodule Onchain.RPCCodegenTest do
  use ExUnit.Case, async: true

  test "the surviving generator checks the spec for metadata declarations too" do
    assert_raise ArgumentError, ~r/unknown OpenRPC method/, fn ->
      Code.compile_quoted(
        quote do
          defmodule UnknownDocumentedRPC do
            @moduledoc false
            import Onchain.RPC.Codegen

            defrpc(:unknown, method: "eth_typo", summary: "Typo")
          end
        end
      )
    end
  end

  test "bang generation unwraps success and raises with the original error" do
    assert Onchain.RPC.chain_id!(
             req_options: [
               plug: fn conn ->
                 request = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()
                 Req.Test.json(conn, %{id: request["id"], jsonrpc: "2.0", result: "0x1"})
               end
             ]
           ) == 1

    assert_raise RuntimeError, ~r/get_balance failed:.*invalid_address/, fn ->
      Onchain.RPC.get_balance!("bad address")
    end
  end
end
