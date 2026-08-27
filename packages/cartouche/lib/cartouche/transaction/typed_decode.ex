defmodule Cartouche.Transaction.TypedDecode do
  @moduledoc """
  Shared EIP-2718 typed-transaction envelope helpers.

  Every typed transaction (EIP-2930 `V_2930`, EIP-7702 `V4`, …) decodes the
  same way: match the leading type byte, RLP-decode the remaining payload, then
  hand the decoded field list to a type-specific `decode_fields` callback. This
  module also owns the EIP-2930 access-list encode/decode guards so every
  envelope that carries an access list rejects the same malformed entries on
  both sides of the wire.
  """

  @doc """
  Dispatches a typed-transaction binary.

  Matches the leading `tx_type` byte, RLP-decodes the rest (returning `invalid`
  on malformed RLP), and applies `decode_fields` to the decoded field list. Any
  other leading byte (or non-binary) yields `{:error, invalid}`.
  """
  @spec decode(binary(), byte(), String.t(), (list() -> {:ok, term()} | {:error, String.t()})) ::
          {:ok, term()} | {:error, String.t()}
  def decode(<<tx_type, trx_enc::binary>>, tx_type, invalid, decode_fields) do
    with {:ok, fields} <- safe_rlp_decode(trx_enc, invalid) do
      decode_fields.(fields)
    end
  end

  def decode(_, _tx_type, invalid, _decode_fields), do: {:error, invalid}

  @spec safe_rlp_decode(binary(), String.t()) :: {:ok, list()} | {:error, String.t()}
  defp safe_rlp_decode(trx_enc, invalid) do
    {:ok, ExRLP.decode(trx_enc)}
  rescue
    # ExRLP raises DecodeError on most malformed input, but leaks a MatchError
    # on truncated length-prefixed binaries (an internal `<<_::size>> = tail`).
    _e in [ExRLP.DecodeError, MatchError] -> {:error, invalid}
  end

  @typedoc "EIP-2930 access list: `{address, [storage_key]}` pairs."
  @type access_list :: [{<<_::160>>, [<<_::256>>]}]
  @type access_list_entry :: {<<_::160>>, [<<_::256>>]}

  @invalid_access_list "access_list entries must contain a 20-byte address and 32-byte storage keys"

  @doc """
  Decodes an RLP-decoded access list into `{address, [storage_key]}` tuples.

  Each entry must be a `[20-byte address, [32-byte storage_key, ...]]` list;
  anything else yields `{:error, invalid}`. Shared by every typed transaction
  that carries an EIP-2930 access list (`V_2930`, `V3`, …).
  """
  @spec decode_access_list(term(), String.t()) :: {:ok, access_list()} | {:error, String.t()}
  def decode_access_list(access_list, invalid) when is_list(access_list),
    do: access_list |> Enum.reduce_while({:ok, []}, &decode_access_entry(&1, &2, invalid)) |> reverse_ok()

  def decode_access_list(_, invalid), do: {:error, invalid}

  @doc """
  Encodes an access list as EIP-2930 RLP items (`[address, storage_keys]`).

  Constructors that document a bare-address shorthand must canonicalize to
  `{address, []}` before calling this. Malformed entries raise `ArgumentError`.
  """
  @spec encode_access_list(term()) :: [[<<_::160>> | [<<_::256>>]]]
  def encode_access_list(access_list) when is_list(access_list) do
    Enum.map(access_list, fn entry ->
      {address, storage} = validate_access_list_entry!(entry)
      [address, storage]
    end)
  end

  def encode_access_list(_access_list), do: raise(ArgumentError, @invalid_access_list)

  @doc """
  Accepts a canonical `{address, storage_keys}` access-list entry.

  Used by constructors that lift documented shorthand before encoding.
  """
  @spec validate_access_list_entry!(term()) :: access_list_entry()
  def validate_access_list_entry!({address, storage} = entry)
      when is_binary(address) and byte_size(address) == 20 and is_list(storage) do
    if Enum.all?(storage, &(is_binary(&1) and byte_size(&1) == 32)) do
      entry
    else
      raise ArgumentError, @invalid_access_list
    end
  end

  def validate_access_list_entry!(_entry), do: raise(ArgumentError, @invalid_access_list)

  @spec decode_access_entry(term(), {:ok, access_list()}, String.t()) ::
          {:cont, {:ok, access_list()}} | {:halt, {:error, String.t()}}
  defp decode_access_entry([address, storage], {:ok, entries}, invalid)
       when byte_size(address) == 20 and is_list(storage) do
    case decode_storage_keys(storage, invalid) do
      {:ok, storage} -> {:cont, {:ok, [{address, storage} | entries]}}
      _ -> {:halt, {:error, invalid}}
    end
  end

  defp decode_access_entry(_, _, invalid), do: {:halt, {:error, invalid}}

  @spec decode_storage_keys(list(), String.t()) :: {:ok, [<<_::256>>]} | {:error, String.t()}
  defp decode_storage_keys(storage, invalid) do
    storage
    |> Enum.reduce_while({:ok, []}, fn
      storage_key, {:ok, keys} when byte_size(storage_key) == 32 ->
        {:cont, {:ok, [storage_key | keys]}}

      _storage_key, _acc ->
        {:halt, {:error, invalid}}
    end)
    |> reverse_ok()
  end

  @doc """
  Left-pads a signature/word binary to a full 32-byte word.

  Words longer than 32 bytes are rejected with `{:error, invalid}`.
  """
  @spec decode_word(binary(), String.t()) :: {:ok, <<_::256>>} | {:error, String.t()}
  def decode_word(word, _invalid) when byte_size(word) <= 32, do: {:ok, Cartouche.Hex.pad(word, 32)}
  def decode_word(_, invalid), do: {:error, invalid}

  @doc """
  Decodes an RLP `y_parity` field (`0`/`1`) into a boolean.

  Any other value — or a non-binary that `:binary.decode_unsigned/1` rejects —
  yields `{:error, invalid}`.
  """
  @spec decode_y_parity(binary(), String.t()) :: {:ok, boolean()} | {:error, String.t()}
  def decode_y_parity(y_parity, invalid) do
    case :binary.decode_unsigned(y_parity) do
      0 -> {:ok, false}
      1 -> {:ok, true}
      _ -> {:error, invalid}
    end
  rescue
    ArgumentError -> {:error, invalid}
  end

  @spec reverse_ok({:ok, list()} | {:error, String.t()}) :: {:ok, list()} | {:error, String.t()}
  defp reverse_ok({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_ok({:error, _} = error), do: error
end
