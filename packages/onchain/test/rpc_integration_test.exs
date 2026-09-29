defmodule Cartouche.RPC.IntegrationTest do
  @moduledoc """
  Mainnet archive integration tests.

  Hits a real mainnet archive node (default `http://127.0.0.1:8545`, override
  via `CARTOUCHE_LIVE_NODE_URL`). Excluded from `mix test` by default; opt in
  via `mix integration` or `mix test --include integration`.

  Anchor blocks/txs/contracts are pinned to historical mainnet data — the
  chain is immutable, so assertions are deterministic forever.
  """
  use ExUnit.Case, async: true

  import Cartouche.Test.Live, only: [live_opts: 0]

  alias Cartouche.Transaction.Call
  alias Cartouche.Transaction.V1
  alias Cartouche.Transaction.V2
  alias Cartouche.Transaction.V_2930

  @moduletag :integration

  setup_all do
    Cartouche.Test.Live.assert_node_available!()
    :ok
  end

  # ───────────────────────── anchor data ─────────────────────────

  # Pre-London anchor (block 10,000,000)
  @pre_london_block 10_000_000
  @pre_london_hash <<0xAA20F7BDE5BE60603F11A45FC4923AAB7552BE775403FC00C2E6B805E6297DBE::256>>
  @pre_london_parent <<0x966BF6849DA92FF2A0E3DB9A371F5B9F07DD6001E2770A4269A5C134F1BF9C4C::256>>
  @pre_london_miner <<0xEA674FDDE714FD979DE3EDF0F56AA9716B898EC8::160>>
  @pre_london_gas_limit 0x98705C
  @pre_london_gas_used 0x9824B3
  @pre_london_timestamp 0x5EB01705

  # Post-London / pre-Shanghai (block 15,000,000)
  @post_london_block 15_000_000
  @post_london_hash <<0x9A71A95BE3FE957457B11817587E5AF4C7E24836D5B383C430FF25B9286A457F::256>>
  @post_london_parent <<0x93A8A23A2F5296DB7251AB4C5E9B10BDC5A6C9C4ED56FB230DC729D3DC03A138::256>>
  @post_london_miner <<0xEA674FDDE714FD979DE3EDF0F56AA9716B898EC8::160>>
  @post_london_gas_limit 0x1C9C380
  @post_london_gas_used 0x1C9BED2
  @post_london_timestamp 0x62B12CC4

  # Post-Shanghai / pre-Cancun (block 18,000,000)
  @post_shanghai_block 18_000_000
  @post_shanghai_hash <<0x95B198E154ACBFC64109DFD22D8224FE927FD8DFDEDFAE01587674482BA4BAF3::256>>
  @post_shanghai_parent <<0x198723E0DDF20153951C6304093CBD97FD306C5DB03287C5586C0430A986080D::256>>
  @post_shanghai_miner <<0xDAFEA492D9C6733AE3D56B7ED1ADB60692C98BC5::160>>
  @post_shanghai_gas_limit 0x1C9C380
  @post_shanghai_gas_used 0xF7E9AB
  @post_shanghai_timestamp 0x64EA268F

  # Post-Cancun (block 20,000,000)
  @post_cancun_block 20_000_000
  @post_cancun_hash <<0xD24FD73F794058A3807DB926D8898C6481E902B7EDB91CE0D479D6760F276183::256>>
  @post_cancun_parent <<0xB390D63AAC03BBEF75DE888D16BD56B91C9291C2A7E38D36AC24731351522BD1::256>>
  @post_cancun_miner <<0x95222290DD7278AA3DDD389CC1E1D165CC4BAFE5::160>>
  @post_cancun_gas_limit 0x1C9C380
  @post_cancun_gas_used 0xA9371C
  @post_cancun_timestamp 0x665BA27F

  # Type-0 (legacy) receipt anchor — first tx of block 10,000,000, simple ETH transfer
  @type_0_receipt_hash <<0x4A1E3E3A2AA4AA79A777D0AE3E2C3A6DE158226134123F6C14334964C6EC70CF::256>>
  @type_0_receipt_block 10_000_000
  @type_0_receipt_gas_used 0x5208

  # Type-2 (EIP-1559) receipt anchor — first tx of block 18,000,000, has 1 log
  @type_2_receipt_hash <<0x16E199673891DF518E25DB2EF5320155DA82A3DD71A677E7D84363251885D133::256>>
  @type_2_receipt_block 18_000_000
  @type_2_receipt_gas_used 0xEC18
  @type_2_receipt_effective_gas_price 0x54A485839

  # Type-3 (EIP-4844 blob) receipt anchor — blob tx after Dencun activation.
  @type_3_receipt_hash <<0xBBC6C82F2D81479E2A7FFA61529FBA4BD4671A8AEFB69A261F6A9B07E46B7F79::256>>
  @type_3_receipt_block 19_449_343
  @type_3_receipt_gas_used 0x2A8E4
  @type_3_receipt_blob_gas_used 0x20_000
  @type_3_receipt_blob_gas_price 0x1

  # Type-1 (EIP-2930 access-list) transaction anchor — block 20,000,000 has
  # exactly one type-1 transaction at index 0x6d.
  @type_1_block @post_cancun_block
  @type_1_gas_price 0x12A522A31

  # Type-4 (EIP-7702) trace anchor — delegation tx post-Pectra. Top-level action
  # remains a CALL because EIP-7702 ships no new opcode mnemonics; delegation
  # executes through the existing CALL-family.
  @type_4_trace_hash <<0xABBB91F9F26DE50D689EEF62092AF9693CAA92D8CD18D813310F2F43E87CB423::256>>
  @type_4_trace_block 23_600_000

  # CREATE trace anchor — contract-deployment tx at block 18,000,000.
  # Exercises `Cartouche.Trace.Action.deserialize/1`'s `"init"` clause: action.init
  # carries the constructor bytecode, and the trace's result_address/result_code
  # carry the deployed address + runtime bytecode.
  @create_trace_hash <<0x24578BF2676FABD01269543DDA61E53496A3282B1D9794DDB141319578052359::256>>
  @create_trace_block 18_000_000

  # SELFDESTRUCT trace anchor — pre-Cancun (block < 19,426,587 to avoid the
  # EIP-6780 no-op). The CHI gas-token (0x000000…1c) free-up at block 11,500,000
  # produces 4 internal "suicide" actions inside a 27-trace tx, exercising
  # `Trace.Action.deserialize/1`'s `"refundAddress"` clause.
  @selfdestruct_trace_hash <<0x2FA0398F9B38B1510B6618713769124D1D42CB32F3D81773B708389DC70F33DD::256>>
  @selfdestruct_trace_block 11_500_000

  # WETH9 anchor at block 18,000,000
  @weth9 <<0xC02AAA39B223FE8D0A0E5C4F27EAD9083C756CC2::160>>
  @weth9_anchor_block 18_000_000
  @weth9_code_hash <<0xD0A06B12AC47863B5C7BE4185C2DEAAD1C61557033F56C7D4EA74429CBB25E23::256>>
  @weth9_code_byte_length 3124
  @weth9_balance 0x2B30B5DBA159D35B4FEC1
  @weth9_nonce 0x1
  @weth9_total_supply 0x2B30B5DBA159D35B4FEC1
  @weth9_total_supply_selector <<0x18, 0x16, 0x0D, 0xDD>>
  @weth9_balance_of_zero_call <<0x70A08231::32, 0::256>>
  @weth9_zero_balance_storage_key <<0x3617319A054D772F909F7C479A2CEBE5066E836A939412E32403C99029B92EFF::256>>
  @weth9_withdraw_max_call <<0x2E1A7D4D::32, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF::256>>
  @weth9_access_list_gas_used 0x65AA
  @weth9_revert_access_list_gas_used 0x5DEB

  # feeHistory anchor at block 18,000,000
  @fee_history_newest_block 18_000_000
  @fee_history_block_count 4
  @fee_history_oldest_block 0x112A87D

  # EIP-1559 and EIP-4844 constants used only to independently verify the node reads.
  @base_fee_elasticity_multiplier 2
  @base_fee_change_denominator 8
  @minimum_blob_base_fee 1
  @blob_gas_per_blob 131_072
  @blob_base_cost 8_192
  @stable_head_attempts 3

  describe "chain-level reads" do
    test "eth_chainId returns 1 (mainnet)" do
      assert {:ok, 1} = Cartouche.RPC.eth_chain_id(live_opts())
    end

    test "eth_blockNumber is past archive baseline" do
      assert {:ok, n} = Cartouche.RPC.eth_block_number(live_opts())
      assert is_integer(n)
      assert n > 19_000_000
    end

    test "eth_gasPrice > 0" do
      assert {:ok, p} = Cartouche.RPC.gas_price(live_opts())
      assert is_integer(p)
      assert p > 0
    end

    test "eth_maxPriorityFeePerGas >= 0" do
      assert {:ok, p} = Cartouche.RPC.max_priority_fee_per_gas(live_opts())
      assert is_integer(p)
      assert p >= 0
    end

    test "eth_config reports mainnet fork constants" do
      config = live_result!("eth_config", Cartouche.RPC.eth_config(live_opts()))

      assert config.current.chain_id == 1
      assert byte_size(config.current.fork_id) == 4
      assert config.current.precompiles["KZG_POINT_EVALUATION"] == <<10::160>>

      assert config.current.system_contracts["BEACON_ROOTS_ADDRESS"] ==
               <<0x000F3DF6D732807EF1319FB7B8BB8522D0BEAC02::160>>

      assert config.current.blob_schedule.target > 0
      assert config.current.blob_schedule.max >= config.current.blob_schedule.target
    end

    test "eth_capabilities reports an archive node and a real canonical head" do
      capabilities = live_result!("eth_capabilities", Cartouche.RPC.eth_capabilities(live_opts()))

      block =
        live_result!("eth_getBlockByNumber", Cartouche.RPC.get_block_by_number(capabilities.head.number, live_opts()))

      assert block.hash == capabilities.head.hash
      assert capabilities.state.disabled == false
      assert capabilities.state.oldest_block == 0
      assert capabilities.blocks.disabled == false
      assert capabilities.blocks.oldest_block == 0
      assert capabilities.stateproofs.disabled == false
    end
  end

  describe "block reads at fork-tier anchors" do
    test "pre-London (block 10,000,000) by number" do
      assert {:ok, b} = Cartouche.RPC.get_block_by_number(@pre_london_block, live_opts())
      assert b.number == @pre_london_block
      assert b.hash == @pre_london_hash
      assert b.parent_hash == @pre_london_parent
      assert b.miner == @pre_london_miner
      assert b.gas_limit == @pre_london_gas_limit
      assert b.gas_used == @pre_london_gas_used
      assert b.timestamp == @pre_london_timestamp
    end

    test "pre-London (block 10,000,000) by hash" do
      assert {:ok, b} = Cartouche.RPC.get_block_by_hash(@pre_london_hash, live_opts())
      assert b.number == @pre_london_block
      assert b.hash == @pre_london_hash
    end

    test "post-London (block 15,000,000) by number" do
      assert {:ok, b} = Cartouche.RPC.get_block_by_number(@post_london_block, live_opts())
      assert b.number == @post_london_block
      assert b.hash == @post_london_hash
      assert b.parent_hash == @post_london_parent
      assert b.miner == @post_london_miner
      assert b.gas_limit == @post_london_gas_limit
      assert b.gas_used == @post_london_gas_used
      assert b.timestamp == @post_london_timestamp

      assert is_integer(b.base_fee_per_gas)
      assert b.base_fee_per_gas > 0
    end

    test "post-London (block 15,000,000) by hash" do
      assert {:ok, b} = Cartouche.RPC.get_block_by_hash(@post_london_hash, live_opts())
      assert b.number == @post_london_block
      assert b.hash == @post_london_hash
    end

    test "post-Shanghai (block 18,000,000) by number" do
      assert {:ok, b} = Cartouche.RPC.get_block_by_number(@post_shanghai_block, live_opts())
      assert b.number == @post_shanghai_block
      assert b.hash == @post_shanghai_hash
      assert b.parent_hash == @post_shanghai_parent
      assert b.miner == @post_shanghai_miner
      assert b.gas_limit == @post_shanghai_gas_limit
      assert b.gas_used == @post_shanghai_gas_used
      assert b.timestamp == @post_shanghai_timestamp

      assert is_list(b.withdrawals)
      assert byte_size(b.withdrawals_root) == 32
      # The 18M anchor is well past Shanghai (block ≥ 17,034,870), so a real
      # mainnet block at this height carries at least one validator withdrawal.
      assert [%Cartouche.Block.Withdrawal{} | _] = b.withdrawals
    end

    test "post-Shanghai (block 18,000,000) by hash" do
      assert {:ok, b} = Cartouche.RPC.get_block_by_hash(@post_shanghai_hash, live_opts())
      assert b.number == @post_shanghai_block
      assert b.hash == @post_shanghai_hash
    end

    test "post-Cancun (block 20,000,000) by number" do
      assert {:ok, b} = Cartouche.RPC.get_block_by_number(@post_cancun_block, live_opts())
      assert b.number == @post_cancun_block
      assert b.hash == @post_cancun_hash
      assert b.parent_hash == @post_cancun_parent
      assert b.miner == @post_cancun_miner
      assert b.gas_limit == @post_cancun_gas_limit
      assert b.gas_used == @post_cancun_gas_used
      assert b.timestamp == @post_cancun_timestamp

      assert byte_size(b.parent_beacon_block_root) == 32
      assert is_integer(b.blob_gas_used)
      assert is_integer(b.excess_blob_gas)
      assert byte_size(b.mix_hash) == 32
    end

    test "post-Cancun (block 20,000,000) by hash" do
      assert {:ok, b} = Cartouche.RPC.get_block_by_hash(@post_cancun_hash, live_opts())
      assert b.number == @post_cancun_block
      assert b.hash == @post_cancun_hash
    end

    # Task 66: pin only deterministic fields — wrapper struct module per
    # element, hash round-trip via `Cartouche.Transaction.V1.t/0`'s `r` /
    # `Cartouche.Transaction.V2.t/0`'s `signature_r` round-trip is too
    # node-variant; instead we pin shape-level invariants (struct module,
    # at least one V1, at least one V2 — block 18M is post-London so the
    # mempool shape mixes both; full-detail decode succeeds end-to-end).
    test "post-Shanghai (block 18,000,000) with `:include_transaction_details, true` — full-detail decode" do
      opts = Keyword.put(live_opts(), :include_transaction_details, true)
      assert {:ok, b} = Cartouche.RPC.get_block_by_number(@post_shanghai_block, opts)

      assert b.number == @post_shanghai_block
      assert b.hash == @post_shanghai_hash
      assert is_list(b.transactions)
      assert b.transactions != []

      # Every element must be one of the supported Vn structs (no leftover
      # raw maps or hash strings); struct-module dispatch verified per-element.
      assert Enum.all?(b.transactions, fn tx ->
               case tx do
                 %V1{} -> true
                 %V2{} -> true
                 %Cartouche.Transaction.V3{} -> true
                 %Cartouche.Transaction.V4{} -> true
                 _other -> false
               end
             end)

      # Block 18,000,000 is post-London — by historical mempool composition
      # it carries both legacy (V1) and EIP-1559 (V2) transactions. We
      # don't pin counts (mempool variance across nodes / re-orgs), only
      # presence — both shapes must round-trip through `from_json/1`.
      assert Enum.any?(b.transactions, &match?(%V1{}, &1))
      assert Enum.any?(b.transactions, &match?(%V2{}, &1))
    end

    test "post-Cancun (block 20,000,000) includes the pinned EIP-2930 type-1 transaction" do
      opts = Keyword.put(live_opts(), :include_transaction_details, true)
      assert {:ok, b} = Cartouche.RPC.get_block_by_number(@type_1_block, opts)

      assert b.number == @type_1_block
      assert b.hash == @post_cancun_hash

      type_1_transactions = Enum.filter(b.transactions, &match?(%V_2930{}, &1))
      assert [tx] = type_1_transactions
      assert tx.chain_id == 1
      assert tx.gas_price == @type_1_gas_price
      assert tx.destination == <<0xC02953F316C5C18808E2D3961424F952788D69F5::160>>
      assert tx.amount == 19_999_050_487_900_000
      assert tx.access_list == []
    end

    # Hash-only mode — ensures `:include_transaction_details, false` (and
    # the default-omitted case) still preserves the wire String.t() hash
    # shape per the @type t/0 union after the Task 66 widening.
    test "post-Shanghai (block 18,000,000) with `:include_transaction_details, false` — hashes preserved" do
      opts = Keyword.put(live_opts(), :include_transaction_details, false)
      assert {:ok, b} = Cartouche.RPC.get_block_by_number(@post_shanghai_block, opts)

      assert is_list(b.transactions)
      assert b.transactions != []
      assert Enum.all?(b.transactions, &is_binary/1)
      # Each element is an 0x-prefixed 32-byte hash hex string (66 chars).
      assert Enum.all?(b.transactions, fn h ->
               String.starts_with?(h, "0x") and String.length(h) == 66
             end)
    end
  end

  describe "receipt reads" do
    test "type-0 (legacy) receipt at block 10,000,000" do
      assert {:ok, r} = Cartouche.RPC.get_trx_receipt(@type_0_receipt_hash, live_opts())
      assert r.transaction_hash == @type_0_receipt_hash
      assert r.block_number == @type_0_receipt_block
      assert r.status == 1
      assert r.type == 0
      assert r.gas_used == @type_0_receipt_gas_used
      assert r.logs == []
    end

    test "type-2 (EIP-1559) receipt at block 18,000,000" do
      assert {:ok, r} = Cartouche.RPC.get_trx_receipt(@type_2_receipt_hash, live_opts())
      assert r.transaction_hash == @type_2_receipt_hash
      assert r.block_number == @type_2_receipt_block
      assert r.status == 1
      assert r.type == 2
      assert r.gas_used == @type_2_receipt_gas_used
      assert r.effective_gas_price == @type_2_receipt_effective_gas_price
      assert match?([_], r.logs)
      assert r.blob_gas_used == nil
      assert r.blob_gas_price == nil
    end

    test "type-3 (EIP-4844 blob) receipt at block 19,449,343" do
      assert {:ok, r} = Cartouche.RPC.get_trx_receipt(@type_3_receipt_hash, live_opts())
      assert r.transaction_hash == @type_3_receipt_hash
      assert r.block_number == @type_3_receipt_block
      assert r.status == 1
      assert r.type == 3
      assert r.gas_used == @type_3_receipt_gas_used

      assert is_integer(r.blob_gas_used)
      assert r.blob_gas_used == @type_3_receipt_blob_gas_used
      assert r.blob_gas_used > 0

      assert is_integer(r.blob_gas_price)
      assert r.blob_gas_price == @type_3_receipt_blob_gas_price
      assert r.blob_gas_price > 0
    end
  end

  describe "account/code reads (WETH9 at block 18,000,000)" do
    test "eth_getCode returns pinned bytecode" do
      opts = Keyword.put(live_opts(), :block_number, @weth9_anchor_block)
      assert {:ok, code} = Cartouche.RPC.get_code(@weth9, opts)
      assert is_binary(code)
      assert byte_size(code) == @weth9_code_byte_length
      assert <<first, _::binary>> = code
      # 0x60 = PUSH1, valid EVM bytecode prefix
      assert first == 0x60
      assert Cartouche.Hash.keccak(code) == @weth9_code_hash
    end

    test "eth_getBalance pins to historical balance" do
      opts = Keyword.put(live_opts(), :block_number, @weth9_anchor_block)
      assert {:ok, balance} = Cartouche.RPC.get_balance(@weth9, opts)
      assert balance == @weth9_balance
    end

    test "eth_getTransactionCount pins to historical nonce" do
      opts = Keyword.put(live_opts(), :block_number, @weth9_anchor_block)
      assert {:ok, nonce} = Cartouche.RPC.get_transaction_count(@weth9, opts)
      assert nonce == @weth9_nonce
    end
  end

  describe "speculative reads" do
    test "eth_call WETH9.totalSupply() at block 18,000,000" do
      trx = V1.new(0, {0, :gwei}, 100_000, @weth9, 0, @weth9_total_supply_selector)

      opts = Keyword.put(live_opts(), :block_number, @weth9_anchor_block)
      assert {:ok, result} = Cartouche.RPC.call_trx(trx, opts)
      assert is_binary(result)
      assert byte_size(result) == 32
      assert :binary.decode_unsigned(result) == @weth9_total_supply
    end

    test "eth_estimateGas for a simple ETH transfer (~21,000)" do
      # transfer 0 wei to a non-zero EOA, no calldata → intrinsic 21,000 gas
      to = <<0x000000000000000000000000000000000000DEAD::160>>
      trx = V1.new(0, {1, :gwei}, 30_000, to, 0, <<>>)

      assert {:ok, gas} = Cartouche.RPC.estimate_gas(trx, live_opts())
      assert is_integer(gas)
      assert gas == 21_000
    end

    test "eth_createAccessList returns WETH9's pinned balance storage key" do
      call = Call.new(@weth9, @weth9_balance_of_zero_call)
      opts = Keyword.put(live_opts(), :block_number, @weth9_anchor_block)

      assert {:ok,
              %{
                access_list: [{@weth9, [@weth9_zero_balance_storage_key]}],
                gas_used: @weth9_access_list_gas_used
              }} = Cartouche.RPC.create_access_list(call, opts)
    end

    test "eth_createAccessList retains the node's observed WETH9 revert result" do
      call = Call.new(@weth9, @weth9_withdraw_max_call)
      opts = Keyword.put(live_opts(), :block_number, @weth9_anchor_block)

      assert {:ok,
              %{
                access_list: [{@weth9, [@weth9_zero_balance_storage_key]}],
                error: "execution reverted",
                gas_used: @weth9_revert_access_list_gas_used
              }} = Cartouche.RPC.create_access_list(call, opts)
    end
  end

  describe "fee reads" do
    test "eth_baseFee matches the EIP-1559 next-block update rule" do
      {head, base_fee} = stable_head_fee!("eth_baseFee", &Cartouche.RPC.base_fee/1)

      assert base_fee == next_base_fee(head)
    end

    test "eth_blobBaseFee matches the next-block excess update and EIP-4844 fake_exponential" do
      {head, blob_base_fee} = stable_head_fee!("eth_blobBaseFee", &Cartouche.RPC.blob_base_fee/1)
      config = live_result!("eth_config", Cartouche.RPC.eth_config(live_opts()))
      schedule = config.current.blob_schedule
      next_excess_blob_gas = next_excess_blob_gas(head, schedule)

      assert blob_base_fee ==
               fake_exponential(@minimum_blob_base_fee, next_excess_blob_gas, schedule.base_fee_update_fraction)
    end

    test "eth_feeHistory at block 18,000,000 returns expected shape" do
      opts =
        live_opts()
        |> Keyword.put(:block_count, @fee_history_block_count)
        |> Keyword.put(:newest_block, "0x#{Integer.to_string(@fee_history_newest_block, 16)}")
        |> Keyword.put(:reward_percentiles, [25.0, 50.0, 75.0])

      assert {:ok, fh} = Cartouche.RPC.fee_history(opts)

      assert fh.oldest_block == @fee_history_oldest_block
      # block_count + 1
      assert length(fh.base_fee_per_gas) == @fee_history_block_count + 1
      assert length(fh.gas_used_ratio) == @fee_history_block_count
      assert length(fh.reward) == @fee_history_block_count
      assert Enum.all?(fh.reward, &match?([_, _, _], &1))
    end
  end

  describe "trace methods" do
    # Pin: wrapper struct, transaction_hash round-trip, block_number, top-level
    # type/call_type. Shape-only: gas_used (positive int — varies across nodes),
    # subtraces count (depends on internal trace structure).
    test "trace_transaction at type-0 anchor (block 10,000,000, ETH transfer)" do
      assert {:ok, [trace]} = Cartouche.RPC.trace_trx(@type_0_receipt_hash, live_opts())
      assert %Cartouche.Trace{} = trace
      assert trace.transaction_hash == @type_0_receipt_hash
      assert trace.block_number == @type_0_receipt_block
      assert trace.type == "call"
      assert trace.action.call_type == "call"
      # Plain ETH transfer — no subtraces, no contract execution.
      assert trace.subtraces == 0
      assert is_integer(trace.gas_used)
      assert trace.gas_used >= 0
    end

    test "trace_transaction at type-2 anchor (block 18,000,000, contract call)" do
      assert {:ok, traces} = Cartouche.RPC.trace_trx(@type_2_receipt_hash, live_opts())
      assert [%Cartouche.Trace{} = top | _] = traces
      assert top.transaction_hash == @type_2_receipt_hash
      assert top.block_number == @type_2_receipt_block
      assert top.type == "call"
      assert top.action.call_type == "call"
      assert is_integer(top.gas_used)
      assert is_integer(top.subtraces)
      assert top.subtraces >= 0
    end

    test "trace_call WETH9.totalSupply() at block 18,000,000" do
      trx = V1.new(0, {0, :gwei}, 100_000, @weth9, 0, @weth9_total_supply_selector)
      opts = Keyword.put(live_opts(), :block_number, @weth9_anchor_block)

      assert {:ok, %Cartouche.TraceCall{} = result} = Cartouche.RPC.trace_call(trx, opts)
      assert is_binary(result.output)
      assert byte_size(result.output) == 32
      assert :binary.decode_unsigned(result.output) == @weth9_total_supply
      # `state_diff` and `vm_trace` are unsupported — always nil per moduledoc.
      assert result.state_diff == nil
      assert result.vm_trace == nil
      assert [%Cartouche.Trace{} = top | _] = result.trace
      assert top.type == "call"
      assert top.action.call_type == "call"
    end

    test "trace_callMany — two WETH9 reads at block 18,000,000" do
      # balanceOf(address(0)) = 0x70a08231 ++ 32-byte zero-padded zero address.
      balance_of_zero = <<0x70, 0xA0, 0x82, 0x31>> <> <<0::256>>

      trx_total = V1.new(0, {0, :gwei}, 100_000, @weth9, 0, @weth9_total_supply_selector)
      trx_balance = V1.new(0, {0, :gwei}, 100_000, @weth9, 0, balance_of_zero)
      opts = Keyword.put(live_opts(), :block_number, @weth9_anchor_block)

      assert {:ok, [first, second]} = Cartouche.RPC.trace_call_many([trx_total, trx_balance], opts)
      assert %Cartouche.TraceCall{} = first
      assert %Cartouche.TraceCall{} = second

      assert byte_size(first.output) == 32
      assert :binary.decode_unsigned(first.output) == @weth9_total_supply

      # balanceOf(0x0) returns a uint256; value not pinned (any address can hold
      # WETH historically), but the wire shape is always a 32-byte word.
      assert byte_size(second.output) == 32
    end

    # `debug_traceCall` lives in `test/rpc_debug_namespace_test.exs` under its
    # own `:debug_namespace` tag — the archive node keeps the `debug_*`
    # namespace disabled for security, so it cannot pass here. See that file's
    # moduledoc for the rationale and how to opt in.

    test "trace_transaction at type-4 (EIP-7702) anchor — delegation tx" do
      assert {:ok, traces} = Cartouche.RPC.trace_trx(@type_4_trace_hash, live_opts())
      assert [%Cartouche.Trace{} = top | _] = traces
      assert top.transaction_hash == @type_4_trace_hash
      assert top.block_number == @type_4_trace_block
      # 7702 delegation runs through the existing CALL-family — no new opcodes,
      # so the wrapper action stays a call. This is the precise property that
      # justifies leaving the `lib/cartouche/debug_trace.ex` opcode whitelist
      # unchanged for Pectra (verified under Task 68 closure).
      assert top.type == "call"
      assert top.action.call_type == "call"
    end

    test "trace_transaction at CREATE anchor — exercises action.init / result_address / result_code" do
      assert {:ok, [%Cartouche.Trace{} = trace]} =
               Cartouche.RPC.trace_trx(@create_trace_hash, live_opts())

      assert trace.transaction_hash == @create_trace_hash
      assert trace.block_number == @create_trace_block

      # CREATE-action shape: `type == "create"`, action.init carries the
      # constructor bytecode, action.call_type is nil, and the result fields
      # carry the deployed contract address + runtime bytecode.
      assert trace.type == "create"
      assert trace.action.call_type == nil
      assert is_binary(trace.action.init)
      assert byte_size(trace.action.init) > 0

      assert is_binary(trace.result_address)
      assert byte_size(trace.result_address) == 20
      assert is_binary(trace.result_code)
      assert byte_size(trace.result_code) > 0
    end

    test "trace_transaction at SELFDESTRUCT anchor — exercises action.refund_address" do
      assert {:ok, traces} = Cartouche.RPC.trace_trx(@selfdestruct_trace_hash, live_opts())

      # CHI-token gas refund tx at block 11,500,000 — internal "suicide" actions.
      # We don't pin the count (depends on how many CHI tokens were freed in the
      # tx), only that at least one suicide action surfaces and its shape is
      # correct.
      suicides = Enum.filter(traces, fn t -> t.type == "suicide" end)
      assert suicides != []

      Enum.each(suicides, fn trace ->
        assert %Cartouche.Trace{} = trace
        assert trace.transaction_hash == @selfdestruct_trace_hash
        assert trace.block_number == @selfdestruct_trace_block
        assert is_binary(trace.action.refund_address)
        assert byte_size(trace.action.refund_address) == 20
        assert is_integer(trace.action.balance)
        assert trace.action.balance >= 0
      end)
    end
  end

  @spec live_result!(String.t(), {:ok, term()} | {:error, term()}) :: term() | no_return()
  defp live_result!(_method, {:ok, result}), do: result
  defp live_result!(method, {:error, error}), do: flunk("#{method} failed against the live node: #{inspect(error)}")

  @spec stable_head_fee!(String.t(), (Keyword.t() -> {:ok, non_neg_integer()} | {:error, term()})) ::
          {Cartouche.Block.t(), non_neg_integer()} | no_return()
  defp stable_head_fee!(method, fee_reader), do: stable_head_fee!(method, fee_reader, @stable_head_attempts)

  @spec stable_head_fee!(String.t(), (Keyword.t() -> {:ok, non_neg_integer()} | {:error, term()}), pos_integer()) ::
          {Cartouche.Block.t(), non_neg_integer()} | no_return()
  defp stable_head_fee!(method, fee_reader, attempts_left) do
    before = live_result!("eth_getBlockByNumber", Cartouche.RPC.get_block_by_number("latest", live_opts()))
    fee = live_result!(method, fee_reader.(live_opts()))
    after_read = live_result!("eth_getBlockByNumber", Cartouche.RPC.get_block_by_number("latest", live_opts()))

    if before.hash == after_read.hash do
      {before, fee}
    else
      retry_stable_head_fee!(method, fee_reader, attempts_left)
    end
  end

  @spec retry_stable_head_fee!(
          String.t(),
          (Keyword.t() -> {:ok, non_neg_integer()} | {:error, term()}),
          pos_integer()
        ) :: {Cartouche.Block.t(), non_neg_integer()} | no_return()
  defp retry_stable_head_fee!(method, fee_reader, attempts_left) when attempts_left > 1 do
    stable_head_fee!(method, fee_reader, attempts_left - 1)
  end

  defp retry_stable_head_fee!(method, _fee_reader, 1) do
    flunk("#{method} could not be compared at a stable head after #{@stable_head_attempts} attempts")
  end

  @spec next_base_fee(Cartouche.Block.t()) :: non_neg_integer()
  defp next_base_fee(block) do
    gas_target = div(block.gas_limit, @base_fee_elasticity_multiplier)
    base_fee_delta(block.base_fee_per_gas, block.gas_used - gas_target, gas_target)
  end

  @spec base_fee_delta(non_neg_integer(), integer(), pos_integer()) :: non_neg_integer()
  defp base_fee_delta(base_fee, 0, _gas_target), do: base_fee

  defp base_fee_delta(base_fee, gas_delta, gas_target) when gas_delta > 0 do
    increase = max(div(base_fee * gas_delta, gas_target * @base_fee_change_denominator), 1)
    base_fee + increase
  end

  defp base_fee_delta(base_fee, gas_delta, gas_target) do
    base_fee - div(base_fee * -gas_delta, gas_target * @base_fee_change_denominator)
  end

  @spec next_excess_blob_gas(Cartouche.Block.t(), Cartouche.RPC.Configuration.BlobSchedule.t()) ::
          non_neg_integer()
  defp next_excess_blob_gas(block, schedule) do
    # Post-Fusaka EIP-7918 changes the child excess update when execution gas
    # sets the blob reserve price; eth_blobBaseFee reflects that child price.
    target_blob_gas = @blob_gas_per_blob * schedule.target
    total_blob_gas = block.excess_blob_gas + block.blob_gas_used

    parent_blob_base_fee =
      fake_exponential(@minimum_blob_base_fee, block.excess_blob_gas, schedule.base_fee_update_fraction)

    cond do
      total_blob_gas < target_blob_gas ->
        0

      @blob_base_cost * block.base_fee_per_gas > @blob_gas_per_blob * parent_blob_base_fee ->
        block.excess_blob_gas + div(block.blob_gas_used * (schedule.max - schedule.target), schedule.max)

      true ->
        total_blob_gas - target_blob_gas
    end
  end

  @spec fake_exponential(non_neg_integer(), non_neg_integer(), pos_integer()) :: non_neg_integer()
  defp fake_exponential(factor, numerator, denominator) do
    0 |> fake_exponential_(factor * denominator, numerator, denominator, 1) |> div(denominator)
  end

  @spec fake_exponential_(non_neg_integer(), non_neg_integer(), non_neg_integer(), pos_integer(), pos_integer()) ::
          non_neg_integer()
  defp fake_exponential_(output, 0, _numerator, _denominator, _iteration), do: output

  defp fake_exponential_(output, numerator_accumulator, numerator, denominator, iteration) do
    fake_exponential_(
      output + numerator_accumulator,
      div(numerator_accumulator * numerator, denominator * iteration),
      numerator,
      denominator,
      iteration + 1
    )
  end
end
