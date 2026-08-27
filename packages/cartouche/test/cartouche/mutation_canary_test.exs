defmodule Cartouche.MutationCanaryTest do
  @moduledoc false
  # Deliberate-fault canaries for the mutation-adequacy campaign (ROADMAP task 114).
  #
  # A mutation score is only meaningful if the suite can be shown to detect a real
  # fault. Each canary below reconstructs one specific mutant of the signing path by
  # hand and pins WHICH invariant kills it — and, just as importantly, which plausible
  # invariant does NOT. An assertion that merely appears to cover a fault class is
  # worse than an absent one, because it makes the gap invisible.
  #
  # These canaries are assertions about the SUITE, not about the library. They must
  # stay green: a red canary means the corresponding invariant lost its teeth.

  use ExUnit.Case, async: true

  alias Cartouche.Hash
  alias Cartouche.Recover
  alias Cartouche.Signer
  alias Cartouche.Signer.Curvy
  alias Cartouche.Test.HighSSignerBackend
  alias Cartouche.Transaction.V1

  @private_key Base.decode16!("800509FA3E80882AD0BE77C27505BDC91380F800D51ED80897D22F9FCC75F4BF")
  @signer_address Base.decode16!("63CC7C25E0CDB121ABB0FE477A6B9901889F99A7")
  @secp256k1_n 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
  @secp256k1_half_n div(@secp256k1_n, 2)
  @chain_id 5
  @message "mutation canary"

  describe "canary: low-s normalization deleted from the emission funnel" do
    # Mutant: `Cartouche.Signer.emit_signature/4` with the
    # `Recover.normalize_low_s/1` call removed (statement_deletion / function_call
    # on lib/cartouche/signer.ex). A high-s backend then emits a malleable
    # signature, violating EIP-2.

    test "the unmutated funnel canonicalizes a high-s backend signature" do
      signer = start_signer!({HighSSignerBackend, @private_key})

      assert {:ok, <<_r::256, s::256, _v::8>>} = Signer.sign(@message, signer, chain_id: @chain_id)
      assert s <= @secp256k1_half_n
    end

    test "the mutant emits a genuinely high-s signature" do
      <<_r::256, s::256, _v::8>> = high_s_mutant()

      assert s > @secp256k1_half_n
    end

    test "INV-SIGN-LOW-S kills the mutant" do
      <<_r::256, s::256, _v::8>> = high_s_mutant()

      assert s > @secp256k1_half_n
    end

    test "address recovery does NOT kill it — the low-s assertion is the sole detector" do
      # Both (r, s) and (r, n - s) are valid signatures over the same digest, so the
      # recid search simply finds the bit matching the un-normalized s and recovery
      # succeeds. Dropping the low-s assertion would make this mutant survive.
      assert Recover.recover_eth(@message, high_s_mutant()) == @signer_address
    end
  end

  describe "canary: wrong chain id in the EIP-155 v byte" do
    # Mutant: `Cartouche.Signer.encode_eip155/3` computing v from `chain_id + 1`
    # (arithmetic / literal on lib/cartouche/signer.ex).

    test "the unmutated signer packs v = chain_id * 2 + 35 + parity" do
      assert {:ok, <<_r::256, _s::256, v::8>>} =
               Signer.sign_direct(@message, @signer_address, {Curvy, :sign, [@private_key]}, @chain_id)

      assert (v - (@chain_id * 2 + 35)) in [0, 1]
    end

    test "INV-TX-ENVELOPE's EIP-155 formula kills the mutant" do
      <<_r::256, _s::256, v::8>> = wrong_chain_id_mutant(@chain_id + 1)

      refute (v - (@chain_id * 2 + 35)) in [0, 1]
    end

    test "raw-signature recovery does NOT kill it — v carries the chain id, the digest does not" do
      # `Recover.decode_signature/1` reduces v to `rem(v + 1, 2)`, and shifting the
      # chain id by one shifts v by two — so the parity, and therefore the recovered
      # address, is invariant. Only an assertion on the v FORMULA detects this fault.
      assert Recover.recover_eth(@message, wrong_chain_id_mutant(@chain_id + 1)) == @signer_address
    end
  end

  describe "canary: wrong chain id in the V1 signing hash domain" do
    # Mutant: `Cartouche.Transaction.V1.recover_signer/2` (or the symmetric signing
    # path) re-encoding the EIP-155 payload under the wrong chain id. Here the chain
    # id is inside the digest, so the failure mode is the opposite of the v-byte case.

    test "the unmutated transaction recovers its signer on its own chain" do
      {transaction, _signature} = signed_v1()

      assert {:ok, @signer_address} = V1.recover_signer(transaction, @chain_id)
    end

    test "INV-TX-DOMAIN kills the mutant: a neighbouring chain recovers a stranger" do
      {transaction, _signature} = signed_v1()

      assert {:ok, other} = V1.recover_signer(transaction, @chain_id + 1)
      refute other == @signer_address
    end
  end

  # --- mutant constructions -------------------------------------------------
  #
  # Each helper reproduces the code under mutation with the fault applied, rather
  # than mutating the library at runtime, so the canary stays readable and cannot
  # leak a faulted module into another test.

  # `emit_signature/4` with the `normalize_low_s/1` call deleted.
  defp high_s_mutant do
    digest = Hash.keccak(@message)

    assert {:ok, raw_signature} = HighSSignerBackend.sign_payload(digest, @private_key)
    assert raw_signature.s > @secp256k1_half_n

    assert {:ok, recid} = Recover.find_recid_from_digest(digest, raw_signature, @signer_address)

    <<raw_signature.r::256, raw_signature.s::256, @chain_id * 2 + 35 + recid>>
  end

  # `encode_eip155/3` packing v under `chain_id` instead of the signing chain.
  defp wrong_chain_id_mutant(chain_id) do
    digest = Hash.keccak(@message)

    assert {:ok, raw_signature} = Curvy.sign_payload(digest, @private_key)
    signature = Recover.normalize_low_s(raw_signature)

    assert {:ok, recid} = Recover.find_recid_from_digest(digest, signature, @signer_address)

    <<signature.r::256, signature.s::256, chain_id * 2 + 35 + recid>>
  end

  defp signed_v1 do
    signer = start_signer!({Curvy, @private_key})
    transaction = V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, @chain_id)

    assert {:ok, signature} = Signer.sign(V1.encode(transaction), signer, chain_id: @chain_id)

    {V1.add_signature(transaction, signature), signature}
  end

  defp start_signer!(mfa) do
    start_supervised!(%{
      id: {Signer, make_ref()},
      start: {Signer, :start_link, [[mfa: mfa, name: nil]]}
    })
  end
end
