defmodule Onchain.Aerodrome.Contracts do
  @moduledoc """
  Aerodrome Finance contract address registry and verified protocol constants.

  Pure-function lookup for Aerodrome's deployed contracts on Base (chain id
  8453). Every other `Onchain.Aerodrome.*` module resolves addresses through
  here rather than hardcoding them at call sites.

  ## Supported Networks

  Base only (`:base`, chain id 8453). Aerodrome is a Base-native deployment;
  its Velodrome sibling on Optimism uses different addresses and is out of
  scope for this package.

  ## Address Provenance

  Every address below carries a comment naming the source it was verified
  against and the date. The two authorities are:

  1. `velodrome-finance/sugar@main:deployments/base.env` — the Sugar team's own
     deployment manifest, which is what the Sugar contracts themselves are
     wired to.
  2. A live `eth_call` against Base confirming the contract answers as
     expected (see `priv/abis/README.md` for the exact probes).

  BaseScan labels were used only as a cross-check, never as the sole source.

  ## Concentrated Liquidity Factories

  There are **three** CL (Slipstream) factories on Base, not one. `:cl_factory`
  resolves the primary one; `cl_factories/1` returns all three. Code that
  enumerates positions or pools must decide explicitly which factories are in
  scope — silently assuming one is a data-loss bug.

  ## Error Format

  - Unknown contract: `{:error, {:unknown_contract, key}}`
  - Unsupported network: `{:error, {:unsupported_network, network}}`

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `address/2` | Look up a contract's EIP-55 checksummed address |
  | `address!/2` | Same, raises on error |
  | `cl_factories/1` | All three Slipstream CL factory addresses |
  | `chain_id/1` | Chain id for a network |
  | `networks/0` | List supported networks |
  | `contracts/1` | List contract keys for a network |
  | `constants/0` | Verified on-chain protocol constants |
  """

  use Descripex, namespace: "/aerodrome/contracts"

  @chain_ids %{base: 8453}

  # All addresses verified 2026-08-26 against
  # velodrome-finance/sugar@main:deployments/base.env plus a live eth_call.
  @addresses %{
    base: %{
      # Sugar read layer. LpSugar.count() answered 35_156 on 2026-08-26 (it only grows).
      lp_sugar: "0x69dD9db6d8f8E7d83887A704f447b1a584b599A1",
      rewards_sugar: "0x1b121EfDaF4ABb8785a315C51D29BCE0552A7678",
      ve_sugar: "0x4d6A741cEE6A8cC5632B2d948C050303F6246D24",
      relay_sugar: "0x3dd0849D66DBd63D06f11442502e200601c50790",
      # LpSugar.token_sugar() returns this address — self-confirming.
      token_sugar: "0x910CD56277994B4970F49AEDA52c96aD620aE81D",
      # Protocol core.
      voter: "0x16613524e02ad97eDfeF371bC883F2F5d6C480A5",
      factory_registry: "0x5C3F18F06CC09CA1910767A34a20F771039E37C0",
      # v2 (volatile + stable) pool factory. BaseScan: "Aerodrome: Pool Factory".
      pool_factory: "0x420DD381b31aEf6683db6B902084cB0FFECe40Da",
      # Primary Slipstream CL factory. See cl_factories/1 for all three.
      cl_factory: "0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A",
      alm_factory: "0xE46EC96906fc6dEC53De25F013639969Fe10180d",
      slipstream_helper: "0x9c62ab10577fB3C20A22E231b7703Ed6D456CC7a"
    }
  }

  # base.env CL_FACTORIES_8453 — order preserved as published.
  @cl_factories %{
    base: [
      "0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A",
      "0xaDe65c38CD4849aDBA595a4323a8C7DdfE89716a",
      "0xf8f2eB4940CFE7d13603DDDD87f123820Fc061Ef"
    ]
  }

  # Verified live on 2026-08-26 against https://mainnet.base.org.
  # Probes are recorded in priv/abis/README.md; re-run them after any redeploy.
  @constants %{
    # cast call <cl_factory> "tickSpacings()(int24[])" — raw return order.
    tick_spacings: [1, 50, 100, 200, 2000, 10],
    # cast call <cl_factory> "defaultUnstakedFee()(uint24)" => 100_000 pips.
    # Pips are 1e-6, so this is 10% of an unstaked CL position's trading fees
    # routed to the gauge. Per-pool overridable; Lp.unstaked_fee is authority.
    default_unstaked_fee_pips: 100_000,
    unstaked_fee_denominator: 1_000_000,
    # Hard per-call caps compiled into LpSugar/RewardsSugar. Exceeding them
    # reverts; limit: 500 is confirmed working against the public Base RPC.
    max_lps: 500,
    max_positions: 200,
    max_tokens: 2000,
    # ve(3,3) epoch length. Epochs flip Thursday 00:00 UTC because Unix epoch 0
    # was a Thursday, so floor(ts / week) * week lands on Thursday midnight.
    epoch_seconds: 604_800
  }

  # --- address ---

  api(:address, "Look up an Aerodrome contract's EIP-55 checksummed address.",
    params: [
      contract: [
        kind: :value,
        description: "Contract key atom, e.g. :lp_sugar, :voter, :cl_factory"
      ],
      opts: [kind: :value, default: [], description: "Options: [network: :base]"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Checksummed hex address",
      example: "0x69dD9db6d8f8E7d83887A704f447b1a584b599A1"
    }
  )

  @spec address(atom(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def address(contract, opts \\ []) do
    network = Keyword.get(opts, :network, :base)

    case @addresses do
      %{^network => %{^contract => hex}} -> Onchain.Address.checksum(hex)
      %{^network => _keys} -> {:error, {:unknown_contract, contract}}
      %{} -> {:error, {:unsupported_network, network}}
    end
  end

  # --- address! ---

  api(:address!, "Look up an Aerodrome contract's address. Raises on error.",
    params: [
      contract: [kind: :value, description: "Contract key atom, e.g. :lp_sugar"],
      opts: [kind: :value, default: [], description: "Options: [network: :base]"]
    ],
    returns: %{
      type: :string,
      description: "Checksummed hex address"
    }
  )

  @spec address!(atom(), keyword()) :: String.t()
  def address!(contract, opts \\ []) do
    case address(contract, opts) do
      {:ok, addr} -> addr
      {:error, reason} -> raise "address lookup failed: #{inspect(reason)}"
    end
  end

  # --- cl_factories ---

  api(:cl_factories, "List every Slipstream concentrated-liquidity factory address.",
    params: [
      opts: [kind: :value, default: [], description: "Options: [network: :base]"]
    ],
    returns: %{
      type: "{:ok, [String.t()]} | {:error, {:unsupported_network, atom()}}",
      description: "Checksummed CL factory addresses, published order preserved"
    }
  )

  @spec cl_factories(keyword()) :: {:ok, [String.t()]} | {:error, {:unsupported_network, atom()}}
  def cl_factories(opts \\ []) do
    network = Keyword.get(opts, :network, :base)

    case @cl_factories do
      %{^network => hexes} -> checksum_all(hexes)
      %{} -> {:error, {:unsupported_network, network}}
    end
  end

  # Checksum a list, short-circuiting on the first malformed address so a typo
  # in the registry surfaces as an error rather than a silently skipped entry.
  @spec checksum_all([String.t()]) :: {:ok, [String.t()]} | {:error, term()}
  defp checksum_all(hexes) do
    hexes
    |> Enum.reduce_while({:ok, []}, fn hex, {:ok, acc} ->
      case Onchain.Address.checksum(hex) do
        {:ok, addr} -> {:cont, {:ok, [addr | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, _reason} = error -> error
    end
  end

  # --- chain_id ---

  api(:chain_id, "Chain id for a supported network.",
    params: [
      opts: [kind: :value, default: [], description: "Options: [network: :base]"]
    ],
    returns: %{
      type: "{:ok, pos_integer()} | {:error, {:unsupported_network, atom()}}",
      description: "EIP-155 chain id",
      example: "8453"
    }
  )

  @spec chain_id(keyword()) :: {:ok, pos_integer()} | {:error, {:unsupported_network, atom()}}
  def chain_id(opts \\ []) do
    network = Keyword.get(opts, :network, :base)

    case @chain_ids do
      %{^network => id} -> {:ok, id}
      %{} -> {:error, {:unsupported_network, network}}
    end
  end

  # --- networks ---

  api(:networks, "List supported networks.",
    params: [],
    returns: %{
      type: "[atom()]",
      description: "List of network atoms",
      example: "[:base]"
    }
  )

  @spec networks() :: [atom()]
  def networks, do: Map.keys(@addresses)

  # --- contracts ---

  api(:contracts, "List available contract keys for a network.",
    params: [
      opts: [kind: :value, default: [], description: "Options: [network: :base]"]
    ],
    returns: %{
      type: "{:ok, [atom()]} | {:error, {:unsupported_network, atom()}}",
      description: "List of contract key atoms"
    }
  )

  @spec contracts(keyword()) :: {:ok, [atom()]} | {:error, {:unsupported_network, atom()}}
  def contracts(opts \\ []) do
    network = Keyword.get(opts, :network, :base)

    case @addresses do
      %{^network => network_map} -> {:ok, Map.keys(network_map)}
      %{} -> {:error, {:unsupported_network, network}}
    end
  end

  # --- constants ---

  api(:constants, "Verified on-chain protocol constants (pagination caps, fees, epoch).",
    params: [],
    returns: %{
      type: "map()",
      description: "Constants verified by live eth_call; see moduledoc for provenance",
      example: "%{max_lps: 500, epoch_seconds: 604_800}"
    }
  )

  @spec constants() :: map()
  def constants, do: @constants
end
