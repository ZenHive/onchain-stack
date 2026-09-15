defmodule Onchain.Aerodrome.CalldataFixtureTest do
  use ExUnit.Case, async: false

  alias Onchain.ABI
  alias Onchain.Aerodrome.Bindings.Abi
  alias Onchain.Aerodrome.CalldataFixture
  alias Onchain.Aerodrome.Contracts
  alias Onchain.Aerodrome.Fixtures

  defmodule Transport do
    @moduledoc false

    @spec run(Req.Request.t()) :: {Req.Request.t(), Req.Response.t()}
    def run(request), do: Process.get(__MODULE__).(request)
  end

  test "Voter.reset calldata matches cast at uint256 boundaries" do
    assert {:ok, "reset(uint256)" = signature} = Abi.signature("voter.json", "reset")

    for id <- [0, 1, 256, Integer.pow(2, 256) - 1] do
      assert {:ok, calldata} = ABI.encode_call(signature, [id])
      assert CalldataFixture.assert_calldata(calldata, signature, [Integer.to_string(id)])
    end
  end

  test "the reference catches a wrong argument and a wrong selector" do
    assert {:ok, wrong_id} = ABI.encode_call("reset(uint256)", [2])
    assert {:ok, wrong_selector} = ABI.encode_call("poke(uint256)", [1])

    for wrong <- [wrong_id, wrong_selector] do
      assert_raise ExUnit.AssertionError, fn ->
        CalldataFixture.assert_calldata(wrong, "reset(uint256)", ["1"])
      end
    end
  end

  test "cast handles dynamic arguments independently" do
    signature = "example(uint256[],string)"
    assert {:ok, calldata} = ABI.encode_call(signature, [[1, 256], "two words"])
    assert CalldataFixture.assert_calldata(calldata, signature, ["[1,256]", "two words"])
  end

  test "a cast encoding failure flunks" do
    error = assert_raise ExUnit.AssertionError, fn -> CalldataFixture.reference!("reset(uint256)", ["-1"]) end
    assert error.message =~ "cast calldata failed (exit"
  end

  test "missing cast flunks with the exact install commands" do
    original = System.get_env("PATH")

    try do
      System.put_env("PATH", "")
      error = assert_raise ExUnit.AssertionError, fn -> CalldataFixture.reference!("reset(uint256)", ["1"]) end
      assert error.message =~ "curl -L https://getfoundry.sh/install | bash"
      assert error.message =~ "foundryup"
    after
      case original do
        path when is_binary(path) -> System.put_env("PATH", path)
        nil -> System.delete_env("PATH")
      end
    end
  end

  test "impersonation sends the Sugar owner as from and preserves return bytes and revert data" do
    fixture = Fixtures.load("ve_sugar.byId")
    {:ok, [nft]} = Fixtures.decode(fixture)
    owner = Onchain.Hex.encode(elem(nft, 1))
    voter = Contracts.address!(:voter)
    block = "0x30f85d0"

    for reply <- [
          %{"result" => "0x"},
          %{"error" => %{"code" => 3, "message" => "execution reverted", "data" => "0xe433766c"}}
        ] do
      adapter = fn request ->
        case request.body |> IO.iodata_to_binary() |> Jason.decode!() do
          %{"id" => id, "method" => "eth_call", "params" => [call, ^block]} ->
            assert String.downcase(call["to"]) == String.downcase(fixture["address"])
            assert call["data"] == fixture["calldata"]
            respond(request, %{"jsonrpc" => "2.0", "id" => id, "result" => fixture["response"]})

          [%{"id" => id, "method" => "eth_call", "params" => [call, ^block]}] ->
            assert call == %{"to" => voter, "from" => owner, "data" => "0x12345678"}
            respond(request, [Map.merge(%{"jsonrpc" => "2.0", "id" => id}, reply)])
        end
      end

      result =
        CalldataFixture.eth_call_as_sugar_owner(voter, "0x12345678", 1,
          block: block,
          rpc_url: "http://stub.invalid",
          req_options: transport(adapter)
        )

      case reply do
        %{"result" => bytes} -> assert result == {:ok, bytes}
        %{"error" => _} -> assert {:error, {:rpc_error, %{data: "0xe433766c", code: 3}}} = result
      end
    end
  end

  test "a Sugar read failure is returned without impersonating anyone" do
    adapter = fn request ->
      assert %{"id" => id, "method" => "eth_call"} = request.body |> IO.iodata_to_binary() |> Jason.decode!()

      respond(request, %{
        "jsonrpc" => "2.0",
        "id" => id,
        "error" => %{"code" => -32_000, "message" => "missing trie node"}
      })
    end

    assert {:error, {:rpc_error, %{code: -32_000, message: "missing trie node"}}} =
             CalldataFixture.eth_call_as_sugar_owner(Contracts.address!(:voter), "0x12345678", 1,
               rpc_url: "http://stub.invalid",
               req_options: transport(adapter)
             )
  end

  test "a missing Sugar owner is rejected before impersonation" do
    fixture = Fixtures.load("ve_sugar.byId")
    {:ok, [nft]} = Fixtures.decode(fixture)
    owner_hex = Base.encode16(elem(nft, 1), case: :lower)
    response = String.replace(fixture["response"], owner_hex, String.duplicate("0", 40))

    adapter = fn request ->
      assert %{"id" => id} = request.body |> IO.iodata_to_binary() |> Jason.decode!()
      respond(request, %{"jsonrpc" => "2.0", "id" => id, "result" => response})
    end

    assert {:error, {:sugar_owner_not_found, 1}} =
             CalldataFixture.eth_call_as_sugar_owner(Contracts.address!(:voter), "0x12345678", 1,
               rpc_url: "http://stub.invalid",
               req_options: transport(adapter)
             )
  end

  test "an integer block is hex-encoded on the Sugar read and the impersonation" do
    fixture = Fixtures.load("ve_sugar.byId")
    {:ok, [nft]} = Fixtures.decode(fixture)
    owner = Onchain.Hex.encode(elem(nft, 1))
    voter = Contracts.address!(:voter)
    block = Onchain.Hex.from_integer(51_348_944)

    adapter = fn request ->
      case request.body |> IO.iodata_to_binary() |> Jason.decode!() do
        %{"id" => id, "method" => "eth_call", "params" => [_call, ^block]} ->
          respond(request, %{"jsonrpc" => "2.0", "id" => id, "result" => fixture["response"]})

        [%{"id" => id, "method" => "eth_call", "params" => [call, ^block]}] ->
          assert call == %{"to" => voter, "from" => owner, "data" => "0x12345678"}
          respond(request, [%{"jsonrpc" => "2.0", "id" => id, "result" => "0x"}])
      end
    end

    assert {:ok, "0x"} =
             CalldataFixture.eth_call_as_sugar_owner(voter, "0x12345678", 1,
               block: 51_348_944,
               rpc_url: "http://stub.invalid",
               req_options: transport(adapter)
             )
  end

  test "an invalid block is returned without impersonating" do
    adapter = fn _request -> flunk("must not RPC") end

    assert {:error, {:invalid_block, "0xzz"}} =
             CalldataFixture.eth_call_as_sugar_owner(Contracts.address!(:voter), "0x12345678", 1,
               block: "0xzz",
               rpc_url: "http://stub.invalid",
               req_options: transport(adapter)
             )
  end

  defp respond(request, body) do
    {request, Req.Response.new(status: 200, body: Jason.encode!(body))}
  end

  defp transport(adapter) do
    Process.put(Transport, adapter)
    [adapter: Transport]
  end
end
