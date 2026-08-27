defmodule Onchain.Tempo.TIP20Test do
  use ExUnit.Case, async: true

  alias Onchain.Tempo.TIP20

  describe "selectors" do
    test "transfer_selector is 4 bytes" do
      assert byte_size(TIP20.transfer_selector()) == 4
      assert TIP20.transfer_selector() == <<0xA9, 0x05, 0x9C, 0xBB>>
    end

    test "transfer_with_memo_selector is 4 bytes" do
      assert byte_size(TIP20.transfer_with_memo_selector()) == 4
      assert TIP20.transfer_with_memo_selector() == <<0x95, 0x77, 0x7D, 0x59>>
    end

    test "approve_selector is 4 bytes" do
      assert byte_size(TIP20.approve_selector()) == 4
      assert TIP20.approve_selector() == <<0x09, 0x5E, 0xA7, 0xB3>>
    end

    test "swap_exact_amount_out_selector is 4 bytes" do
      assert byte_size(TIP20.swap_exact_amount_out_selector()) == 4
      assert TIP20.swap_exact_amount_out_selector() == <<0xF0, 0x12, 0x2B, 0x75>>
    end

    test "balance_of_selector is 4 bytes" do
      assert byte_size(TIP20.balance_of_selector()) == 4
      assert TIP20.balance_of_selector() == <<0x70, 0xA0, 0x82, 0x31>>
    end
  end

  describe "stablecoin_dex_address/0" do
    test "returns 20-byte binary" do
      assert byte_size(TIP20.stablecoin_dex_address()) == 20
    end

    test "starts with 0xDEC0" do
      <<0xDE, 0xC0, _::binary>> = TIP20.stablecoin_dex_address()
    end
  end

  describe "transfer_calldata/2" do
    test "encodes transfer(address,uint256) with correct selector and ABI layout" do
      recipient = TIP20.decode_address("0x70997970c51812dc3a010c7d01b50e0d17dc79c8")
      calldata = TIP20.transfer_calldata(recipient, 1_000_000)

      # 4 (selector) + 32 (address) + 32 (uint256) = 68 bytes
      assert byte_size(calldata) == 68

      <<selector::binary-size(4), _::binary>> = calldata
      assert selector == TIP20.transfer_selector()
    end

    test "encodes amount correctly" do
      recipient = :binary.copy(<<0x01>>, 20)
      calldata = TIP20.transfer_calldata(recipient, 256)

      # Extract amount from last 32 bytes
      <<_::binary-size(36), amount::unsigned-big-size(256)>> = calldata
      assert amount == 256
    end
  end

  describe "transfer_with_memo_calldata/3" do
    test "encodes transferWithMemo(address,uint256,bytes32) with correct layout" do
      recipient = TIP20.decode_address("0x70997970c51812dc3a010c7d01b50e0d17dc79c8")
      memo = :binary.copy(<<0xAB>>, 32)
      calldata = TIP20.transfer_with_memo_calldata(recipient, 500_000, memo)

      # 4 (selector) + 32 (address) + 32 (uint256) + 32 (bytes32) = 100 bytes
      assert byte_size(calldata) == 100

      <<selector::binary-size(4), _::binary>> = calldata
      assert selector == TIP20.transfer_with_memo_selector()
    end
  end

  describe "approve_calldata/2" do
    test "encodes approve(address,uint256) with correct selector" do
      spender = TIP20.decode_address("0xdec0000000000000000000000000000000000000")
      calldata = TIP20.approve_calldata(spender, 1_000_000)

      assert byte_size(calldata) == 68

      <<selector::binary-size(4), _::binary>> = calldata
      assert selector == TIP20.approve_selector()
    end
  end

  describe "balance_of_calldata/1" do
    test "encodes balanceOf(address) with correct selector and left-padded address" do
      owner = TIP20.decode_address("0x70997970c51812dc3a010c7d01b50e0d17dc79c8")
      calldata = TIP20.balance_of_calldata(owner)

      # 4 (selector) + 32 (address) = 36 bytes
      assert byte_size(calldata) == 36

      <<selector::binary-size(4), padding::binary-size(12), addr::binary-size(20)>> = calldata
      assert selector == TIP20.balance_of_selector()
      assert padding == <<0::96>>
      assert addr == owner
    end
  end

  describe "decode_address/1" do
    test "decodes hex with 0x prefix" do
      addr = TIP20.decode_address("0x70997970c51812dc3a010c7d01b50e0d17dc79c8")
      assert byte_size(addr) == 20
    end

    test "decodes hex without 0x prefix" do
      addr = TIP20.decode_address("70997970c51812dc3a010c7d01b50e0d17dc79c8")
      assert byte_size(addr) == 20
    end

    test "decodes mixed case hex" do
      addr = TIP20.decode_address("0x70997970C51812DC3A010C7D01B50E0D17DC79C8")
      assert byte_size(addr) == 20
    end
  end
end
