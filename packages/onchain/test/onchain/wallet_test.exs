defmodule Onchain.WalletTest do
  use ExUnit.Case, async: true

  alias Onchain.Wallet

  # --- Unit tests: input validation pass-through (no network calls) ---

  describe "classify/2 input validation" do
    test "rejects invalid address" do
      assert {:error, {:invalid_address, "0xshort"}} = Wallet.classify("0xshort")
    end

    test "rejects non-binary input" do
      assert {:error, {:invalid_address, 12_345}} = Wallet.classify(12_345)
    end
  end

  describe "classify!/2" do
    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/classify failed/, fn ->
        Wallet.classify!("0xshort")
      end
    end
  end

  describe "balance/2 input validation" do
    test "rejects invalid address" do
      assert {:error, {:invalid_address, "0xshort"}} = Wallet.balance("0xshort")
    end

    test "rejects non-binary input" do
      assert {:error, {:invalid_address, 12_345}} = Wallet.balance(12_345)
    end
  end

  describe "balance!/2" do
    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/balance failed/, fn ->
        Wallet.balance!("0xshort")
      end
    end
  end
end
