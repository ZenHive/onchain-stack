defmodule Onchain.Aerodrome.Types.AbiDriftTest do
  use ExUnit.Case, async: true

  alias Onchain.Aerodrome.Types.Lp
  alias Onchain.Aerodrome.Types.LpEpoch
  alias Onchain.Aerodrome.Types.Position
  alias Onchain.Aerodrome.Types.Relay
  alias Onchain.Aerodrome.Types.Reward
  alias Onchain.Aerodrome.Types.Swap
  alias Onchain.Aerodrome.Types.Token
  alias Onchain.Aerodrome.Types.VeNFT
  alias Onchain.Aerodrome.Types.Vote

  @types_dir Path.expand("../../../../lib/onchain/aerodrome/types", __DIR__)

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

    test "VeNFT fields match ve_sugar.json byId components in ABI order" do
      assert struct_field_names(VeNFT) == abi_field_names("ve_sugar.json", "byId")
    end

    test "Vote is the single {lp, weight} shape shared by VeNFT and Relay" do
      ve_votes = nested_components("ve_sugar.json", "byId", "votes")
      relay_votes = nested_components("relay_sugar.json", "all", "votes", ["address"])

      # Byte-identical nested components are why Vote is defined once.
      assert ve_votes == relay_votes
      assert struct_field_names(Vote) == Enum.map(ve_votes, & &1["name"])

      ve_source = File.read!(Path.join(@types_dir, "ve_nft.ex"))
      relay_source = File.read!(Path.join(@types_dir, "relay.ex"))

      assert ve_source =~ "alias Onchain.Aerodrome.Types.Vote"
      assert relay_source =~ "alias Onchain.Aerodrome.Types.Vote"
      refute ve_source =~ ~r/defstruct\s+\[:lp,\s*:weight\]/
      refute relay_source =~ ~r/defstruct\s+\[:lp,\s*:weight\]/
    end

    test "Relay fields match relay_sugar.json all(address) components in ABI order" do
      # Field names come from the ABI JSON in this test. Do not transcribe a
      # count: Relay is wider than RelaySugar's function count, and hand
      # counts of this struct have already been wrong more than once.
      components = abi_components("relay_sugar.json", "all", ["address"])
      assert struct_field_names(Relay) == Enum.map(components, & &1["name"])

      account = Enum.find(components, &(&1["name"] == "account_venfts"))
      assert struct_field_names(Relay.AccountVeNFT) == Enum.map(account["components"], & &1["name"])
    end

    test "LpEpoch fields match rewards_sugar.json epochsLatest components in ABI order" do
      components = abi_components("rewards_sugar.json", "epochsLatest")
      assert struct_field_names(LpEpoch) == Enum.map(components, & &1["name"])

      bribes = Enum.find(components, &(&1["name"] == "bribes"))
      fees = Enum.find(components, &(&1["name"] == "fees"))
      assert bribes["components"] == fees["components"]
      assert struct_field_names(LpEpoch.TokenAmount) == Enum.map(bribes["components"], & &1["name"])
    end

    test "Reward fields match rewards_sugar.json rewards components in ABI order" do
      assert struct_field_names(Reward) == abi_field_names("rewards_sugar.json", "rewards")
    end

    test "LpEpoch TokenAmount is not Types.Reward" do
      bribes = nested_components("rewards_sugar.json", "epochsLatest", "bribes")
      refute struct_field_names(LpEpoch.TokenAmount) == struct_field_names(Reward)
      assert struct_field_names(LpEpoch.TokenAmount) == Enum.map(bribes, & &1["name"])
      assert struct_field_names(Reward) == abi_field_names("rewards_sugar.json", "rewards")
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

  defp abi_field_names(file, function, input_types \\ nil) do
    Enum.map(abi_components(file, function, input_types), & &1["name"])
  end

  defp nested_components(file, function, field, input_types \\ nil) do
    file
    |> abi_components(function, input_types)
    |> Enum.find(&(&1["name"] == field))
    |> Map.fetch!("components")
  end

  defp abi_components(file, function, input_types \\ nil) do
    @abi_dir
    |> Path.join(file)
    |> File.read!()
    |> Jason.decode!()
    |> Enum.find(&function_match?(&1, function, input_types))
    |> Map.fetch!("outputs")
    |> hd()
    |> Map.fetch!("components")
  end

  defp function_match?(%{"type" => "function", "name" => name}, function, nil) when name == function do
    true
  end

  defp function_match?(%{"type" => "function", "name" => name, "inputs" => inputs}, function, input_types)
       when name == function do
    Enum.map(inputs, & &1["type"]) == input_types
  end

  defp function_match?(_entry, _function, _input_types), do: false
end
