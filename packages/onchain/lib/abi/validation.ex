defmodule ABI.Validation do
  @moduledoc false
  alias ABI.FunctionSelector
  alias ABI.Math
  alias ABI.TypeDecoder.StrictViolation

  @word_size_bytes 32
  @word_size_bits 256

  @doc false
  @spec chunks(binary(), [FunctionSelector.argument_type()], keyword()) :: [binary()]
  def chunks(data, types, opts) do
    {chunks, rest} =
      Enum.map_reduce(types, data, fn %{type: type}, bytes ->
        remaining = consume(type, bytes, opts)
        size = byte_size(bytes) - byte_size(remaining)
        {canonical(type, binary_part(bytes, 0, size)), remaining}
      end)

    if rest != <<>> do
      if strict?(opts),
        do: strict_violation!({:trailing_bytes, byte_size(rest)}),
        else: raise("Found extra binary data: #{inspect(rest)}")
    end

    chunks
  end

  # Legacy decoders consumed tuple tails in declaration order, ignoring offsets.
  # Normalize those offsets before alloy follows them. Payloads that already
  # use that layout are returned unchanged — rebuilding them copies every
  # dynamic tail.
  defp canonical(type, data) do
    if identity?(type, data), do: data, else: rewrite(type, data)
  end

  defp identity?({:tuple, []}, data), do: data == <<>>
  defp identity?({:array, _, 0}, data), do: data == <<>>

  defp identity?(type, data) do
    if FunctionSelector.dynamic?(type), do: match?({:ok, <<>>}, skip(type, data)), else: true
  end

  # Word-only scan. `consume/3` already checked padding and lengths; this only
  # asks whether offset words already name the declaration-order tails.
  defp skip(type, data) do
    if FunctionSelector.dynamic?(type), do: skip_dynamic(type, data), else: take_static(type, data)
  end

  defp skip_dynamic(type, <<len::256, rest::binary>>) when type in [:string, :bytes] do
    padded = padded_bytes(len)

    if byte_size(rest) < padded do
      :mismatch
    else
      <<_::binary-size(^padded), rest::binary>> = rest
      {:ok, rest}
    end
  end

  defp skip_dynamic({:array, type}, <<count::256, rest::binary>>), do: skip_repeated(type, count, rest)
  defp skip_dynamic({:array, type, count}, data), do: skip_repeated(type, count, data)

  defp skip_dynamic({:tuple, types}, data) do
    case split_head(types, data, []) do
      {:ok, markers, tails} -> scan_tails(markers, tails, byte_size(data) - byte_size(tails))
      :mismatch -> :mismatch
    end
  end

  defp skip_dynamic(_, _), do: :mismatch

  defp skip_repeated(_type, 0, data), do: {:ok, data}

  defp skip_repeated(type, count, data) do
    if FunctionSelector.dynamic?(type) do
      skip_dynamic_repeated(type, count, data)
    else
      take_static({:array, type, count}, data)
    end
  end

  defp skip_dynamic_repeated(type, count, data) do
    head_bytes = count * @word_size_bytes

    if byte_size(data) < head_bytes do
      :mismatch
    else
      <<head::binary-size(^head_bytes), tails::binary>> = data
      check_offsets(type, count, head, tails, head_bytes)
    end
  end

  defp check_offsets(_type, 0, <<>>, tails, _offset), do: {:ok, tails}
  defp check_offsets(_type, 0, _, _, _), do: :mismatch

  defp check_offsets(type, count, <<claimed::256, head::binary>>, tails, offset) when claimed == offset do
    case skip(type, tails) do
      {:ok, rest} -> check_offsets(type, count - 1, head, rest, offset + (byte_size(tails) - byte_size(rest)))
      :mismatch -> :mismatch
    end
  end

  defp check_offsets(_, _, _, _, _), do: :mismatch

  defp split_head([], data, acc), do: {:ok, Enum.reverse(acc), data}

  defp split_head([%{type: type} | types], data, acc) do
    if FunctionSelector.dynamic?(type) do
      case data do
        <<offset::256, rest::binary>> -> split_head(types, rest, [{:tail, offset, type} | acc])
        _ -> :mismatch
      end
    else
      case take_static(type, data) do
        {:ok, rest} -> split_head(types, rest, [:head | acc])
        :mismatch -> :mismatch
      end
    end
  end

  defp scan_tails([], tails, _offset), do: {:ok, tails}
  defp scan_tails([:head | markers], tails, offset), do: scan_tails(markers, tails, offset)

  defp scan_tails([{:tail, claimed, type} | markers], tails, offset) when claimed == offset do
    case skip(type, tails) do
      {:ok, rest} -> scan_tails(markers, rest, offset + (byte_size(tails) - byte_size(rest)))
      :mismatch -> :mismatch
    end
  end

  defp scan_tails(_, _, _), do: :mismatch

  defp take_static(type, data) do
    size = static_bytes(type)

    if byte_size(data) < size do
      :mismatch
    else
      <<_::binary-size(^size), rest::binary>> = data
      {:ok, rest}
    end
  end

  defp static_bytes({:tuple, types}), do: Enum.sum_by(types, &static_bytes(&1.type))
  defp static_bytes({:array, type, count}), do: count * static_bytes(type)
  defp static_bytes({:bytes, 0}), do: 0
  defp static_bytes(_type), do: @word_size_bytes

  defp padded_bytes(size) do
    size + Math.mod(@word_size_bytes - Math.mod(size, @word_size_bytes), @word_size_bytes)
  end

  defp rewrite({:tuple, types}, data) do
    {heads, tails} =
      Enum.map_reduce(types, data, fn %{type: type}, bytes ->
        if FunctionSelector.dynamic?(type) do
          <<_::256, rest::binary>> = bytes
          {{:tail, type}, rest}
        else
          rest = consume(type, bytes, [])
          size = byte_size(bytes) - byte_size(rest)
          {{:head, canonical(type, binary_part(bytes, 0, size))}, rest}
        end
      end)

    start = byte_size(data) - byte_size(tails)

    {parts, {_, _, tail_parts}} =
      Enum.map_reduce(heads, {tails, start, []}, fn
        {:head, bytes}, acc ->
          {bytes, acc}

        {:tail, type}, {remaining, offset, acc} ->
          rest = consume(type, remaining, [])
          size = byte_size(remaining) - byte_size(rest)
          bytes = canonical(type, binary_part(remaining, 0, size))
          {<<offset::256>>, {rest, offset + byte_size(bytes), [bytes | acc]}}
      end)

    IO.iodata_to_binary([parts, Enum.reverse(tail_parts)])
  end

  defp rewrite({:array, type}, <<count::256, rest::binary>>) do
    IO.iodata_to_binary([<<count::256>>, rewrite({:array, type, count}, rest)])
  end

  defp rewrite({:array, type, count}, data) do
    rewrite({:tuple, List.duplicate(%{type: type}, count)}, data)
  end

  defp rewrite(_type, data), do: data

  @spec consume(FunctionSelector.type(), binary(), keyword()) :: binary()
  defp consume({:uint, bits}, data, opts) do
    validate_uint_padding!(data, bits, opts)
    <<_::256, rest::binary>> = data
    rest
  end

  defp consume({:int, bits}, data, opts) do
    validate_int_padding!(data, bits, opts)
    <<_::256, rest::binary>> = data
    rest
  end

  defp consume(:bool, data, opts) do
    rest = consume({:uint, 8}, data, opts)
    <<value::256, _::binary>> = data
    if value not in [0, 1], do: decode_invalid_bool!(value, opts)
    rest
  end

  defp consume(type, data, opts) when type in [:string, :bytes] do
    <<size::256, rest::binary>> = data
    validate_dynamic_length!(rest, size, type, opts)
    {_, rest} = Math.unpad(rest, size, :right)
    rest
  end

  defp consume({:bytes, 0}, data, _opts), do: data

  defp consume({:bytes, size}, data, _opts) when size > 0 and size <= 32 do
    {_, rest} = Math.unpad(data, size, :right)
    rest
  end

  defp consume(:address, data, _opts) do
    {_, rest} = Math.unpad(data, 20, :left)
    rest
  end

  defp consume(:function, data, _opts) do
    {_, rest} = Math.unpad(data, 24, :right)
    rest
  end

  defp consume({:array, type}, data, opts) do
    <<count::256, rest::binary>> = data
    consume({:array, type, count}, rest, opts)
  end

  defp consume({:array, _, 0}, data, _opts), do: data

  defp consume({:array, type, count}, data, opts) do
    validate_element_count!(data, type, count, opts)
    if count > 100_000, do: raise(ArgumentError, "ABI value limit exceeded")
    consume({:tuple, List.duplicate(%{type: type}, count)}, data, opts)
  end

  defp consume({:tuple, types}, data, opts) do
    rest =
      Enum.reduce(types, data, fn %{type: type}, bytes ->
        if FunctionSelector.dynamic?(type),
          do: consume({:uint, 256}, bytes, opts),
          else: consume(type, bytes, opts)
      end)

    Enum.reduce(types, rest, fn %{type: type}, bytes ->
      if FunctionSelector.dynamic?(type), do: consume(type, bytes, opts), else: bytes
    end)
  end

  defp consume(type, _, _), do: raise("Unsupported decoding type: #{inspect(type)}")

  # An array of `n` elements needs at least `n * min_element_words(element)`
  # words of payload behind it, so a larger count can never be satisfied.
  # Checked BEFORE the element type list is materialized: the count comes from
  # a chain-supplied length prefix, and building a list that long is an
  # allocation DoS the later decode failure would never get the chance to
  # prevent. Zero-width element types (an empty tuple, a fixed-size array of
  # length zero, or a nest of those) admit no such bound and are left
  # unguarded — Solidity cannot emit them.
  @spec validate_element_count!(binary(), FunctionSelector.type(), non_neg_integer(), keyword()) ::
          :ok
  defp validate_element_count!(data, type, element_count, opts) do
    min_words = min_element_words(type)
    available_words = div(byte_size(data), @word_size_bytes)

    cond do
      min_words == 0 or element_count * min_words <= available_words ->
        :ok

      strict?(opts) ->
        strict_violation!(
          {:length_out_of_bounds,
           %{
             type: {:array, type},
             length: element_count,
             available: byte_size(data)
           }}
        )

      true ->
        raise "Array element count #{element_count} exceeds the #{available_words} remaining 32-byte words"
    end
  end

  # Smallest number of 32-byte words one element of this type can occupy: a
  # single tail-offset word when dynamic, the summed static width otherwise.
  @spec min_element_words(FunctionSelector.type()) :: non_neg_integer()
  defp min_element_words(type) do
    if FunctionSelector.dynamic?(type) do
      1
    else
      static_element_words(type)
    end
  end

  @spec static_element_words(FunctionSelector.type()) :: non_neg_integer()
  defp static_element_words({:tuple, types}) do
    Enum.sum_by(types, fn %{type: member} -> min_element_words(member) end)
  end

  defp static_element_words({:array, inner, count}), do: count * min_element_words(inner)
  defp static_element_words(_type), do: 1

  @spec strict?(keyword()) :: boolean()
  defp strict?(opts), do: Keyword.get(opts, :strict, false)

  @spec strict_violation!(term()) :: no_return()
  defp strict_violation!(detail) do
    raise StrictViolation, detail
  end

  @spec decode_invalid_bool!(integer(), keyword()) :: no_return()
  defp decode_invalid_bool!(value, opts) do
    if strict?(opts) do
      strict_violation!({:invalid_bool, value})
    else
      raise CaseClauseError, term: value
    end
  end

  @spec validate_uint_padding!(binary(), integer(), keyword()) :: :ok
  defp validate_uint_padding!(data, size_in_bits, opts) do
    validate_left_padding!(
      data,
      size_in_bits,
      :zero,
      {:uint, size_in_bits},
      opts
    )
  end

  @spec validate_int_padding!(binary(), integer(), keyword()) :: :ok
  defp validate_int_padding!(data, size_in_bits, opts) do
    validate_left_padding!(
      data,
      size_in_bits,
      :sign,
      {:int, size_in_bits},
      opts
    )
  end

  @spec validate_left_padding!(
          binary(),
          integer(),
          :zero | :sign,
          term(),
          keyword()
        ) :: :ok
  defp validate_left_padding!(_data, @word_size_bits, _mode, _type, _opts), do: :ok

  defp validate_left_padding!(data, size_in_bits, mode, type, opts) do
    if strict?(opts) do
      value_size = div(size_in_bits, 8)
      padding_size = @word_size_bytes - value_size

      {padding, value} = split_left_padded(data, padding_size, value_size)

      expected = expected_left_padding(mode, padding_size, value)

      if padding == expected do
        :ok
      else
        strict_violation!({:non_canonical_padding, %{type: type}})
      end
    else
      :ok
    end
  end

  @spec expected_left_padding(:zero | :sign, non_neg_integer(), binary()) ::
          binary()
  defp expected_left_padding(:zero, padding_size, _value) do
    :binary.copy(<<0>>, padding_size)
  end

  defp expected_left_padding(:sign, padding_size, value) do
    <<sign::1, _::bitstring>> = value
    fill = if sign == 1, do: <<0xFF>>, else: <<0>>
    :binary.copy(fill, padding_size)
  end

  @spec split_left_padded(binary(), non_neg_integer(), non_neg_integer()) ::
          {binary(), binary()}
  defp split_left_padded(data, padding_size, value_size) do
    <<padding::binary-size(^padding_size), after_padding::binary>> = data
    <<value::binary-size(^value_size), _rest::binary>> = after_padding

    {padding, value}
  end

  @spec validate_dynamic_length!(
          binary(),
          non_neg_integer(),
          atom(),
          keyword()
        ) :: :ok
  defp validate_dynamic_length!(data, size_in_bytes, type, opts) do
    if strict?(opts) do
      total_size =
        size_in_bytes +
          Math.mod(
            @word_size_bytes - Math.mod(size_in_bytes, @word_size_bytes),
            @word_size_bytes
          )

      if byte_size(data) >= total_size do
        :ok
      else
        strict_violation!(
          {:length_out_of_bounds,
           %{
             type: type,
             length: size_in_bytes,
             available: byte_size(data)
           }}
        )
      end
    else
      :ok
    end
  end
end
