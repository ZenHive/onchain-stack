defmodule Cartouche.Signer.BeforeConsolidationTest do
  use ExUnit.Case, async: true

  alias Cartouche.Signer
  alias Cartouche.Transaction.V2

  @fixture Path.expand("../support/fixtures/signers_before_consolidation.etf", __DIR__)
  @external_resource @fixture
  @records @fixture |> File.read!() |> :erlang.binary_to_term()

  test "every captured signer fixture retains its exact signed bytes" do
    assert Enum.frequencies_by(@records, fn {mod, fun, _, _} -> {mod, fun} end) == %{
             {Onchain.Signer, :sign_transaction} => 10,
             {Signer, :sign_direct} => 74,
             {Signer, :backend_sign} => 353
           }

    for {record, index} <- Enum.with_index(@records) do
      {_module, function, args, expected} = record
      actual = replay(function, args, index)
      assert actual == expected, "signed bytes changed for fixture #{index} (#{function})"
    end
  end

  defp replay(:sign_transaction, args, _index) do
    {:ok, signed} = apply(Signer, :sign_transaction, args)
    V2.encode(signed)
  end

  defp replay(:sign_direct, args, _index) do
    {:ok, signature} = apply(Signer, :sign_direct, args)
    signature
  end

  defp replay(:backend_sign, [carrier, payload, address, chain_id], index) do
    signer = start_supervised!({Signer, mfa: carrier, name: nil}, id: index)
    assert Signer.address(signer) == address

    result =
      case payload do
        {:digest, digest, original} -> Signer.sign_digest(digest, original, signer, chain_id: chain_id)
        message -> Signer.sign(message, signer, chain_id: chain_id)
      end

    assert {:ok, signature} = result
    stop_supervised!(index)
    signature
  end
end
