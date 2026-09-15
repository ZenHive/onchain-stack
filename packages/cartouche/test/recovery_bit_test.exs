defmodule Cartouche.RecoveryBitTest do
  use ExUnit.Case, async: false

  @unknown_convention :not_a_convention
  doctest Cartouche.RecoveryBit

  describe "EIP-155 normalization" do
    setup do
      previous_chain_id = Application.get_env(:cartouche, :chain_id)
      Application.put_env(:cartouche, :chain_id, 5)

      on_exit(fn ->
        if is_nil(previous_chain_id) do
          Application.delete_env(:cartouche, :chain_id)
        else
          Application.put_env(:cartouche, :chain_id, previous_chain_id)
        end
      end)
    end

    test "normalize/2 applies the configured chain id" do
      assert Cartouche.RecoveryBit.normalize(28, :eip155) == 46
    end

    test "normalize_signature/2 applies the configured chain id" do
      assert Cartouche.RecoveryBit.normalize_signature(<<1::256, 2::256, 28>>, :eip155) ==
               <<1::256, 2::256, 46>>
    end

    test "recover_base/1 returns 0/1 for valid EIP-155 recovery bits" do
      assert Cartouche.RecoveryBit.recover_base(45) == 0
      assert Cartouche.RecoveryBit.recover_base(46) == 1
    end

    test "recover_base/1 reports the configured chain id for invalid EIP-155 values" do
      assert_raise RuntimeError, "Invalid EIP-155 Signature: recovery_bit=47, chain_id=5", fn ->
        Cartouche.RecoveryBit.recover_base(47)
      end
    end

    # The arity-1 heads were the largest uncovered cluster in the ROADMAP task 114
    # mutation campaign (35 of 55 unexecuted mutants). Every existing call site,
    # doctests included, passes `rec_type` explicitly, so nothing pinned the
    # `:eip155` default or the `rec_type in @rec_types` guard that protects it.

    test "normalize/1 defaults to the EIP-155 convention" do
      assert Cartouche.RecoveryBit.normalize(28) == Cartouche.RecoveryBit.normalize(28, :eip155)
      assert Cartouche.RecoveryBit.normalize(28) == 46
      assert Cartouche.RecoveryBit.normalize(27) == 45
    end

    test "normalize_signature/1 defaults to the EIP-155 convention" do
      signature = <<1::256, 2::256, 28>>

      assert Cartouche.RecoveryBit.normalize_signature(signature) ==
               Cartouche.RecoveryBit.normalize_signature(signature, :eip155)

      assert Cartouche.RecoveryBit.normalize_signature(signature) == <<1::256, 2::256, 46>>
    end

    test "normalize/2 rejects an unknown convention rather than falling through" do
      assert_raise FunctionClauseError, fn ->
        Cartouche.RecoveryBit.normalize(28, unknown_convention())
      end
    end

    test "normalize_signature/2 rejects an unknown convention rather than falling through" do
      assert_raise FunctionClauseError, fn ->
        Cartouche.RecoveryBit.normalize_signature(<<1::256, 2::256, 28>>, unknown_convention())
      end
    end

    test "normalize_signature/2 rejects a signature that is missing the trailing v" do
      assert_raise FunctionClauseError, fn ->
        Cartouche.RecoveryBit.normalize_signature(<<1::256, 2::256>>, :eip155)
      end
    end

    test "recover_base/2 reduces an EIP-155 v against the supplied chain id" do
      assert Cartouche.RecoveryBit.recover_base(16_941, 8453) == 0
      assert Cartouche.RecoveryBit.recover_base(16_942, 8453) == 1
    end

    test "recover_base/2 names both recovery_bit and chain_id on a cross-chain miss" do
      assert_raise RuntimeError, "Invalid EIP-155 Signature: recovery_bit=16941, chain_id=5", fn ->
        Cartouche.RecoveryBit.recover_base(16_941, 5)
      end
    end

    test "recover_base/1 documents a cross-chain miss against the process-global chain_id" do
      assert_raise RuntimeError, "Invalid EIP-155 Signature: recovery_bit=16941, chain_id=5", fn ->
        Cartouche.RecoveryBit.recover_base(16_941)
      end
    end

    test "normalize_signature/3 accepts a multi-byte EIP-155 v without FunctionClauseError" do
      sig = <<1::256, 2::256>> <> :binary.encode_unsigned(16_941)

      assert byte_size(sig) == 66
      assert Cartouche.RecoveryBit.normalize_signature(sig, :base, 8453) == <<1::256, 2::256, 0>>

      assert Cartouche.RecoveryBit.normalize_signature(sig, :ethereum, 8453) ==
               <<1::256, 2::256, 27>>

      assert Cartouche.RecoveryBit.normalize_signature(sig, :eip155, 8453) == sig
    end

    test "normalize/3 produces a Base EIP-155 v from an Ethereum recovery bit" do
      assert Cartouche.RecoveryBit.normalize(28, :eip155, 8453) == 16_942
    end
  end

  # Routed through the atom table so the compiler sees `atom()` instead of the
  # literal; passing the literal directly is reported as an incompatible argument,
  # which is precisely the contract these two tests exist to exercise at runtime.
  @spec unknown_convention() :: atom()
  defp unknown_convention, do: String.to_existing_atom(Atom.to_string(@unknown_convention))
end
