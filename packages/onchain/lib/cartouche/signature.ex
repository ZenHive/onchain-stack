defmodule Cartouche.Signature do
  @moduledoc "A secp256k1 signature with integer scalars and an optional recovery ID."
  @enforce_keys [:r, :s]
  defstruct [:r, :s, :recid]

  @type t :: %__MODULE__{r: pos_integer(), s: pos_integer(), recid: 0..3 | nil}
  @order 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141

  @doc "Normalizes s while preserving recovery by flipping the parity bit."
  @spec normalize(t()) :: t()
  def normalize(%__MODULE__{s: s, recid: recid} = signature) when s > div(@order, 2) do
    %{signature | s: @order - s, recid: if(is_nil(recid), do: nil, else: Bitwise.bxor(recid, 1))}
  end

  def normalize(%__MODULE__{} = signature), do: signature

  @doc "Parses a canonical DER ECDSA signature, rejecting invalid scalars and encodings."
  @spec from_der(binary()) :: {:ok, t()} | {:error, :invalid_signature}
  def from_der(<<48, length, body::binary-size(length)>>) do
    with <<2, r_size, r::binary-size(r_size), 2, s_size, s::binary-size(s_size)>> <- body,
         true <- canonical_integer?(r) and canonical_integer?(s),
         r = :binary.decode_unsigned(r),
         s = :binary.decode_unsigned(s),
         true <- r > 0 and r < @order and s > 0 and s < @order do
      {:ok, %__MODULE__{r: r, s: s}}
    else
      _ -> {:error, :invalid_signature}
    end
  end

  def from_der(_), do: {:error, :invalid_signature}

  @spec canonical_integer?(binary()) :: boolean()
  defp canonical_integer?(<<0, next, _::binary>>), do: next >= 128
  defp canonical_integer?(<<first, _::binary>>), do: first < 128
  defp canonical_integer?(_), do: false
end
