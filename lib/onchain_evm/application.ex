defmodule OnchainEvm.Application do
  # TODO: This module is not wired up (mod: commented out in mix.exs).
  # Either enable it when supervised children are needed, or remove both
  # this module and the commented mod: line in mix.exs.
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: OnchainEvm.Worker.start_link(arg)
      # {OnchainEvm.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: OnchainEvm.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
