defmodule Faucet.Source.ERC20Mint do
  @moduledoc """
  A testnet faucet **contract** exposing `mint(address token, address to, uint256 amount)`
  — the shape Aave deploys on Sepolia and Base Sepolia for its `TestnetERC20`
  reserves.

  Unlike the HTTP sources this one signs and broadcasts a transaction, so it
  needs a funded gas key and the optional `onchain` dependency
  (`Onchain.Signer`, `Onchain.ABI`). Without `onchain` every call returns
  `{:error, :onchain_not_available}`.

  Each request mints exactly the loop's `:deficit` (or `:amount` when given),
  so one request normally suffices.

  ## Options

    * `:faucet` — faucet contract address (required)
    * `:token` — ERC-20 to mint and to read the balance from (required)
    * `:rpc_url`, `:chain_id`, `:private_key` — signer configuration (required)
    * `:amount` — fixed mint amount per request; default is the loop's `:deficit`
    * `:gas_limit` (default 200_000), `:max_fee_per_gas`, `:max_priority_fee_per_gas`
    * `:send_transaction` — `(to, calldata, signer_opts) -> {:ok, hash} | {:error, _}`;
      defaults to `Onchain.Signer.send_transaction/3`. Injection point for tests.
    * `:req_options` — passed to Req for balance reads and receipt polling

  Known deployments (verify on-chain before relying on them):

    * Sepolia: faucet `#{"0xC959483DBa39aa9E78757139af0e9a2EDEb3f42D"}`
    * Base Sepolia: faucet `#{"0xd9145b5f45ad4519c7accd6e0a4a82e83bb8a6dc"}`,
      testUSDC `#{"0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f"}`
  """

  @behaviour Faucet.Source

  alias Faucet.EVM
  alias Faucet.JSONRPC

  @default_gas_limit 200_000
  @signature "mint(address,address,uint256)"

  @impl true
  def unit, do: "token units"

  @impl true
  def balance(address, opts) do
    with {:ok, token} <- require_opt(opts, :token) do
      EVM.erc20_balance(token, address, opts)
    end
  end

  @impl true
  def fund(address, opts) do
    with :ok <- ensure_onchain(),
         {:ok, faucet} <- require_opt(opts, :faucet),
         {:ok, token} <- require_opt(opts, :token),
         {:ok, key} <- require_opt(opts, :private_key),
         {:ok, chain_id} <- require_opt(opts, :chain_id),
         {:ok, rpc_url} <- require_opt(opts, :rpc_url),
         {:ok, amount} <- mint_amount(opts),
         {:ok, calldata} <- calldata(token, address, amount),
         {:ok, signer} <- Onchain.Signer.address_from_key(key),
         {:ok, nonce_hex} <- JSONRPC.call(rpc_url, "eth_getTransactionCount", [signer, "pending"], opts),
         {:ok, nonce} <- JSONRPC.quantity(nonce_hex) do
      signer_opts =
        opts
        |> Keyword.take([:max_fee_per_gas, :max_priority_fee_per_gas, :timeout])
        |> Keyword.merge(
          private_key: key,
          chain_id: chain_id,
          rpc_url: rpc_url,
          nonce: nonce,
          gas_limit: Keyword.get(opts, :gas_limit, @default_gas_limit)
        )

      send = Keyword.get(opts, :send_transaction, &Onchain.Signer.send_transaction/3)

      with {:ok, hash} <- send.(faucet, calldata, signer_opts), do: {:ok, [hash]}
    end
  end

  @impl true
  def wait_confirmed(hashes, _address, opts), do: EVM.wait_receipts(hashes, opts)

  @doc "ABI-encode the `mint(token, to, amount)` call as raw binary calldata (needs `onchain`)."
  @spec calldata(String.t(), String.t(), non_neg_integer()) :: {:ok, binary()} | {:error, term()}
  def calldata(token, to, amount) do
    with :ok <- ensure_onchain(),
         {:ok, token_bin} <- Onchain.Address.validate(token),
         {:ok, to_bin} <- Onchain.Address.validate(to),
         {:ok, hex} <- Onchain.ABI.encode_hex_call(@signature, [token_bin, to_bin, amount]) do
      {:ok, Onchain.Hex.decode!(hex)}
    end
  end

  defp mint_amount(opts) do
    case Keyword.get(opts, :amount) || Keyword.get(opts, :deficit) do
      amount when is_integer(amount) and amount > 0 -> {:ok, amount}
      other -> {:error, {:invalid_option, :amount, other}}
    end
  end

  defp require_opt(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_option, key}}
    end
  end

  defp ensure_onchain do
    if Code.ensure_loaded?(Onchain.Signer) and Code.ensure_loaded?(Onchain.ABI),
      do: :ok,
      else: {:error, :onchain_not_available}
  end
end
