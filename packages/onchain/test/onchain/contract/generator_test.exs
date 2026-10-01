defmodule Onchain.Contract.GeneratorTest do
  use ExUnit.Case, async: true

  alias Onchain.Contract.Generator

  @contract_address "0x1111111111111111111111111111111111111111"
  @user_address "0x2222222222222222222222222222222222222222"

  # --- Test modules defined inline ---

  # ABI JSON module (Chainlink aggregator)
  defmodule ChainlinkModule do
    @moduledoc false
    use Generator,
      abi_json: File.read!(Path.join(:code.priv_dir(:onchain), "abis/chainlink_aggregator.json"))
  end

  # ABI file module
  defmodule ChainlinkFileModule do
    @moduledoc false
    use Generator,
      abi_file: Path.join(:code.priv_dir(:onchain), "abis/chainlink_aggregator.json")
  end

  # Overloaded function module
  defmodule OverloadModule do
    @moduledoc false
    use Generator,
      abi_json: ~s([
        {"inputs":[{"name":"to","type":"address"},{"name":"value","type":"uint256"}],"name":"transfer","outputs":[{"name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},
        {"inputs":[{"name":"from","type":"address"},{"name":"to","type":"address"},{"name":"value","type":"uint256"}],"name":"transfer","outputs":[{"name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"}
      ])
  end

  # Same-arity overload module — two functions sharing a name AND input count,
  # so disambiguate_collisions/1 must fall into its collision branch and
  # exercise disambiguation_suffix/2 -> unique_type_suffix/2 (unlike
  # OverloadModule above, whose two `transfer` overloads differ in arity and
  # never reach that code path).
  defmodule SameArityOverloadModule do
    @moduledoc false
    use Generator,
      abi_json: ~s([
        {"inputs":[{"name":"a","type":"address"},{"name":"b","type":"uint256"}],"name":"swap","outputs":[{"name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},
        {"inputs":[{"name":"a","type":"uint256"},{"name":"b","type":"address"}],"name":"swap","outputs":[{"name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"}
      ])
  end

  # Empty ABI module
  defmodule EmptyModule do
    @moduledoc false
    use Generator,
      abi_json: "[]"
  end

  defmodule ReadModule do
    @moduledoc false
    use Generator,
      abi_json: ~s([
        {"type":"function","name":"getUserData","stateMutability":"view","inputs":[{"name":"user","type":"address"}],"outputs":[{"name":"amount","type":"uint256"}]},
        {"type":"function","name":"decimals","stateMutability":"view","inputs":[],"outputs":[{"name":"","type":"uint8"}]}
      ])
  end

  defmodule SleuthBytecodeModule do
    @moduledoc false
    use Generator,
      abi_json: ~s([
        {"type":"function","name":"answer","stateMutability":"view","inputs":[],"outputs":[{"name":"","type":"uint256"}]}
      ]),
      bytecode: "0x6001600155"
  end

  # --- Unit tests: to_snake_case ---

  describe "to_snake_case/1" do
    test "converts camelCase" do
      assert Generator.to_snake_case("getUserAccountData") == "get_user_account_data"
    end

    test "converts PascalCase" do
      assert Generator.to_snake_case("LatestRoundData") == "latest_round_data"
    end

    test "handles consecutive capitals" do
      assert Generator.to_snake_case("getERC20Balance") == "get_erc20_balance"
    end

    test "leaves snake_case unchanged" do
      assert Generator.to_snake_case("already_snake") == "already_snake"
    end

    test "handles single word" do
      assert Generator.to_snake_case("decimals") == "decimals"
    end
  end

  # --- Unit tests: ABI JSON module ---

  describe "ABI JSON module (Chainlink)" do
    test "generates functions with snake_case names" do
      assert function_exported?(ChainlinkModule, :decimals, 2)
      assert function_exported?(ChainlinkModule, :description, 2)
      assert function_exported?(ChainlinkModule, :latest_round_data, 2)
      assert function_exported?(ChainlinkModule, :version, 2)
    end

    test "generates bang variants" do
      assert function_exported?(ChainlinkModule, :decimals!, 2)
      assert function_exported?(ChainlinkModule, :description!, 2)
      assert function_exported?(ChainlinkModule, :latest_round_data!, 2)
      assert function_exported?(ChainlinkModule, :version!, 2)
    end

    test "read functions accept default opts (arity - 1)" do
      # Read functions have opts \\ [] so they work with one less arg
      assert function_exported?(ChainlinkModule, :decimals, 1)
      assert function_exported?(ChainlinkModule, :decimals!, 1)
    end

    test "__contract_abi__/0 returns parsed ABI" do
      abi = ChainlinkModule.__contract_abi__()
      assert is_map(abi)
      assert is_list(abi.functions)
      assert match?([_, _, _, _], abi.functions)

      names = Enum.map(abi.functions, & &1.name)
      assert "decimals" in names
      assert "latestRoundData" in names
    end

    test "address validation rejects invalid addresses" do
      # latestRoundData has no address params, so test with a module that does
      result = ReadModule.get_user_data("not_a_contract", "also_invalid")
      assert {:error, {:invalid_address, "also_invalid"}} = result
    end

    test "__contract_abi__ contains all expected function names" do
      abi = ChainlinkModule.__contract_abi__()
      names = abi.functions |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["decimals", "description", "latestRoundData", "version"]
    end
  end

  # --- Unit tests: abi_file option ---

  describe "abi_file option" do
    test "generates same functions as abi_json" do
      assert function_exported?(ChainlinkFileModule, :decimals, 2)
      assert function_exported?(ChainlinkFileModule, :latest_round_data, 2)
    end

    test "__contract_abi__/0 matches" do
      abi = ChainlinkFileModule.__contract_abi__()
      assert match?([_, _, _, _], abi.functions)
    end
  end

  # --- Unit tests: empty ABI ---

  describe "empty ABI" do
    test "compiles successfully" do
      assert function_exported?(EmptyModule, :__contract_abi__, 0)
    end

    test "__contract_abi__/0 returns empty functions list" do
      abi = EmptyModule.__contract_abi__()
      assert abi.functions == []
    end
  end

  # --- Unit tests: overload disambiguation ---

  describe "overload disambiguation" do
    test "generates disambiguated function names for same-arity overloads" do
      # transfer(address,uint256) → 2 inputs + contract + opts = arity 4
      # transfer(address,address,uint256) → 3 inputs + contract + opts = arity 5
      # Different arities, so no disambiguation needed for these

      # Both should exist with their natural arities
      # transfer(address,uint256) → transfer/4
      assert function_exported?(OverloadModule, :transfer, 4) ||
               function_exported?(OverloadModule, :transfer_address, 4)

      # transfer(address,address,uint256) → transfer/5
      # With different arities, no suffix needed
      fns = OverloadModule.__info__(:functions)

      transfer_fns =
        Enum.filter(fns, fn {name, _arity} -> name |> Atom.to_string() |> String.starts_with?("transfer") end)

      # 2 normal + 2 bang (with default opts arities)
      assert match?([_, _, _, _ | _], transfer_fns)
    end

    test "disambiguates genuinely same-arity overloads by differing input type" do
      # swap(address,uint256) and swap(uint256,address): same name, same input
      # count (2), so disambiguate_collisions/1's collision branch fires and
      # calls disambiguation_suffix/2 -> unique_type_suffix/2 for real, unlike
      # the differing-arity OverloadModule case above.
      fns = SameArityOverloadModule.__info__(:functions)

      swap_fns =
        fns
        |> Enum.filter(fn {name, _arity} -> name |> Atom.to_string() |> String.starts_with?("swap") end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.uniq()

      # Each overload gets a distinct elixir_name, suffixed by its
      # disambiguating (first-differing) input type.
      assert :swap_address in swap_fns
      assert :swap_uint256 in swap_fns

      # Both are callable at their natural arity: contract + 2 params + opts.
      assert function_exported?(SameArityOverloadModule, :swap_address, 4)
      assert function_exported?(SameArityOverloadModule, :swap_uint256, 4)
    end
  end

  # --- Unit tests: .sol module ---

  describe "address validation in generated functions" do
    test "validates address params before calling" do
      # getUserData(address user) → validates user
      result = ReadModule.get_user_data("0x" <> String.duplicate("a", 40), "invalid")
      assert {:error, {:invalid_address, "invalid"}} = result
    end

    test "contract address is passed through to Contract.call" do
      # With invalid contract, we get an address error from Contract.call
      result = ReadModule.decimals("not_a_contract")
      assert {:error, {:invalid_address, "not_a_contract"}} = result
    end
  end

  describe "generated Multicall helper module" do
    test "builds aggregate3 entries with the direct wrapper argument types" do
      assert {:ok, {@contract_address, true, calldata}} =
               ReadModule.Multicall.get_user_data(@contract_address, @user_address)

      assert {:ok, user_bin} = Onchain.Address.validate(@user_address)

      assert {:ok, expected_calldata} =
               Onchain.ABI.encode_hex_call("getUserData(address)", [user_bin])

      assert calldata == expected_calldata

      assert {:ok, {@contract_address, false, _calldata}} =
               ReadModule.Multicall.get_user_data(@contract_address, @user_address, false)
    end

    test "returns address validation errors while building entries" do
      assert {:error, {:invalid_address, "invalid contract"}} =
               ReadModule.Multicall.get_user_data("invalid contract", @user_address)

      assert {:error, {:invalid_address, "invalid user"}} =
               ReadModule.Multicall.get_user_data(@contract_address, "invalid user")
    end

    test "decodes a scalar result like the direct wrapper" do
      result = raw_result("(uint8)", [8])

      assert {:ok, [8]} = ChainlinkModule.Multicall.decode_decimals({true, result})
    end

    test "preserves failed aggregate3 entries without treating them as simulation results" do
      assert {:error, "0xdeadbeef"} =
               ChainlinkModule.Multicall.decode_decimals({false, "0xdeadbeef"})
    end
  end

  describe "Sleuth bytecode surface" do
    test "emits bytecode and query_by helpers when :bytecode is set" do
      assert function_exported?(SleuthBytecodeModule, :bytecode, 0)
      assert function_exported?(SleuthBytecodeModule, :answer_selector, 0)
      assert function_exported?(SleuthBytecodeModule, :encode_answer, 0)
      assert function_exported?(SleuthBytecodeModule, :decode_call, 1)

      assert <<0x60, 0x01, 0x60, 0x01, 0x55>> = SleuthBytecodeModule.bytecode()
      assert is_binary(SleuthBytecodeModule.encode_answer())
      assert %Onchain.ABI.FunctionSelector{function: "answer"} = SleuthBytecodeModule.answer_selector()
    end

    test "does not pass init bytecode off as deployed bytecode" do
      refute function_exported?(SleuthBytecodeModule, :deployed_bytecode, 0)

      artifact_module = Onchain.Contract.BlockNumber
      assert is_binary(artifact_module.deployed_bytecode())
      refute artifact_module.deployed_bytecode() == artifact_module.bytecode()
    end

    test "omits bytecode helpers without :bytecode" do
      refute function_exported?(ReadModule, :bytecode, 0)
      refute function_exported?(ReadModule, :decode_call, 1)
    end
  end

  # --- Unit tests: resolve_abi ---

  describe "resolve_abi/1" do
    test "raises on missing options" do
      assert_raise ArgumentError, ~r/requires :sol, :sol_file, :abi_json, or :abi_file/, fn ->
        Generator.resolve_abi([])
      end
    end

    test "raises on invalid ABI JSON" do
      assert_raise RuntimeError, ~r/ABI parse failed/, fn ->
        Generator.resolve_abi(abi_json: "not json")
      end
    end

    test "parses valid ABI JSON" do
      result = Generator.resolve_abi(abi_json: "[]")
      assert result.functions == []
    end

    if !Code.ensure_loaded?(Onchain.Solidity) do
      test "sol input without the Solidity frontend names the missing package" do
        assert_raise ArgumentError, ~r/onchain_evm/, fn ->
          Generator.resolve_abi(sol: "contract C {}")
        end
      end
    end
  end

  defp raw_result(type, values) do
    type |> Onchain.ABI.encode([List.to_tuple(values)]) |> Onchain.Hex.encode()
  end
end
