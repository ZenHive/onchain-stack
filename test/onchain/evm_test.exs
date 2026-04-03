defmodule Onchain.EVMTest do
  use ExUnit.Case, async: true

  alias Onchain.EVM

  @valid_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @valid_data "0x18160ddd"
  @valid_rpc_url "https://eth-mainnet.example.com"

  describe "simulate_call/3 input validation" do
    test "returns error when rpc_url is missing" do
      assert {:error, {:evm_error, msg}} = EVM.simulate_call(@valid_address, @valid_data, [])
      assert msg =~ "rpc_url"
    end

    test "returns error for invalid address" do
      assert {:error, {:invalid_address, "not-an-address"}} =
               EVM.simulate_call("not-an-address", @valid_data, rpc_url: @valid_rpc_url)
    end

    test "returns error for invalid data (no 0x prefix)" do
      assert {:error, {:invalid_data, "18160ddd"}} =
               EVM.simulate_call(@valid_address, "18160ddd", rpc_url: @valid_rpc_url)
    end

    test "returns error for invalid data (bad hex)" do
      assert {:error, {:invalid_data, "0xZZZZ"}} =
               EVM.simulate_call(@valid_address, "0xZZZZ", rpc_url: @valid_rpc_url)
    end

    test "accepts 20-byte binary address" do
      binary_addr = <<160, 184, 105, 145, 198, 33, 139, 54, 193, 209, 157, 74, 46, 158, 176, 206, 54, 6, 235, 72>>

      # Should pass validation and fail at NIF level (bad RPC URL), not at address validation
      result = EVM.simulate_call(binary_addr, @valid_data, rpc_url: @valid_rpc_url)

      case result do
        {:error, {:fork_error, _}} -> :ok
        {:error, {:evm_error, _}} -> :ok
        {:error, {:invalid_address, _}} -> flunk("Binary address should be accepted")
        other -> flunk("Unexpected result: #{inspect(other)}")
      end
    end
  end

  describe "simulate_call/3 :from validation" do
    test "returns error for invalid :from address" do
      assert {:error, {:invalid_address, "not-valid"}} =
               EVM.simulate_call(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 from: "not-valid"
               )
    end
  end

  describe "simulate_call!/3" do
    test "raises on missing rpc_url" do
      assert_raise RuntimeError, ~r/simulate_call failed/, fn ->
        EVM.simulate_call!(@valid_address, @valid_data, [])
      end
    end

    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/simulate_call failed/, fn ->
        EVM.simulate_call!("bad", @valid_data, rpc_url: @valid_rpc_url)
      end
    end
  end

  describe "simulate_transaction/3 input validation" do
    test "returns error when rpc_url is missing" do
      assert {:error, {:evm_error, _}} = EVM.simulate_transaction(@valid_address, @valid_data, [])
    end

    test "returns error for invalid address" do
      assert {:error, {:invalid_address, _}} =
               EVM.simulate_transaction("bad", @valid_data, rpc_url: @valid_rpc_url)
    end
  end

  describe "simulate_transaction!/3" do
    test "raises on error" do
      assert_raise RuntimeError, ~r/simulate_transaction failed/, fn ->
        EVM.simulate_transaction!(@valid_address, @valid_data, [])
      end
    end
  end

  describe "simulate_batch/2 input validation" do
    test "returns error when rpc_url is missing" do
      calls = [{@valid_address, @valid_data}]
      assert {:error, {:evm_error, _}} = EVM.simulate_batch(calls, [])
    end

    test "returns error for invalid address in calls list" do
      calls = [{"bad-addr", @valid_data}]
      assert {:error, {:invalid_address, _}} = EVM.simulate_batch(calls, rpc_url: @valid_rpc_url)
    end

    test "returns error for invalid data in calls list" do
      calls = [{@valid_address, "no-prefix"}]
      assert {:error, {:invalid_data, _}} = EVM.simulate_batch(calls, rpc_url: @valid_rpc_url)
    end
  end

  describe "simulate_batch!/2" do
    test "raises on error" do
      assert_raise RuntimeError, ~r/simulate_batch failed/, fn ->
        EVM.simulate_batch!([{@valid_address, @valid_data}], [])
      end
    end
  end
end
