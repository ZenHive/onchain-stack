defmodule Cartouche.RPCStateReadsTest do
  use ExUnit.Case, async: true

  alias Cartouche.RPC
  alias Cartouche.RPC.Proof
  alias Cartouche.RPC.Proof.StorageProof

  @address "0x6b175474e89094c44da98b954eedeac495271d0f"
  @key "0x" <> String.duplicate("0", 63) <> "1"
  @value 0xC989643A2D611A5D119644B
  @moduletag :capture_log
  @fixtures Path.expand("fixtures/state_reads", __DIR__)

  test "storage returns exactly 32 bytes and normalizes address, slot and block" do
    result = fixture("alchemy_eth_getStorageAt_historical")["result"]

    assert {:ok, <<@value::256>>} =
             RPC.eth_get_storage_at(String.replace(@address, "6b", "6B"), "0x0A", opts(result, block: 18_000_000))

    assert_request("eth_getStorageAt", [@address, "0x0a", "0x112a880"])

    assert {:ok, <<@value::256>>} = RPC.eth_get_storage_at(@address, @key, opts(result))
    assert_request("eth_getStorageAt", [@address, @key, "latest"])
  end

  test "storage rejects empty, oversized and nonhex slots and malformed words" do
    for slot <- ["0x", "0x" <> String.duplicate("0", 65), "0xgg", -1] do
      assert {:error, {:invalid_slot, ^slot}} = RPC.eth_get_storage_at(@address, slot)
    end

    for result <- ["0x1", "0x" <> String.duplicate("00", 33), nil] do
      assert {:error, message} = RPC.eth_get_storage_at(@address, "0x0", opts(result))
      assert message =~ "eth_getStorageAt"
    end
  end

  test "proof decodes the recorded EIP-1186 response and preserves key order" do
    result = fixture("alchemy_eth_getProof_historical")["result"]
    key2 = "0x" <> String.duplicate("AB", 32)
    assert {:ok, %Proof{} = proof} = RPC.eth_get_proof(@address, [key2, @key], opts(result, block: "safe"))
    assert_request("eth_getProof", [@address, [String.downcase(key2), @key], "safe"])
    assert proof.address == Cartouche.Hex.decode_address!(@address)
    assert proof.balance == 0
    assert proof.nonce == 1
    assert proof.code_hash == Cartouche.Hex.decode_word!(result["codeHash"])
    assert proof.storage_hash == Cartouche.Hex.decode_word!(result["storageHash"])
    assert proof.account_proof == Enum.map(result["accountProof"], &Cartouche.Hex.decode_hex!/1)
    assert [%StorageProof{key: 1, value: @value, proof: nodes}] = proof.storage_proof
    assert nodes == Enum.map(hd(result["storageProof"])["proof"], &Cartouche.Hex.decode_hex!/1)
  end

  test "proof keys of 1..64 hex digits are left-padded to 32 bytes; others are rejected" do
    result = fixture("alchemy_eth_getProof_before_deployment")["result"]

    assert {:ok, %Proof{}} = RPC.eth_get_proof(@address, ["0x1", "0xAB"], opts(result))
    assert_request("eth_getProof", [@address, [@key, "0x" <> String.duplicate("0", 62) <> "ab"], "latest"])

    for key <- ["0x", "0x" <> String.duplicate("0", 65), "0xgg", "1", 1] do
      assert {:error, {:invalid_storage_key, ^key}} = RPC.eth_get_proof(@address, [@key, key])
    end

    assert {:error, {:invalid_storage_keys, "0x1"}} = RPC.eth_get_proof(@address, "0x1")
  end

  test "account-only and non-existent storage proofs retain empty arrays" do
    result = fixture("alchemy_eth_getProof_before_deployment")["result"]

    assert {:ok, %Proof{nonce: 0, storage_proof: [%StorageProof{key: 1, value: 0, proof: []}]}} =
             RPC.eth_get_proof(@address, [@key], opts(result))

    assert {:ok, %Proof{storage_proof: []}} =
             RPC.eth_get_proof(@address, [], opts(Map.put(result, "storageProof", [])))

    assert_request("eth_getProof", [@address, [@key], "latest"])
    assert_request("eth_getProof", [@address, [], "latest"])
  end

  test "missing proof fields and malformed nested values fail instead of inventing a partial proof" do
    result = fixture("alchemy_eth_getProof_historical")["result"]
    bad_entry = put_in(result, ["storageProof", Access.at(0), "value"], "broken")
    short_hash = Map.put(result, "codeHash", "0x00")

    for malformed <- [Map.delete(result, "accountProof"), Map.delete(result, "storageProof"), bad_entry, short_hash] do
      assert {:error, message} = RPC.eth_get_proof(@address, [@key], opts(malformed))
      assert message =~ "eth_getProof"
    end
  end

  test "real node refusals survive the shared transport without decoding" do
    for {method, call, expected} <- [
          {"eth_getStorageAt", &RPC.eth_get_storage_at(@address, "0x1", &1),
           %{code: -32_001, message: "block not found: 0xffffffffffffffff"}},
          {"eth_getProof", &RPC.eth_get_proof(@address, [@key], &1),
           %{code: -32_602, message: "invalid argument 2: blocknumber too high"}}
        ] do
      response = fixture("alchemy_#{method}_future")
      assert {:error, ^expected} = call.(response_opts(response, block: "0xffffffffffffffff"))
    end
  end

  defp fixture(name),
    do: @fixtures |> Path.join(name <> ".json") |> File.read!() |> Jason.decode!() |> Map.fetch!("response")

  defp opts(result, extra \\ []), do: response_opts(%{"result" => result}, extra)

  defp response_opts(response, extra) do
    pid = self()

    plug = fn conn ->
      request = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()
      send(pid, {:request, request})
      Req.Test.json(conn, Map.merge(response, %{"jsonrpc" => "2.0", "id" => request["id"]}))
    end

    Keyword.merge([rpc_url: "http://stub.invalid", req_options: [plug: plug]], extra)
  end

  defp assert_request(method, params) do
    assert_receive {:request, %{"method" => ^method, "params" => ^params}}
  end
end
