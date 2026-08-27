defmodule Cartouche.Test.Signer do
  @moduledoc false

  use Cartouche.Hex

  @doc false
  @spec start_signer(atom() | nil) :: GenServer.server()
  def start_signer(name \\ nil) do
    priv_key = ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]

    [mfa: {Cartouche.Signer.Curvy, :sign, [priv_key]}, name: name]
    |> Cartouche.Signer.start_link()
    |> signer_server(name)
  end

  @spec signer_server({:ok, pid()} | {:error, {:already_started, pid()}}, atom() | nil) ::
          GenServer.server()
  defp signer_server({:ok, pid}, nil), do: pid
  defp signer_server({:ok, _pid}, name), do: name
  defp signer_server({:error, {:already_started, _pid}}, name) when not is_nil(name), do: name
end
