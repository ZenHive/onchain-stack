defmodule Onchain.RPCTest do
  use ExUnit.Case, async: true

  alias Onchain.RPC

  # --- Unit tests: input validation (no network calls) ---

  describe "eth_call/3 input validation" do
    test "rejects address with wrong byte size (not 20 bytes)" do
      short_addr = "0x" <> String.duplicate("aa", 10)
      assert {:error, {:invalid_address, ^short_addr}} = RPC.eth_call(short_addr, "0x18160ddd")
    end

    test "rejects address with invalid hex characters" do
      bad_addr = "0xZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"
      assert {:error, {:invalid_address, ^bad_addr}} = RPC.eth_call(bad_addr, "0x18160ddd")
    end

    test "rejects data without 0x prefix" do
      addr = "0x" <> String.duplicate("aa", 20)
      assert {:error, {:invalid_data, "18160ddd"}} = RPC.eth_call(addr, "18160ddd")
    end

    test "rejects data with invalid hex characters" do
      addr = "0x" <> String.duplicate("aa", 20)
      assert {:error, {:invalid_data, "0xZZZZ"}} = RPC.eth_call(addr, "0xZZZZ")
    end

    test "rejects non-binary address" do
      assert {:error, {:invalid_address, 12_345}} = RPC.eth_call(12_345, "0x18160ddd")
    end

    test "accepts 20-byte raw binary address (internal callers pass binaries)" do
      addr = <<1::160>>
      result = RPC.eth_call(addr, "0x18160ddd")
      refute match?({:error, {:invalid_address, _}}, result)
    end

    test "rejects bare hex address without 0x prefix" do
      bare_addr = String.duplicate("aa", 20)
      assert {:error, {:invalid_address, ^bare_addr}} = RPC.eth_call(bare_addr, "0x18160ddd")
    end
  end

  describe "eth_call/3 block validation" do
    test "rejects invalid block value" do
      addr = "0x" <> String.duplicate("aa", 20)
      assert {:error, {:invalid_block, :foo}} = RPC.eth_call(addr, "0x18160ddd", block: :foo)
    end

    test "rejects negative integer block" do
      addr = "0x" <> String.duplicate("aa", 20)
      assert {:error, {:invalid_block, -1}} = RPC.eth_call(addr, "0x18160ddd", block: -1)
    end

    test "accepts integer block (passes input validation)" do
      addr = "0x" <> String.duplicate("aa", 20)
      result = RPC.eth_call(addr, "0x18160ddd", block: 15_000_000)
      refute match?({:error, {:invalid_block, _}}, result)
    end

    test "accepts tag block (passes input validation)" do
      addr = "0x" <> String.duplicate("aa", 20)
      result = RPC.eth_call(addr, "0x18160ddd", block: "finalized")
      refute match?({:error, {:invalid_block, _}}, result)
    end

    test "accepts hex block string (passes input validation)" do
      addr = "0x" <> String.duplicate("aa", 20)
      result = RPC.eth_call(addr, "0x18160ddd", block: "0xe4e1c0")
      refute match?({:error, {:invalid_block, _}}, result)
    end

    test "rejects invalid hex block string" do
      addr = "0x" <> String.duplicate("aa", 20)
      assert {:error, {:invalid_block, "0xZZZZ"}} = RPC.eth_call(addr, "0x18160ddd", block: "0xZZZZ")
    end
  end

  describe "get_balance/2 input validation" do
    test "rejects address with wrong byte size" do
      short_addr = "0x" <> String.duplicate("aa", 10)
      assert {:error, {:invalid_address, ^short_addr}} = RPC.get_balance(short_addr)
    end

    test "rejects invalid hex address" do
      bad_addr = "0xnotreallyhex000000000000000000000000000000"
      assert {:error, {:invalid_address, ^bad_addr}} = RPC.get_balance(bad_addr)
    end
  end

  describe "get_balance/2 block validation" do
    test "rejects invalid block value" do
      addr = "0x" <> String.duplicate("aa", 20)
      assert {:error, {:invalid_block, "bogus"}} = RPC.get_balance(addr, block: "bogus")
    end

    test "accepts integer block (passes input validation)" do
      addr = "0x" <> String.duplicate("aa", 20)
      result = RPC.get_balance(addr, block: 15_000_000)
      refute match?({:error, {:invalid_block, _}}, result)
    end
  end

  describe "eth_send_raw_transaction/2 input validation" do
    test "rejects data without 0x prefix" do
      assert {:error, {:invalid_data, "deadbeef"}} = RPC.eth_send_raw_transaction("deadbeef")
    end

    test "rejects data with invalid hex characters" do
      assert {:error, {:invalid_data, "0xZZZZ"}} = RPC.eth_send_raw_transaction("0xZZZZ")
    end
  end

  # --- Bang variant tests (raise on invalid input) ---

  describe "eth_call!/3" do
    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/eth_call failed/, fn ->
        RPC.eth_call!("0xshort", "0x18160ddd")
      end
    end

    test "raises on invalid data" do
      addr = "0x" <> String.duplicate("aa", 20)

      assert_raise RuntimeError, ~r/eth_call failed/, fn ->
        RPC.eth_call!(addr, "no_prefix")
      end
    end
  end

  describe "eth_send_raw_transaction!/2" do
    test "raises on invalid data" do
      assert_raise RuntimeError, ~r/eth_send_raw_transaction failed/, fn ->
        RPC.eth_send_raw_transaction!("no_prefix")
      end
    end
  end

  describe "get_balance!/2" do
    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/get_balance failed/, fn ->
        RPC.get_balance!("0xshort")
      end
    end
  end

  describe "block_number!/1" do
    test "raises when RPC unavailable" do
      assert_raise RuntimeError, ~r/block_number failed/, fn ->
        RPC.block_number!(rpc_url: "http://localhost:1")
      end
    end
  end

  describe "chain_id!/1" do
    test "raises when RPC unavailable" do
      assert_raise RuntimeError, ~r/chain_id failed/, fn ->
        RPC.chain_id!(rpc_url: "http://localhost:1")
      end
    end
  end

  describe "syncing/1 (connection failure)" do
    test "returns rpc_error tuple when RPC unavailable" do
      assert {:error, {:rpc_error, %{message: _}}} = RPC.syncing(rpc_url: "http://localhost:1")
    end
  end

  describe "syncing!/1" do
    test "raises when RPC unavailable" do
      assert_raise RuntimeError, ~r/syncing failed/, fn ->
        RPC.syncing!(rpc_url: "http://localhost:1")
      end
    end
  end

  describe "get_block_by_number/2 input validation" do
    test "rejects negative integer" do
      assert {:error, {:invalid_block_id, -1}} = RPC.get_block_by_number(-1)
    end

    test "rejects non-integer, non-string input" do
      assert {:error, {:invalid_block_id, :foo}} = RPC.get_block_by_number(:foo)
    end

    test "rejects invalid hex string" do
      assert {:error, {:invalid_block_id, "0xZZZZ"}} = RPC.get_block_by_number("0xZZZZ")
    end

    test "rejects unknown string tag" do
      assert {:error, {:invalid_block_id, "unknown_tag"}} = RPC.get_block_by_number("unknown_tag")
    end
  end

  describe "get_block_by_number!/2" do
    test "raises on invalid input" do
      assert_raise RuntimeError, ~r/get_block_by_number failed/, fn ->
        RPC.get_block_by_number!(-1)
      end
    end
  end

  describe "eth_get_logs/2 filter validation" do
    test "returns error for invalid from_block value" do
      filter = %{from_block: "bogus"}
      assert {:error, {:invalid_filter, {:fromBlock, "bogus"}}} = RPC.eth_get_logs(filter)
    end

    test "returns error for invalid to_block value" do
      filter = %{from_block: 100, to_block: :not_valid}
      assert {:error, {:invalid_filter, {:toBlock, :not_valid}}} = RPC.eth_get_logs(filter)
    end

    test "returns error for negative block number" do
      filter = %{from_block: -1}
      assert {:error, {:invalid_filter, {:fromBlock, -1}}} = RPC.eth_get_logs(filter)
    end

    test "returns error for invalid hex block string" do
      filter = %{from_block: "0xZZZZ"}
      assert {:error, {:invalid_filter, {:fromBlock, "0xZZZZ"}}} = RPC.eth_get_logs(filter)
    end

    test "accepts valid block tags" do
      # Will fail at RPC level but should pass filter validation
      filter = %{from_block: "latest", to_block: "finalized"}
      result = RPC.eth_get_logs(filter)
      refute match?({:error, {:invalid_filter, _}}, result)
    end

    test "accepts valid integer blocks" do
      filter = %{from_block: 100, to_block: 200}
      result = RPC.eth_get_logs(filter)
      refute match?({:error, {:invalid_filter, _}}, result)
    end

    test "accepts valid hex block strings" do
      filter = %{from_block: "0x64", to_block: "0xc8"}
      result = RPC.eth_get_logs(filter)
      refute match?({:error, {:invalid_filter, _}}, result)
    end
  end

  describe "eth_get_logs/2 filter key validation" do
    test "rejects non-canonical snake_case string keys" do
      # "from_block"/"to_block" (snake_case strings) are NOT canonical
      # JSON-RPC names — only the camelCase forms ("fromBlock"/"toBlock") are
      # accepted aliases per Task 60.
      filter = %{"from_block" => 100, "to_block" => 200}
      assert {:error, {:invalid_filter_key, unknown}} = RPC.eth_get_logs(filter)
      assert unknown in ["from_block", "to_block"]
    end

    test "rejects unsupported camelCase atom keys like :blockHash" do
      # The canonical atom is :block_hash (snake_case). :blockHash (camelCase
      # atom) is not in the allowlist.
      filter = %{blockHash: "0x" <> String.duplicate("ab", 32)}
      assert {:error, {:invalid_filter_key, :blockHash}} = RPC.eth_get_logs(filter)
    end

    test "rejects arbitrary unknown keys" do
      filter = %{from_block: 100, to_block: 200, foo: :bar}
      assert {:error, {:invalid_filter_key, :foo}} = RPC.eth_get_logs(filter)
    end

    test "empty filter still succeeds through key validation" do
      result = RPC.eth_get_logs(%{})
      refute match?({:error, {:invalid_filter_key, _}}, result)
    end

    test "canonical atom keys pass key validation (regression guard)" do
      filter = %{from_block: 100, to_block: 200}
      result = RPC.eth_get_logs(filter)
      refute match?({:error, {:invalid_filter_key, _}}, result)
      refute match?({:error, {:invalid_filter, _}}, result)
    end
  end

  describe "eth_get_logs/2 camelCase string-key aliases (Task 60)" do
    test ~s|accepts "fromBlock" / "toBlock" as aliases for :from_block / :to_block| do
      filter = %{"fromBlock" => 100, "toBlock" => 200}
      result = RPC.eth_get_logs(filter)
      refute match?({:error, {:invalid_filter_key, _}}, result)
      refute match?({:error, {:invalid_filter, _}}, result)
    end

    test ~s|accepts "address" string-key alias| do
      filter = %{"address" => "0x" <> String.duplicate("ab", 20)}
      result = RPC.eth_get_logs(filter)
      refute match?({:error, {:invalid_filter_key, _}}, result)
      refute match?({:error, {:invalid_filter, _}}, result)
    end

    test ~s|accepts "topics" string-key alias| do
      filter = %{"topics" => []}
      result = RPC.eth_get_logs(filter)
      refute match?({:error, {:invalid_filter_key, _}}, result)
      refute match?({:error, {:invalid_filter, _}}, result)
    end

    test "atom key wins when both atom and camelCase string are present" do
      # Atom takes precedence on conflict — the string-key value is dropped
      # silently. The rejection below proves the atom value (:bogus) made it
      # through to validation, not the string-key value (100).
      filter = %{"fromBlock" => 100, from_block: :bogus}
      assert {:error, {:invalid_filter, {:fromBlock, :bogus}}} = RPC.eth_get_logs(filter)
    end
  end

  describe "eth_get_logs/2 :block_hash filter (Task 61, EIP-1474)" do
    @valid_hash "0x" <> String.duplicate("ab", 32)

    test "accepts :block_hash as a valid 32-byte hex" do
      filter = %{block_hash: @valid_hash}
      result = RPC.eth_get_logs(filter)
      refute match?({:error, {:invalid_filter_key, _}}, result)
      refute match?({:error, {:invalid_filter, _}}, result)
    end

    test ~s|accepts "blockHash" string-key alias| do
      filter = %{"blockHash" => @valid_hash}
      result = RPC.eth_get_logs(filter)
      refute match?({:error, {:invalid_filter_key, _}}, result)
      refute match?({:error, {:invalid_filter, _}}, result)
    end

    test "rejects malformed block hash" do
      filter = %{block_hash: "0xdeadbeef"}
      assert {:error, {:invalid_filter, {:blockHash, "0xdeadbeef"}}} = RPC.eth_get_logs(filter)
    end

    test "rejects non-hex block hash" do
      filter = %{block_hash: :not_a_hash}
      assert {:error, {:invalid_filter, {:blockHash, :not_a_hash}}} = RPC.eth_get_logs(filter)
    end

    test ":block_hash mutually exclusive with :from_block (EIP-1474)" do
      filter = %{block_hash: @valid_hash, from_block: 100}

      assert {:error, {:invalid_filter, {:block_hash_mutually_exclusive, present}}} =
               RPC.eth_get_logs(filter)

      assert :from_block in present
      assert :block_hash in present
    end

    test ":block_hash mutually exclusive with :to_block (EIP-1474)" do
      filter = %{block_hash: @valid_hash, to_block: 200}

      assert {:error, {:invalid_filter, {:block_hash_mutually_exclusive, present}}} =
               RPC.eth_get_logs(filter)

      assert :to_block in present
      assert :block_hash in present
    end

    test ":block_hash mutually exclusive with both :from_block and :to_block" do
      filter = %{block_hash: @valid_hash, from_block: 100, to_block: 200}

      assert {:error, {:invalid_filter, {:block_hash_mutually_exclusive, present}}} =
               RPC.eth_get_logs(filter)

      assert :from_block in present
      assert :to_block in present
      assert :block_hash in present
    end
  end

  describe "get_transaction_receipt/2 input validation" do
    test "rejects tx_hash without 0x prefix" do
      assert {:error, {:invalid_tx_hash, "abcd1234"}} = RPC.get_transaction_receipt("abcd1234")
    end

    test "rejects tx_hash with invalid hex characters" do
      assert {:error, {:invalid_tx_hash, "0xZZZZ"}} = RPC.get_transaction_receipt("0xZZZZ")
    end

    test "rejects non-binary input" do
      assert {:error, {:invalid_tx_hash, 12_345}} = RPC.get_transaction_receipt(12_345)
    end

    test "rejects too-short hex string" do
      short_hash = "0x1234"
      assert {:error, {:invalid_tx_hash, ^short_hash}} = RPC.get_transaction_receipt(short_hash)
    end

    test "rejects too-long hex string" do
      long_hash = "0x" <> String.duplicate("ab", 33)
      assert {:error, {:invalid_tx_hash, ^long_hash}} = RPC.get_transaction_receipt(long_hash)
    end

    test "accepts valid 32-byte hash (passes input validation)" do
      valid_hash = "0x" <> String.duplicate("ab", 32)
      result = RPC.get_transaction_receipt(valid_hash)
      refute match?({:error, {:invalid_tx_hash, _}}, result)
    end
  end

  describe "get_transaction_receipt!/2" do
    test "raises on invalid input" do
      assert_raise RuntimeError, ~r/get_transaction_receipt failed/, fn ->
        RPC.get_transaction_receipt!("no_prefix")
      end
    end

    test "returns the same parsed receipt shape as the non-bang variant" do
      tx_hash = "0x" <> String.duplicate("ab", 32)

      raw_receipt = %{
        "transactionHash" => tx_hash,
        "transactionIndex" => "0x2",
        "blockHash" => "0x" <> String.duplicate("cd", 32),
        "blockNumber" => "0x10",
        "from" => "0x" <> String.duplicate("11", 20),
        "to" => nil,
        "cumulativeGasUsed" => "0x5208",
        "gasUsed" => "0x5208",
        "effectiveGasPrice" => "0x3b9aca00",
        "status" => "0x1",
        "contractAddress" => nil,
        "logs" => [],
        "type" => "0x2"
      }

      opts = [rpc_url: "http://stub.invalid", req_options: [plug: rpc_result_plug(raw_receipt)]]

      assert {:ok, parsed} = RPC.get_transaction_receipt(tx_hash, opts)
      assert parsed == RPC.get_transaction_receipt!(tx_hash, opts)
      assert parsed.transaction_hash == tx_hash
      assert parsed.transaction_index == 2
      assert parsed.block_number == 16
      assert parsed.gas_used == 21_000
    end
  end

  describe "get_transaction_count/2 input validation" do
    test "rejects address with wrong byte size" do
      short_addr = "0x" <> String.duplicate("aa", 10)
      assert {:error, {:invalid_address, ^short_addr}} = RPC.get_transaction_count(short_addr)
    end

    test "rejects invalid hex address" do
      bad_addr = "0xnotreallyhex000000000000000000000000000000"
      assert {:error, {:invalid_address, ^bad_addr}} = RPC.get_transaction_count(bad_addr)
    end

    test "rejects non-binary input" do
      assert {:error, {:invalid_address, 12_345}} = RPC.get_transaction_count(12_345)
    end

    test "accepts 20-byte raw binary address (internal callers pass binaries)" do
      addr = <<1::160>>
      result = RPC.get_transaction_count(addr)
      refute match?({:error, {:invalid_address, _}}, result)
    end
  end

  describe "get_transaction_count/2 block validation" do
    test "rejects invalid block value" do
      addr = "0x" <> String.duplicate("aa", 20)
      assert {:error, {:invalid_block, :foo}} = RPC.get_transaction_count(addr, block: :foo)
    end

    test "accepts integer block (passes input validation)" do
      addr = "0x" <> String.duplicate("aa", 20)
      result = RPC.get_transaction_count(addr, block: 15_000_000)
      refute match?({:error, {:invalid_block, _}}, result)
    end

    test "accepts tag block (passes input validation)" do
      addr = "0x" <> String.duplicate("aa", 20)
      result = RPC.get_transaction_count(addr, block: "pending")
      refute match?({:error, {:invalid_block, _}}, result)
    end
  end

  describe "get_transaction_count!/2" do
    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/get_transaction_count failed/, fn ->
        RPC.get_transaction_count!("0xshort")
      end
    end
  end

  # --- eth_get_code ---

  describe "eth_get_code/2 input validation" do
    test "rejects address with wrong byte size" do
      short_addr = "0x" <> String.duplicate("aa", 10)
      assert {:error, {:invalid_address, ^short_addr}} = RPC.eth_get_code(short_addr)
    end

    test "rejects invalid hex address" do
      bad_addr = "0xnotreallyhex000000000000000000000000000000"
      assert {:error, {:invalid_address, ^bad_addr}} = RPC.eth_get_code(bad_addr)
    end

    test "rejects non-binary input" do
      assert {:error, {:invalid_address, 12_345}} = RPC.eth_get_code(12_345)
    end

    test "accepts 20-byte raw binary address (internal callers pass binaries)" do
      addr = <<1::160>>
      result = RPC.eth_get_code(addr)
      refute match?({:error, {:invalid_address, _}}, result)
    end
  end

  describe "eth_get_code/2 block validation" do
    test "rejects invalid block value" do
      addr = "0x" <> String.duplicate("aa", 20)
      assert {:error, {:invalid_block, :foo}} = RPC.eth_get_code(addr, block: :foo)
    end

    test "accepts integer block (passes input validation)" do
      addr = "0x" <> String.duplicate("aa", 20)
      result = RPC.eth_get_code(addr, block: 15_000_000)
      refute match?({:error, {:invalid_block, _}}, result)
    end

    test "accepts tag block (passes input validation)" do
      addr = "0x" <> String.duplicate("aa", 20)
      result = RPC.eth_get_code(addr, block: "finalized")
      refute match?({:error, {:invalid_block, _}}, result)
    end
  end

  describe "eth_get_code!/2" do
    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/eth_get_code failed/, fn ->
        RPC.eth_get_code!("0xshort")
      end
    end
  end

  # --- get_transaction_by_hash ---

  describe "get_transaction_by_hash/2 input validation" do
    test "rejects tx_hash without 0x prefix" do
      assert {:error, {:invalid_tx_hash, "abcd1234"}} = RPC.get_transaction_by_hash("abcd1234")
    end

    test "rejects tx_hash with invalid hex characters" do
      assert {:error, {:invalid_tx_hash, "0xZZZZ"}} = RPC.get_transaction_by_hash("0xZZZZ")
    end

    test "rejects non-binary input" do
      assert {:error, {:invalid_tx_hash, 12_345}} = RPC.get_transaction_by_hash(12_345)
    end

    test "rejects too-short hex string" do
      short_hash = "0x1234"
      assert {:error, {:invalid_tx_hash, ^short_hash}} = RPC.get_transaction_by_hash(short_hash)
    end

    test "rejects too-long hex string" do
      long_hash = "0x" <> String.duplicate("ab", 33)
      assert {:error, {:invalid_tx_hash, ^long_hash}} = RPC.get_transaction_by_hash(long_hash)
    end

    test "accepts valid 32-byte hash (passes input validation)" do
      valid_hash = "0x" <> String.duplicate("ab", 32)
      result = RPC.get_transaction_by_hash(valid_hash)
      refute match?({:error, {:invalid_tx_hash, _}}, result)
    end
  end

  describe "get_transaction_by_hash!/2" do
    test "raises on invalid input" do
      assert_raise RuntimeError, ~r/get_transaction_by_hash failed/, fn ->
        RPC.get_transaction_by_hash!("no_prefix")
      end
    end

    test "returns the same parsed transaction shape as the non-bang variant" do
      tx_hash = "0x" <> String.duplicate("ab", 32)

      raw_transaction = %{
        "hash" => tx_hash,
        "nonce" => "0x3",
        "blockHash" => "0x" <> String.duplicate("cd", 32),
        "blockNumber" => "0x10",
        "transactionIndex" => "0x2",
        "from" => "0x" <> String.duplicate("11", 20),
        "to" => "0x" <> String.duplicate("22", 20),
        "value" => "0x4",
        "gas" => "0x5208",
        "gasPrice" => "0x3b9aca00",
        "input" => "0x",
        "type" => "0x0",
        "chainId" => "0x1"
      }

      opts = [rpc_url: "http://stub.invalid", req_options: [plug: rpc_result_plug(raw_transaction)]]

      assert {:ok, parsed} = RPC.get_transaction_by_hash(tx_hash, opts)
      assert parsed == RPC.get_transaction_by_hash!(tx_hash, opts)
      assert parsed.hash == tx_hash
      assert parsed.nonce == 3
      assert parsed.block_number == 16
      assert parsed.gas == 21_000
    end
  end

  describe "eth_get_logs!/2" do
    test "raises on invalid filter" do
      assert_raise RuntimeError, ~r/eth_get_logs failed/, fn ->
        RPC.eth_get_logs!(%{from_block: "bogus"})
      end
    end
  end

  # --- call (generic JSON-RPC passthrough) ---

  describe "call/3" do
    test "returns wrapped rpc_error tuple when transport fails" do
      assert {:error, {:rpc_error, %{message: _}}} =
               RPC.call("eth_blockNumber", [], rpc_url: "http://localhost:1")
    end

    test "two-arity form (default opts) dispatches identically" do
      # No opts → no :rpc_url override → cartouche falls back to app config which
      # is unconfigured in test env, surfacing as a transport-level rpc_error.
      assert {:error, {:rpc_error, _}} = RPC.call("eth_blockNumber", [])
    end

    test "raises FunctionClauseError when method is not a binary" do
      # apply/3 defeats compile-time type checking so we can exercise the runtime guard
      assert_raise FunctionClauseError, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(RPC, :call, [:eth_blockNumber, [], [rpc_url: "http://localhost:1"]])
      end
    end

    test "raises FunctionClauseError when params is not a list" do
      assert_raise FunctionClauseError, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(RPC, :call, ["eth_blockNumber", nil, [rpc_url: "http://localhost:1"]])
      end

      assert_raise FunctionClauseError, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(RPC, :call, ["eth_blockNumber", %{}, [rpc_url: "http://localhost:1"]])
      end
    end
  end

  describe "call!/3" do
    test "raises with method-prefixed message when RPC unavailable" do
      assert_raise RuntimeError, ~r/RPC eth_blockNumber failed/, fn ->
        RPC.call!("eth_blockNumber", [], rpc_url: "http://localhost:1")
      end
    end

    test "method name is interpolated into the raise message" do
      assert_raise RuntimeError, ~r/RPC debug_traceTransaction failed/, fn ->
        RPC.call!("debug_traceTransaction", ["0x" <> String.duplicate("ab", 32)], rpc_url: "http://localhost:1")
      end
    end
  end

  describe "fee_history/2 block_count validation" do
    test "rejects zero" do
      assert {:error, {:invalid_block_count, 0}} = RPC.fee_history(0, rpc_url: "http://localhost:1")
    end

    test "rejects negative integer" do
      assert {:error, {:invalid_block_count, -1}} = RPC.fee_history(-1, rpc_url: "http://localhost:1")
    end

    test "rejects values above 1024" do
      assert {:error, {:invalid_block_count, 1025}} = RPC.fee_history(1025, rpc_url: "http://localhost:1")
    end

    test "rejects non-integer (string)" do
      assert {:error, {:invalid_block_count, "20"}} = RPC.fee_history("20", rpc_url: "http://localhost:1")
    end

    test "rejects non-integer (float)" do
      assert {:error, {:invalid_block_count, 1.5}} = RPC.fee_history(1.5, rpc_url: "http://localhost:1")
    end
  end

  describe "fee_history/2 reward_percentiles validation" do
    test "rejects empty list" do
      assert {:error, {:invalid_reward_percentiles, :empty}} =
               RPC.fee_history(20, reward_percentiles: [], rpc_url: "http://localhost:1")
    end

    test "rejects out-of-range value above 100" do
      assert {:error, {:invalid_reward_percentiles, {:out_of_range, 150}}} =
               RPC.fee_history(20, reward_percentiles: [50, 150], rpc_url: "http://localhost:1")
    end

    test "rejects out-of-range negative value" do
      assert {:error, {:invalid_reward_percentiles, {:out_of_range, -10}}} =
               RPC.fee_history(20, reward_percentiles: [-10, 50], rpc_url: "http://localhost:1")
    end

    test "rejects non-monotonic list" do
      assert {:error, {:invalid_reward_percentiles, :not_monotonic}} =
               RPC.fee_history(20, reward_percentiles: [50, 25], rpc_url: "http://localhost:1")
    end

    test "rejects non-list" do
      assert {:error, {:invalid_reward_percentiles, :not_a_list}} =
               RPC.fee_history(20, reward_percentiles: 50, rpc_url: "http://localhost:1")
    end

    test "rejects non-integer entries" do
      assert {:error, {:invalid_reward_percentiles, {:out_of_range, 50.0}}} =
               RPC.fee_history(20, reward_percentiles: [50.0], rpc_url: "http://localhost:1")
    end
  end

  describe "fee_history/2 newest_block validation" do
    test "rejects unknown tag" do
      assert {:error, {:invalid_block, "bogus"}} =
               RPC.fee_history(20, newest_block: "bogus", rpc_url: "http://localhost:1")
    end
  end

  describe "fee_history!/2" do
    test "raises when validation fails" do
      assert_raise RuntimeError, ~r/fee_history failed.*invalid_block_count/, fn ->
        RPC.fee_history!(0, rpc_url: "http://localhost:1")
      end
    end
  end

  # --- get_proof ---

  describe "get_proof/3 input validation" do
    @valid_address "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
    @valid_storage_key "0x" <> String.duplicate("00", 32)

    test "rejects address without 0x prefix" do
      assert {:error, {:invalid_address, "abcd1234"}} = RPC.get_proof("abcd1234", [])
    end

    test "rejects non-list storage_keys" do
      assert {:error, {:invalid_storage_keys, "0x00"}} = RPC.get_proof(@valid_address, "0x00")
    end

    test "rejects storage key with bad length" do
      bad_key = "0x1234"
      assert {:error, {:invalid_storage_key, ^bad_key}} = RPC.get_proof(@valid_address, [bad_key])
    end

    test "rejects storage key with invalid hex chars" do
      bad_key = "0x" <> String.duplicate("ZZ", 32)
      assert {:error, {:invalid_storage_key, ^bad_key}} = RPC.get_proof(@valid_address, [bad_key])
    end

    test "rejects non-binary storage key entry" do
      assert {:error, {:invalid_storage_key, 123}} = RPC.get_proof(@valid_address, [123])
    end

    test "rejects bad block tag" do
      assert {:error, {:invalid_block, "bogus"}} =
               RPC.get_proof(@valid_address, [], block: "bogus")
    end

    test "accepts empty storage_keys list (passes input validation)" do
      result = RPC.get_proof(@valid_address, [], rpc_url: "http://localhost:1")
      refute match?({:error, {:invalid_storage_keys, _}}, result)
      refute match?({:error, {:invalid_address, _}}, result)
    end

    test "accepts populated storage_keys list (passes input validation)" do
      result = RPC.get_proof(@valid_address, [@valid_storage_key], rpc_url: "http://localhost:1")
      refute match?({:error, {:invalid_storage_keys, _}}, result)
      refute match?({:error, {:invalid_storage_key, _}}, result)
    end
  end

  describe "get_proof!/3" do
    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/get_proof failed.*invalid_address/, fn ->
        RPC.get_proof!("no_prefix", [])
      end
    end

    test "raises on invalid storage key" do
      assert_raise RuntimeError, ~r/get_proof failed.*invalid_storage_key/, fn ->
        RPC.get_proof!("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045", ["0x1234"])
      end
    end
  end

  describe "base_fee/1 block validation" do
    test "rejects an invalid :block value before any network call" do
      assert {:error, {:invalid_block_id, :bogus}} = RPC.base_fee(block: :bogus)
    end

    test "accepts a block tag (passes input validation)" do
      result = RPC.base_fee(block: "latest", rpc_url: "http://localhost:1")
      refute match?({:error, {:invalid_block_id, _}}, result)
    end

    test "accepts an integer block number (passes input validation)" do
      result = RPC.base_fee(block: 20_000_000, rpc_url: "http://localhost:1")
      refute match?({:error, {:invalid_block_id, _}}, result)
    end
  end

  describe "base_fee!/1" do
    test "raises on an invalid :block value" do
      assert_raise RuntimeError, ~r/base_fee failed.*invalid_block_id/, fn ->
        RPC.base_fee!(block: :bogus)
      end
    end
  end

  describe "blob_base_fee/1 (connection failure)" do
    test "returns an rpc_error tuple when the node is unreachable" do
      assert {:error, {:rpc_error, %{message: _}}} =
               RPC.blob_base_fee(rpc_url: "http://localhost:1")
    end
  end

  describe "blob_base_fee!/1" do
    test "raises when the node is unreachable" do
      assert_raise RuntimeError, ~r/blob_base_fee failed/, fn ->
        RPC.blob_base_fee!(rpc_url: "http://localhost:1")
      end
    end
  end

  defp rpc_result_plug(result) do
    fn conn ->
      %{"id" => id} = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()
      Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => id, "result" => result})
    end
  end
end
