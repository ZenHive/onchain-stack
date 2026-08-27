defmodule Cartouche.BlockTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.Block
  alias Cartouche.Block.Withdrawal
  alias Cartouche.Hex.InvalidHex
  alias Cartouche.Transaction.V1
  alias Cartouche.Transaction.V2
  alias Cartouche.Transaction.V3
  alias Cartouche.Transaction.V4
  alias Cartouche.Transaction.V_2930

  doctest Block
  doctest Withdrawal

  # Minimal pre-London block fixture — strips the moduledoc doctest's
  # logsBloom/extraData/etc. down to the smallest set deserialize/1 will
  # tolerate. Pre-London blocks omit baseFeePerGas, withdrawals*, and the
  # Cancun fields entirely on the wire.
  defp pre_london_params(extra \\ %{}) do
    Map.merge(
      %{
        "number" => "0x989680",
        "hash" => "0xaa20f7bde5be60603f11a45fc4923aab7552be775403fc00c2e6b805e6297dbe",
        "parentHash" => "0x966bf6849da92ff2a0e3db9a371f5b9f07dd6001e2770a4269a5c134f1bf9c4c",
        "nonce" => "0x0000000000000000",
        "sha3Uncles" => "0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
        "logsBloom" => "0x" <> String.duplicate("00", 256),
        "transactionsRoot" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
        "stateRoot" => "0xddc8b0234c2e0cad087c8b389aa7ef01f7d79b2570bccb77ce48648aa61c904d",
        "receiptsRoot" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
        "miner" => "0xea674fdde714fd979de3edf0f56aa9716b898ec8",
        "difficulty" => "0x4ea3f27bc",
        "totalDifficulty" => "0x78ed983323d",
        "extraData" => "0x",
        "size" => "0x220",
        "gasLimit" => "0x98705c",
        "gasUsed" => "0x9824b3",
        "timestamp" => "0x5eb01705",
        "transactions" => [],
        "uncles" => []
      },
      extra
    )
  end

  describe "deserialize/1 — fork-tier optional fields (Tasks 63 + 64 + 65)" do
    test "pre-London block: every fork-tier optional field is nil" do
      b = Block.deserialize(pre_london_params())

      # All seven nullable fields default to nil when the wire payload omits them.
      assert b.base_fee_per_gas == nil
      assert b.withdrawals_root == nil
      assert b.withdrawals == nil
      assert b.parent_beacon_block_root == nil
      assert b.blob_gas_used == nil
      assert b.excess_blob_gas == nil
      # mixHash is the only field present pre-London — but the minimal fixture omits it.
      assert b.mix_hash == nil
    end

    test "post-London block: base_fee_per_gas decodes; Shanghai/Cancun fields nil (Task 63)" do
      b =
        Block.deserialize(
          pre_london_params(%{
            "mixHash" => "0x4fffe9ae21f1c9e15207b1f472d5bbdd68c9595d461666602f2be20daf5e7843",
            "baseFeePerGas" => "0x6f4f8d96"
          })
        )

      assert b.base_fee_per_gas == 0x6F4F8D96
      assert is_integer(b.base_fee_per_gas)
      assert byte_size(b.mix_hash) == 32
      # Shanghai + Cancun fields still nil at this fork tier.
      assert b.withdrawals_root == nil
      assert b.withdrawals == nil
      assert b.parent_beacon_block_root == nil
      assert b.blob_gas_used == nil
      assert b.excess_blob_gas == nil
    end

    test "post-Shanghai block: withdrawals + withdrawals_root populated (Task 64)" do
      b =
        Block.deserialize(
          pre_london_params(%{
            "baseFeePerGas" => "0x6f4f8d96",
            "withdrawalsRoot" => "0x9d56fa5a08e21cd3ff7f8b6f5b6cb6f5b6cb6f5b6cb6f5b6cb6f5b6cb6f5b6cb",
            "withdrawals" => [
              %{
                "index" => "0x4d8f7d",
                "validatorIndex" => "0xc8a5f",
                "address" => "0x1f9090aae28b8a3dceadf281b0f12828e676c326",
                "amount" => "0x111c8c2"
              },
              %{
                "index" => "0x4d8f7e",
                "validatorIndex" => "0xc8a60",
                "address" => "0x1f9090aae28b8a3dceadf281b0f12828e676c326",
                "amount" => "0x111c8c3"
              }
            ]
          })
        )

      assert byte_size(b.withdrawals_root) == 32
      assert is_list(b.withdrawals)
      assert [_, _] = b.withdrawals
      assert [%Withdrawal{index: 0x4D8F7D} | _] = b.withdrawals
      # Cancun fields still nil at the Shanghai tier.
      assert b.parent_beacon_block_root == nil
      assert b.blob_gas_used == nil
    end

    test "empty withdrawals list deserializes to [] (not nil)" do
      b =
        Block.deserialize(
          pre_london_params(%{
            "withdrawalsRoot" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
            "withdrawals" => []
          })
        )

      # The boundary between "absent on the wire" (→ nil) and "present but empty"
      # (→ []) — consumers depend on this distinction to detect Shanghai+ blocks
      # with no validator withdrawals in this slot.
      assert b.withdrawals == []
      assert byte_size(b.withdrawals_root) == 32
    end

    test "post-Cancun block: all four Cancun fields populated (Task 65)" do
      b =
        Block.deserialize(
          pre_london_params(%{
            "mixHash" => "0x4fffe9ae21f1c9e15207b1f472d5bbdd68c9595d461666602f2be20daf5e7843",
            "baseFeePerGas" => "0x6f4f8d96",
            "withdrawalsRoot" => "0x9d56fa5a08e21cd3ff7f8b6f5b6cb6f5b6cb6f5b6cb6f5b6cb6f5b6cb6f5b6cb",
            "withdrawals" => [],
            "parentBeaconBlockRoot" => "0xb390d63aac03bbef75de888d16bd56b91c9291c2a7e38d36ac24731351522bd1",
            "blobGasUsed" => "0x80000",
            "excessBlobGas" => "0x4a0000"
          })
        )

      assert byte_size(b.parent_beacon_block_root) == 32
      assert b.blob_gas_used == 0x80000
      assert b.excess_blob_gas == 0x4A0000
      assert is_integer(b.blob_gas_used)
      assert is_integer(b.excess_blob_gas)
      assert byte_size(b.mix_hash) == 32
    end

    test "mix_hash decodes when present, regardless of fork tier" do
      mix_hash_hex =
        "0x4fffe9ae21f1c9e15207b1f472d5bbdd68c9595d461666602f2be20daf5e7843"

      b = Block.deserialize(pre_london_params(%{"mixHash" => mix_hash_hex}))

      assert b.mix_hash ==
               ~h[0x4fffe9ae21f1c9e15207b1f472d5bbdd68c9595d461666602f2be20daf5e7843]

      assert byte_size(b.mix_hash) == 32
    end
  end

  describe "deserialize/1 — transactions field shape (Task 66)" do
    # Minimal full V1 (legacy / type 0) transaction JSON shape — mirrors what
    # `eth_getBlockBy*` returns when `:include_transaction_details, true`.
    defp tx_v1_json(extra \\ %{}) do
      Map.merge(
        %{
          "type" => "0x0",
          "nonce" => "0x1",
          "gasPrice" => "0x174876e800",
          "gas" => "0x186a0",
          "to" => "0x0000000000000000000000000000000000000001",
          "value" => "0x2",
          "input" => "0x010203",
          "v" => "0x25",
          "r" => "0x1",
          "s" => "0x2"
        },
        extra
      )
    end

    defp tx_v2_json(extra \\ %{}) do
      Map.merge(
        %{
          "type" => "0x2",
          "chainId" => "0x1",
          "nonce" => "0x1",
          "maxPriorityFeePerGas" => "0x3b9aca00",
          "maxFeePerGas" => "0x174876e800",
          "gas" => "0x186a0",
          "to" => "0x0000000000000000000000000000000000000002",
          "value" => "0x2",
          "input" => "0x010203",
          "accessList" => [],
          "yParity" => "0x1",
          "r" => "0x1",
          "s" => "0x2"
        },
        extra
      )
    end

    defp tx_v2930_json(extra \\ %{}) do
      Map.merge(
        %{
          "type" => "0x1",
          "chainId" => "0x1",
          "nonce" => "0x0",
          "gasPrice" => "0x12a522a31",
          "gas" => "0x186a0",
          "to" => "0xc02953f316c5c18808e2d3961424f952788d69f5",
          "value" => "0x470d07cc2d2760",
          "input" => "0x",
          "accessList" => [],
          "yParity" => "0x0",
          "r" => "0xdb55cfd6a6b449e82e05bf465b64d679b7e6030dacab412b7867d83cacabe07d",
          "s" => "0x7e1452c5ba57f8ab8a34aa6405e44bd6536d6fd1ff0b44d3360f05832d824c39"
        },
        extra
      )
    end

    defp tx_v3_json(extra \\ %{}) do
      Map.merge(
        %{
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
          "blobVersionedHashes" => [
            "0x0100000000000000000000000000000000000000000000000000000000000000"
          ],
          "yParity" => "0x0",
          "r" => "0x1",
          "s" => "0x2"
        },
        extra
      )
    end

    defp tx_v4_json(extra \\ %{}) do
      Map.merge(
        %{
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
        },
        extra
      )
    end

    test "hash-only response (`:include_transaction_details` false / default) — preserves wire String.t() shape" do
      hashes = [
        "0x4a1e3e3a2aa4aa79a777d0ae3e2c3a6de158226134123f6c14334964c6ec70cf",
        "0x16e199673891df518e25db2ef5320155da82a3dd71a677e7d84363251885d133"
      ]

      b = Block.deserialize(pre_london_params(%{"transactions" => hashes}))

      # Hash-only path: each element preserved as-is (String.t()), not
      # decoded into <<_::256>>. This matches the @type t/0 union and
      # keeps the wire shape addressable for direct equality comparisons
      # against API responses.
      assert b.transactions == hashes
      assert Enum.all?(b.transactions, &is_binary/1)
      # Sanity-check: each hash is a 0x-prefixed hex string of the expected width.
      assert Enum.all?(b.transactions, fn h -> String.starts_with?(h, "0x") and String.length(h) == 66 end)
    end

    test "empty transactions list — distinguishes [] from nil at the wire boundary" do
      b = Block.deserialize(pre_london_params(%{"transactions" => []}))
      assert b.transactions == []
    end

    test "full-detail V1 response — decodes legacy transaction shape" do
      b = Block.deserialize(pre_london_params(%{"transactions" => [tx_v1_json()]}))

      assert [%V1{} = tx] = b.transactions
      assert tx.nonce == 1
      assert tx.gas_price == 100_000_000_000
      assert tx.gas_limit == 100_000
      assert tx.to == ~h[0x0000000000000000000000000000000000000001]
      assert tx.value == 2
      assert tx.data == <<1, 2, 3>>
      assert tx.v == 0x25
      assert tx.r == 1
      assert tx.s == 2
    end

    test "full-detail V1 with absent `type` field — defaults to V1 (pre-Berlin nodes)" do
      json = Map.delete(tx_v1_json(), "type")
      b = Block.deserialize(pre_london_params(%{"transactions" => [json]}))

      # Some older / non-canonical node responses omit `type` on legacy txs.
      # The dispatch must treat absent `type` as V1, matching the EIP-2718
      # default-to-legacy semantics.
      assert [%V1{}] = b.transactions
    end

    test "full-detail V1 contract creation — `to: nil` preserved" do
      json = tx_v1_json(%{"to" => nil, "input" => "0x60606040"})
      b = Block.deserialize(pre_london_params(%{"transactions" => [json]}))

      # Contract creations are common on mainnet; the JSON `to: null` must
      # round-trip as `to: nil` rather than crashing the address decoder.
      # The strict RLP `decode/1` path enforces a 20-byte address, but the
      # JSON path mirrors the wire shape per the type widening on V1.t/0.
      assert [%V1{to: nil, data: <<0x60, 0x60, 0x60, 0x40>>}] = b.transactions
    end

    test "full-detail V2 response — decodes EIP-1559 transaction shape" do
      b = Block.deserialize(pre_london_params(%{"transactions" => [tx_v2_json()]}))

      assert [%V2{} = tx] = b.transactions
      assert tx.chain_id == 1
      assert tx.max_priority_fee_per_gas == 1_000_000_000
      assert tx.max_fee_per_gas == 100_000_000_000
      assert tx.destination == ~h[0x0000000000000000000000000000000000000002]
      assert tx.access_list == []
      assert tx.signature_y_parity == true
      # `r`/`s` are normalised to 32-byte words even when the wire value
      # ships with leading zeros stripped (here: "0x1"/"0x2").
      assert tx.signature_r == <<1::256>>
      assert tx.signature_s == <<2::256>>
    end

    test "full-detail V2 with `v` instead of `yParity` (legacy backwards-compat shape)" do
      json =
        tx_v2_json()
        |> Map.delete("yParity")
        |> Map.put("v", "0x1")

      b = Block.deserialize(pre_london_params(%{"transactions" => [json]}))

      # Per the execution-apis spec, `yParity` is the canonical field on
      # signed typed transactions; `v` is provided as an optional
      # backwards-compat shadow holding the y-parity bit directly. We
      # accept either to be robust to nodes that haven't migrated yet.
      assert [%V2{signature_y_parity: true}] = b.transactions
    end

    test "full-detail V2 contract creation — `destination: nil` preserved" do
      json = tx_v2_json(%{"to" => nil})
      b = Block.deserialize(pre_london_params(%{"transactions" => [json]}))

      assert [%V2{destination: nil}] = b.transactions
    end

    test "full-detail V2 with non-empty access list" do
      json =
        tx_v2_json(%{
          "accessList" => [
            %{
              "address" => "0x0000000000000000000000000000000000000005",
              "storageKeys" => [
                "0x0000000000000000000000000000000000000000000000000000000000000016"
              ]
            }
          ]
        })

      b = Block.deserialize(pre_london_params(%{"transactions" => [json]}))

      assert [%V2{access_list: [{address, [storage_key]}]}] = b.transactions
      assert address == <<5::160>>
      assert storage_key == <<22::256>>
    end

    test "full-detail V_2930 response — decodes EIP-2930 access-list transaction shape" do
      b = Block.deserialize(pre_london_params(%{"transactions" => [tx_v2930_json()]}))

      assert [tx] = b.transactions
      assert tx.__struct__ == V_2930
      assert tx.chain_id == 1
      assert tx.gas_price == 5_004_995_121
      assert tx.gas_limit == 100_000
      assert tx.destination == ~h[0xc02953f316c5c18808e2d3961424f952788d69f5]
      assert tx.amount == 19_999_050_487_900_000
      assert tx.data == <<>>
      assert tx.access_list == []
      assert tx.signature_y_parity == false
      assert tx.signature_r == ~h[0xdb55cfd6a6b449e82e05bf465b64d679b7e6030dacab412b7867d83cacabe07d]
      assert tx.signature_s == ~h[0x7e1452c5ba57f8ab8a34aa6405e44bd6536d6fd1ff0b44d3360f05832d824c39]
    end

    test "full-detail V3 response — decodes EIP-4844 blob transaction shape" do
      b = Block.deserialize(pre_london_params(%{"transactions" => [tx_v3_json()]}))

      assert [%V3{} = tx] = b.transactions
      assert tx.chain_id == 1
      assert tx.max_fee_per_blob_gas == 1

      assert tx.blob_versioned_hashes == [
               ~h[0x0100000000000000000000000000000000000000000000000000000000000000]
             ]

      assert tx.signature_y_parity == false
    end

    test "full-detail V4 response — decodes EIP-7702 set-code transaction shape" do
      b = Block.deserialize(pre_london_params(%{"transactions" => [tx_v4_json()]}))

      assert [%V4{} = tx] = b.transactions
      assert tx.chain_id == 1
      # Authorization list is decoded into the {chain_id, address, nonce,
      # y_parity, r, s} tuple shape used elsewhere in V4 (matches
      # `Cartouche.Transaction.V4.authorization()` type).
      assert tx.authorization_list == [
               {1, ~h[0x000000000000000000000000000000000000beef], 7, false, <<1::256>>, <<2::256>>}
             ]
    end

    test "mixed-shape response — defensive per-element dispatch (V1 + V2 in same list)" do
      # Per the issue: "per-element dispatch is robust to node implementations
      # that mix shapes (some Erigon configs)." Verify a heterogeneous list
      # decodes per element rather than per block.
      b =
        Block.deserialize(
          pre_london_params(%{
            "transactions" => [
              tx_v1_json(),
              tx_v2_json(),
              "0x4a1e3e3a2aa4aa79a777d0ae3e2c3a6de158226134123f6c14334964c6ec70cf"
            ]
          })
        )

      assert [%V1{}, %V2{}, hash] = b.transactions
      assert is_binary(hash)
      assert hash == "0x4a1e3e3a2aa4aa79a777d0ae3e2c3a6de158226134123f6c14334964c6ec70cf"
    end

    test "V2.from_json/1 with `accessList` omitted — defensive nil → []" do
      # `accessList` is required on the wire for type 2/3/4 per the
      # execution-apis spec, but `from_json/1` is publicly callable and
      # tolerates omission to keep the JSON-decoder defensively
      # symmetric with the optional-on-wire fields elsewhere.
      json = Map.delete(tx_v2_json(), "accessList")
      tx = V2.from_json(json)
      assert tx.access_list == []
    end

    test "V3.from_json/1 with `blobVersionedHashes` omitted — defensive nil → []" do
      json = Map.delete(tx_v3_json(), "blobVersionedHashes")
      tx = V3.from_json(json)
      assert tx.blob_versioned_hashes == []
    end

    test "V4.from_json/1 with `authorizationList` omitted — defensive nil → []" do
      json = Map.delete(tx_v4_json(), "authorizationList")
      tx = V4.from_json(json)
      assert tx.authorization_list == []
    end

    test "y_parity hex value other than 0/1 raises Cartouche.Hex.InvalidHex" do
      # Defensive: the spec says yParity ∈ {0, 1}; a malformed node
      # response with `"yParity": "0x2"` should raise rather than
      # silently truncate.
      json = Map.put(tx_v2_json(), "yParity", "0x2")

      assert_raise InvalidHex, ~r/invalid y_parity/, fn ->
        Block.deserialize(pre_london_params(%{"transactions" => [json]}))
      end
    end

    test "signed envelope decoders reject a corrupt signature" do
      signed_transactions = [
        {V1, tx_v1_json(%{"r" => "not-hex"})},
        {V2, tx_v2_json(%{"r" => "not-hex"})},
        {V3, tx_v3_json(%{"r" => "not-hex"})},
        {V4, tx_v4_json(%{"r" => "not-hex"})}
      ]

      Enum.each(signed_transactions, fn {transaction_module, params} ->
        assert_raise InvalidHex, fn -> transaction_module.from_json(params) end
      end)
    end

    test "full-detail V_2930 contract creation — `destination: nil` preserved" do
      json = tx_v2930_json(%{"to" => nil})
      b = Block.deserialize(pre_london_params(%{"transactions" => [json]}))

      assert [tx] = b.transactions
      assert tx.__struct__ == V_2930
      assert tx.destination == nil
    end

    test "truly-unknown envelope type raises the generic message" do
      # Distinct from supported typed envelopes (0x0–0x4): a type byte we
      # don't recognize at all should raise the generic message.
      json = %{"type" => "0x99", "nonce" => "0x0"}

      assert_raise ArgumentError, ~r/unsupported transaction envelope type/, fn ->
        Block.deserialize(pre_london_params(%{"transactions" => [json]}))
      end
    end

    test "hash-only path validates hex — non-hex string raises Cartouche.Hex.InvalidHex" do
      # Cartouche.Block.transactions hash-only branch returns the wire
      # String.t() unchanged but must not let a malformed hash leak
      # through — otherwise downstream code that expects 0x-prefixed
      # 32-byte hex breaks far from the failure point.
      assert_raise InvalidHex, fn ->
        Block.deserialize(pre_london_params(%{"transactions" => ["not-a-hash"]}))
      end
    end
  end

  describe "Cartouche.Block.Withdrawal.deserialize/1 (Task 64)" do
    test "happy path — single withdrawal" do
      w =
        Withdrawal.deserialize(%{
          "index" => "0x4d8f7d",
          "validatorIndex" => "0xc8a5f",
          "address" => "0x1f9090aae28b8a3dceadf281b0f12828e676c326",
          "amount" => "0x111c8c2"
        })

      assert w.index == 0x4D8F7D
      assert w.validator_index == 0xC8A5F
      assert w.address == ~h[0x1f9090aae28b8a3dceadf281b0f12828e676c326]
      assert w.amount == 0x111C8C2
      assert byte_size(w.address) == 20
    end

    test "zero-amount boundary" do
      w =
        Withdrawal.deserialize(%{
          "index" => "0x0",
          "validatorIndex" => "0x0",
          "address" => "0x0000000000000000000000000000000000000000",
          "amount" => "0x0"
        })

      assert w.index == 0
      assert w.validator_index == 0
      assert w.amount == 0
      assert byte_size(w.address) == 20
    end

    test "uint64 max amount round-trips as Elixir integer" do
      # Validator pool amounts are uint64-bounded gwei. Exercise the upper
      # boundary to confirm the integer decoder handles full-width values.
      max_uint64 = 0xFFFF_FFFF_FFFF_FFFF

      w =
        Withdrawal.deserialize(%{
          "index" => "0x0",
          "validatorIndex" => "0x0",
          "address" => "0x0000000000000000000000000000000000000000",
          "amount" => "0x" <> Integer.to_string(max_uint64, 16)
        })

      assert w.amount == max_uint64
    end
  end
end
