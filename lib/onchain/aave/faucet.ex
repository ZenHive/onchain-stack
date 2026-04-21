defmodule Onchain.Aave.Faucet do
  @moduledoc """
  Aave testnet faucet operations.

  Mints test ERC-20 tokens on Aave testnets (Sepolia). The faucet contract
  is testnet-only — calling `mint/4` with a mainnet network will return
  `{:error, {:unknown_contract, :faucet}}` from the address registry.

  ## Error Format

  Errors pass through from underlying modules:

  | Source | Error Shape |
  |--------|-------------|
  | `Onchain.Address.validate/1` | `{:error, {:invalid_address, input}}` |
  | `Onchain.Aave.Contracts.address/2` | `{:error, {:unknown_contract, :faucet}}` |
  | `Onchain.ABI.encode_call/2` | `{:error, {:encode_error, ...}}` |
  | `Onchain.Signer.send_transaction/3` | `{:error, {:missing_option, ...}}`, `{:error, {:sign_error, ...}}`, etc. |

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `mint/4` | Mint test tokens from the faucet (returns tx hash) |
  | `mint!/4` | Same, raises on error |
  """

  use Descripex, namespace: "/aave/faucet"

  alias Onchain.Aave.Contracts
  alias Onchain.ABI
  alias Onchain.Address
  alias Onchain.Hex
  alias Onchain.Signer

  @default_gas_limit 200_000

  # --- mint ---

  api(:mint, "Mint test ERC-20 tokens from the Aave testnet faucet.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address to mint"],
      to: [kind: :value, description: "Recipient address"],
      amount: [kind: :value, description: "Amount to mint (raw integer, not decimal-adjusted)"],
      opts: [
        kind: :value,
        description:
          "Required: :private_key, :nonce, :chain_id, :rpc_url, :network. Optional: :gas_limit (default 200k), :max_fee_per_gas, :max_priority_fee_per_gas"
      ]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Transaction hash hex string"
    }
  )

  @spec mint(String.t() | binary(), String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def mint(token, to, amount, opts) do
    {network_opts, signer_opts} = split_opts(opts)

    with {:ok, token_bin} <- Address.validate(token),
         {:ok, to_bin} <- Address.validate(to),
         {:ok, faucet_addr} <- Contracts.address(:faucet, network_opts),
         {:ok, calldata_hex} <-
           ABI.encode_call("mint(address,address,uint256)", [token_bin, to_bin, amount]) do
      Signer.send_transaction(faucet_addr, Hex.decode!(calldata_hex), signer_opts)
    end
  end

  # --- mint! ---

  api(:mint!, "Mint test ERC-20 tokens from the Aave testnet faucet. Raises on error.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address to mint"],
      to: [kind: :value, description: "Recipient address"],
      amount: [kind: :value, description: "Amount to mint (raw integer, not decimal-adjusted)"],
      opts: [
        kind: :value,
        description:
          "Required: :private_key, :nonce, :chain_id, :rpc_url, :network. Optional: :gas_limit (default 200k), :max_fee_per_gas, :max_priority_fee_per_gas"
      ]
    ],
    returns: %{type: :string, description: "Transaction hash hex string"}
  )

  @spec mint!(String.t() | binary(), String.t() | binary(), non_neg_integer(), keyword()) ::
          String.t()
  def mint!(token, to, amount, opts) do
    case mint(token, to, amount, opts) do
      {:ok, tx_hash} -> tx_hash
      {:error, reason} -> raise "mint failed: #{inspect(reason)}"
    end
  end

  # --- Private helpers ---

  @doc false
  # Splits opts into network lookup opts and signer opts, applying default gas limit.
  defp split_opts(opts) do
    {network, rest} = Keyword.pop(opts, :network, :ethereum)
    signer_opts = Keyword.put_new(rest, :gas_limit, @default_gas_limit)
    {[network: network], signer_opts}
  end
end
