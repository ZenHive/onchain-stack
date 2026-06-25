defmodule Onchain.EVM.ParamsTest do
  use ExUnit.Case, async: true

  alias Onchain.EVM.Params

  @valid_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @valid_data "0x18160ddd"
  @valid_rpc_url "https://eth-mainnet.example.com"

  describe "build_call_params/3 success assembly" do
    test "assembles a full param map from all supported options" do
      overrides = %{@valid_address => %{"balance" => "0xDE0B6B3A7640000"}}

      assert {:ok, params} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 block: 100,
                 from: @valid_address,
                 value: "0x1",
                 gas_limit: 21_000,
                 timeout_ms: 5_000,
                 state_overrides: overrides
               )

      assert params["rpc_url"] == @valid_rpc_url
      assert params["to"] == String.downcase(@valid_address)
      assert params["data"] == @valid_data
      assert params["block_number"] == 100
      assert params["from"] == String.downcase(@valid_address)
      assert params["value"] == "0x1"
      assert params["gas_limit"] == 21_000
      assert params["timeout_ms"] == 5_000
      assert params["state_overrides"] == overrides
    end

    test "omits optional keys when not provided" do
      assert {:ok, params} =
               Params.build_call_params(@valid_address, @valid_data, rpc_url: @valid_rpc_url)

      assert params |> Map.keys() |> Enum.sort() == ["data", "rpc_url", "to"]
    end

    test "accepts a hex block and converts it to an integer block_number" do
      assert {:ok, params} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 block: "0x10"
               )

      assert params["block_number"] == 16
    end

    test "accepts a block tag" do
      assert {:ok, params} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 block: "latest"
               )

      assert params["block_tag"] == "latest"
    end
  end

  describe "build_call_params/3 validation errors" do
    test "rejects an invalid :from address" do
      assert {:error, {:invalid_address, "nope"}} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 from: "nope"
               )
    end

    test "rejects a non-binary :value" do
      assert {:error, {:invalid_value, 100}} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 value: 100
               )
    end

    test "rejects a non-positive :gas_limit" do
      assert {:error, {:invalid_gas_limit, 0}} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 gas_limit: 0
               )
    end

    test "rejects a non-map :state_overrides" do
      assert {:error, {:invalid_state_overrides, []}} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 state_overrides: []
               )
    end

    test "rejects a missing :rpc_url" do
      assert {:error, {:invalid_rpc_url, :missing}} =
               Params.build_call_params(@valid_address, @valid_data, [])
    end

    test "rejects a non-string :rpc_url" do
      assert {:error, {:invalid_rpc_url, {:not_a_string, 42}}} =
               Params.build_call_params(@valid_address, @valid_data, rpc_url: 42)
    end

    test "rejects an empty/whitespace-only :rpc_url" do
      assert {:error, {:invalid_rpc_url, :empty}} =
               Params.build_call_params(@valid_address, @valid_data, rpc_url: "   ")
    end

    test "rejects a non-HTTP(S) :rpc_url scheme" do
      assert {:error, {:invalid_rpc_url, {:invalid_scheme, "ftp://eth.example.com"}}} =
               Params.build_call_params(@valid_address, @valid_data, rpc_url: "ftp://eth.example.com")
    end

    test "rejects an :rpc_url with no host" do
      assert {:error, {:invalid_rpc_url, {:missing_host, "https://"}}} =
               Params.build_call_params(@valid_address, @valid_data, rpc_url: "https://")
    end

    test "folds a malformed-URI :rpc_url into :invalid_scheme" do
      assert {:error, {:invalid_rpc_url, {:invalid_scheme, "ht<tp://eth.example.com"}}} =
               Params.build_call_params(@valid_address, @valid_data, rpc_url: "ht<tp://eth.example.com")
    end

    test "rejects a non-positive :timeout_ms" do
      assert {:error, {:invalid_timeout_ms, 0}} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 timeout_ms: 0
               )
    end

    test "rejects a :timeout_ms above u64::MAX" do
      over_max = 0x1_0000_0000_0000_0000

      assert {:error, {:invalid_timeout_ms, ^over_max}} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 timeout_ms: over_max
               )
    end

    test "rejects an unrecognized :block value" do
      assert {:error, {:invalid_block, :nonsense}} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 block: :nonsense
               )
    end

    test "rejects a malformed hex :block" do
      assert {:error, {:invalid_block, _}} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 block: "0xzz"
               )
    end
  end

  describe "build_batch_params/2" do
    test "validates and assembles a batch of calls" do
      calls = [{@valid_address, @valid_data}, {@valid_address, "0x70a08231"}]

      assert {:ok, params} =
               Params.build_batch_params(calls,
                 rpc_url: @valid_rpc_url,
                 from: @valid_address,
                 gas_limit: 50_000
               )

      assert params["rpc_url"] == @valid_rpc_url
      assert [{addr1, data1}, {_addr2, data2}] = params["calls"]
      assert addr1 == String.downcase(@valid_address)
      assert data1 == @valid_data
      assert data2 == "0x70a08231"
      assert params["from"] == String.downcase(@valid_address)
      assert params["gas_limit"] == 50_000
    end

    test "halts on the first invalid call in the batch" do
      calls = [{@valid_address, @valid_data}, {"bad-address", @valid_data}]

      assert {:error, {:invalid_address, _}} =
               Params.build_batch_params(calls, rpc_url: @valid_rpc_url)
    end

    test "rejects a missing :rpc_url before validating calls" do
      assert {:error, {:invalid_rpc_url, :missing}} =
               Params.build_batch_params([{@valid_address, @valid_data}], [])
    end
  end
end
