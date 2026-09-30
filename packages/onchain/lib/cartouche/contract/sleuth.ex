defmodule Cartouche.Contract.Sleuth do
  @moduledoc false
  @abi_path Path.expand("../../../priv/Sleuth.json", __DIR__)

  # Sleuth deploys query bytecode inside eth_call. Its ABI says nonpayable,
  # but these bindings intentionally simulate it without sending a transaction.
  use Onchain.Contract.Generator,
    abi_json:
      @abi_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("abi")
      |> Enum.map(fn
        %{"type" => "function"} = entry -> Map.put(entry, "stateMutability", "view")
        entry -> entry
      end)
      |> Jason.encode!()

  @external_resource @abi_path
end
