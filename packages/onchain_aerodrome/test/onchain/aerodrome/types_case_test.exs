defmodule Onchain.Aerodrome.TypesCaseTest do
  use ExUnit.Case, async: true

  alias Onchain.Aerodrome.TypesCase

  # A hypothetical relay_sugar re-capture that grew a second `all` overload.
  # It is built here rather than captured: priv/abis holds real Sourcify
  # output and must not be edited to exercise a resolution rule.
  @overloaded [
    %{"type" => "constructor", "inputs" => []},
    %{
      "type" => "function",
      "name" => "all",
      "inputs" => [%{"name" => "_account", "type" => "address"}],
      "outputs" => [
        %{"type" => "tuple[]", "components" => [%{"name" => "venft_id", "type" => "uint256"}]}
      ]
    },
    %{
      "type" => "function",
      "name" => "all",
      "inputs" => [
        %{"name" => "_limit", "type" => "uint256"},
        %{"name" => "_offset", "type" => "uint256"}
      ],
      "outputs" => [
        %{"type" => "tuple[]", "components" => [%{"name" => "relay_id", "type" => "uint256"}]}
      ]
    }
  ]

  describe "ABI entry resolution across same-named overloads" do
    test "selects the overload whose input types the caller asked for" do
      assert %{"inputs" => [%{"type" => "address"}]} =
               TypesCase.resolve_entry(@overloaded, "relay_sugar.json", "all", ["address"])

      assert %{"inputs" => [%{"type" => "uint256"}, %{"type" => "uint256"}]} =
               TypesCase.resolve_entry(@overloaded, "relay_sugar.json", "all", ["uint256", "uint256"])
    end

    test "fails naming the file, the sought signature and the candidates when nothing matches" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          TypesCase.resolve_entry(@overloaded, "relay_sugar.json", "all", ["uint256"])
        end

      assert error.message =~ "relay_sugar.json"
      assert error.message =~ "all(uint256)"
      assert error.message =~ "all(address)"
      assert error.message =~ "all(uint256,uint256)"
    end

    test "says the file carries no such function rather than crashing on an empty match" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          TypesCase.resolve_entry(@overloaded, "relay_sugar.json", "byId", ["uint256"])
        end

      assert error.message =~ "byId(uint256)"
      assert error.message =~ "(none)"
    end

    test "refuses to guess when a bare name matches more than one overload" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          TypesCase.resolve_entry(@overloaded, "relay_sugar.json", "all", nil)
        end

      assert error.message =~ "2 ABI function entries match"
      assert error.message =~ "pass the overload's input types explicitly"
    end
  end

  describe "ABI entry resolution against the captured files" do
    test "resolves relay_sugar all(address) by name and input types" do
      assert [%{"name" => "venft_id"} | _] = TypesCase.abi_components("relay_sugar.json", "all", ["address"])
    end

    test "a wrong input-type list fails loudly instead of grading against the wrong entry" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          TypesCase.abi_components("relay_sugar.json", "all", ["uint256", "uint256"])
        end

      assert error.message =~ "relay_sugar.json"
      assert error.message =~ "all(uint256,uint256)"
      assert error.message =~ "all(address)"
    end
  end
end
