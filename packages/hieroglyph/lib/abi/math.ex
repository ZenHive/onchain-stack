defmodule ABI.Math do
  @moduledoc """
  Helper functions for ABI's math functions.
  """

  use Descripex, namespace: "/math"

  api(:mod, "Compute integer modulo with sign-aware behavior, returning a non-negative result for negative dividends.",
    params: [
      x: [kind: :value, description: "Integer dividend (any sign)"],
      n: [kind: :value, description: "Positive integer divisor"]
    ],
    returns: %{type: :integer, description: "Non-negative remainder in the range 0..n-1"}
  )

  @doc """
  Simple function to compute modulo function to work on integers of any sign.

  ## Examples

      iex> ABI.Math.mod(5, 2)
      1

      iex> ABI.Math.mod(-5, 1337)
      1332

      iex> ABI.Math.mod(1337 + 5, 1337)
      5

      iex> ABI.Math.mod(0, 1337)
      0

      iex> ABI.Math.mod(-7, 5)
      3

      iex> ABI.Math.mod(-1338, 1337)
      1336
  """
  @spec mod(integer(), pos_integer()) :: non_neg_integer()
  def mod(x, n) when x > 0, do: rem(x, n)
  def mod(x, n) when x < 0, do: rem(rem(x, n) + n, n)
  def mod(0, _n), do: 0

  api(
    :kec,
    "Compute the keccak-256 hash of a binary input. The hash function used throughout Ethereum and the ABI spec for selector and event-topic derivation.",
    params: [
      data: [kind: :value, description: "Binary input of any length"]
    ],
    returns: %{type: :binary, description: "32-byte keccak-256 digest"}
  )

  @doc """
  Returns the keccak sha256 of a given input.

  ## Examples

      iex> ABI.Math.kec("hello world")
      <<71, 23, 50, 133, 168, 215, 52, 30, 94, 151, 47, 198, 119, 40, 99,
        132, 248, 2, 248, 239, 66, 165, 236, 95, 3, 187, 250, 37, 76, 176,
        31, 173>>

      iex> ABI.Math.kec(<<0x01, 0x02, 0x03>>)
      <<241, 136, 94, 218, 84, 183, 160, 83, 49, 140, 212, 30, 32, 147, 34,
        13, 171, 21, 214, 83, 129, 177, 21, 122, 54, 51, 168, 59, 253, 92,
        146, 57>>
  """
  @spec kec(binary()) :: binary()
  def kec(data) do
    ExSha3.keccak_256(data)
  end

  api(:pad, "Pad a binary up to the next 32-byte ABI word boundary, with side and fill byte chosen by argument.",
    params: [
      bin: [kind: :value, description: "The binary content to pad"],
      size_in_bytes: [
        kind: :value,
        description:
          "Logical field width used to compute the word boundary; output is rounded up to the next 32-byte multiple from this value"
      ],
      direction: [
        kind: :value,
        description:
          "Padding side — :left for left-aligned types like uint/int/address, :right for right-padded types like bytes<M> and string"
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Optional keyword list. Supports fill_byte: <<0xFF>> for signed sign-extension; defaults to <<0x00>>"
      ]
    ],
    returns: %{type: :binary, description: "Padded binary aligned to a 32-byte multiple"}
  )

  @doc """
  Pads a binary up to the next 32-byte ABI word boundary.

  `size_in_bytes` is the **logical field width** used to compute the word
  boundary — not necessarily `byte_size(bin)`. The output is always rounded
  up from `size_in_bytes` to a 32-byte multiple. `bin` may be shorter than
  `size_in_bytes` (callers like `encode_int`/`encode_uint` pass a target
  slot size and let padding absorb the difference); `encode_bytes` passes
  `byte_size(bin)` directly.

  `direction` is `:left` for left-aligned types like `uint`/`int`/`address`,
  `:right` for right-padded types like `bytes<M>` and `string`. Pass
  `fill_byte: <<0xFF>>` for signed sign-extension; defaults to `<<0x00>>`.

  ## Examples

      iex> ABI.Math.pad(<<1, 2, 3>>, 3, :left)
      <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3>>

      iex> ABI.Math.pad(<<1, 2, 3>>, 3, :right)
      <<1, 2, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>
  """
  @spec pad(binary(), non_neg_integer(), :left | :right, keyword()) :: binary()
  def pad(bin, size_in_bytes, direction, opts \\ []) do
    fill_byte = Keyword.get(opts, :fill_byte, <<0x00>>)

    total_size = size_in_bytes + mod(32 - mod(size_in_bytes, 32), 32)

    padding_size_bytes = total_size - byte_size(bin)

    padding =
      fill_byte
      |> Stream.duplicate(padding_size_bytes)
      |> Enum.to_list()
      |> :binary.list_to_bin()

    case direction do
      :left -> padding <> bin
      :right -> bin <> padding
    end
  end

  api(
    :unpad,
    "Inverse of pad/4. Reads size_in_bytes of content out of data, skipping 32-byte-slot padding on the matching side.",
    params: [
      data: [kind: :value, description: "Binary containing one padded ABI word followed by remaining bytes"],
      size_in_bytes: [kind: :value, description: "Logical field width to extract from the padded slot"],
      padding_direction: [
        kind: :value,
        description: "Side that was padded — :left for address/uint/int, :right for bytes<M>/string"
      ]
    ],
    returns: %{
      type: :tuple,
      description:
        "Two-tuple {value, rest} where value is the unpadded content and rest is whatever follows the padded word"
    }
  )

  @doc """
  Inverse of `pad/4`. Reads `size_in_bytes` of content out of `data`,
  skipping 32-byte-slot padding on the side matching `padding_direction`
  (`:left` for left-padded types like `address`, `:right` for right-padded
  types like `bytes<M>` and `string`). Returns `{value, rest}`, where
  `rest` is whatever follows the padded word in `data`.

  ## Examples

      iex> ABI.Math.unpad(
      ...>   <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      ...>     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3>>,
      ...>   3,
      ...>   :left
      ...> )
      {<<1, 2, 3>>, <<>>}

      iex> ABI.Math.unpad(
      ...>   <<1, 2, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      ...>     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      ...>     9, 9>>,
      ...>   3,
      ...>   :right
      ...> )
      {<<1, 2, 3>>, <<9, 9>>}
  """
  @spec unpad(binary(), non_neg_integer(), :left | :right) ::
          {binary(), binary()}
  def unpad(data, size_in_bytes, padding_direction) do
    total_size_in_bytes = size_in_bytes + mod(32 - mod(size_in_bytes, 32), 32)

    padding_size_in_bytes = total_size_in_bytes - size_in_bytes

    case padding_direction do
      :left ->
        <<_::binary-size(^padding_size_in_bytes), after_pad::binary>> = data
        <<value::binary-size(^size_in_bytes), rest::binary>> = after_pad
        {value, rest}

      :right ->
        <<value::binary-size(^size_in_bytes), after_value::binary>> = data
        <<_::binary-size(^padding_size_in_bytes), rest::binary>> = after_value
        {value, rest}
    end
  end
end
