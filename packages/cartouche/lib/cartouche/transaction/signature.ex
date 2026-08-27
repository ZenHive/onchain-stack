defmodule Cartouche.Transaction.Signature do
  @moduledoc """
  Shared signature-field helpers for typed-transaction structs that carry the
  `signature_y_parity` / `signature_r` / `signature_s` triple
  (EIP-2930 `V_2930`, EIP-1559 `V2`, EIP-4844 `V3`, EIP-7702 `V4`).

  `pack/3` is the shared primitive behind both struct recovery (`get/1`) and
  EIP-7702 authorization 6-tuples, which do not carry those map keys.

  These functions operate on the struct as a plain map, so they work uniformly
  across the typed-transaction modules without coupling them to one another.
  """

  @doc """
  Attaches explicit signature fields (`y_parity`, `r`, `s`) to a transaction
  struct. `r` and `s` must be exactly 32 bytes and `v` a boolean y-parity.
  """
  @spec add(map(), boolean(), <<_::256>>, <<_::256>>) :: map()
  def add(transaction, v, <<_::256>> = r, <<_::256>> = s) when is_boolean(v) do
    %{transaction | signature_y_parity: v, signature_r: r, signature_s: s}
  end

  @doc """
  Packs `y_parity`, `r`, and `s` into the `r <> s <> y_parity` binary used by
  typed-transaction recovery. `r` and `s` must be exactly 32 bytes.

  Returns `{:error, :missing}` when any field is nil. Callers map that atom to
  a domain string (`"transaction missing signature"`, `"authorization missing
  signature"`). A short `r` or `s` raises `ArgumentError` rather than emitting
  a malformed packed signature.
  """
  @spec pack(boolean() | nil, binary() | nil, binary() | nil) :: {:ok, binary()} | {:error, :missing}
  def pack(v, r, s) when is_nil(v) or is_nil(r) or is_nil(s), do: {:error, :missing}

  def pack(v, r, s) do
    v_enc = :binary.encode_unsigned(if v, do: 1, else: 0)
    {:ok, <<r::binary-size(32), s::binary-size(32), v_enc::binary>>}
  end

  @doc """
  Recovers the packed `r <> s <> y_parity` signature from a signed transaction,
  or `{:error, "transaction missing signature"}` when any signature field is nil.
  """
  @spec get(map()) :: {:ok, binary()} | {:error, String.t()}
  def get(%{signature_y_parity: v, signature_r: r, signature_s: s}) do
    case pack(v, r, s) do
      {:ok, packed} -> {:ok, packed}
      {:error, :missing} -> {:error, "transaction missing signature"}
    end
  end

  @doc """
  Attaches a packed `r <> s <> v` signature to a transaction struct.
  """
  @spec add_packed(map(), <<_::512, _::_*8>>) :: map()
  def add_packed(transaction, <<r::binary-size(32), s::binary-size(32), v_bin::binary>>) when byte_size(v_bin) > 0 do
    add(transaction, y_parity_from_v(v_bin), r, s)
  end

  @doc """
  Derives EIP-155-style y-parity from a packed recovery `v` byte sequence.
  """
  @spec y_parity_from_v(binary()) :: boolean()
  def y_parity_from_v(v_bin) do
    v = :binary.decode_unsigned(v_bin)
    if v < 2, do: v == 1, else: rem(v, 2) == 0
  end
end
