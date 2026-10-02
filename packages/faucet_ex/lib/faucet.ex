defmodule Faucet do
  @moduledoc """
  Programmatic testnet funding for integration tests.

  One loop — read the balance, request funding, wait for it to land, read
  again — over pluggable sources. The loop lives here; each source knows one
  provider and one asset:

  | Source | Provider | Asset |
  |---|---|---|
  | `Faucet.Source.CDP` | Coinbase Developer Platform faucet | ETH / USDC / EURC / cbBTC on Base Sepolia, Ethereum Sepolia |
  | `Faucet.Source.Tempo` | Moderato `tempo_fundAddress` RPC | pathUSD (fee token) + native gas |
  | `Faucet.Source.Solana` | `requestAirdrop` RPC | SOL on devnet / testnet |
  | `Faucet.Source.XRPL` | Testnet faucet HTTP API | XRP drops on altnet |
  | `Faucet.Source.ERC20Mint` | A testnet token faucet contract (Aave-style `mint(token,to,amount)`) | Any mintable ERC-20 |
  | `Faucet.ForkOverride` | No provider — state override for `Onchain.EVM` fork simulation | ETH / ERC-20 balances |

  ## Usage

      # Top up an existing address to at least 0.001 ETH on Base Sepolia.
      {:ok, wei} = Faucet.ensure_min_balance(Faucet.Source.CDP, address, 1_000_000_000_000_000, network: "base-sepolia")

      # Fresh keypair funded with pathUSD on Tempo Moderato (needs `onchain`).
      {:ok, %{private_key: key, address_hex: hex}} = Faucet.EVM.fresh_funded_wallet(Faucet.Source.Tempo, 1_000_000)

      # In ExUnit: fail loudly with the provider's message instead of skipping.
      wei = Faucet.ensure_min_balance!(Faucet.Source.CDP, address, minimum, network: "base-sepolia")

  ## Options

  Loop options, read here; everything else is passed through to the source:

    * `:max_requests` — funding requests per call before giving up (default 10)
    * `:timeout_ms` — confirmation deadline per request (default 60_000)
    * `:poll_interval_ms` — confirmation poll interval (default 1_000)
    * `:lock` — serialize per `{source, address}` via `:global.trans/2` (default `true`)

  Every source documents its own keys (`:rpc_url`, `:network`, credentials).
  """

  use Descripex, namespace: "/faucet"
  use Descripex.Discoverable, modules: [Faucet.Wait, Faucet.JSONRPC, Faucet.EVM, Faucet.ForkOverride]

  alias Faucet.TopUp

  api(:ensure_min_balance, "Fund `address` through `source` until its balance reaches `minimum`.",
    params: [
      source: [kind: :value, description: "A module implementing `Faucet.Source`"],
      address: [kind: :value, description: "Recipient address in the source's native format"],
      minimum: [
        kind: :value,
        description: "Target balance in the source's base unit (wei, lamports, drops, token units)"
      ],
      opts: [
        kind: :value,
        default: [],
        description: "`:max_requests`, `:timeout_ms`, `:poll_interval_ms`, `:lock`, plus the source's own options"
      ]
    ],
    returns: %{
      type: "{:ok, balance} | {:error, {:budget_exhausted, map} | term}",
      description:
        "Final balance once at or above `minimum`; existing balances are reused, nothing is requested when already sufficient"
    }
  )

  @spec ensure_min_balance(module(), String.t(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, TopUp.error()}
  def ensure_min_balance(source, address, minimum, opts \\ [])
      when is_atom(source) and is_binary(address) and is_integer(minimum) and minimum >= 0 do
    TopUp.run(source, address, minimum, opts)
  end

  api(:ensure_min_balance!, "Same as `ensure_min_balance/4`; raises `Faucet.Error` with the provider's reason.",
    params: [
      source: [kind: :value, description: "A module implementing `Faucet.Source`"],
      address: [kind: :value, description: "Recipient address"],
      minimum: [kind: :value, description: "Target balance in base units"],
      opts: [kind: :value, default: [], description: "See `ensure_min_balance/4`"]
    ],
    returns: %{type: :integer, description: "Final balance"}
  )

  @spec ensure_min_balance!(module(), String.t(), non_neg_integer(), keyword()) :: non_neg_integer()
  def ensure_min_balance!(source, address, minimum, opts \\ []) do
    case ensure_min_balance(source, address, minimum, opts) do
      {:ok, balance} -> balance
      {:error, reason} -> raise Faucet.Error, source: source, address: address, minimum: minimum, reason: reason
    end
  end

  api(:fund, "Send exactly one funding request through `source`, without reading or waiting.",
    params: [
      source: [kind: :value, description: "A module implementing `Faucet.Source`"],
      address: [kind: :value, description: "Recipient address"],
      opts: [kind: :value, default: [], description: "The source's own options"]
    ],
    returns: %{type: "{:ok, [ref]} | {:error, term}", description: "Provider references (tx hashes, signatures)"}
  )

  @spec fund(module(), String.t(), keyword()) :: {:ok, [Faucet.Source.ref()]} | {:error, term()}
  def fund(source, address, opts \\ []) when is_atom(source), do: source.fund(address, opts)

  api(:balance, "Read `address`'s balance through `source`.",
    params: [
      source: [kind: :value, description: "A module implementing `Faucet.Source`"],
      address: [kind: :value, description: "Address to read"],
      opts: [kind: :value, default: [], description: "The source's own options"]
    ],
    returns: %{type: "{:ok, amount} | {:error, term}", description: "Balance in the source's base unit"}
  )

  @spec balance(module(), String.t(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def balance(source, address, opts \\ []) when is_atom(source), do: source.balance(address, opts)
end
