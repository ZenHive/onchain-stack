defmodule Onchain.AAIntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.AA

  @moduletag :integration

  # Read-only ERC-4337 bundler calls against a real bundler endpoint.
  #
  # Requires a bundler RPC URL (Alchemy/Pimlico/Stackup/etc.):
  #   export BUNDLER_RPC_URL="https://api.pimlico.io/v2/sepolia/rpc?apikey=..."
  #
  # None of these tests submit or mutate state — they only query the bundler.
  defp bundler_url! do
    System.get_env("BUNDLER_RPC_URL") ||
      flunk("""
      Missing bundler RPC URL!

      Set this environment variable to a real ERC-4337 bundler endpoint:
        export BUNDLER_RPC_URL="https://api.pimlico.io/v2/<chain>/rpc?apikey=YOUR_KEY"

      Bundlers: Pimlico, Alchemy, Stackup, Biconomy, or a self-hosted Voltaire/Skandha.
      """)
  end

  test "eth_supportedEntryPoints returns a non-empty address list" do
    assert {:ok, entry_points} = AA.supported_entry_points(bundler_url: bundler_url!())
    assert is_list(entry_points)
    assert entry_points != []
    assert Enum.all?(entry_points, &String.starts_with?(&1, "0x"))
  end

  test "eth_getUserOperationReceipt returns nil for an unknown hash" do
    # Non-zero hash: bundlers reject the all-zero value as invalid (-32602) rather
    # than treating it as a well-formed-but-unknown hash. Matches the byHash test below.
    unknown = "0x" <> String.duplicate("22", 32)

    case AA.get_user_operation_receipt(unknown, bundler_url: bundler_url!()) do
      {:ok, nil} -> :ok
      {:ok, other} -> flunk("Expected nil receipt for unknown hash, got: #{inspect(other)}")
      {:error, reason} -> flunk("Bundler call failed: #{inspect(reason)}")
    end
  end

  test "eth_getUserOperationByHash returns nil for an unknown hash" do
    unknown = "0x" <> String.duplicate("11", 32)

    case AA.get_user_operation_by_hash(unknown, bundler_url: bundler_url!()) do
      {:ok, nil} -> :ok
      {:ok, other} -> flunk("Expected nil for unknown hash, got: #{inspect(other)}")
      {:error, reason} -> flunk("Bundler call failed: #{inspect(reason)}")
    end
  end
end
