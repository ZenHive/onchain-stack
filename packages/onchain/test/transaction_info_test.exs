defmodule Cartouche.Transaction.InfoTest do
  use ExUnit.Case, async: true

  alias Cartouche.Hex
  alias Cartouche.Transaction.Info
  alias Cartouche.Transaction.V1
  alias Cartouche.Transaction.V2
  alias Cartouche.Transaction.V3
  alias Cartouche.Transaction.V4
  alias Cartouche.Transaction.V_2930

  @hash "0x" <> String.duplicate("ab", 32)
  @from "0x" <> String.duplicate("11", 20)
  @block_hash "0x" <> String.duplicate("cd", 32)
  @weth "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
  @storage_key "0x0000000000000000000000000000000000000000000000000000000000000001"
  @blob_hash "0x0100000000000000000000000000000000000000000000000000000000000000"

  test "decodes a legacy transaction, including v, and keeps inclusion metadata" do
    assert {:ok, info} = Info.decode(with_inclusion(legacy_body()))

    assert_included(info)
    assert %V1{} = info.transaction
    assert info.transaction.nonce == 1
    assert info.transaction.gas_price == 0x174876E800
    assert info.transaction.gas_limit == 0x186A0
    assert info.transaction.to == Hex.decode_address!("0x0000000000000000000000000000000000000001")
    assert info.transaction.value == 2
    assert info.transaction.data == <<1, 2, 3>>
    assert info.transaction.v == 0x1C
    assert info.transaction.r == 1
    assert info.transaction.s == 2
  end

  test "decodes an EIP-2930 transaction from v when yParity is absent" do
    body = %{
      "type" => "0x1",
      "chainId" => "0x1",
      "nonce" => "0x0",
      "gasPrice" => "0x12a522a31",
      "gas" => "0x186a0",
      "to" => "0xc02953f316c5c18808e2d3961424f952788d69f5",
      "value" => "0x470d07cc2d2760",
      "input" => "0x",
      "accessList" => [
        %{"address" => @weth, "storageKeys" => [@storage_key]}
      ],
      "v" => "0x0",
      "r" => "0x1",
      "s" => "0x2"
    }

    assert {:ok, info} = Info.decode(with_inclusion(body))
    assert_included(info)
    assert %V_2930{} = info.transaction
    assert info.transaction.chain_id == 1
    assert info.transaction.signature_y_parity == false
    assert info.transaction.access_list == [{Hex.decode_address!(@weth), [Hex.decode_word!(@storage_key)]}]
  end

  test "decodes an EIP-1559 transaction, including yParity and accessList" do
    body = %{
      "type" => "0x2",
      "chainId" => "0x1",
      "nonce" => "0x1",
      "maxPriorityFeePerGas" => "0x0",
      "maxFeePerGas" => "0x174876e800",
      "gas" => "0x186a0",
      "to" => "0x0000000000000000000000000000000000000002",
      "value" => "0x2",
      "input" => "0x010203",
      "accessList" => [
        %{"address" => @weth, "storageKeys" => []}
      ],
      "yParity" => "0x1",
      "r" => "0x1",
      "s" => "0x2"
    }

    assert {:ok, info} = Info.decode(with_inclusion(body))
    assert_included(info)
    assert %V2{} = info.transaction
    assert info.transaction.chain_id == 1
    assert info.transaction.nonce == 1
    assert info.transaction.max_priority_fee_per_gas == 0
    assert info.transaction.max_fee_per_gas == 0x174876E800
    assert info.transaction.signature_y_parity == true
    assert info.transaction.signature_r == <<1::256>>
    assert info.transaction.access_list == [{Hex.decode_address!(@weth), []}]
  end

  test "decodes an EIP-4844 transaction, including blobVersionedHashes" do
    body = %{
      "type" => "0x3",
      "chainId" => "0x1",
      "nonce" => "0x1",
      "maxPriorityFeePerGas" => "0x3b9aca00",
      "maxFeePerGas" => "0x174876e800",
      "gas" => "0x186a0",
      "to" => "0x0000000000000000000000000000000000000003",
      "value" => "0x2",
      "input" => "0x010203",
      "accessList" => [],
      "maxFeePerBlobGas" => "0x1",
      "blobVersionedHashes" => [@blob_hash],
      "yParity" => "0x0",
      "r" => "0x1",
      "s" => "0x2"
    }

    assert {:ok, info} = Info.decode(with_inclusion(body))
    assert_included(info)
    assert %V3{} = info.transaction
    assert info.transaction.max_fee_per_blob_gas == 1
    assert info.transaction.blob_versioned_hashes == [Hex.decode_word!(@blob_hash)]
    assert info.transaction.signature_y_parity == false
  end

  test "decodes an EIP-7702 transaction, including authorizationList" do
    body = %{
      "type" => "0x4",
      "chainId" => "0x1",
      "nonce" => "0x1",
      "maxPriorityFeePerGas" => "0x3b9aca00",
      "maxFeePerGas" => "0x174876e800",
      "gas" => "0x186a0",
      "to" => "0x0000000000000000000000000000000000000004",
      "value" => "0x2",
      "input" => "0x010203",
      "accessList" => [],
      "authorizationList" => [
        %{
          "chainId" => "0x1",
          "address" => "0x000000000000000000000000000000000000beef",
          "nonce" => "0x7",
          "yParity" => "0x0",
          "r" => "0x1",
          "s" => "0x2"
        }
      ],
      "yParity" => "0x1",
      "r" => "0x1",
      "s" => "0x2"
    }

    assert {:ok, info} = Info.decode(with_inclusion(body))
    assert_included(info)
    assert %V4{} = info.transaction

    assert info.transaction.authorization_list == [
             {1, Hex.decode_address!("0x000000000000000000000000000000000000beef"), 7, false, <<1::256>>, <<2::256>>}
           ]

    assert info.transaction.signature_y_parity == true
  end

  test "a pending transaction object decodes with null inclusion fields nil" do
    # execution-apis v1.0.0-beta.7, "Pending transaction information":
    # blockHash, blockNumber, blockTimestamp, and transactionIndex are null.
    params =
      legacy_body()
      |> with_inclusion()
      |> Map.merge(%{
        "blockHash" => nil,
        "blockNumber" => nil,
        "blockTimestamp" => nil,
        "transactionIndex" => nil
      })

    assert {:ok, info} = Info.decode(params)
    assert info.hash == Hex.decode_word!(@hash)
    assert info.from == Hex.decode_address!(@from)
    assert info.block_hash == nil
    assert info.block_number == nil
    assert info.block_timestamp == nil
    assert info.transaction_index == nil
    assert info.transaction.nonce == 1

    absent = Map.drop(params, ["blockHash", "blockNumber", "blockTimestamp", "transactionIndex"])
    assert {:ok, dropped} = Info.decode(absent)
    assert dropped.block_hash == nil
    assert dropped.block_number == nil
    assert dropped.block_timestamp == nil
    assert dropped.transaction_index == nil
  end

  test "a missing required field returns an error and does not raise" do
    params = legacy_body() |> with_inclusion() |> Map.delete("nonce")
    assert {:error, {:missing_field, "nonce"}} = Info.decode(params)
  end

  test "an unknown type returns an error and does not raise" do
    assert {:error, {:unknown_transaction_type, "0x99"}} =
             Info.decode(with_inclusion(legacy_body(), %{"type" => "0x99"}))

    assert {:error, {:unknown_transaction_type, "0x76"}} =
             Info.decode(with_inclusion(legacy_body(), %{"type" => "0x76"}))
  end

  test "malformed field hex returns an error and does not raise" do
    assert {:error, {:invalid_transaction, message}} =
             Info.decode(with_inclusion(legacy_body(), %{"nonce" => "0xzz"}))

    assert message =~ "invalid hex"
  end

  test "a non-object result is an error" do
    assert {:error, {:unexpected_transaction, nil}} = Info.decode(nil)
  end

  defp assert_included(%Info{} = info) do
    assert info.hash == Hex.decode_word!(@hash)
    assert info.from == Hex.decode_address!(@from)
    assert info.block_hash == Hex.decode_word!(@block_hash)
    assert info.block_number == 16
    assert info.block_timestamp == 0x20
    assert info.transaction_index == 2
  end

  defp with_inclusion(body, overrides \\ %{}) do
    Map.merge(
      %{
        "hash" => @hash,
        "from" => @from,
        "blockHash" => @block_hash,
        "blockNumber" => "0x10",
        "blockTimestamp" => "0x20",
        "transactionIndex" => "0x2"
      },
      Map.merge(body, overrides)
    )
  end

  defp legacy_body do
    %{
      "type" => "0x0",
      "nonce" => "0x1",
      "gasPrice" => "0x174876e800",
      "gas" => "0x186a0",
      "to" => "0x0000000000000000000000000000000000000001",
      "value" => "0x2",
      "input" => "0x010203",
      "v" => "0x1c",
      "r" => "0x1",
      "s" => "0x2"
    }
  end
end
