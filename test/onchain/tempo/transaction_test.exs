defmodule Onchain.Tempo.TransactionTest do
  use ExUnit.Case, async: true

  import Onchain.Tempo.TestHelpers

  alias Cartouche.Signer.Curvy
  alias Onchain.Tempo.Transaction
  alias Onchain.Tempo.Transaction.Builder

  # Test addresses (Hardhat default accounts — testnet only, no security concern)
  @recipient_hex "0x70997970c51812dc3a010c7d01b50e0d17dc79c8"
  @token_hex "0x20c0000000000000000000000000000000000000"
  @other_token_hex "0x1111111111111111111111111111111111111111"
  @moderato_chain_id 42_431

  # --- deserialize/1 tests ---

  describe "deserialize/1" do
    test "deserializes a valid transfer transaction" do
      calldata = transfer_calldata(@recipient_hex, 1_000_000)
      call = build_call(@token_hex, calldata)
      hex = build_tempo_tx(calls: [call])

      assert {:ok, %Transaction{} = tx} = Transaction.deserialize(hex)
      assert tx.chain_id == @moderato_chain_id
      assert tx.raw == hex

      assert [parsed_call] = tx.calls
      assert byte_size(parsed_call.to) == 20
      assert parsed_call.input == calldata
    end

    test "deserializes a transferWithMemo transaction" do
      memo = "0x" <> String.duplicate("ab", 32)
      calldata = transfer_with_memo_calldata(@recipient_hex, 500_000, memo)
      call = build_call(@token_hex, calldata)
      hex = build_tempo_tx(calls: [call])

      assert {:ok, %Transaction{} = tx} = Transaction.deserialize(hex)
      assert [parsed_call] = tx.calls
      assert byte_size(parsed_call.input) == 100
    end

    test "extracts correct chain_id" do
      call = build_call(@token_hex, transfer_calldata(@recipient_hex, 100))
      hex = build_tempo_tx(chain_id: 4217, calls: [call])

      assert {:ok, %Transaction{chain_id: 4217}} = Transaction.deserialize(hex)
    end

    test "handles multiple calls" do
      call1 = build_call(@token_hex, transfer_calldata(@recipient_hex, 100))
      call2 = build_call(@other_token_hex, transfer_calldata(@recipient_hex, 200))
      hex = build_tempo_tx(calls: [call1, call2])

      assert {:ok, %Transaction{calls: calls}} = Transaction.deserialize(hex)
      assert [_first, _second] = calls
    end

    test "rejects non-0x76 prefix" do
      body = ExRLP.encode([<<1>>, <<>>, <<>>, <<>>, [], [], <<>>, <<>>, <<>>])
      hex = "0x02" <> Base.encode16(body, case: :lower)

      assert {:error, msg} = Transaction.deserialize(hex)
      assert msg =~ "Not a Tempo transaction"
      assert msg =~ "0x2"
    end

    test "rejects invalid hex encoding" do
      assert {:error, "Invalid hex encoding"} = Transaction.deserialize("0x76zzzz")
    end

    test "rejects empty transaction data" do
      assert {:error, "Empty transaction data"} = Transaction.deserialize("0x")
    end

    test "rejects malformed RLP" do
      hex = "0x76" <> Base.encode16(<<0xFF, 0xFF, 0xFF>>, case: :lower)
      assert {:error, msg} = Transaction.deserialize(hex)
      assert msg =~ "Failed to RLP-decode"
    end

    test "rejects malformed call entries" do
      bad_call = [<<"garbage">>]

      body = [
        :binary.encode_unsigned(42_431),
        <<>>,
        <<>>,
        :binary.encode_unsigned(21_000),
        [bad_call],
        [],
        <<>>,
        <<>>,
        <<>>,
        <<>>,
        <<>>,
        <<>>,
        [],
        <<1::512>>
      ]

      raw = <<0x76>> <> ExRLP.encode(body)
      hex = "0x" <> Base.encode16(raw, case: :lower)

      assert {:error, msg} = Transaction.deserialize(hex)
      assert msg =~ "Malformed call at index 0"
    end

    test "rejects non-string input" do
      assert {:error, "Invalid input: expected a hex string"} = Transaction.deserialize(123)
    end

    test "deserializes hex without 0x prefix" do
      calldata = transfer_calldata(@recipient_hex, 1_000_000)
      call = build_call(@token_hex, calldata)
      hex = build_tempo_tx(calls: [call])

      "0x" <> bare = hex
      assert {:ok, %Transaction{chain_id: @moderato_chain_id}} = Transaction.deserialize(bare)
    end

    test "rejects transaction with non-binary chain_id" do
      body = [
        [<<1>>],
        <<>>,
        <<>>,
        :binary.encode_unsigned(21_000),
        [],
        [],
        <<>>,
        <<>>,
        <<>>,
        <<>>,
        <<>>,
        <<>>,
        [],
        <<1::512>>
      ]

      raw = <<0x76>> <> ExRLP.encode(body)
      hex = "0x" <> Base.encode16(raw, case: :lower)

      assert {:error, "Missing or invalid chain_id field"} = Transaction.deserialize(hex)
    end

    test "rejects transaction too short for calls field" do
      body = [
        :binary.encode_unsigned(42_431),
        <<>>,
        <<>>
      ]

      raw = <<0x76>> <> ExRLP.encode(body)
      hex = "0x" <> Base.encode16(raw, case: :lower)

      assert {:error, "Transaction too short: missing calls field"} = Transaction.deserialize(hex)
    end

    test "rejects empty calls list" do
      hex = build_tempo_tx(calls: [])
      assert {:error, "Calls list cannot be empty"} = Transaction.deserialize(hex)
    end

    test "handles call with two elements (to, value, no input)" do
      to = decode_address(@token_hex)
      value = :binary.encode_unsigned(100)

      body = [
        :binary.encode_unsigned(42_431),
        <<>>,
        <<>>,
        :binary.encode_unsigned(21_000),
        [[to, value]],
        [],
        <<>>,
        <<>>,
        <<>>,
        <<>>,
        <<>>,
        <<>>,
        [],
        <<1::512>>
      ]

      raw = <<0x76>> <> ExRLP.encode(body)
      hex = "0x" <> Base.encode16(raw, case: :lower)

      assert {:ok, %Transaction{calls: [call]}} = Transaction.deserialize(hex)
      assert call.value == 100
      assert call.input == <<>>
    end
  end

  # --- find_payment_call/3 tests ---

  describe "find_payment_call/3" do
    setup do
      calldata = transfer_calldata(@recipient_hex, 1_000_000)
      call = build_call(@token_hex, calldata)
      hex = build_tempo_tx(calls: [call])
      {:ok, tx} = Transaction.deserialize(hex)
      {:ok, tx: tx}
    end

    test "finds matching transfer call", %{tx: tx} do
      assert {:ok, match} =
               Transaction.find_payment_call(tx, @token_hex,
                 amount: "1000000",
                 recipient: @recipient_hex
               )

      assert match.amount == 1_000_000

      assert String.downcase(match.recipient) ==
               @recipient_hex
               |> strip_0x()
               |> String.downcase()
               |> then(&("0x" <> &1))
    end

    test "finds matching transferWithMemo call" do
      memo = "0x" <> String.duplicate("cd", 32)
      calldata = transfer_with_memo_calldata(@recipient_hex, 2_000_000, memo)
      call = build_call(@token_hex, calldata)
      hex = build_tempo_tx(calls: [call])
      {:ok, tx} = Transaction.deserialize(hex)

      assert {:ok, match} =
               Transaction.find_payment_call(tx, @token_hex,
                 amount: "2000000",
                 recipient: @recipient_hex,
                 memo: memo
               )

      assert match.amount == 2_000_000
      assert match.memo
    end

    test "accepts transferWithMemo when no memo required" do
      memo = "0x" <> String.duplicate("ee", 32)
      calldata = transfer_with_memo_calldata(@recipient_hex, 1_000_000, memo)
      call = build_call(@token_hex, calldata)
      hex = build_tempo_tx(calls: [call])
      {:ok, tx} = Transaction.deserialize(hex)

      assert {:ok, _match} =
               Transaction.find_payment_call(tx, @token_hex,
                 amount: "1000000",
                 recipient: @recipient_hex
               )
    end

    test "rejects when recipient doesn't match", %{tx: tx} do
      other_recipient = "0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc"

      assert {:error, msg} =
               Transaction.find_payment_call(tx, @token_hex,
                 amount: "1000000",
                 recipient: other_recipient
               )

      assert msg =~ "No matching transfer call"
    end

    test "rejects when amount doesn't match", %{tx: tx} do
      assert {:error, msg} =
               Transaction.find_payment_call(tx, @token_hex,
                 amount: "9999999",
                 recipient: @recipient_hex
               )

      assert msg =~ "No matching transfer call"
    end

    test "rejects when token address doesn't match", %{tx: tx} do
      assert {:error, msg} =
               Transaction.find_payment_call(tx, @other_token_hex,
                 amount: "1000000",
                 recipient: @recipient_hex
               )

      assert msg =~ "No matching transfer call"
    end

    test "rejects transfer when memo is required", %{tx: tx} do
      memo = "0x" <> String.duplicate("ab", 32)

      assert {:error, msg} =
               Transaction.find_payment_call(tx, @token_hex,
                 amount: "1000000",
                 recipient: @recipient_hex,
                 memo: memo
               )

      assert msg =~ "No matching transferWithMemo call"
    end

    test "rejects transferWithMemo with wrong memo" do
      actual_memo = "0x" <> String.duplicate("aa", 32)
      expected_memo = "0x" <> String.duplicate("bb", 32)

      calldata = transfer_with_memo_calldata(@recipient_hex, 1_000_000, actual_memo)
      call = build_call(@token_hex, calldata)
      hex = build_tempo_tx(calls: [call])
      {:ok, tx} = Transaction.deserialize(hex)

      assert {:error, msg} =
               Transaction.find_payment_call(tx, @token_hex,
                 amount: "1000000",
                 recipient: @recipient_hex,
                 memo: expected_memo
               )

      assert msg =~ "No matching transferWithMemo call"
    end

    test "rejects invalid amount string" do
      calldata = transfer_calldata(@recipient_hex, 100)
      call = build_call(@token_hex, calldata)
      hex = build_tempo_tx(calls: [call])
      {:ok, tx} = Transaction.deserialize(hex)

      assert {:error, msg} =
               Transaction.find_payment_call(tx, @token_hex,
                 amount: "not_a_number",
                 recipient: @recipient_hex
               )

      assert msg =~ "Invalid amount"
    end

    test "ignores call with unknown function selector" do
      unknown_selector = <<0xDE, 0xAD, 0xBE, 0xEF>>
      calldata = unknown_selector <> :binary.copy(<<0>>, 64)
      call = build_call(@token_hex, calldata)
      hex = build_tempo_tx(calls: [call])
      {:ok, tx} = Transaction.deserialize(hex)

      assert {:error, msg} =
               Transaction.find_payment_call(tx, @token_hex,
                 amount: "1000000",
                 recipient: @recipient_hex
               )

      assert msg =~ "No matching transfer call"
    end

    test "handles raw 20-byte binary address for currency" do
      calldata = transfer_calldata(@recipient_hex, 1_000_000)
      call = build_call(@token_hex, calldata)
      hex = build_tempo_tx(calls: [call])
      {:ok, tx} = Transaction.deserialize(hex)

      currency_bytes = decode_address(@token_hex)

      assert {:ok, _match} =
               Transaction.find_payment_call(tx, currency_bytes,
                 amount: "1000000",
                 recipient: @recipient_hex
               )
    end

    test "handles bare hex address without 0x prefix" do
      calldata = transfer_calldata(@recipient_hex, 1_000_000)
      call = build_call(@token_hex, calldata)
      hex = build_tempo_tx(calls: [call])
      {:ok, tx} = Transaction.deserialize(hex)

      "0x" <> bare_token = @token_hex

      assert {:ok, _match} =
               Transaction.find_payment_call(tx, bare_token,
                 amount: "1000000",
                 recipient: @recipient_hex
               )
    end

    test "rejects when address is invalid (wrong length)" do
      calldata = transfer_calldata(@recipient_hex, 1_000_000)
      call = build_call(@token_hex, calldata)
      hex = build_tempo_tx(calls: [call])
      {:ok, tx} = Transaction.deserialize(hex)

      assert {:error, _} =
               Transaction.find_payment_call(tx, "0xDEAD",
                 amount: "1000000",
                 recipient: @recipient_hex
               )
    end

    test "finds correct call among multiple calls" do
      other_calldata = transfer_calldata(@recipient_hex, 999)
      other_call = build_call(@other_token_hex, other_calldata)

      calldata = transfer_calldata(@recipient_hex, 1_000_000)
      target_call = build_call(@token_hex, calldata)

      hex = build_tempo_tx(calls: [other_call, target_call])
      {:ok, tx} = Transaction.deserialize(hex)

      assert {:ok, match} =
               Transaction.find_payment_call(tx, @token_hex,
                 amount: "1000000",
                 recipient: @recipient_hex
               )

      assert match.amount == 1_000_000
    end
  end

  # --- validate_call_scope/1 tests ---

  describe "validate_call_scope/1" do
    @dex_hex dex_address()

    defp build_scoped_tx(calls) do
      rlp_calls = Enum.map(calls, fn {to, input} -> build_call(to, input) end)
      hex = build_tempo_tx(calls: rlp_calls, fee_payer: true)
      {:ok, tx} = Transaction.deserialize(hex)
      tx
    end

    test "accepts single transfer" do
      tx = build_scoped_tx([{@token_hex, transfer_calldata(@recipient_hex, 1_000_000)}])
      assert :ok = Transaction.validate_call_scope(tx)
    end

    test "accepts single transferWithMemo" do
      memo = "0x" <> String.duplicate("ab", 32)
      tx = build_scoped_tx([{@token_hex, transfer_with_memo_calldata(@recipient_hex, 500_000, memo)}])
      assert :ok = Transaction.validate_call_scope(tx)
    end

    test "accepts approve + swapExactAmountOut + transfer" do
      tx =
        build_scoped_tx([
          {@token_hex, approve_calldata(@dex_hex, 1_000_000)},
          {@dex_hex, swap_calldata()},
          {@token_hex, transfer_calldata(@recipient_hex, 1_000_000)}
        ])

      assert :ok = Transaction.validate_call_scope(tx)
    end

    test "accepts approve + swapExactAmountOut + transferWithMemo" do
      memo = "0x" <> String.duplicate("cd", 32)

      tx =
        build_scoped_tx([
          {@token_hex, approve_calldata(@dex_hex, 1_000_000)},
          {@dex_hex, swap_calldata()},
          {@token_hex, transfer_with_memo_calldata(@recipient_hex, 1_000_000, memo)}
        ])

      assert :ok = Transaction.validate_call_scope(tx)
    end

    test "rejects empty calls" do
      hex = build_tempo_tx(calls: [], fee_payer: true)
      assert {:error, "Calls list cannot be empty"} = Transaction.deserialize(hex)
    end

    test "rejects unknown selector" do
      unknown = <<0xDE, 0xAD, 0xBE, 0xEF>> <> :binary.copy(<<0>>, 64)
      tx = build_scoped_tx([{@token_hex, unknown}])
      assert {:error, "disallowed call pattern" <> _} = Transaction.validate_call_scope(tx)
    end

    test "rejects extra call beyond allowed patterns" do
      tx =
        build_scoped_tx([
          {@token_hex, transfer_calldata(@recipient_hex, 1_000_000)},
          {@token_hex, transfer_calldata(@recipient_hex, 500_000)}
        ])

      assert {:error, "disallowed call pattern" <> _} = Transaction.validate_call_scope(tx)
    end

    test "rejects wrong order (transfer before approve + swap)" do
      tx =
        build_scoped_tx([
          {@token_hex, transfer_calldata(@recipient_hex, 1_000_000)},
          {@token_hex, approve_calldata(@dex_hex, 1_000_000)},
          {@dex_hex, swap_calldata()}
        ])

      assert {:error, "disallowed call pattern" <> _} = Transaction.validate_call_scope(tx)
    end

    test "rejects approve with non-DEX spender" do
      non_dex = "0x1111111111111111111111111111111111111111"

      tx =
        build_scoped_tx([
          {@token_hex, approve_calldata(non_dex, 1_000_000)},
          {@dex_hex, swap_calldata()},
          {@token_hex, transfer_calldata(@recipient_hex, 1_000_000)}
        ])

      assert {:error, "approve spender is not the DEX"} = Transaction.validate_call_scope(tx)
    end

    test "rejects approve with truncated calldata" do
      truncated = <<0x09, 0x5E, 0xA7, 0xB3>> <> :binary.copy(<<0>>, 10)

      tx =
        build_scoped_tx([
          {@token_hex, truncated},
          {@dex_hex, swap_calldata()},
          {@token_hex, transfer_calldata(@recipient_hex, 1_000_000)}
        ])

      assert {:error, "malformed approve calldata"} = Transaction.validate_call_scope(tx)
    end

    test "rejects swap targeting non-DEX address" do
      non_dex = "0x2222222222222222222222222222222222222222"

      tx =
        build_scoped_tx([
          {@token_hex, approve_calldata(@dex_hex, 1_000_000)},
          {non_dex, swap_calldata()},
          {@token_hex, transfer_calldata(@recipient_hex, 1_000_000)}
        ])

      assert {:error, "buy target is not the DEX"} = Transaction.validate_call_scope(tx)
    end

    test "rejects approve + swap without transfer" do
      tx =
        build_scoped_tx([
          {@token_hex, approve_calldata(@dex_hex, 1_000_000)},
          {@dex_hex, swap_calldata()}
        ])

      assert {:error, "disallowed call pattern" <> _} = Transaction.validate_call_scope(tx)
    end
  end

  # --- sender/1 and simulate_request/1 tests ---

  describe "sender/1 and simulate_request/1" do
    # Hardhat default accounts (testnet only, no security concern).
    @client_key Base.decode16!("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", case: :lower)
    @fee_payer_key Base.decode16!("59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d", case: :lower)
    @fee_token_bin Base.decode16!("20c0000000000000000000000000000000000000", case: :lower)

    defp cosigned_transfer(opts) do
      defaults = [
        private_key: @client_key,
        token: @token_hex,
        recipient: @recipient_hex,
        amount: 1,
        chain_id: @moderato_chain_id,
        rpc_url: "http://localhost",
        nonce: 7,
        gas_limit: 100_000
      ]

      {:ok, raw} = Builder.build_fee_payer_transfer(Keyword.merge(defaults, opts))
      {:ok, tx} = Transaction.deserialize(raw)
      {:ok, cosigned} = Transaction.cosign_fee_payer(tx, @fee_payer_key, @fee_token_bin)
      cosigned
    end

    test "sender/1 recovers the client sender from a co-signed transaction" do
      {:ok, expected} = Curvy.get_address(@client_key)
      assert {:ok, ^expected} = Transaction.sender(cosigned_transfer([]))
    end

    test "sender/1 errors on a transaction with too few fields" do
      tx = %Transaction{chain_id: 1, calls: [%{to: <<0::160>>, value: 0, input: <<>>}], fields: [<<1>>], raw: "0x"}
      assert {:error, "Transaction missing fields required to recover sender"} = Transaction.sender(tx)
    end

    test "sender/1 errors on an invalid sender signature" do
      # build_tempo_tx uses a fake 64-byte sender signature, not a real 65-byte one.
      hex = build_tempo_tx(calls: [build_call(@token_hex, transfer_calldata(@recipient_hex, 1))], fee_payer: true)
      {:ok, tx} = Transaction.deserialize(hex)
      assert {:error, msg} = Transaction.sender(tx)
      assert msg =~ "Invalid sender signature format"
    end

    test "simulate_request/1 builds the TempoTransactionRequest wire object" do
      {:ok, expected_from} = Curvy.get_address(@client_key)
      {:ok, req} = Transaction.simulate_request(cosigned_transfer([]))

      assert req["from"] == "0x" <> Base.encode16(expected_from, case: :lower)
      assert req["to"] == String.downcase(@token_hex)
      assert req["value"] == "0x0"
      assert String.starts_with?(req["input"], "0x")
      # Single-call tx: the only call is folded into to/input, leaving calls empty.
      assert req["calls"] == []
      assert req["gas"] == "0x186a0"
      assert req["nonce"] == "0x7"
      assert req["chainId"] == "0xa5bf"
      assert req["type"] == "0x76"
      assert req["feeToken"] == "0x" <> Base.encode16(@fee_token_bin, case: :lower)
      # Zero fields are omitted, not encoded as "0x0".
      refute Map.has_key?(req, "nonceKey")
      refute Map.has_key?(req, "validBefore")
    end

    test "simulate_request/1 includes nonceKey and validBefore when non-zero" do
      {:ok, req} = Transaction.simulate_request(cosigned_transfer(nonce_key: 3, valid_before: 99))
      assert req["nonceKey"] == "0x3"
      assert req["validBefore"] == "0x63"
    end

    test "simulate_request/1 folds the last call and keeps N-1 in calls for a multi-call tx" do
      call1 = build_call(@token_hex, transfer_calldata(@recipient_hex, 1))
      call2 = build_call(@other_token_hex, transfer_calldata(@recipient_hex, 2))

      {:ok, raw} =
        Builder.build_fee_payer_multicall(
          private_key: @client_key,
          calls: [call1, call2],
          chain_id: @moderato_chain_id,
          rpc_url: "http://localhost",
          nonce: 0,
          gas_limit: 100_000
        )

      {:ok, tx} = Transaction.deserialize(raw)
      {:ok, cosigned} = Transaction.cosign_fee_payer(tx, @fee_payer_key, @fee_token_bin)
      {:ok, req} = Transaction.simulate_request(cosigned)

      assert [head] = req["calls"]
      assert head["to"] == String.downcase(@token_hex)
      assert req["to"] == String.downcase(@other_token_hex)
    end

    test "simulate_request/1 errors when the parsed call list is empty" do
      tx = %{cosigned_transfer([]) | calls: []}
      assert {:error, "Cannot simulate a transaction with no calls"} = Transaction.simulate_request(tx)
    end

    test "simulate_request/1 treats a non-binary gas field as zero" do
      tx = cosigned_transfer([])
      fields = List.replace_at(tx.fields, 3, [])
      {:ok, req} = Transaction.simulate_request(%{tx | fields: fields})
      assert req["gas"] == "0x0"
    end

    test "sender/1 reports recovery failure for a 65-byte signature off the curve" do
      tx = cosigned_transfer([])
      bad_sig = <<0::unsigned-big-size(256), 0::unsigned-big-size(256), 27>>
      tx = %{tx | fields: Enum.drop(tx.fields, -1) ++ [bad_sig]}
      assert {:error, msg} = Transaction.sender(tx)
      assert msg =~ "Failed to recover sender"
    end
  end

  test "validate_call_scope rejects a call whose input is shorter than a selector" do
    hex = build_tempo_tx(calls: [build_call(@token_hex, <<1, 2, 3>>)])
    {:ok, tx} = Transaction.deserialize(hex)
    assert {:error, "disallowed call pattern" <> _} = Transaction.validate_call_scope(tx)
  end

  test "find_payment_call ignores a non-address currency and a non-binary memo" do
    calldata = transfer_calldata(@recipient_hex, 1_000_000)
    hex = build_tempo_tx(calls: [build_call(@token_hex, calldata)])
    {:ok, tx} = Transaction.deserialize(hex)

    assert {:error, "No matching transfer call found in transaction"} =
             Transaction.find_payment_call(tx, "not-an-address", amount: "1000000", recipient: @recipient_hex)

    memo = "0x" <> String.duplicate("cd", 32)
    memo_calldata = transfer_with_memo_calldata(@recipient_hex, 1_000_000, memo)
    {:ok, memo_tx} = Transaction.deserialize(build_tempo_tx(calls: [build_call(@token_hex, memo_calldata)]))
    bare = String.duplicate("cd", 32)

    assert {:ok, match} =
             Transaction.find_payment_call(memo_tx, @token_hex,
               amount: "1000000",
               recipient: @recipient_hex,
               memo: bare
             )

    assert match.memo == memo
  end
end
