defmodule Onchain.Aerodrome.Types.AbiDriftTest do
  use ExUnit.Case, async: true

  alias Onchain.Aerodrome.Types.Lp
  alias Onchain.Aerodrome.Types.Position
  alias Onchain.Aerodrome.Types.Swap
  alias Onchain.Aerodrome.Types.Token

  # Drift tests read the captured ABI JSON themselves. Types must not go
  # through Bindings.Abi: the layer contract forbids that edge, and a helper
  # that shared Bindings' parse would hide a Sugar re-capture that the
  # bindings layer had already absorbed.
  @abi_dir Application.app_dir(:onchain_aerodrome, "priv/abis")

  describe "ABI field-order drift" do
    test "Lp fields match lp_sugar.json all components in ABI order" do
      assert struct_field_names(Lp) == abi_field_names("lp_sugar.json", "all")
    end

    test "Position fields match lp_sugar.json positions components in ABI order" do
      assert struct_field_names(Position) == abi_field_names("lp_sugar.json", "positions")
    end

    test "Swap fields match lp_sugar.json forSwaps components in ABI order" do
      assert struct_field_names(Swap) == abi_field_names("lp_sugar.json", "forSwaps")
    end

    test "Token fields match lp_sugar.json tokens components in ABI order" do
      assert struct_field_names(Token) == abi_field_names("lp_sugar.json", "tokens")
    end

    test "Token matches the tokens output of both lp_sugar.json and token_sugar.json" do
      lp_components = abi_components("lp_sugar.json", "tokens")
      token_components = abi_components("token_sugar.json", "tokens")

      # Byte-identical component arrays are the shared-type contract. A
      # future capture that diverges the two ABIs must fail here.
      assert lp_components == token_components
      assert struct_field_names(Token) == Enum.map(lp_components, & &1["name"])
      assert struct_field_names(Token) == Enum.map(token_components, & &1["name"])
    end
  end

  defp struct_field_names(module) do
    module
    |> struct_fields()
    |> Enum.map(&Atom.to_string/1)
  end

  defp struct_fields(module) do
    for %{field: field} <- List.wrap(module.__info__(:struct)), do: field
  end

  defp abi_field_names(file, function) do
    Enum.map(abi_components(file, function), & &1["name"])
  end

  defp abi_components(file, function) do
    @abi_dir
    |> Path.join(file)
    |> File.read!()
    |> Jason.decode!()
    |> Enum.find(&(&1["type"] == "function" and &1["name"] == function))
    |> Map.fetch!("outputs")
    |> hd()
    |> Map.fetch!("components")
  end
end
