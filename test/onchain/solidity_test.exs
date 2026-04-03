defmodule Onchain.SolidityTest do
  use ExUnit.Case, async: true

  alias Onchain.Solidity

  @priv_abis Path.join(:code.priv_dir(:onchain_evm), "abis")
  @priv_contracts Path.join(:code.priv_dir(:onchain_evm), "contracts")

  describe "parse_abi_json/1" do
    test "parses function with no inputs and single output" do
      json = File.read!(Path.join(@priv_abis, "chainlink_aggregator.json"))
      assert {:ok, abi} = Solidity.parse_abi_json(json)

      decimals = find_function(abi, "decimals")
      assert decimals.name == "decimals"
      assert decimals.signature == "decimals()"
      assert decimals.return_type == "(uint8)"
      assert decimals.state_mutability == "view"
      assert decimals.inputs == []
      assert [%{name: "", ty: "uint8"}] = decimals.outputs
    end

    test "parses function with multiple outputs and mixed types" do
      json = File.read!(Path.join(@priv_abis, "chainlink_aggregator.json"))
      assert {:ok, abi} = Solidity.parse_abi_json(json)

      latest = find_function(abi, "latestRoundData")
      assert latest.signature == "latestRoundData()"
      assert latest.return_type == "(uint80,int256,uint256,uint256,uint80)"
      assert length(latest.outputs) == 5
      assert Enum.at(latest.outputs, 0).ty == "uint80"
      assert Enum.at(latest.outputs, 1).ty == "int256"
    end

    test "parses function with address input" do
      json = File.read!(Path.join(@priv_abis, "aave_pool.json"))
      assert {:ok, abi} = Solidity.parse_abi_json(json)

      func = find_function(abi, "getUserAccountData")
      assert func.signature == "getUserAccountData(address)"
      assert func.return_type == "(uint256,uint256,uint256,uint256,uint256,uint256)"
      assert func.state_mutability == "view"
      assert [%{name: "user", ty: "address"}] = func.inputs
      assert length(func.outputs) == 6
    end

    test "parses nested tuple/struct returns" do
      json = File.read!(Path.join(@priv_abis, "aave_pool.json"))
      assert {:ok, abi} = Solidity.parse_abi_json(json)

      func = find_function(abi, "getReserveData")
      assert func.signature == "getReserveData(address)"

      # The return type wraps the struct in outer parens (function returns one tuple)
      # Inner tuple is the ReserveData struct, first field is ReserveConfigurationMap((uint256))
      assert func.return_type ==
               "(((uint256),uint128,uint128,uint128,uint128,uint128,uint40,uint16,address,address,address,address,uint128,uint128,uint128))"

      # The output should have components for the struct fields
      assert [output] = func.outputs
      assert output.ty == "tuple"
      assert length(output.components) == 15

      # First component is itself a nested tuple (ReserveConfigurationMap)
      config = Enum.at(output.components, 0)
      assert config.name == "configuration"
      assert config.ty == "tuple"
      assert [%{name: "data", ty: "uint256"}] = config.components
    end

    test "computes correct 4-byte selectors" do
      # balanceOf(address) selector is the well-known 0x70a08231
      erc20_json =
        ~s([{"inputs":[{"name":"account","type":"address"}],"name":"balanceOf","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"}])

      assert {:ok, abi} = Solidity.parse_abi_json(erc20_json)
      func = find_function(abi, "balanceOf")
      assert func.selector == "0x70a08231"
    end

    test "return_type is compatible with Onchain.ABI.decode_response/2" do
      json = File.read!(Path.join(@priv_abis, "chainlink_aggregator.json"))
      assert {:ok, abi} = Solidity.parse_abi_json(json)

      # Verify the return_type for decimals() works with the existing ABI module
      decimals = find_function(abi, "decimals")

      # encode_call should work with the parsed signature
      assert {:ok, _calldata} = Onchain.ABI.encode_call(decimals.signature, [])

      # The selector from encoding should match the parsed selector
      {:ok, calldata} = Onchain.ABI.encode_call(decimals.signature, [])
      # calldata is "0x" + 4-byte selector + params — selector starts at same position
      assert String.slice(calldata, 0, 10) == decimals.selector
    end

    test "parses empty ABI" do
      assert {:ok, abi} = Solidity.parse_abi_json("[]")
      assert abi.functions == []
      assert abi.events == []
      assert abi.errors == []
      assert abi.constructor == nil
    end

    test "returns error for invalid JSON" do
      assert {:error, {:parse_error, reason}} = Solidity.parse_abi_json("not json")
      assert is_binary(reason)
    end

    test "returns error for malformed ABI (valid JSON, wrong structure)" do
      assert {:error, {:parse_error, _reason}} = Solidity.parse_abi_json(~s({"not": "an abi"}))
    end

    test "parses events with indexed parameters" do
      transfer_json =
        ~s([{"anonymous":false,"inputs":[{"indexed":true,"name":"from","type":"address"},{"indexed":true,"name":"to","type":"address"},{"indexed":false,"name":"value","type":"uint256"}],"name":"Transfer","type":"event"}])

      assert {:ok, abi} = Solidity.parse_abi_json(transfer_json)
      assert [event] = abi.events
      assert event.name == "Transfer"
      assert event.signature == "Transfer(address,address,uint256)"
      assert event.anonymous == false
      assert is_binary(event.topic)
      assert String.length(event.topic) == 66
      assert String.starts_with?(event.topic, "0x")

      [from, to, value] = event.inputs
      assert from.name == "from"
      assert from.ty == "address"
      assert from.indexed == true
      assert to.indexed == true
      assert value.indexed == false
    end

    test "parses custom errors" do
      error_json =
        ~s([{"inputs":[{"name":"available","type":"uint256"},{"name":"required","type":"uint256"}],"name":"InsufficientBalance","type":"error"}])

      assert {:ok, abi} = Solidity.parse_abi_json(error_json)
      assert [err] = abi.errors
      assert err.name == "InsufficientBalance"
      assert err.signature == "InsufficientBalance(uint256,uint256)"
      assert is_binary(err.selector)
      assert length(err.inputs) == 2
    end

    test "parses constructor" do
      ctor_json = ~s([{"inputs":[{"name":"admin","type":"address"}],"stateMutability":"nonpayable","type":"constructor"}])

      assert {:ok, abi} = Solidity.parse_abi_json(ctor_json)
      assert abi.constructor
      assert abi.constructor.state_mutability == "nonpayable"
      assert [%{name: "admin", ty: "address"}] = abi.constructor.inputs
    end

    test "handles overloaded functions" do
      json = ~s([
        {"inputs":[{"name":"to","type":"address"},{"name":"value","type":"uint256"}],"name":"transfer","outputs":[{"name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},
        {"inputs":[{"name":"from","type":"address"},{"name":"to","type":"address"},{"name":"value","type":"uint256"}],"name":"transfer","outputs":[{"name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"}
      ])

      assert {:ok, abi} = Solidity.parse_abi_json(json)
      transfers = Enum.filter(abi.functions, &(&1.name == "transfer"))
      assert length(transfers) == 2

      sigs = transfers |> Enum.map(& &1.signature) |> Enum.sort()
      assert "transfer(address,address,uint256)" in sigs
      assert "transfer(address,uint256)" in sigs
    end
  end

  describe "parse_abi_json!/1" do
    test "returns map on success" do
      assert %{functions: _, events: _, errors: _, constructor: _} =
               Solidity.parse_abi_json!("[]")
    end

    test "raises on invalid input" do
      assert_raise RuntimeError, ~r/ABI parse failed/, fn ->
        Solidity.parse_abi_json!("bad")
      end
    end
  end

  describe "parse_abi_file/1" do
    test "reads and parses file" do
      path = Path.join(@priv_abis, "chainlink_aggregator.json")
      assert {:ok, abi} = Solidity.parse_abi_file(path)
      assert length(abi.functions) == 4
    end

    test "returns file_error for missing file" do
      assert {:error, {:file_error, reason}} = Solidity.parse_abi_file("/nonexistent/file.json")
      assert reason =~ "/nonexistent/file.json"
    end
  end

  describe "parse_abi_file!/1" do
    test "returns map on success" do
      path = Path.join(@priv_abis, "chainlink_aggregator.json")
      assert %{functions: funcs} = Solidity.parse_abi_file!(path)
      assert length(funcs) == 4
    end

    test "raises on missing file" do
      assert_raise RuntimeError, ~r/ABI file error/, fn ->
        Solidity.parse_abi_file!("/nonexistent/file.json")
      end
    end

    test "raises on invalid file contents" do
      # Create a temp file with invalid JSON
      path = Path.join(System.tmp_dir!(), "bad_abi.json")
      File.write!(path, "not json")

      assert_raise RuntimeError, ~r/ABI parse failed/, fn ->
        Solidity.parse_abi_file!(path)
      end
    after
      File.rm(Path.join(System.tmp_dir!(), "bad_abi.json"))
    end
  end

  describe "parse_sol/1" do
    test "parses minimal interface with view function" do
      sol = """
      pragma solidity ^0.8.0;
      interface ISimple {
          function decimals() external pure returns (uint8);
      }
      """

      assert {:ok, result} = Solidity.parse_sol(sol)
      assert [func] = result.functions
      assert func.name == "decimals"
      assert func.signature == "decimals()"
      assert func.return_type == "(uint8)"
      assert func.state_mutability == "pure"
      assert func.inputs == []
      assert is_binary(func.selector)
      assert String.starts_with?(func.selector, "0x")
    end

    test "parses interface with struct definitions" do
      sol = File.read!(Path.join(@priv_contracts, "test_interface.sol"))
      assert {:ok, result} = Solidity.parse_sol(sol)

      assert length(result.structs) == 2

      user_data = Enum.find(result.structs, &(&1.name == "ITestContract.UserData"))
      assert user_data
      assert length(user_data.fields) == 3

      field_names = Enum.map(user_data.fields, & &1.name)
      assert "balance" in field_names
      assert "owner" in field_names
      assert "active" in field_names

      balance_field = Enum.find(user_data.fields, &(&1.name == "balance"))
      assert balance_field.ty == "uint256"

      owner_field = Enum.find(user_data.fields, &(&1.name == "owner"))
      assert owner_field.ty == "address"
    end

    test "parses interface with enum" do
      sol = File.read!(Path.join(@priv_contracts, "test_interface.sol"))
      assert {:ok, result} = Solidity.parse_sol(sol)

      assert [status_enum] = result.enums
      assert status_enum.name == "ITestContract.Status"
      assert status_enum.variants == ["Pending", "Active", "Closed"]
    end

    test "parses interface with NatSpec" do
      sol = File.read!(Path.join(@priv_contracts, "test_interface.sol"))
      assert {:ok, result} = Solidity.parse_sol(sol)

      get_user = Enum.find(result.functions, &(&1.name == "getUserData"))
      assert get_user.natspec
      assert get_user.natspec.notice == "Get user data by address"
      assert get_user.natspec.params["user"] == "The user address to query"
      assert get_user.natspec.returns["data"] == "The user's data struct"
    end

    test "functions without NatSpec have nil natspec" do
      sol = File.read!(Path.join(@priv_contracts, "test_interface.sol"))
      assert {:ok, result} = Solidity.parse_sol(sol)

      total = Enum.find(result.functions, &(&1.name == "totalSupply"))
      assert total.natspec == nil
    end

    test "parses empty interface" do
      sol = """
      pragma solidity ^0.8.0;
      interface IEmpty {}
      """

      assert {:ok, result} = Solidity.parse_sol(sol)
      assert result.functions == []
      assert result.events == []
      assert result.errors == []
      assert result.structs == []
      assert result.enums == []
      assert result.constants == []
      assert result.constructor == nil
    end

    test "returns error for invalid Solidity" do
      assert {:error, {:parse_error, _reason}} = Solidity.parse_sol("not solidity {{{")
    end

    test "struct types resolve to tuple in signatures and return_type" do
      sol = File.read!(Path.join(@priv_contracts, "test_interface.sol"))
      assert {:ok, result} = Solidity.parse_sol(sol)

      get_user = Enum.find(result.functions, &(&1.name == "getUserData"))
      # UserData has 3 fields: uint256, address, bool → signature uses tuple
      assert get_user.signature == "getUserData(address)"
      # Return type wraps struct fields in parens
      assert get_user.return_type == "((uint256,address,bool))"

      # Output param should be tuple type with components
      assert [output] = get_user.outputs
      assert output.ty == "tuple"
      assert length(output.components) == 3
    end

    test "event with struct type resolves to tuple signature and components" do
      sol = File.read!(Path.join(@priv_contracts, "test_interface.sol"))
      assert {:ok, result} = Solidity.parse_sol(sol)

      assert [event] = result.events
      assert event.name == "Updated"
      # Struct expands in signature: Updated((uint256,address,bool))
      assert event.signature == "Updated((uint256,address,bool))"
      assert is_binary(event.topic)
      assert String.starts_with?(event.topic, "0x")

      # Input param has tuple type with components
      assert [input] = event.inputs
      assert input.ty == "tuple"
      assert length(input.components) == 3
    end

    test "error with struct type resolves to tuple signature and components" do
      sol = File.read!(Path.join(@priv_contracts, "test_interface.sol"))
      assert {:ok, result} = Solidity.parse_sol(sol)

      assert [err] = result.errors
      assert err.name == "BadData"
      # Struct expands in signature: BadData((uint256,address,bool))
      assert err.signature == "BadData((uint256,address,bool))"
      assert is_binary(err.selector)
      assert String.starts_with?(err.selector, "0x")

      # Input param has tuple type with components
      assert [input] = err.inputs
      assert input.ty == "tuple"
      assert length(input.components) == 3
    end

    test "nested struct resolves recursively" do
      sol = File.read!(Path.join(@priv_contracts, "test_interface.sol"))
      assert {:ok, result} = Solidity.parse_sol(sol)

      get_nested = Enum.find(result.functions, &(&1.name == "getNested"))
      assert get_nested

      # Nested has fields: uint256 id, UserData data
      # UserData expands to (uint256,address,bool)
      # So Nested becomes (uint256,(uint256,address,bool))
      assert get_nested.return_type == "((uint256,(uint256,address,bool)))"

      # Output param is tuple with 2 components
      assert [output] = get_nested.outputs
      assert output.ty == "tuple"
      assert length(output.components) == 2

      # Second component (data) is itself a tuple with 3 sub-components
      data_comp = Enum.at(output.components, 1)
      assert data_comp.name == "data"
      assert data_comp.ty == "tuple"
      assert length(data_comp.components) == 3
    end

    test "parses block-style NatSpec comments" do
      sol = File.read!(Path.join(@priv_contracts, "test_interface.sol"))
      assert {:ok, result} = Solidity.parse_sol(sol)

      name_fn = Enum.find(result.functions, &(&1.name == "name"))
      assert name_fn.natspec
      assert name_fn.natspec.notice == "Get the token name"
      assert name_fn.natspec.returns["name"] == "The token name string"
    end

    test "has all required map keys" do
      sol = File.read!(Path.join(@priv_contracts, "test_interface.sol"))
      assert {:ok, result} = Solidity.parse_sol(sol)

      assert Map.has_key?(result, :functions)
      assert Map.has_key?(result, :events)
      assert Map.has_key?(result, :errors)
      assert Map.has_key?(result, :constructor)
      assert Map.has_key?(result, :structs)
      assert Map.has_key?(result, :enums)
      assert Map.has_key?(result, :constants)
    end
  end

  describe "parse_sol!/1" do
    test "returns map on success" do
      sol = """
      pragma solidity ^0.8.0;
      interface ISimple {
          function decimals() external pure returns (uint8);
      }
      """

      result = Solidity.parse_sol!(sol)
      assert is_map(result)
      assert [func] = result.functions
      assert func.name == "decimals"
    end

    test "raises on invalid input" do
      assert_raise RuntimeError, ~r/Solidity parse failed/, fn ->
        Solidity.parse_sol!("not solidity {{{")
      end
    end
  end

  describe "parse_sol_file/1" do
    test "reads and parses file" do
      path = Path.join(@priv_contracts, "test_interface.sol")
      assert {:ok, result} = Solidity.parse_sol_file(path)
      assert length(result.functions) == 6
    end

    test "returns file_error for missing file" do
      assert {:error, {:file_error, reason}} = Solidity.parse_sol_file("/nonexistent/file.sol")
      assert reason =~ "/nonexistent/file.sol"
    end
  end

  describe "parse_sol_file!/1" do
    test "returns map on success" do
      path = Path.join(@priv_contracts, "test_interface.sol")
      assert %{functions: funcs} = Solidity.parse_sol_file!(path)
      assert length(funcs) == 6
    end

    test "raises on missing file" do
      assert_raise RuntimeError, ~r/Solidity file error/, fn ->
        Solidity.parse_sol_file!("/nonexistent/file.sol")
      end
    end
  end

  describe "resolve_sol_file/2" do
    test "resolves a real DefiSaver file graph with relative imports" do
      path =
        Path.join(
          @priv_contracts,
          "real/defisaver-v3-contracts/contracts/interfaces/protocols/aaveV3/IPoolV3.sol"
        )

      assert {:ok, resolution} = Solidity.resolve_sol_file(path)
      assert resolution.root_contract == "IPoolV3"
      assert Enum.any?(resolution.files, &String.ends_with?(&1, "IPoolV3.sol"))
      assert Enum.any?(resolution.files, &String.ends_with?(&1, "DataTypes.sol"))
      assert Enum.any?(resolution.files, &String.ends_with?(&1, "IPoolAddressesProvider.sol"))
      assert String.contains?(resolution.source, "interface IPoolV3")
      assert String.contains?(resolution.source, "library DataTypes")
    end

    test "resolves a real Aave file graph with remappings" do
      path =
        Path.join(
          @priv_contracts,
          "real/aave-v3-periphery/contracts/misc/interfaces/IUiPoolDataProviderV3.sol"
        )

      assert {:ok, resolution} = Solidity.resolve_sol_file(path)
      assert resolution.root_contract == "IUiPoolDataProviderV3"
      assert Enum.any?(resolution.files, &String.ends_with?(&1, "IUiPoolDataProviderV3.sol"))

      assert Enum.any?(
               resolution.files,
               &String.ends_with?(&1, "lib/aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol")
             )
    end
  end

  describe "parse_sol_file/2 with real fixtures" do
    test "parses DefiSaver relative imports, namespaced structs, and imported contract types" do
      path =
        Path.join(
          @priv_contracts,
          "real/defisaver-v3-contracts/contracts/interfaces/protocols/aaveV3/IPoolV3.sol"
        )

      assert {:ok, result} = Solidity.parse_sol_file(path)

      assert Enum.any?(result.functions, &(&1.name == "getReserveData"))
      refute Enum.any?(result.functions, &(&1.name == "getMarketId"))

      get_reserve_data = Enum.find(result.functions, &(&1.name == "getReserveData"))

      assert get_reserve_data.return_type ==
               "(((uint256),uint128,uint128,uint128,uint128,uint128,uint40,uint16,address,address,address,address,uint128,uint128,uint128))"

      assert [reserve_output] = get_reserve_data.outputs
      assert reserve_output.ty == "tuple"
      assert length(reserve_output.components) == 15

      configuration = Enum.at(reserve_output.components, 0)
      assert configuration.name == "configuration"
      assert configuration.ty == "tuple"
      assert [%{name: "data", ty: "uint256"}] = configuration.components

      addresses_provider = Enum.find(result.functions, &(&1.name == "ADDRESSES_PROVIDER"))
      assert addresses_provider.return_type == "(address)"
      assert [%{name: "", ty: "address"}] = addresses_provider.outputs
    end

    test "parses Aave remapped imports and canonicalizes imported interface params" do
      path =
        Path.join(
          @priv_contracts,
          "real/aave-v3-periphery/contracts/misc/interfaces/IUiPoolDataProviderV3.sol"
        )

      assert {:ok, result} = Solidity.parse_sol_file(path)

      assert Enum.any?(result.functions, &(&1.name == "getReservesData"))
      refute Enum.any?(result.functions, &(&1.name == "getMarketId"))

      get_reserves_data = Enum.find(result.functions, &(&1.name == "getReservesData"))
      assert get_reserves_data.signature == "getReservesData(address)"
      assert [%{name: "provider", ty: "address"}] = get_reserves_data.inputs
    end
  end

  describe "roundtrip with Onchain.ABI" do
    test "parsed signatures produce matching selectors when encoded" do
      json = File.read!(Path.join(@priv_abis, "aave_pool.json"))
      assert {:ok, abi} = Solidity.parse_abi_json(json)

      for func <- abi.functions, func.inputs != [] do
        {:ok, calldata} = Onchain.ABI.encode_call(func.signature, dummy_args(func.inputs))
        encoded_selector = String.slice(calldata, 0, 10)

        assert encoded_selector == func.selector,
               "Selector mismatch for #{func.name}: encoded=#{encoded_selector}, parsed=#{func.selector}"
      end
    end
  end

  describe "roundtrip: parse_sol vs parse_abi_json consistency" do
    test "selectors match between sol and abi_json for same contract" do
      # Build a minimal ERC-20 interface in both formats
      sol = """
      pragma solidity ^0.8.0;
      interface IERC20 {
          function balanceOf(address account) external view returns (uint256);
          function transfer(address to, uint256 amount) external returns (bool);
          function decimals() external pure returns (uint8);
      }
      """

      abi_json = ~s([
        {"inputs":[{"name":"account","type":"address"}],"name":"balanceOf","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
        {"inputs":[{"name":"to","type":"address"},{"name":"amount","type":"uint256"}],"name":"transfer","outputs":[{"name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"},
        {"inputs":[],"name":"decimals","outputs":[{"name":"","type":"uint8"}],"stateMutability":"pure","type":"function"}
      ])

      {:ok, from_sol} = Solidity.parse_sol(sol)
      {:ok, from_json} = Solidity.parse_abi_json(abi_json)

      for json_func <- from_json.functions do
        sol_func = Enum.find(from_sol.functions, &(&1.name == json_func.name))
        assert sol_func, "Function #{json_func.name} not found in sol parse"

        assert sol_func.signature == json_func.signature,
               "Signature mismatch for #{json_func.name}: sol=#{sol_func.signature}, json=#{json_func.signature}"

        assert sol_func.selector == json_func.selector,
               "Selector mismatch for #{json_func.name}: sol=#{sol_func.selector}, json=#{json_func.selector}"

        assert sol_func.return_type == json_func.return_type,
               "Return type mismatch for #{json_func.name}: sol=#{sol_func.return_type}, json=#{json_func.return_type}"
      end
    end
  end

  describe "regression: same-named structs in different interfaces" do
    test "structs with same short name in different interfaces get distinct canonical names" do
      sol = """
      pragma solidity ^0.8.0;
      interface IA {
          struct Data { uint256 x; }
          function getA() external view returns (Data memory);
      }
      interface IB {
          struct Data { address y; }
          function getB() external view returns (Data memory);
      }
      """

      assert {:ok, result} = Solidity.parse_sol(sol)

      struct_names = result.structs |> Enum.map(& &1.name) |> Enum.sort()
      assert struct_names == ["IA.Data", "IB.Data"]

      ia_data = Enum.find(result.structs, &(&1.name == "IA.Data"))
      ib_data = Enum.find(result.structs, &(&1.name == "IB.Data"))

      assert [%{name: "x", ty: "uint256"}] = ia_data.fields
      assert [%{name: "y", ty: "address"}] = ib_data.fields
    end

    test "root contract resolves types from its own scope correctly" do
      sol = """
      pragma solidity ^0.8.0;
      interface IA {
          struct Data { uint256 x; }
          function getA() external view returns (Data memory);
      }
      interface IB {
          struct Data { address y; }
          function getB() external view returns (Data memory);
      }
      """

      # Use the root-contract NIF to parse each interface independently
      {:ok, result_a} = Solidity.__parse_sol_root__(sol, "IA")
      {:ok, result_b} = Solidity.__parse_sol_root__(sol, "IB")

      get_a = Enum.find(result_a.functions, &(&1.name == "getA"))
      get_b = Enum.find(result_b.functions, &(&1.name == "getB"))

      # IA.Data has uint256 → return type should be ((uint256))
      assert get_a.return_type == "((uint256))"

      # IB.Data has address → return type should be ((address))
      assert get_b.return_type == "((address))"
    end
  end

  # --- Helpers ---

  @doc false
  # Finds a function by name in the parsed ABI, raises if not found
  defp find_function(abi, name) do
    Enum.find(abi.functions, fn f -> f.name == name end) ||
      raise "Function #{name} not found in ABI"
  end

  @doc false
  defp dummy_args(inputs), do: Enum.map(inputs, &dummy_value/1)

  @doc false
  defp dummy_value(%{ty: "address"}), do: <<0::160>>
  defp dummy_value(%{ty: "bool"}), do: false
  defp dummy_value(%{ty: "string"}), do: ""
  defp dummy_value(%{ty: "bytes"}), do: ""
  defp dummy_value(%{ty: "tuple", components: comps}), do: List.to_tuple(dummy_args(comps))
  defp dummy_value(%{ty: "uint" <> _}), do: 0
  defp dummy_value(%{ty: "int" <> _}), do: 0
  defp dummy_value(%{ty: "bytes" <> _}), do: <<0::256>>
  defp dummy_value(_), do: 0
end
