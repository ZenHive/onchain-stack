defmodule Onchain.Aave.DebtTokenTest do
  use ExUnit.Case, async: false

  alias Onchain.Aave.DebtToken

  @valid_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @valid_address_2 "0xF380B8F1e63e2BEd7CA329CA1FdDbC39B52cC0d3"
  @test_amount 1_000_000

  @approve_delegation_selector <<0xC0, 0x4A, 0x8A, 0x10>>

  describe "debt_token_address/3" do
    test "returns error for invalid asset address" do
      assert {:error, {:invalid_address, "bad_asset"}} =
               DebtToken.debt_token_address("bad_asset", :variable)
    end

    test "returns error for unsupported network" do
      assert {:error, {:unsupported_network, :solana}} =
               DebtToken.debt_token_address(@valid_address, :variable, network: :solana)
    end

    test "returns error for unsupported network with stable rate mode" do
      assert {:error, {:unsupported_network, :solana}} =
               DebtToken.debt_token_address(@valid_address, :stable, network: :solana)
    end

    test "returns error for invalid interest_rate_mode" do
      assert {:error, {:invalid_interest_rate_mode, :fixed}} =
               DebtToken.debt_token_address(@valid_address, :fixed)
    end
  end

  describe "approve_delegation/4" do
    test "returns error for invalid debt_token address" do
      assert {:error, {:invalid_address, "bad_token"}} =
               DebtToken.approve_delegation("bad_token", @valid_address_2, @test_amount, [])
    end

    test "returns error for invalid delegatee address" do
      assert {:error, {:invalid_address, "bad_delegatee"}} =
               DebtToken.approve_delegation(@valid_address, "bad_delegatee", @test_amount, [])
    end
  end

  describe "borrow_allowance/3" do
    test "returns error for invalid debt_token address" do
      assert {:error, {:invalid_address, "bad_token"}} =
               DebtToken.borrow_allowance("bad_token", @valid_address, @valid_address_2)
    end

    test "returns error for invalid from_user address" do
      assert {:error, {:invalid_address, "bad_from"}} =
               DebtToken.borrow_allowance(@valid_address, "bad_from", @valid_address_2)
    end

    test "returns error for invalid to_user address" do
      assert {:error, {:invalid_address, "bad_to"}} =
               DebtToken.borrow_allowance(@valid_address, @valid_address_2, "bad_to")
    end
  end

  describe "approve_delegation calldata verification" do
    test "sends to debt token with correct selector and arguments" do
      {to, calldata} =
        capture_signer_args(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   DebtToken.approve_delegation(
                     @valid_address,
                     @valid_address_2,
                     @test_amount,
                     []
                   )
        end)

      assert to == @valid_address

      <<selector::binary-size(4), args::binary>> = calldata
      assert selector == @approve_delegation_selector

      <<delegatee_arg::binary-size(32), amount_arg::binary-size(32)>> = args

      {:ok, delegatee_bin} = Onchain.Address.validate(@valid_address_2)

      assert :binary.decode_unsigned(delegatee_arg) ==
               :binary.decode_unsigned(pad_left(delegatee_bin))

      assert :binary.decode_unsigned(amount_arg) == @test_amount
    end

    test "encodes zero amount for revocation" do
      {_to, calldata} =
        capture_signer_args(fn ->
          assert {:error, {:missing_option, :private_key}} =
                   DebtToken.approve_delegation(@valid_address, @valid_address_2, 0, [])
        end)

      <<_selector::binary-size(4), _delegatee::binary-size(32), amount_arg::binary-size(32)>> =
        calldata

      assert :binary.decode_unsigned(amount_arg) == 0
    end
  end

  defp capture_signer_args(fun) do
    {to, calldata, _opts} = Onchain.TraceCase.capture_signer_call(fun)
    {to, calldata}
  end

  defp pad_left(bin) when byte_size(bin) <= 32 do
    padding_size = 32 - byte_size(bin)
    <<0::size(padding_size * 8), bin::binary>>
  end
end
