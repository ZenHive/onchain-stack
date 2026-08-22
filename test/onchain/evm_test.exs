defmodule Onchain.EVMTest do
  use ExUnit.Case, async: true

  alias Onchain.EVM

  @valid_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @valid_data "0x18160ddd"
  @valid_rpc_url "https://eth-mainnet.example.com"

  describe "simulate_call/3 input validation" do
    test "returns error when opts default to empty" do
      assert {:error, {:invalid_rpc_url, :missing}} =
               EVM.simulate_call(@valid_address, @valid_data)
    end

    test "returns error when rpc_url is missing" do
      assert {:error, {:invalid_rpc_url, :missing}} =
               EVM.simulate_call(@valid_address, @valid_data, [])
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

  describe "simulate_call/3 rpc_url validation" do
    test "returns error for empty rpc_url" do
      assert {:error, {:invalid_rpc_url, :empty}} =
               EVM.simulate_call(@valid_address, @valid_data, rpc_url: "")
    end

    test "returns error for whitespace-only rpc_url" do
      assert {:error, {:invalid_rpc_url, :empty}} =
               EVM.simulate_call(@valid_address, @valid_data, rpc_url: "   ")
    end

    test "returns error for non-HTTP scheme" do
      assert {:error, {:invalid_rpc_url, {:invalid_scheme, "ftp://example.com"}}} =
               EVM.simulate_call(@valid_address, @valid_data, rpc_url: "ftp://example.com")
    end

    test "returns error for bare string without scheme" do
      assert {:error, {:invalid_rpc_url, {:invalid_scheme, "not-a-url"}}} =
               EVM.simulate_call(@valid_address, @valid_data, rpc_url: "not-a-url")
    end

    test "returns error for non-string rpc_url" do
      assert {:error, {:invalid_rpc_url, {:not_a_string, 12_345}}} =
               EVM.simulate_call(@valid_address, @valid_data, rpc_url: 12_345)
    end

    test "returns error for http:// with no host" do
      assert {:error, {:invalid_rpc_url, {:missing_host, "http://"}}} =
               EVM.simulate_call(@valid_address, @valid_data, rpc_url: "http://")
    end

    test "returns error for https:// with no host" do
      assert {:error, {:invalid_rpc_url, {:missing_host, "https://"}}} =
               EVM.simulate_call(@valid_address, @valid_data, rpc_url: "https://")
    end

    test "returns error for malformed URI characters" do
      assert {:error, {:invalid_rpc_url, {:invalid_scheme, "https://exa<mple.com"}}} =
               EVM.simulate_call(@valid_address, @valid_data, rpc_url: "https://exa<mple.com")
    end

    test "accepts http:// URL" do
      result = EVM.simulate_call(@valid_address, @valid_data, rpc_url: "http://localhost:8545")
      refute match?({:error, {:invalid_rpc_url, _}}, result)
    end

    test "accepts https:// URL" do
      result = EVM.simulate_call(@valid_address, @valid_data, rpc_url: "https://eth.example.com")
      refute match?({:error, {:invalid_rpc_url, _}}, result)
    end
  end

  describe "simulate_call/3 block validation" do
    test "accepts string block tag 'latest'" do
      result = EVM.simulate_call(@valid_address, @valid_data, rpc_url: @valid_rpc_url, block: "latest")
      refute match?({:error, {:invalid_block, _}}, result)
    end

    test "accepts string block tag 'finalized'" do
      result = EVM.simulate_call(@valid_address, @valid_data, rpc_url: @valid_rpc_url, block: "finalized")
      refute match?({:error, {:invalid_block, _}}, result)
    end

    test "accepts string block tag 'safe'" do
      result = EVM.simulate_call(@valid_address, @valid_data, rpc_url: @valid_rpc_url, block: "safe")
      refute match?({:error, {:invalid_block, _}}, result)
    end

    test "accepts string block tag 'earliest'" do
      result = EVM.simulate_call(@valid_address, @valid_data, rpc_url: @valid_rpc_url, block: "earliest")
      refute match?({:error, {:invalid_block, _}}, result)
    end

    test "accepts string block tag 'pending'" do
      result = EVM.simulate_call(@valid_address, @valid_data, rpc_url: @valid_rpc_url, block: "pending")
      refute match?({:error, {:invalid_block, _}}, result)
    end

    test "accepts hex block string" do
      result = EVM.simulate_call(@valid_address, @valid_data, rpc_url: @valid_rpc_url, block: "0x1234")
      refute match?({:error, {:invalid_block, _}}, result)
    end

    test "accepts integer block number" do
      result = EVM.simulate_call(@valid_address, @valid_data, rpc_url: @valid_rpc_url, block: 12_345_678)
      refute match?({:error, {:invalid_block, _}}, result)
    end

    test "rejects invalid block string" do
      assert {:error, {:invalid_block, "bogus"}} =
               EVM.simulate_call(@valid_address, @valid_data, rpc_url: @valid_rpc_url, block: "bogus")
    end

    test "rejects negative integer block" do
      assert {:error, {:invalid_block, -1}} =
               EVM.simulate_call(@valid_address, @valid_data, rpc_url: @valid_rpc_url, block: -1)
    end

    test "rejects invalid hex block" do
      assert {:error, {:invalid_block, "0xZZZZ"}} =
               EVM.simulate_call(@valid_address, @valid_data, rpc_url: @valid_rpc_url, block: "0xZZZZ")
    end

    test "rejects bare 0x block" do
      assert {:error, {:invalid_block, "0x"}} =
               EVM.simulate_call(@valid_address, @valid_data, rpc_url: @valid_rpc_url, block: "0x")
    end

    test "rejects a hex block above u64::MAX" do
      hex = "0x1" <> String.duplicate("0", 16)

      assert {:error, {:invalid_block, ^hex}} =
               EVM.simulate_call(@valid_address, @valid_data, rpc_url: @valid_rpc_url, block: hex)
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

  describe "simulate_call/3 option validation" do
    test "returns error for non-string value" do
      assert {:error, {:invalid_value, 123}} =
               EVM.simulate_call(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 value: 123
               )
    end

    test "accepts string value" do
      result =
        EVM.simulate_call(@valid_address, @valid_data,
          rpc_url: @valid_rpc_url,
          value: "0x1"
        )

      refute match?({:error, {:invalid_value, _}}, result)
    end

    test "returns error for empty value" do
      assert {:error, {:invalid_value, ""}} =
               EVM.simulate_call(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 value: ""
               )
    end

    test "returns error for non-hex value" do
      assert {:error, {:invalid_value, "not-a-hex"}} =
               EVM.simulate_call(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 value: "not-a-hex"
               )
    end

    test "returns error for negative gas_limit" do
      assert {:error, {:invalid_gas_limit, -1}} =
               EVM.simulate_call(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 gas_limit: -1
               )
    end

    test "returns error for zero gas_limit" do
      assert {:error, {:invalid_gas_limit, 0}} =
               EVM.simulate_call(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 gas_limit: 0
               )
    end

    test "returns error for string gas_limit" do
      assert {:error, {:invalid_gas_limit, "30000"}} =
               EVM.simulate_call(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 gas_limit: "30000"
               )
    end

    test "returns error for non-map state_overrides" do
      assert {:error, {:invalid_state_overrides, "invalid"}} =
               EVM.simulate_call(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 state_overrides: "invalid"
               )
    end

    test "returns error for list state_overrides" do
      assert {:error, {:invalid_state_overrides, []}} =
               EVM.simulate_call(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 state_overrides: []
               )
    end

    test "returns error for state_overrides with atom keys" do
      overrides = %{atom_key: %{"balance" => "0x1"}}

      assert {:error, {:invalid_state_overrides, ^overrides}} =
               EVM.simulate_call(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 state_overrides: overrides
               )
    end
  end

  describe "simulate_call/3 :timeout_ms validation" do
    test "accepts positive integer timeout_ms (passes validation)" do
      result =
        EVM.simulate_call(@valid_address, @valid_data,
          rpc_url: @valid_rpc_url,
          timeout_ms: 1_000
        )

      refute match?({:error, {:invalid_timeout_ms, _}}, result)
    end

    test "returns error for zero timeout_ms" do
      assert {:error, {:invalid_timeout_ms, 0}} =
               EVM.simulate_call(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 timeout_ms: 0
               )
    end

    test "returns error for negative timeout_ms" do
      assert {:error, {:invalid_timeout_ms, -500}} =
               EVM.simulate_call(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 timeout_ms: -500
               )
    end

    test "returns error for string timeout_ms" do
      assert {:error, {:invalid_timeout_ms, "5000"}} =
               EVM.simulate_call(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 timeout_ms: "5000"
               )
    end

    test "returns error for float timeout_ms" do
      assert {:error, {:invalid_timeout_ms, 1.5}} =
               EVM.simulate_call(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 timeout_ms: 1.5
               )
    end

    test "returns error for timeout_ms greater than u64::MAX" do
      too_big = 0x1_0000_0000_0000_0000

      assert {:error, {:invalid_timeout_ms, ^too_big}} =
               EVM.simulate_call(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 timeout_ms: too_big
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
    test "returns error when opts default to empty" do
      assert {:error, {:invalid_rpc_url, :missing}} =
               EVM.simulate_transaction(@valid_address, @valid_data)
    end

    test "returns error when rpc_url is missing" do
      assert {:error, {:invalid_rpc_url, :missing}} =
               EVM.simulate_transaction(@valid_address, @valid_data, [])
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
    test "returns error when opts default to empty" do
      calls = [{@valid_address, @valid_data}]
      assert {:error, {:invalid_rpc_url, :missing}} = EVM.simulate_batch(calls)
    end

    test "returns error when rpc_url is missing" do
      calls = [{@valid_address, @valid_data}]
      assert {:error, {:invalid_rpc_url, :missing}} = EVM.simulate_batch(calls, [])
    end

    test "returns error for invalid address in calls list" do
      calls = [{"bad-addr", @valid_data}]
      assert {:error, {:invalid_address, _}} = EVM.simulate_batch(calls, rpc_url: @valid_rpc_url)
    end

    test "returns error for invalid data in calls list" do
      calls = [{@valid_address, "no-prefix"}]
      assert {:error, {:invalid_data, _}} = EVM.simulate_batch(calls, rpc_url: @valid_rpc_url)
    end

    test "returns tagged error for a non-list calls argument" do
      assert {:error, {:invalid_calls, %{}}} =
               EVM.simulate_batch(%{}, rpc_url: @valid_rpc_url)
    end

    test "returns tagged error for a non-2-tuple call element" do
      assert {:error, {:invalid_calls, "not-a-tuple"}} =
               EVM.simulate_batch(["not-a-tuple"], rpc_url: @valid_rpc_url)
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
