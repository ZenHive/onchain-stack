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

    test "accepts an empty calls list" do
      assert {:ok, params} = Params.build_batch_params([], rpc_url: @valid_rpc_url)
      assert params["calls"] == []
    end

    # Reproduced 2026-08-22: %{} reduced as an empty Enumerable to {:ok, []}.
    test "rejects a non-list calls argument" do
      assert {:error, {:invalid_calls, %{}}} =
               Params.build_batch_params(%{}, rpc_url: @valid_rpc_url)
    end

    # Reproduced 2026-08-22: a non-2-tuple raised FunctionClauseError from validate_calls/1.
    test "rejects a calls element that is not a 2-tuple" do
      assert {:error, {:invalid_calls, "not-a-tuple"}} =
               Params.build_batch_params(["not-a-tuple"], rpc_url: @valid_rpc_url)
    end

    test "rejects a 3-tuple calls element" do
      assert {:error, {:invalid_calls, {@valid_address, @valid_data, :extra}}} =
               Params.build_batch_params([{@valid_address, @valid_data, :extra}], rpc_url: @valid_rpc_url)
    end
  end

  # Samples a shallow is_binary / is_integer / is_map guard would accept.
  # A newly documented sim_opts key without an entry fails this test; an entry
  # whose malformed value still assembles into {:ok, _} also fails.
  @u64_overflow 0x1_0000_0000_0000_0000
  @malformed_option_samples %{
    rpc_url: "",
    block: "0x1" <> String.duplicate("0", 16),
    from: "not-an-address",
    value: "not-a-hex",
    gas_limit: @u64_overflow,
    timeout_ms: @u64_overflow,
    state_overrides: %{atom_key: %{"balance" => "0x1"}}
  }

  describe "documented option surface" do
    test "every sim_opts key has an Elixir-layer guard" do
      documented = documented_sim_opt_keys()
      sampled = @malformed_option_samples |> Map.keys() |> MapSet.new()

      missing = MapSet.difference(documented, sampled)

      assert missing == MapSet.new(),
             "documented sim_opts keys have no malformed sample (add a guard + sample): #{inspect(MapSet.to_list(missing))}"

      extra = MapSet.difference(sampled, documented)

      assert extra == MapSet.new(),
             "malformed samples for keys not in sim_opts: #{inspect(MapSet.to_list(extra))}"

      Enum.each(@malformed_option_samples, fn {key, bad} ->
        opts = Keyword.put([rpc_url: @valid_rpc_url], key, bad)
        result = Params.build_call_params(@valid_address, @valid_data, opts)

        assert {:error, {tag, _reason}} = result
        assert is_atom(tag)

        refute tag in [:evm_error, :evm_revert, :fork_error, :timeout],
               "#{key} leaked past Elixir validation: #{inspect(result)}"
      end)
    end

    # Reproduced 2026-08-22: "" and "not-a-hex" assembled into the NIF params map.
    test "rejects an empty :value" do
      assert {:error, {:invalid_value, ""}} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 value: ""
               )
    end

    test "rejects a non-hex :value" do
      assert {:error, {:invalid_value, "not-a-hex"}} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 value: "not-a-hex"
               )
    end

    test "rejects a :value above U256::MAX" do
      too_wide = "0x1" <> String.duplicate("0", 64)

      assert {:error, {:invalid_value, ^too_wide}} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 value: too_wide
               )
    end

    # Reproduced 2026-08-22: atom keys and integer values assembled into the NIF params map.
    test "rejects :state_overrides with atom keys" do
      overrides = %{atom_key: %{"balance" => "0x1"}}

      assert {:error, {:invalid_state_overrides, ^overrides}} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 state_overrides: overrides
               )
    end

    test "rejects :state_overrides with integer values" do
      overrides = %{@valid_address => %{"balance" => 1}}

      assert {:error, {:invalid_state_overrides, ^overrides}} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 state_overrides: overrides
               )
    end

    test "rejects :state_overrides whose keys are not addresses" do
      overrides = %{"not-an-address" => %{"balance" => "0x1"}}

      assert {:error, {:invalid_state_overrides, ^overrides}} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 state_overrides: overrides
               )
    end

    # Reproduced 2026-08-22: a >u64 hex block assembled as block_number and
    # failed in the NIF as "invalid param type: block_number".
    test "rejects a hex :block above u64::MAX" do
      hex = "0x1" <> String.duplicate("0", 16)

      assert {:error, {:invalid_block, ^hex}} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 block: hex
               )
    end

    test "rejects an integer :block above u64::MAX" do
      over = @u64_overflow

      assert {:error, {:invalid_block, ^over}} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 block: over
               )
    end

    test "accepts a u64::MAX integer :block" do
      max = 0xFFFF_FFFF_FFFF_FFFF

      assert {:ok, params} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 block: max
               )

      assert params["block_number"] == max
    end

    test "rejects a :gas_limit above u64::MAX" do
      over = @u64_overflow

      assert {:error, {:invalid_gas_limit, ^over}} =
               Params.build_call_params(@valid_address, @valid_data,
                 rpc_url: @valid_rpc_url,
                 gas_limit: over
               )
    end
  end

  defp documented_sim_opt_keys do
    {:ok, types} = Code.Typespec.fetch_types(Onchain.EVM)

    case Enum.find(types, &match?({:type, {:sim_opts, _, []}}, &1)) do
      {:type, {:sim_opts, type, []}} ->
        type |> sim_opt_keys() |> MapSet.new()

      nil ->
        flunk("Onchain.EVM no longer exports @type sim_opts — the option-surface enumerator cannot run")
    end
  end

  defp sim_opt_keys({:type, _, :list, [inner]}), do: sim_opt_keys(inner)
  defp sim_opt_keys({:type, _, :union, variants}), do: Enum.flat_map(variants, &sim_opt_keys/1)
  defp sim_opt_keys({:type, _, :tuple, [{:atom, _, key}, _rest]}), do: [key]
  defp sim_opt_keys(other), do: flunk("unexpected sim_opts typespec node: #{inspect(other)}")
end
