defmodule Faucet.Source.CDP do
  @moduledoc """
  Coinbase Developer Platform faucet — `POST /platform/v2/evm/faucet`.

  Funds native gas (`"eth"`) or a CDP-dispensed token (`"usdc"`, `"eurc"`,
  `"cbbtc"`) on Base Sepolia or Ethereum Sepolia. Each request pays a fixed
  provider-side amount (0.0001 ETH at the time of writing), so reaching a
  larger minimum takes several requests; bound them with `:max_requests`.

  CDP's USDC is Circle's testnet USDC, **not** the Aave `TestnetERC20` — use
  `Faucet.Source.ERC20Mint` for protocol-specific test tokens.

  ## Options

    * `:network` — `"base-sepolia"` or `"ethereum-sepolia"` (required)
    * `:token` — CDP token id, default `"eth"`
    * `:token_address` — ERC-20 contract to read the balance from; required
      when `:token` is not `"eth"`
    * `:rpc_url` — node for balance reads and receipt polling; defaults per network
    * `:api_key_id` / `:api_key_secret` — CDP API key; default to the
      `CDP_API_KEY_ID` / `CDP_API_KEY_SECRET` environment variables. The
      secret is the base64-encoded Ed25519 key (64 bytes: seed + public key)
      from https://portal.cdp.coinbase.com/access/api
    * `:faucet_url` — override the provider endpoint (tests)
    * `:req_options` — passed to Req for every HTTP call

  Balance reads and receipt polling go through the node at `:rpc_url`, never
  through CDP, so the provider's own accounting is never trusted for the final
  verdict.
  """

  @behaviour Faucet.Source

  alias Faucet.EVM

  @host "api.cdp.coinbase.com"
  @path "/platform/v2/evm/faucet"
  @jwt_lifetime_seconds 120
  @request_timeout_ms 30_000

  @networks %{
    "base-sepolia" => "https://sepolia.base.org",
    "ethereum-sepolia" => "https://ethereum-sepolia-rpc.publicnode.com"
  }

  @doc "Networks this source accepts."
  @spec networks() :: [String.t()]
  def networks, do: Map.keys(@networks)

  @impl true
  def unit, do: "base units"

  @impl true
  def balance(address, opts) do
    with {:ok, opts} <- resolve(opts) do
      read_balance(address, Keyword.fetch!(opts, :token), Keyword.fetch(opts, :token_address), opts)
    end
  end

  defp read_balance(address, "eth", _token_address, opts), do: EVM.native_balance(address, opts)
  defp read_balance(address, _token, {:ok, token_address}, opts), do: EVM.erc20_balance(token_address, address, opts)
  defp read_balance(_address, _token, :error, _opts), do: {:error, {:missing_option, :token_address}}

  @impl true
  def fund(address, opts) do
    with {:ok, opts} <- resolve(opts),
         {:ok, bearer} <- bearer(opts) do
      body = %{network: Keyword.fetch!(opts, :network), address: address, token: Keyword.fetch!(opts, :token)}

      [
        url: Keyword.get(opts, :faucet_url, "https://#{@host}#{@path}"),
        method: :post,
        auth: {:bearer, bearer},
        headers: [{"x-idempotency-key", idempotency_key()}],
        json: body,
        receive_timeout: @request_timeout_ms,
        retry: false
      ]
      |> Req.request(Keyword.get(opts, :req_options, []))
      |> case do
        {:ok, %Req.Response{status: status, body: %{"transactionHash" => hash}}} when status in 200..299 ->
          {:ok, [hash]}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:provider_rejected, status, body}}

        {:error, exception} ->
          {:error, {:transport, exception}}
      end
    end
  end

  @impl true
  def wait_confirmed(hashes, _address, opts) do
    with {:ok, opts} <- resolve(opts), do: EVM.wait_receipts(hashes, opts)
  end

  defp resolve(opts) do
    network = Keyword.get(opts, :network)

    case Map.fetch(@networks, network) do
      {:ok, default_rpc} ->
        {:ok, opts |> Keyword.put_new(:rpc_url, default_rpc) |> Keyword.put_new(:token, "eth")}

      :error ->
        {:error, {:unsupported_network, network, Map.keys(@networks)}}
    end
  end

  # CDP authenticates with a short-lived EdDSA JWT signed by the API key secret.
  defp bearer(opts) do
    with {:ok, id} <- credential(opts, :api_key_id, "CDP_API_KEY_ID"),
         {:ok, secret} <- credential(opts, :api_key_secret, "CDP_API_KEY_SECRET"),
         {:ok, seed} <- ed25519_seed(secret) do
      now = System.system_time(:second)

      header =
        encode(%{alg: "EdDSA", typ: "JWT", kid: id, nonce: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)})

      claims =
        encode(%{
          sub: id,
          iss: "cdp",
          aud: ["cdp_service"],
          nbf: now,
          exp: now + @jwt_lifetime_seconds,
          uris: ["POST #{@host}#{@path}"]
        })

      input = header <> "." <> claims
      signature = :crypto.sign(:eddsa, :none, input, [seed, :ed25519])
      {:ok, input <> "." <> Base.url_encode64(signature, padding: false)}
    end
  end

  defp ed25519_seed(secret) do
    case Base.decode64(secret) do
      {:ok, <<seed::binary-size(32), _public::binary-size(32)>>} ->
        {:ok, seed}

      {:ok, <<seed::binary-size(32)>>} ->
        {:ok, seed}

      _ ->
        {:error,
         {:invalid_credential, :api_key_secret, "expected base64 Ed25519 key (32-byte seed or 64-byte seed+pub)"}}
    end
  end

  defp credential(opts, key, env) do
    case Keyword.get(opts, key) || System.get_env(env) do
      value when is_binary(value) and value != "" ->
        {:ok, value}

      _ ->
        {:error,
         {:missing_credential, env,
          "export #{env} from https://portal.cdp.coinbase.com/access/api (source ~/.secrets) or pass #{inspect(key)}"}}
    end
  end

  defp encode(map), do: map |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp idempotency_key do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)

    "~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b"
    |> :io_lib.format([a, b, c, d, e])
    |> IO.iodata_to_binary()
  end
end
