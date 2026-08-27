defmodule Cartouche.Solana.Test.Signer do
  @moduledoc false

  # RFC 8032 Test 1 seed
  @test_seed Base.decode16!(
               "9D61B19DEFFD5A60BA844AF492EC2CC44449C5697B326919703BAC031CAE7F60",
               case: :upper
             )

  @doc false
  @spec test_seed() :: binary()
  def test_seed, do: @test_seed

  @doc false
  @spec start_signer(atom() | nil) :: GenServer.server()
  def start_signer(name \\ nil) do
    [mfa: {Cartouche.Solana.Signer.Ed25519, :sign, [@test_seed]}, name: name]
    |> Cartouche.Solana.Signer.start_link()
    |> signer_server(name)
  end

  @spec signer_server({:ok, pid()} | {:error, {:already_started, pid()}}, atom() | nil) ::
          GenServer.server()
  defp signer_server({:ok, pid}, nil), do: pid
  defp signer_server({:ok, _pid}, name), do: name
  defp signer_server({:error, {:already_started, _pid}}, name) when not is_nil(name), do: name
end
