defmodule Cartouche.Transaction.SignatureTest do
  use ExUnit.Case, async: true

  alias Cartouche.Transaction.Signature
  alias Cartouche.Transaction.V3

  describe "pack/3" do
    test "32-byte r/s packing is byte-identical to r <> s <> <<y_parity>>" do
      r = <<1::256>>
      s = <<2::256>>

      assert Signature.pack(false, r, s) == {:ok, r <> s <> <<0>>}
      assert Signature.pack(true, r, s) == {:ok, r <> s <> <<1>>}
    end

    test "returns :missing when any field is nil" do
      r = <<1::256>>
      s = <<2::256>>

      assert Signature.pack(nil, r, s) == {:error, :missing}
      assert Signature.pack(true, nil, s) == {:error, :missing}
      assert Signature.pack(true, r, nil) == {:error, :missing}
    end

    test "raises when r or s is shorter than 32 bytes" do
      assert_raise ArgumentError, fn -> Signature.pack(false, <<1, 2, 3>>, <<2::256>>) end
      assert_raise ArgumentError, fn -> Signature.pack(true, <<1::256>>, <<2, 3>>) end
    end
  end

  describe "get/1" do
    test "32-byte path is byte-identical to r <> s <> y_parity" do
      tx = %{signature_y_parity: false, signature_r: <<1::256>>, signature_s: <<2::256>>}

      assert Signature.get(tx) == {:ok, <<1::256, 2::256, 0>>}

      assert Signature.get(%{tx | signature_y_parity: true}) == {:ok, <<1::256, 2::256, 1>>}
    end

    test "returns transaction missing signature when any field is nil" do
      tx = %{signature_y_parity: true, signature_r: <<1::256>>, signature_s: <<2::256>>}

      assert Signature.get(%{tx | signature_y_parity: nil}) == {:error, "transaction missing signature"}
      assert Signature.get(%{tx | signature_r: nil}) == {:error, "transaction missing signature"}
      assert Signature.get(%{tx | signature_s: nil}) == {:error, "transaction missing signature"}
    end

    test "raises on short r or s instead of emitting a malformed packed signature" do
      tx = %{signature_y_parity: false, signature_r: <<1, 2, 3>>, signature_s: <<2::256>>}

      assert_raise ArgumentError, fn -> Signature.get(tx) end
    end
  end

  describe "y_parity_from_v/1" do
    test "treats 0 and 1 as direct y-parity values" do
      assert Signature.y_parity_from_v(<<0>>) == false
      assert Signature.y_parity_from_v(<<1>>) == true
    end

    test "derives y-parity from EIP-155-style recovery bits" do
      assert Signature.y_parity_from_v(<<38::8>>) == true
      assert Signature.y_parity_from_v(<<27::8>>) == false
    end
  end

  describe "add_packed/2" do
    test "attaches packed signature fields to a transaction struct" do
      tx = %V3{signature_y_parity: nil, signature_r: nil, signature_s: nil}

      assert %V3{signature_y_parity: true, signature_r: <<1::256>>, signature_s: <<2::256>>} =
               Signature.add_packed(tx, <<1::256, 2::256, 1>>)
    end

    test "rejects packed signatures without a recovery byte" do
      tx = %V3{signature_y_parity: nil, signature_r: nil, signature_s: nil}

      assert_raise FunctionClauseError, fn ->
        Signature.add_packed(tx, <<1::256, 2::256>>)
      end
    end
  end
end
