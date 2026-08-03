defmodule Onchain.Aave.DebtToken.IntegrationTest do
  use ExUnit.Case, async: false

  # Every sibling *_integration_test.exs carries this; this module was the one
  # that never got it, so its two Sepolia tests ran unconditionally and failed on
  # credential-less CI (`sepolia_rpc_url!/0` raises without ETH_SEPOLIA_RPC_URL).
  @moduletag :integration

  alias Onchain.Aave.DebtToken

  @aave_sepolia_usdc "0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8"
  @delegatee "0xF380B8F1e63e2BEd7CA329CA1FdDbC39B52cC0d3"

  describe "debt_token_address/3 on Sepolia" do
    test "resolves variable and stable debt token addresses for USDC" do
      rpc_url = Onchain.SignerCase.sepolia_rpc_url!()
      opts = [network: :sepolia, rpc_url: rpc_url]

      assert {:ok, variable_debt} = DebtToken.debt_token_address(@aave_sepolia_usdc, :variable, opts)
      assert {:ok, stable_debt} = DebtToken.debt_token_address(@aave_sepolia_usdc, :stable, opts)

      assert String.starts_with?(variable_debt, "0x")
      assert String.starts_with?(stable_debt, "0x")
      refute variable_debt == stable_debt
    end
  end

  describe "borrow_allowance/3 on Sepolia" do
    test "returns zero when no delegation exists" do
      rpc_url = Onchain.SignerCase.sepolia_rpc_url!()
      opts = [network: :sepolia, rpc_url: rpc_url]
      delegator = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

      {:ok, variable_debt} = DebtToken.debt_token_address(@aave_sepolia_usdc, :variable, opts)

      assert {:ok, 0} =
               DebtToken.borrow_allowance(variable_debt, delegator, @delegatee, rpc_url: rpc_url)
    end
  end
end
