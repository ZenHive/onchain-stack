# Helpers for the mainnet archive integration suite.
#
# Tests pass `live_opts()` as the keyword list to every `Cartouche.RPC.*` call.
# The opts include `req_options: [plug: nil]` (clearing the test-env stub plug so
# the call hits the real network per-call) and `ethereum_node: <url>` (overriding
# the default). No Application env mutation, no `on_exit` cleanup needed.
#
#     test "eth_chainId returns 1" do
#       assert {:ok, 1} = Cartouche.RPC.eth_chain_id(live_opts())
#     end
#
# Override the URL with `CARTOUCHE_LIVE_NODE_URL`.
defmodule Cartouche.Test.Live do
  @moduledoc false
  import ExUnit.Assertions

  @default_url "http://127.0.0.1:8545"

  @doc false
  @spec live_rpc_url() :: String.t()
  def live_rpc_url, do: System.get_env("CARTOUCHE_LIVE_NODE_URL", @default_url)

  @doc false
  @spec live_opts() :: Keyword.t()
  def live_opts, do: [req_options: [plug: nil], ethereum_node: live_rpc_url(), timeout: 30_000]

  @endpoints [
    archive: "CARTOUCHE_LIVE_NODE_URL",
    alchemy: "ETHEREUM_ALCHEMY_URL",
    infura: "ETHEREUM_INFURA_URL",
    cloudflare: "CLOUDFLARE_ETHEREUM_API_URL"
  ]
  @type endpoint :: :archive | :alchemy | :infura | :cloudflare

  @doc "Resolves a named mainnet endpoint; the archive lane retains its localhost default."
  @spec live_rpc_url(endpoint()) :: String.t()
  def live_rpc_url(:archive), do: live_rpc_url()

  def live_rpc_url(endpoint) do
    env = Keyword.fetch!(@endpoints, endpoint)

    case System.get_env(env) do
      url when is_binary(url) and url != "" -> url
      _ -> flunk(endpoint_message(endpoint, "is not configured"))
    end
  end

  @doc "Builds per-call network options for a named endpoint."
  @spec live_opts(endpoint()) :: Keyword.t()
  def live_opts(endpoint), do: [req_options: [plug: nil], ethereum_node: live_rpc_url(endpoint), timeout: 30_000]

  @doc false
  @spec assert_node_available!() :: :ok | no_return()
  def assert_node_available!, do: assert_node_available!(:archive)

  @doc "Requires the named endpoint to answer with chain ID 1 (Ethereum mainnet)."
  @spec assert_node_available!(endpoint()) :: :ok | no_return()
  def assert_node_available!(endpoint) do
    case Cartouche.RPC.eth_chain_id(live_opts(endpoint)) do
      {:ok, 1} -> :ok
      {:ok, _other} -> flunk(endpoint_message(endpoint, "reported a chain ID other than 1 (Ethereum mainnet)"))
      {:error, _reason} -> flunk(endpoint_message(endpoint, "is unreachable or refused eth_chainId"))
    end
  end

  @doc """
  Runs the same call on archive and at least one hosted endpoint, checking every answer.

  Expectations are named boolean predicates over unmodified RPC results, including
  explicit refusals (`-32601`/`-32600`, or an HTTP error response). Return `true` for
  the expected answer; use predicates, not assertions that could print credentials.
  Unexpected answers fail using only the endpoint's env-var name. Returns the raw
  answers for further inspection without logging credential-bearing responses.

  Require a real result or its real refusal, never a skip. Treat
  the consumer's node — not ours — as the case that matters:
  the identical green run on both endpoints is what the portability claim rests on.

      assert_portability!(&Cartouche.RPC.base_fee/1,
        archive: &match?({:ok, fee} when is_integer(fee) and fee >= 0, &1),
        alchemy: &expected_alchemy_refusal?/1
      )

  See `test/rpc_portability_test.exs` for the observed Alchemy refusal predicate.
  Choose expectations from observed responses; some providers refuse with HTTP 400
  and a `%Req.Response{}` instead of a decoded JSON-RPC error map.
  """
  @spec assert_portability!((Keyword.t() -> term()), [{endpoint(), (term() -> boolean())}]) ::
          [{endpoint(), term()}]
  def assert_portability!(call, expectations) do
    endpoints = Keyword.keys(expectations)

    if !(:archive in endpoints and match?([_, _ | _], endpoints) and
           Enum.uniq(endpoints) == endpoints and
           Enum.all?(endpoints, &Keyword.has_key?(@endpoints, &1))) do
      flunk("Portability requires :archive and at least one distinct named hosted endpoint; never a skip.")
    end

    urls = Enum.map(endpoints, &live_rpc_url/1)

    if Enum.uniq(urls) != urls do
      flunk(
        "Portability endpoints must resolve to distinct URLs; the consumer's node — not ours — as the case that matters."
      )
    end

    Enum.each(endpoints, &assert_node_available!/1)
    answers = Enum.map(endpoints, &{&1, call.(live_opts(&1))})

    Enum.each(answers, fn {endpoint, answer} ->
      if Keyword.fetch!(expectations, endpoint).(answer) != true do
        flunk(endpoint_message(endpoint, "returned an unexpected answer"))
      end
    end)

    answers
  end

  @spec endpoint_message(endpoint(), String.t()) :: String.t()
  defp endpoint_message(endpoint, problem) do
    env = Keyword.fetch!(@endpoints, endpoint)

    """
    Mainnet endpoint #{env} #{problem}.
    Require a real result or its real refusal, never a skip.
    Use the consumer's node — not ours — as the case that matters;
    the identical green run on both endpoints is what the portability claim rests on.

    Configure this endpoint:

        export #{env}='https://your-mainnet-endpoint'

    For the archive node, start the SSH tunnel:

        ssh -L 8545:127.0.0.1:8545 -L 8546:127.0.0.1:8546 blockwatch-one

    Then re-run:

        mix test test/rpc_portability_test.exs --include integration
    """
  end

  @dev_env "CARTOUCHE_DEV_NODE_URL"
  @anvil_port 18_545
  @anvil_url "http://127.0.0.1:#{@anvil_port}"
  @anvil_chain_id "31337"
  # Node-custody calls (fill/sign/send) are slower than a plain read.
  @dev_timeout 30_000
  # A reachability probe should fail fast rather than spend the call budget.
  @ping_timeout 5_000
  # 50 x 100 ms — anvil binds its port in well under five seconds.
  @anvil_boot_attempts 50
  @anvil_boot_backoff 100

  @doc false
  @spec dev_rpc_url() :: String.t()
  def dev_rpc_url do
    case System.get_env(@dev_env) do
      url when is_binary(url) and url != "" -> url
      _ -> @anvil_url
    end
  end

  @doc false
  @spec dev_opts() :: Keyword.t()
  def dev_opts, do: [req_options: [plug: nil], ethereum_node: dev_rpc_url(), timeout: @dev_timeout]

  @doc false
  @spec assert_dev_node_available!() :: :ok | no_return()
  def assert_dev_node_available! do
    case System.get_env(@dev_env) do
      url when is_binary(url) and url != "" ->
        ping_dev_node!(url)

      _ ->
        start_ephemeral_anvil!()
    end
  end

  @spec ping_dev_node!(String.t()) :: :ok | no_return()
  defp ping_dev_node!(url) do
    opts = [req_options: [plug: nil], ethereum_node: url, timeout: @ping_timeout]

    case Cartouche.RPC.eth_chain_id(opts) do
      {:ok, _chain_id} ->
        :ok

      {:error, reason} ->
        flunk("""
        CARTOUCHE_DEV_NODE_URL=#{url} is set but the node is unreachable.

        Error: #{inspect(reason)}

        Start the node, or unset the env var to fall back to a locally installed anvil.
        """)
    end
  end

  @spec start_ephemeral_anvil!() :: :ok | no_return()
  defp start_ephemeral_anvil! do
    case Cartouche.RPC.eth_chain_id(dev_opts()) do
      {:ok, _} ->
        :ok

      {:error, _} ->
        anvil = System.find_executable("anvil") || flunk(missing_dev_node_message())

        port =
          Port.open(
            {:spawn_executable, anvil},
            [
              :binary,
              :exit_status,
              :hide,
              args: ["--host", "127.0.0.1", "--port", Integer.to_string(@anvil_port), "--chain-id", @anvil_chain_id]
            ]
          )

        :persistent_term.put({__MODULE__, :anvil_port}, port)
        wait_for_anvil!(port)
        :ok
    end
  end

  @spec wait_for_anvil!(port()) :: :ok | no_return()
  defp wait_for_anvil!(port), do: wait_for_anvil_attempt(port, @anvil_boot_attempts)

  @spec wait_for_anvil_attempt(port(), non_neg_integer()) :: :ok | no_return()
  defp wait_for_anvil_attempt(port, remaining) do
    receive do
      {^port, {:exit_status, status}} ->
        flunk("""
        Ephemeral anvil exited with status #{status} before it accepted RPC.

        #{missing_dev_node_message()}
        """)
    after
      0 -> poll_anvil(port, remaining)
    end
  end

  @spec poll_anvil(port(), non_neg_integer()) :: :ok | no_return()
  defp poll_anvil(_port, 0) do
    stop_ephemeral_anvil()
    flunk(missing_dev_node_message())
  end

  defp poll_anvil(port, remaining) do
    case Cartouche.RPC.eth_chain_id(dev_opts()) do
      {:ok, _} ->
        :ok

      {:error, _} ->
        Process.sleep(@anvil_boot_backoff)
        wait_for_anvil_attempt(port, remaining - 1)
    end
  end

  @doc false
  @spec stop_ephemeral_anvil() :: :ok
  def stop_ephemeral_anvil do
    case :persistent_term.get({__MODULE__, :anvil_port}, nil) do
      nil ->
        :ok

      port ->
        :persistent_term.erase({__MODULE__, :anvil_port})
        stop_port(port)
        :ok
    end
  end

  @spec stop_port(port()) :: :ok
  defp stop_port(port) do
    info = Port.info(port)
    os_pid = info && Keyword.get(info, :os_pid)

    if Port.info(port) do
      Port.close(port)
    end

    if is_integer(os_pid) do
      System.cmd("kill", ["-TERM", Integer.to_string(os_pid)], stderr_to_stdout: true)
    end

    :ok
  end

  @spec missing_dev_node_message() :: String.t()
  defp missing_dev_node_message do
    """
    Development-node tests require an Ethereum node that holds keys (Anvil, Hardhat, or geth --dev).

    Set the node URL:

        export CARTOUCHE_DEV_NODE_URL=http://127.0.0.1:8545

    Or install Foundry and leave the env var unset so the suite can boot anvil on port #{@anvil_port}:

        curl -L https://foundry.paradigm.xyz | bash
        foundryup
        anvil --port #{@anvil_port} --chain-id #{@anvil_chain_id}

    Then re-run:

        mix test --only dev_node
    """
  end
end
