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

  @doc false
  @spec assert_node_available!() :: :ok | no_return()
  def assert_node_available! do
    case Cartouche.RPC.eth_chain_id(live_opts()) do
      {:ok, 1} ->
        :ok

      {:ok, other} ->
        flunk("""
        Integration node at #{live_rpc_url()} reported chain_id=#{other}, expected 1 (Ethereum mainnet).
        This suite pins mainnet historical anchors. Connect to a mainnet archive node.
        """)

      {:error, reason} ->
        flunk("""
        Integration test opt-in detected (mix integration / mix test --include integration)
        but the Ethereum mainnet archive node is unreachable.

        Expected node at: #{live_rpc_url()}
        Error: #{inspect(reason)}

        Start the SSH tunnel:

            ssh -L 8545:127.0.0.1:8545 -L 8546:127.0.0.1:8546 blockwatch-one

        Override the URL via env var:

            export CARTOUCHE_LIVE_NODE_URL=http://your-node:8545

        Then re-run:

            mix integration
        """)
    end
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
