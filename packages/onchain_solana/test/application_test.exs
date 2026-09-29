defmodule Onchain.Solana.ApplicationTest do
  use ExUnit.Case, async: false

  alias Onchain.Solana.Base58
  alias Onchain.Solana.Signer

  @seed Base.decode16!("9D61B19DEFFD5A60BA844AF492EC2CC44449C5697B326919703BAC031CAE7F60")

  setup do
    previous = Application.fetch_env(:cartouche, :solana_signer)
    :ok = Application.stop(:onchain_solana)

    on_exit(fn ->
      Application.stop(:onchain_solana)

      case previous do
        {:ok, config} -> Application.put_env(:cartouche, :solana_signer, config)
        :error -> Application.delete_env(:cartouche, :solana_signer)
      end

      :ok = Application.start(:onchain_solana)
    end)

    :ok
  end

  test "application supervises the default signer for every supported seed encoding" do
    {public_key, _} = :crypto.generate_key(:eddsa, :ed25519, @seed)

    for seed <- [@seed, Base.encode16(@seed), "0x" <> Base.encode16(@seed), Base58.encode(@seed)] do
      Application.put_env(:cartouche, :solana_signer, default: {:ed25519, seed})
      assert :ok = Application.start(:onchain_solana)
      assert Signer.address() == public_key
      assert {:ok, signature} = Signer.sign("package startup")
      assert :crypto.verify(:eddsa, :none, "package startup", signature, [public_key, :ed25519])

      assert [{Signer.Default, pid, :worker, [Signer]}] =
               Supervisor.which_children(Onchain.Solana.Supervisor)

      assert Process.whereis(Signer.Default) == pid
      assert :ok = Application.stop(:onchain_solana)
    end
  end

  test "application accepts an explicit backend and a custom signer name" do
    Application.put_env(:cartouche, :solana_signer, [{__MODULE__, {Signer.Ed25519, @seed}}])
    assert :ok = Application.start(:onchain_solana)
    {public_key, _} = :crypto.generate_key(:eddsa, :ed25519, @seed)
    assert Signer.address(__MODULE__) == public_key

    assert [{__MODULE__, pid, :worker, [Signer]}] =
             Supervisor.which_children(Onchain.Solana.Supervisor)

    assert Process.whereis(__MODULE__) == pid
  end
end
