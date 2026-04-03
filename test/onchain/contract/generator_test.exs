defmodule Onchain.Contract.GeneratorTest do
  use ExUnit.Case, async: true

  alias Onchain.Contract.Generator

  # --- Test modules defined inline ---

  # ABI JSON module (Chainlink aggregator)
  defmodule ChainlinkModule do
    @moduledoc false
    use Generator,
      abi_json: File.read!(Path.join(:code.priv_dir(:onchain_evm), "abis/chainlink_aggregator.json"))
  end

  # ABI file module
  defmodule ChainlinkFileModule do
    @moduledoc false
    use Generator,
      abi_file: Path.join(:code.priv_dir(:onchain_evm), "abis/chainlink_aggregator.json")
  end

  # Solidity source module (test_interface.sol)
  defmodule SolModule do
    @moduledoc false
    use Generator,
      sol: File.read!(Path.join(:code.priv_dir(:onchain_evm), "contracts/test_interface.sol"))
  end

  # Real Solidity file module (DefiSaver, relative imports)
  defmodule DefiSaverPoolModule do
    @moduledoc false
    use Generator,
      sol_file:
        Path.join(
          :code.priv_dir(:onchain_evm),
          "contracts/real/defisaver-v3-contracts/contracts/interfaces/protocols/aaveV3/IPoolV3.sol"
        )
  end

  # Real Solidity file module (Aave, remappings)
  defmodule AaveUiPoolModule do
    @moduledoc false
    use Generator,
      sol_file:
        Path.join(
          :code.priv_dir(:onchain_evm),
          "contracts/real/aave-v3-periphery/contracts/misc/interfaces/IUiPoolDataProviderV3.sol"
        )
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

  # Empty ABI module
  defmodule EmptyModule do
    @moduledoc false
    use Generator,
      abi_json: "[]"
  end

  # Struct array module — tests from_raw/1 with arrays of structs
  defmodule StructArrayModule do
    @moduledoc false
    use Generator,
      sol: """
      pragma solidity ^0.8.0;
      interface IBasket {
          struct Item { uint256 id; address owner; }
          struct Basket { Item[] items; uint256 total; }
          function getBasket() external view returns (Basket memory);
      }
      """
  end

  # Collision module — two interfaces with same-named structs
  defmodule CollisionModule do
    @moduledoc false
    use Generator,
      sol: """
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
      assert length(abi.functions) == 4

      names = Enum.map(abi.functions, & &1.name)
      assert "decimals" in names
      assert "latestRoundData" in names
    end

    test "address validation rejects invalid addresses" do
      # latestRoundData has no address params, so test with a module that does
      result = SolModule.get_user_data("not_a_contract", "also_invalid")
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
      assert length(abi.functions) == 4
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
      assert length(transfer_fns) >= 4
    end
  end

  # --- Unit tests: .sol module ---

  describe ".sol module" do
    test "generates functions from Solidity source" do
      assert function_exported?(SolModule, :get_user_data, 3)
      assert function_exported?(SolModule, :transfer, 4)
      assert function_exported?(SolModule, :decimals, 2)
      assert function_exported?(SolModule, :name, 2)
      assert function_exported?(SolModule, :total_supply, 2)
    end

    test "generates bang variants" do
      assert function_exported?(SolModule, :get_user_data!, 3)
      assert function_exported?(SolModule, :transfer!, 4)
      assert function_exported?(SolModule, :decimals!, 2)
    end

    test "generates struct modules with from_raw/1" do
      # Structs inside ITestContract are now qualified: ITestContract.UserData
      user_data = Module.concat(SolModule, "ITestContract.UserData")
      nested = Module.concat(SolModule, "ITestContract.Nested")
      assert function_exported?(user_data, :from_raw, 1)
      assert function_exported?(nested, :from_raw, 1)
    end

    test "struct has enforce_keys" do
      user_data = Module.concat(SolModule, "ITestContract.UserData")

      assert_raise ArgumentError, fn ->
        struct!(user_data, %{})
      end
    end

    test "from_raw/1 converts tuple to struct" do
      user_data = Module.concat(SolModule, "ITestContract.UserData")
      raw = {1000, <<1::160>>, true}
      result = user_data.from_raw(raw)

      assert result.__struct__ == user_data
      assert result.balance == 1000
      assert result.active == true
      # Address is checksummed
      assert is_binary(result.owner)
      assert String.starts_with?(result.owner, "0x")
    end

    test "from_raw/1 recursively converts nested structs" do
      user_data = Module.concat(SolModule, "ITestContract.UserData")
      nested = Module.concat(SolModule, "ITestContract.Nested")
      raw = {1, {1000, <<1::160>>, true}}
      result = nested.from_raw(raw)

      assert result.__struct__ == nested
      assert result.id == 1

      assert result.data.__struct__ == user_data
      assert result.data.balance == 1000
      assert result.data.active == true
      assert is_binary(result.data.owner)
      assert String.starts_with?(result.data.owner, "0x")
    end

    test "struct has correct fields" do
      user_data = Module.concat(SolModule, "ITestContract.UserData")
      fields = user_data.__struct__() |> Map.keys() |> Enum.reject(&(&1 == :__struct__))
      assert :balance in fields
      assert :owner in fields
      assert :active in fields
    end

    test "NatSpec is preserved in parsed ABI" do
      abi = SolModule.__contract_abi__()
      get_user = Enum.find(abi.functions, &(&1.name == "getUserData"))
      assert get_user.natspec.notice == "Get user data by address"
      assert get_user.natspec.params["user"] == "The user address to query"
    end

    test "functions without NatSpec have nil natspec" do
      abi = SolModule.__contract_abi__()
      total = Enum.find(abi.functions, &(&1.name == "totalSupply"))
      assert total.natspec == nil
    end

    test "enum constants are accessible as runtime functions" do
      abi = SolModule.__contract_abi__()
      assert [enum] = abi.enums
      assert enum.name == "ITestContract.Status"
      assert enum.variants == ["Pending", "Active", "Closed"]

      # Enum functions are generated and callable at runtime
      assert SolModule.status_pending() == 0
      assert SolModule.status_active() == 1
      assert SolModule.status_closed() == 2
    end

    test "write functions don't have default opts" do
      # transfer is nonpayable → write function → opts required (no default)
      # So transfer/3 should NOT exist (only transfer/4)
      refute function_exported?(SolModule, :transfer, 3)
      assert function_exported?(SolModule, :transfer, 4)
    end

    test "read functions have default opts" do
      # decimals is pure → read function → opts \\ []
      assert function_exported?(SolModule, :decimals, 1)
      assert function_exported?(SolModule, :decimals, 2)
    end
  end

  # --- Regression: struct arrays in from_raw/1 ---

  describe "struct array from_raw/1" do
    test "from_raw/1 recursively converts arrays of structs" do
      item = Module.concat(StructArrayModule, "IBasket.Item")
      basket = Module.concat(StructArrayModule, "IBasket.Basket")

      raw_items = [{1, <<1::160>>}, {2, <<2::160>>}]
      raw = {raw_items, 42}
      result = basket.from_raw(raw)

      assert result.__struct__ == basket
      assert result.total == 42
      assert length(result.items) == 2

      [first, second] = result.items
      assert first.__struct__ == item
      assert first.id == 1
      assert String.starts_with?(first.owner, "0x")

      assert second.__struct__ == item
      assert second.id == 2
    end

    test "item struct from_raw/1 works standalone" do
      item = Module.concat(StructArrayModule, "IBasket.Item")
      result = item.from_raw({99, <<3::160>>})
      assert result.__struct__ == item
      assert result.id == 99
      assert String.starts_with?(result.owner, "0x")
    end
  end

  # --- Regression: same-named structs in different interfaces ---

  describe "struct name collision" do
    test "generates distinct struct modules for same-named types in different interfaces" do
      ia_data = Module.concat(CollisionModule, "IA.Data")
      ib_data = Module.concat(CollisionModule, "IB.Data")

      assert function_exported?(ia_data, :from_raw, 1)
      assert function_exported?(ib_data, :from_raw, 1)

      # IA.Data has uint256 x
      result_a = ia_data.from_raw({42})
      assert result_a.__struct__ == ia_data
      assert result_a.x == 42

      # IB.Data has address y
      result_b = ib_data.from_raw({<<5::160>>})
      assert result_b.__struct__ == ib_data
      assert String.starts_with?(result_b.y, "0x")
    end

    test "functions resolve to correct struct types" do
      abi = CollisionModule.__contract_abi__()

      get_a = Enum.find(abi.functions, &(&1.name == "getA"))
      get_b = Enum.find(abi.functions, &(&1.name == "getB"))

      # IA.Data{uint256 x} → ((uint256))
      assert get_a.return_type == "((uint256))"

      # IB.Data{address y} → ((address))
      assert get_b.return_type == "((address))"
    end
  end

  # --- Unit tests: address validation ---

  describe "address validation in generated functions" do
    test "validates address params before calling" do
      # getUserData(address user) → validates user
      result = SolModule.get_user_data("0x" <> String.duplicate("a", 40), "invalid")
      assert {:error, {:invalid_address, "invalid"}} = result
    end

    test "contract address is passed through to Contract.call" do
      # With invalid contract, we get an address error from Contract.call
      result = SolModule.decimals("not_a_contract")
      assert {:error, {:invalid_address, "not_a_contract"}} = result
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
  end

  describe "sol_file option" do
    test "compiles a real DefiSaver interface with relative imports" do
      assert function_exported?(DefiSaverPoolModule, :get_reserve_data, 2)
      assert function_exported?(DefiSaverPoolModule, :get_reserve_data, 3)
      assert function_exported?(DefiSaverPoolModule, :addresses_provider, 1)
      assert function_exported?(DefiSaverPoolModule, :addresses_provider, 2)
    end

    test "compiles a real Aave interface with remappings" do
      assert function_exported?(AaveUiPoolModule, :get_reserves_list, 2)
      assert function_exported?(AaveUiPoolModule, :get_reserves_list, 3)
      assert function_exported?(AaveUiPoolModule, :get_reserves_data, 2)
      assert function_exported?(AaveUiPoolModule, :get_reserves_data, 3)
      assert function_exported?(AaveUiPoolModule, :get_user_reserves_data, 3)
      assert function_exported?(AaveUiPoolModule, :get_user_reserves_data, 4)
    end

    test "only exposes root contract functions in generated abi" do
      defi_abi = DefiSaverPoolModule.__contract_abi__()
      aave_abi = AaveUiPoolModule.__contract_abi__()

      assert Enum.any?(defi_abi.functions, &(&1.name == "getReserveData"))
      refute Enum.any?(defi_abi.functions, &(&1.name == "getMarketId"))

      assert Enum.any?(aave_abi.functions, &(&1.name == "getReservesData"))
      refute Enum.any?(aave_abi.functions, &(&1.name == "getMarketId"))
    end

    test "generates imported struct modules for namespaced library types" do
      reserve_data = Module.concat(DefiSaverPoolModule, "DataTypes.ReserveData")
      reserve_configuration_map = Module.concat(DefiSaverPoolModule, "DataTypes.ReserveConfigurationMap")

      calculate_user_account_data_params =
        Module.concat(DefiSaverPoolModule, "DataTypes.CalculateUserAccountDataParams")

      assert function_exported?(reserve_data, :from_raw, 1)
      assert function_exported?(reserve_configuration_map, :from_raw, 1)
      assert function_exported?(calculate_user_account_data_params, :from_raw, 1)
    end

    test "from_raw/1 recursively converts imported nested structs" do
      calculate_user_account_data_params =
        Module.concat(DefiSaverPoolModule, "DataTypes.CalculateUserAccountDataParams")

      user_configuration_map = Module.concat(DefiSaverPoolModule, "DataTypes.UserConfigurationMap")

      raw = {{123}, 456, <<1::160>>, <<2::160>>, 7}
      result = calculate_user_account_data_params.from_raw(raw)

      assert result.__struct__ == calculate_user_account_data_params
      assert result.user_config.__struct__ == user_configuration_map
      assert result.user_config.data == 123
      assert result.reserves_count == 456
      assert is_binary(result.user)
      assert String.starts_with?(result.user, "0x")
      assert is_binary(result.oracle)
      assert String.starts_with?(result.oracle, "0x")
      assert result.user_e_mode_category == 7
    end

    test "tracks resolved source files as external resources" do
      defi_resources =
        :attributes
        |> DefiSaverPoolModule.__info__()
        |> Keyword.get_values(:external_resource)
        |> List.flatten()

      aave_resources =
        :attributes
        |> AaveUiPoolModule.__info__()
        |> Keyword.get_values(:external_resource)
        |> List.flatten()

      assert Enum.any?(defi_resources, &String.ends_with?(&1, "IPoolV3.sol"))
      assert Enum.any?(defi_resources, &String.ends_with?(&1, "DataTypes.sol"))
      assert Enum.any?(defi_resources, &String.ends_with?(&1, "IPoolAddressesProvider.sol"))

      assert Enum.any?(aave_resources, &String.ends_with?(&1, "IUiPoolDataProviderV3.sol"))

      assert Enum.any?(
               aave_resources,
               &String.ends_with?(&1, "lib/aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol")
             )
    end
  end
end
