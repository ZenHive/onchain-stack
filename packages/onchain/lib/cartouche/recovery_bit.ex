defmodule Cartouche.RecoveryBit do
  @moduledoc """
  There are a number of ways to look at recovery bits. Either:

  * `:base`: In the range `{0,1}`, which are the outputs of a signer library
  * `:ethereum`: In the range `{27,28}`, as defined in the yellow paper
  * `:eip155`: In the range `{35+chain_id*2,35+chain_id*2+1}`, as defined in EIP-155

  This module provides tools between switching through these choices.

  EIP-155 conversion takes an explicit `chain_id`. Omitting it falls back to
  `config :cartouche, :chain_id` (via `Cartouche.Chain.chain_id_value/1`). A
  signature from a different chain than the one supplied (or configured)
  raises `Invalid EIP-155 Signature` naming both `recovery_bit` and `chain_id`.
  """

  use Descripex, namespace: "/ethereum/recovery_bit"

  @rec_types [:base, :ethereum, :eip155]
  @type rec_type() :: :base | :ethereum | :eip155

  api(:normalize, "Convert a recovery bit into the requested recovery-bit convention.",
    params: [
      recovery_bit: [
        kind: :value,
        description: "Recovery bit in base (`0` or `1`), Ethereum (`27` or `28`), or EIP-155 form."
      ],
      rec_type: [
        kind: :value,
        default: :eip155,
        description: "Target convention: `:base`, `:ethereum`, or `:eip155`."
      ],
      chain_id: [
        kind: :value,
        default: nil,
        description:
          "Chain id used when reading or producing EIP-155 `v`. `nil` falls back to `config :cartouche, :chain_id`."
      ]
    ],
    returns: %{
      type: :non_neg_integer,
      description: "Recovery bit normalized to the requested convention."
    }
  )

  @doc """
  Normalizes a binary-encoded signature to the given requested type,
  i.e. `:base`, `:ethereum`, or `:eip155`.

  ## Examples

      iex> Cartouche.RecoveryBit.normalize(28, :ethereum)
      28

      iex> Cartouche.RecoveryBit.normalize(1, :ethereum)
      28

      iex> Cartouche.RecoveryBit.normalize(27, :base)
      0
  """
  @spec normalize(non_neg_integer(), rec_type(), integer() | atom() | nil) ::
          non_neg_integer() | no_return()
  def normalize(recovery_bit, rec_type \\ :eip155, chain_id \\ nil) when rec_type in @rec_types do
    base = recover_base(recovery_bit, chain_id)

    case rec_type do
      :base ->
        base

      :ethereum ->
        base + 27

      :eip155 ->
        35 + Cartouche.Chain.chain_id_value(chain_id) * 2 + base
    end
  end

  api(:normalize_signature, "Normalize the recovery bytes of a packed `r <> s <> v` Ethereum signature.",
    params: [
      signature: [
        kind: :value,
        description: "Packed `r <> s <> v` signature. `v` is one or more bytes (65 bytes total when it fits in one byte)."
      ],
      rec_type: [
        kind: :value,
        default: :eip155,
        description: "Target convention for the trailing `v`: `:base`, `:ethereum`, or `:eip155`."
      ],
      chain_id: [
        kind: :value,
        default: nil,
        description:
          "Chain id used when reading or producing EIP-155 `v`. `nil` falls back to `config :cartouche, :chain_id`."
      ]
    ],
    returns: %{
      type: :ethereum_signature,
      description: "Same `r` and `s` bytes with `v` normalized to the requested recovery-bit convention."
    }
  )

  @doc """
  Normalizes a binary-encoded signature to the given requested type,
  i.e. `:base`, `:ethereum`, or `:eip155`.

  ## Examples

      iex> Cartouche.RecoveryBit.normalize_signature(<<1::256, 2::256, 28>>, :ethereum)
      <<1::256, 2::256, 28>>

      iex> Cartouche.RecoveryBit.normalize_signature(<<1::256, 2::256, 1>>, :ethereum)
      <<1::256, 2::256, 28>>

      iex> Cartouche.RecoveryBit.normalize_signature(<<1::256, 2::256, 27>>, :base)
      <<1::256, 2::256, 0>>
  """
  @spec normalize_signature(Cartouche.signature(), rec_type(), integer() | atom() | nil) ::
          Cartouche.signature() | no_return()
  def normalize_signature(<<rs::binary-size(64), v_bin::binary>>, rec_type \\ :eip155, chain_id \\ nil)
      when byte_size(v_bin) >= 1 and rec_type in @rec_types do
    v = :binary.decode_unsigned(v_bin)
    v_normalized = normalize(v, rec_type, chain_id)

    rs <> :binary.encode_unsigned(v_normalized)
  end

  api(:recover_base, "Convert a recovery bit from any supported convention into base form.",
    params: [
      v: [
        kind: :value,
        description: "Recovery bit in base (`0` or `1`), Ethereum (`27` or `28`), or EIP-155 form."
      ],
      chain_id: [
        kind: :value,
        default: nil,
        description: "Chain id used to reduce an EIP-155 `v`. `nil` falls back to `config :cartouche, :chain_id`."
      ]
    ],
    returns: %{
      type: :base_recovery_bit,
      description: "`0` or `1`, suitable for libraries that expect the raw secp256k1 recovery id."
    }
  )

  @doc """
  Normalizes a recovery bit to be either 0 or 1.

  EIP-155 values are reduced against `chain_id`. Omitting it falls back to
  `config :cartouche, :chain_id`. A `v` from a different chain raises
  `Invalid EIP-155 Signature` naming both `recovery_bit` and `chain_id`.

  ## Examples

      iex> Cartouche.RecoveryBit.recover_base(0)
      0

      iex> Cartouche.RecoveryBit.recover_base(1)
      1

      iex> Cartouche.RecoveryBit.recover_base(27)
      0

      iex> Cartouche.RecoveryBit.recover_base(28)
      1

      iex> Cartouche.RecoveryBit.recover_base(2)
      ** (FunctionClauseError) no function clause matching in Cartouche.RecoveryBit.recover_base/2
  """
  @spec recover_base(non_neg_integer(), integer() | atom() | nil) :: 0 | 1 | no_return()
  def recover_base(v, chain_id \\ nil)

  def recover_base(v, _chain_id) when v in [0, 1], do: v
  def recover_base(v, _chain_id) when v in [27, 28], do: v - 27

  def recover_base(v, chain_id) when v >= 35 do
    id = Cartouche.Chain.chain_id_value(chain_id)

    case v - id * 2 - 35 do
      base when base in [0, 1] ->
        base

      _ ->
        raise "Invalid EIP-155 Signature: recovery_bit=#{v}, chain_id=#{id}"
    end
  end
end
