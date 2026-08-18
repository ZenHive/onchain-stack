defmodule OnchainJs.RuntimeSupervisor do
  @moduledoc """
  `DynamicSupervisor` for `OnchainJs.Runtime` processes.

  Started as part of the OnchainJs application supervision tree under the
  registered name `OnchainJs.RuntimeSupervisor`. No runtimes are started by
  default — consumers spawn supervised runtimes on demand:

      {:ok, pid} =
        DynamicSupervisor.start_child(
          OnchainJs.RuntimeSupervisor,
          {OnchainJs.Runtime, []}
        )

      :ok = DynamicSupervisor.terminate_child(OnchainJs.RuntimeSupervisor, pid)

  Strategy is `:one_for_one`: a crashed runtime is not auto-restarted because
  the child specs `OnchainJs.Runtime` builds use `restart: :transient`,
  matching the lifetime of the loaded JS bundle.
  """

  use DynamicSupervisor

  @doc """
  Start the supervisor under the registered name `OnchainJs.RuntimeSupervisor`.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(init_arg \\ []) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  @spec init(term()) :: {:ok, DynamicSupervisor.sup_flags()}
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
