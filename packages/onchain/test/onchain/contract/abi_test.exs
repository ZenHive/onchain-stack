defmodule Onchain.Contract.ABITest do
  use ExUnit.Case, async: true

  alias Onchain.Contract.ABI, as: ContractABI
  alias Onchain.Contract.Generator

  @abi_path Path.expand("../../fixtures/codegen.json", __DIR__)
  @external_resource @abi_path
  @abi File.read!(@abi_path)

  defmodule Binding do
    @moduledoc false
    use Generator, abi_file: Path.expand("../../fixtures/codegen.json", __DIR__)
  end

  defmodule Adapter do
    @moduledoc false
    @spec run(Req.Request.t()) :: {Req.Request.t(), Req.Response.t()}
    def run(request), do: Process.get({__MODULE__, :callback}).(request)
  end

  test "constructor, events and errors retain their canonical metadata" do
    assert {:ok, abi} = ContractABI.parse_abi_json(@abi)
    assert abi == Binding.__contract_abi__()
    assert %{state_mutability: "payable", inputs: [%{ty: "address", name: "owner"}]} = abi.constructor
    assert [%{name: "Changed", signature: "Changed(address,uint256)", topic: topic, inputs: inputs}] = abi.events
    assert topic == Onchain.Hex.encode(ExKeccak.hash_256("Changed(address,uint256)"))
    assert Enum.map(inputs, & &1.indexed) == [true, false]
    assert [%{signature: "Denied(address)", selector: selector}] = abi.errors
    assert selector == Onchain.Hex.encode(binary_part(ExKeccak.hash_256("Denied(address)"), 0, 4))
  end

  test "tuple arguments and overloads compile and round-trip through a generated read" do
    address = "0x" <> String.duplicate("11", 20)
    value = {42, "alpha" <> <<0>> <> "omega"}

    adapter = fn req ->
      request = req.body |> IO.iodata_to_binary() |> Jason.decode!()
      assert request["method"] == "eth_call"
      [call, "latest"] = request["params"]
      assert call["to"] == address
      assert {:ok, expected} = Onchain.ABI.encode_hex_call("echo((uint256,string))", [value])
      assert call["data"] == expected
      result = "((uint256,string))" |> Onchain.ABI.encode([{value}]) |> Onchain.Hex.encode()

      {req,
       Req.Response.new(
         status: 200,
         body: Jason.encode!(%{"jsonrpc" => "2.0", "id" => request["id"], "result" => result})
       )}
    end

    Process.put({Adapter, :callback}, adapter)

    assert {:ok, [^value]} = Binding.echo_1(address, value, req_options: [adapter: Adapter])
    assert [^value] = Binding.echo_1!(address, value, req_options: [adapter: Adapter])
    assert {:ok, {^address, true, calldata}} = Binding.Multicall.echo_1(address, value)
    assert {:ok, ^calldata} = Onchain.ABI.encode_hex_call("echo((uint256,string))", [value])
    assert function_exported?(Binding, :echo_0, 1)
    assert function_exported?(Binding.Multicall, :echo_0, 1)
  end

  test "malformed input and missing files return tagged errors and bang forms raise" do
    for json <- ["not json", "{}", ~s([{"type":"invalid"}])] do
      assert {:error, {:parse_error, reason}} = ContractABI.parse_abi_json(json)
      assert is_binary(reason)
      assert_raise RuntimeError, ~r/ABI parse failed/, fn -> ContractABI.parse_abi_json!(json) end
    end

    assert {:error, {:file_error, _}} = ContractABI.parse_abi_file("missing-abi.json")
    assert_raise RuntimeError, ~r/file_error/, fn -> ContractABI.parse_abi_file!("missing-abi.json") end
  end

  test "native parser rejects oversized and excessively nested JSON" do
    assert {:error, {:parse_error, "payload_limit"}} =
             ContractABI.parse_abi_json(String.duplicate(" ", 16 * 1024 * 1024 + 1))

    nested = String.duplicate("[", 256) <> String.duplicate("]", 256)
    assert {:error, {:parse_error, _}} = ContractABI.parse_abi_json(nested)
  end

  test "empty ABI has no constructor or entries" do
    assert {:ok, %{constructor: nil, functions: [], events: [], errors: []}} = ContractABI.parse_abi_json("[]")
  end

  test "ABI file codegen registers its input for recompilation" do
    path = Path.join(:code.priv_dir(:onchain), "abis/chainlink_aggregator.json")
    input = Generator.resolve_contract_input([abi_file: path], nil)
    assert input.external_files == [Path.expand(path)]
    assert input.abi == ContractABI.parse_abi_file!(path)
  end
end
