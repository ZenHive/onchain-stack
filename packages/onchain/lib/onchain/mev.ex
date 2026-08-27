defmodule Onchain.MEV do
  @moduledoc """
  MEV protection via private transaction submission to Flashbots-style relays.

  Routes signed transactions (or atomic bundles) to a private relay endpoint
  instead of the public mempool, preventing front-running and sandwiching of
  DEX trades. The request envelope follows the Flashbots Auction JSON-RPC API
  (`eth_sendPrivateTransaction`, `eth_sendBundle`) — see
  https://docs.flashbots.net/flashbots-auction/advanced/rpc-endpoint.

  ## Endpoint and auth are caller-supplied

  Unlike `Onchain.RPC`, there is **no fallback to the configured public node**.
  Silently leaking a would-be-private transaction to the public RPC defeats the
  entire purpose, so the relay URL is a required `:endpoint` option — omitting it
  returns `{:error, :missing_endpoint}` rather than broadcasting.

  Relay authentication (Flashbots requires an `X-Flashbots-Signature: <addr>:<sig>`
  header signed with an arbitrary secp256k1 reputation key) is **not** computed
  here. The caller passes whatever headers the relay needs via `:headers`, e.g.

      Onchain.MEV.send_bundle(txs,
        endpoint: "https://relay.flashbots.net",
        block_number: 19_000_000,
        headers: [{"X-Flashbots-Signature", "0xabc...:0xsig..."}]
      )

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `send_private_transaction/2` | Submit one signed tx privately → tx hash |
  | `send_bundle/2` | Submit an atomic bundle of signed txs → bundle response |

  ## Options

  - `:endpoint` — relay URL (**required**, no default)
  - `:headers` — extra request headers for relay auth (e.g. `X-Flashbots-Signature`)
  - `:timeout` — request timeout in ms (default 30_000)
  - `:max_block_number` — (private tx) highest block the tx may be included in
  - `:preferences` — (private tx) MEV-Share preferences map, passed through verbatim
  - `:block_number` — (bundle) target block (**required for bundles**)
  - `:min_timestamp` / `:max_timestamp` — (bundle) validity window in unix seconds
  - `:reverting_tx_hashes` — (bundle) tx hashes allowed to revert

  ## Error Format

  - Missing relay URL: `{:error, :missing_endpoint}`
  - Invalid relay URL: `{:error, {:invalid_endpoint, input}}`
  - Invalid signed tx hex: `{:error, {:invalid_data, input}}`
  - Empty bundle: `{:error, :empty_bundle}`
  - Non-list bundle: `{:error, {:invalid_bundle, input}}`
  - Bundle missing target block: `{:error, :missing_block_number}`
  - Invalid block value: `{:error, {:invalid_block, input}}`
  - Relay / transport errors: `{:error, {:rpc_error, map}}` — the map always has a
    `:message` key; relay-level JSON-RPC rejections also carry `:code`.
  """

  use Descripex, namespace: "/mev"

  import Onchain.RPC.Helpers, only: [ensure_hex_data: 1, normalize_block_number: 1]

  @default_timeout_ms 30_000

  # --- send_private_transaction ---

  api(:send_private_transaction, "Submit a signed transaction privately via a Flashbots-style relay.",
    params: [
      raw_tx: [kind: :exchange_data, description: "0x-prefixed signed raw transaction"],
      opts: [
        kind: :value,
        default: [],
        description:
          "Options: :endpoint (required relay URL), :headers (relay auth), :timeout, :max_block_number, :preferences"
      ]
    ],
    returns: %{
      type: "{:ok, tx_hash} | {:error, term}",
      description: "Transaction hash as 0x hex string",
      example: "0x45df1bc3de765927b053ec029fc9d15d6321945b23cac0614eb0b5e61f3a2f2a"
    }
  )

  @doc """
  Submit a single signed transaction to a private relay (`eth_sendPrivateTransaction`).

  Requires the `:endpoint` option (the relay URL); see the module docs for the
  full option list and why there is no public-node fallback.
  """
  @spec send_private_transaction(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def send_private_transaction(raw_tx, opts \\ []) do
    with {:ok, params} <- build_private_transaction_params(raw_tx, opts) do
      do_mev_rpc("eth_sendPrivateTransaction", params, opts)
    end
  end

  # --- send_bundle ---

  api(:send_bundle, "Submit an atomic bundle of signed transactions via a Flashbots-style relay.",
    params: [
      raw_txs: [kind: :exchange_data, description: "Non-empty list of 0x-prefixed signed raw transactions"],
      opts: [
        kind: :value,
        default: [],
        description:
          "Options: :endpoint (required relay URL), :block_number (required target block), :headers, :timeout, :min_timestamp, :max_timestamp, :reverting_tx_hashes"
      ]
    ],
    returns: %{
      type: "{:ok, map} | {:error, term}",
      description: ~s|Relay response, e.g. %{"bundleHash" => "0x..."}|,
      example: ~s|{:ok, %{"bundleHash" => "0x2228f5d8954ce31dc1601a8ba264dbd401bf1428388ce88238932815c5d6f23f"}}|
    }
  )

  @doc """
  Submit an atomic bundle of signed transactions to a private relay (`eth_sendBundle`).

  Requires both `:endpoint` (relay URL) and `:block_number` (target block); the
  bundle is only valid for that block. See the module docs for the full option list.
  """
  @spec send_bundle([String.t()], keyword()) :: {:ok, term()} | {:error, term()}
  def send_bundle(raw_txs, opts \\ []) do
    with {:ok, params} <- build_bundle_params(raw_txs, opts) do
      do_mev_rpc("eth_sendBundle", params, opts)
    end
  end

  # --- Request shaping (pure; unit-tested without network) ---

  @doc false
  # Builds the `eth_sendPrivateTransaction` params list from a raw tx + opts.
  @spec build_private_transaction_params(term(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def build_private_transaction_params(raw_tx, opts) do
    with {:ok, tx} <- ensure_hex_data(raw_tx),
         {:ok, max_block} <- normalize_optional_block(Keyword.get(opts, :max_block_number)) do
      param =
        %{"tx" => tx}
        |> maybe_put("maxBlockNumber", max_block)
        |> maybe_put("preferences", Keyword.get(opts, :preferences))

      {:ok, [param]}
    end
  end

  @doc false
  # Builds the `eth_sendBundle` params list from signed txs + opts.
  @spec build_bundle_params(term(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def build_bundle_params(raw_txs, opts) do
    with {:ok, txs} <- validate_raw_txs(raw_txs),
         {:ok, block} <- require_block_number(opts),
         {:ok, hex_block} <- normalize_block_number(block) do
      param =
        %{"txs" => txs, "blockNumber" => hex_block}
        |> maybe_put("minTimestamp", Keyword.get(opts, :min_timestamp))
        |> maybe_put("maxTimestamp", Keyword.get(opts, :max_timestamp))
        |> maybe_put("revertingTxHashes", Keyword.get(opts, :reverting_tx_hashes))

      {:ok, [param]}
    end
  end

  # --- RPC dispatch ---

  # Cartouche.RPC.send_rpc/3 narrowly types errors, but runtime transport errors
  # (Req transport failures — timeouts, connection refused) surface non-map
  # values. Mirror the suppression used in Onchain.RPC.Helpers.do_rpc/3.
  @dialyzer {:no_match, do_mev_rpc: 3}
  @spec do_mev_rpc(String.t(), [map()], keyword()) :: {:ok, term()} | {:error, term()}
  defp do_mev_rpc(method, params, opts) do
    with {:ok, rpc_opts} <- build_rpc_opts(opts) do
      case Cartouche.RPC.send_rpc(method, params, rpc_opts) do
        {:ok, result} -> {:ok, result}
        {:error, %{} = map} -> {:error, {:rpc_error, map}}
        {:error, other} -> {:error, {:rpc_error, %{message: inspect(other)}}}
      end
    end
  end

  # Resolves the relay endpoint (required — no public-node fallback) and maps our
  # option names onto cartouche's transport opts.
  @spec build_rpc_opts(keyword()) :: {:ok, keyword()} | {:error, term()}
  defp build_rpc_opts(opts) do
    case Keyword.get(opts, :endpoint) do
      nil ->
        {:error, :missing_endpoint}

      url when is_binary(url) ->
        rpc_opts =
          maybe_put_kw(
            [ethereum_node: url, timeout: Keyword.get(opts, :timeout, @default_timeout_ms)],
            :headers,
            Keyword.get(opts, :headers)
          )

        {:ok, rpc_opts}

      other ->
        {:error, {:invalid_endpoint, other}}
    end
  end

  @spec normalize_optional_block(term()) :: {:ok, String.t() | nil} | {:error, term()}
  defp normalize_optional_block(nil), do: {:ok, nil}
  defp normalize_optional_block(value), do: normalize_block_number(value)

  @spec require_block_number(keyword()) :: {:ok, term()} | {:error, :missing_block_number}
  defp require_block_number(opts) do
    case Keyword.fetch(opts, :block_number) do
      {:ok, block} -> {:ok, block}
      :error -> {:error, :missing_block_number}
    end
  end

  @spec validate_raw_txs(term()) :: {:ok, [String.t()]} | {:error, term()}
  defp validate_raw_txs([]), do: {:error, :empty_bundle}

  defp validate_raw_txs(list) when is_list(list) do
    list
    |> Enum.reduce_while({:ok, []}, fn tx, {:ok, acc} ->
      case ensure_hex_data(tx) do
        {:ok, validated} -> {:cont, {:ok, [validated | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_raw_txs(other), do: {:error, {:invalid_bundle, other}}

  @spec maybe_put(map(), String.t(), term()) :: map()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @spec maybe_put_kw(keyword(), atom(), term()) :: keyword()
  defp maybe_put_kw(opts, _key, nil), do: opts
  defp maybe_put_kw(opts, key, value), do: Keyword.put(opts, key, value)
end
