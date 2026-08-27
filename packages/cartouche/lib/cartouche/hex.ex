defmodule Cartouche.Hex do
  @moduledoc """
  Helper module for parsing and encoding hex values.

  If you `use Cartouche.Hex`, then you can use the `~h` sigil for compile-time
  hex-to-binary compilation.
  """
  use Descripex, namespace: "/ethereum/hex"

  defmodule InvalidHex do
    @moduledoc """
    Raised by `Cartouche.Hex` decode/encode bang functions when input is not
    valid hex (wrong length, non-hex characters, missing/extra `0x` prefix, etc.).

    Public callers can `rescue Cartouche.Hex.InvalidHex` to handle these.
    """
    defexception message: "invalid hex"
  end

  @type t :: binary()

  defmacro __using__(_opts) do
    quote do
      import Cartouche.Hex,
        only: [sigil_h: 2, hex!: 1, to_hex: 1, to_address: 1, from_hex: 1, from_hex!: 1]

      alias Cartouche.Hex

      require Hex
    end
  end

  @doc ~S"""
  Handles the sigil `~h` for list of words.

  Parses a hex string at compile-time.

  ## Examples

      iex> use Cartouche.Hex
      iex> ~h[0x22]
      <<0x22>>

      iex> use Cartouche.Hex
      iex> ~h[0x2244]
      <<0x22, 0x44>>
  """
  defmacro sigil_h(term, modifiers)

  defmacro sigil_h({:<<>>, _meta, [string]}, _modifiers = []) when is_binary(string) do
    hex_str = :elixir_interpolation.unescape_string(string)

    Cartouche.Hex.decode_hex!(hex_str)
  end

  @doc ~S"""
  Similar non-sigil compile-time hex parser.

  ## Examples

      iex> use Cartouche.Hex
      iex> hex!("0x22")
      <<0x22>>

      iex> use Cartouche.Hex
      iex> hex!("0x2244")
      <<0x22, 0x44>>
  """
  defmacro hex!(hex_str) when is_binary(hex_str) do
    Cartouche.Hex.decode_hex!(hex_str)
  end

  api(:decode_hex, "Decode a hex string into raw bytes without raising on invalid input.",
    params: [
      b: [
        kind: :value,
        description: "Hex string with optional `0x` prefix; odd-length inputs are left-padded by one nibble."
      ]
    ],
    returns: %{
      type: :ok_or_invalid_hex,
      description: "`{:ok, raw_binary}` that can be passed back to `encode_hex/1`, or `:invalid_hex` when decoding fails."
    },
    composes_with: [:encode_hex]
  )

  @doc """
  Parses a hex string, but returns `:error` instead
  of raising if hex is invalid.

  ## Examples

      iex> Cartouche.Hex.decode_hex("0xaabb")
      {:ok, <<170, 187>>}

      iex> Cartouche.Hex.decode_hex("aabb")
      {:ok, <<170, 187>>}

      iex> Cartouche.Hex.decode_hex("0xgggg")
      :invalid_hex
  """
  @spec decode_hex(String.t()) :: {:ok, t()} | :invalid_hex
  def decode_hex(b), do: decode_hex_(b)

  api(:from_hex, "Alias for `decode_hex/1` that decodes a hex string into raw bytes.",
    params: [
      b: [
        kind: :value,
        description: "Hex string with optional `0x` prefix; odd-length inputs are left-padded by one nibble."
      ]
    ],
    returns: %{
      type: :ok_or_invalid_hex,
      description: "`{:ok, raw_binary}` that can be passed back to `to_hex/1`, or `:invalid_hex` when decoding fails."
    },
    composes_with: [:decode_hex, :to_hex]
  )

  @doc """
  Alias for `decode_hex`.

  ## Examples

      iex> Cartouche.Hex.from_hex("0xaabb")
      {:ok, <<0xaa, 0xbb>>}

      iex> Cartouche.Hex.from_hex("0xgggg")
      :invalid_hex
  """
  @spec from_hex(String.t()) :: {:ok, t()} | :invalid_hex
  def from_hex(b), do: decode_hex(b)

  api(:from_hex!, "Alias for `decode_hex!/1` that decodes a hex string into raw bytes or raises.",
    params: [
      b: [
        kind: :value,
        description: "Hex string with optional `0x` prefix; odd-length inputs are left-padded by one nibble."
      ]
    ],
    returns: %{
      type: :raw_binary,
      description: "Raw binary bytes that can be passed back to `to_hex/1`; inverse of `to_hex/1` for binary inputs."
    },
    errors: [invalid_hex: "Raised as `Cartouche.Hex.InvalidHex` when the input cannot be decoded."],
    composes_with: [:decode_hex!, :to_hex]
  )

  @doc """
  Alias for `decode_hex!`.

  ## Examples

    iex> Cartouche.Hex.from_hex!("0xaabb")
    <<0xaa, 0xbb>>

    iex> Cartouche.Hex.from_hex!("0xggaabb")
    ** (Cartouche.Hex.InvalidHex) invalid hex: "0xggaabb"
  """
  @spec from_hex!(String.t()) :: t()
  def from_hex!(b), do: decode_hex!(b)

  api(:decode_hex!, "Decode a hex string into raw bytes, raising on invalid input.",
    params: [
      b: [
        kind: :value,
        description: "Hex string with optional `0x` prefix; odd-length inputs are left-padded by one nibble."
      ]
    ],
    returns: %{
      type: :raw_binary,
      description:
        "Raw binary bytes that can be passed back to `encode_hex/1`; inverse of `encode_hex/1` for binary inputs."
    },
    errors: [invalid_hex: "Raised as `Cartouche.Hex.InvalidHex` when the input cannot be decoded."],
    composes_with: [:decode_hex, :encode_hex]
  )

  @doc """
  Parses a hex string and raises if invalid.

  ## Examples

    iex> Cartouche.Hex.decode_hex!("aabb")
    <<170, 187>>

    iex> Cartouche.Hex.decode_hex!("0xggaabb")
    ** (Cartouche.Hex.InvalidHex) invalid hex: "0xggaabb"
  """
  @spec decode_hex!(String.t()) :: t()
  def decode_hex!(b) do
    case decode_hex_(b) do
      {:ok, hex} ->
        hex

      _ ->
        raise InvalidHex, "invalid hex: \"#{b}\""
    end
  end

  api(:decode_address!, "Decode a 20-byte Ethereum address hex string into raw address bytes.",
    params: [
      hex: [kind: :value, description: "0x-prefixed or bare hex string that must decode to exactly 20 bytes."]
    ],
    returns: %{
      type: :ethereum_address_binary,
      description:
        "20 raw address bytes suitable for `encode_address/1`; inverse of `encode_address/1` for valid address bytes."
    },
    errors: [invalid_hex: "Raised as `Cartouche.Hex.InvalidHex` when the input is not exactly 20 decoded bytes."],
    composes_with: [:decode_sized!, :encode_address]
  )

  @doc """
  Parses an Ethereum 20-bytes hex string.

  Identical to `decode_hex!/1` except fails if
  string is not exactly 20-bytes.

  ## Examples

    iex> Cartouche.Hex.decode_address!("0x0000000000000000000000000000000000000001")
    <<1::160>>

    iex> Cartouche.Hex.decode_address!("0xaabb")
    ** (Cartouche.Hex.InvalidHex) invalid hex address: "0xaabb"
  """
  @spec decode_address!(String.t()) :: t() | no_return()
  def decode_address!(hex) do
    decode_sized!(hex, 20, "invalid hex address")
  end

  api(:decode_word!, "Decode a 32-byte Ethereum word hex string into raw bytes.",
    params: [
      hex: [kind: :value, description: "0x-prefixed or bare hex string that must decode to exactly 32 bytes."]
    ],
    returns: %{type: :ethereum_word_binary, description: "32 raw bytes suitable for ABI words or hashes."},
    errors: [invalid_hex: "Raised as `Cartouche.Hex.InvalidHex` when the input is not exactly 32 decoded bytes."],
    composes_with: [:decode_sized!]
  )

  @doc """
  Parses an Ethereum 32-bytes hex string.

  Identical to `decode_hex!/1` except fails if
  string is not exactly 32-bytes.

  ## Examples

    iex> Cartouche.Hex.decode_word!("0x0000000000000000000000000000000000000000000000000000000000000001")
    <<1::256>>

    iex> Cartouche.Hex.decode_word!("0xaabb")
    ** (Cartouche.Hex.InvalidHex) invalid hex word: "0xaabb"
  """
  @spec decode_word!(String.t()) :: t() | no_return()
  def decode_word!(hex) do
    decode_sized!(hex, 32, "invalid hex word")
  end

  api(:decode_sized!, "Decode a hex string and require an exact byte size.",
    params: [
      hex: [kind: :value, description: "0x-prefixed or bare hex string to decode."],
      sz: [kind: :value, description: "Required decoded byte length."],
      msg: [
        kind: :value,
        default: nil,
        description: "Optional error message prefix used when the decoded byte length is wrong."
      ]
    ],
    returns: %{type: :raw_binary, description: "Raw decoded bytes of exactly `sz` bytes."},
    errors: [invalid_hex: "Raised as `Cartouche.Hex.InvalidHex` when decoding fails or decoded length differs from `sz`."],
    composes_with: [:decode_hex!]
  )

  @doc """
  Parses an Ethereum x-bytes hex string.

  Identical to `decode_hex!/1` except fails if
  string is not exactly x-bytes.

  ## Examples

    iex> Cartouche.Hex.decode_sized!("0x001122", 3)
    <<0x00, 0x11, 0x22>>

    iex> Cartouche.Hex.decode_sized!("0xaabb", 3)
    ** (Cartouche.Hex.InvalidHex) invalid 3-byte sized hex: "0xaabb"
  """
  @spec decode_sized!(String.t(), integer(), String.t() | nil) :: t() | no_return()
  def decode_sized!(hex, sz, msg \\ nil) do
    res = decode_hex!(hex)

    if byte_size(res) == sz do
      res
    else
      raise InvalidHex,
            (case msg do
               nil ->
                 "invalid #{sz}-byte sized hex: \"#{hex}\""

               _ ->
                 "#{msg}: \"#{hex}\""
             end)
    end
  end

  api(:decode_maybe_hex!, "Decode a hex string into raw bytes, preserving `nil` inputs.",
    params: [
      h: [kind: :value, description: "Hex string with optional `0x` prefix, or `nil`."]
    ],
    returns: %{
      type: :raw_binary_or_nil,
      description: "Raw binary bytes that can be passed to `maybe_encode_hex/1`, or `nil` when input is `nil`."
    },
    errors: [invalid_hex: "Raised as `Cartouche.Hex.InvalidHex` when a non-nil input cannot be decoded."],
    composes_with: [:decode_hex!, :maybe_encode_hex]
  )

  @doc """
  Parses hex is value is not nil, otherwise returns `nil`.

  ## Examples

    iex> Cartouche.Hex.decode_maybe_hex!("0xaabb")
    <<170, 187>>

    iex> Cartouche.Hex.decode_maybe_hex!(nil)
    nil
  """
  @spec decode_maybe_hex!(String.t() | nil) :: t() | nil
  def decode_maybe_hex!(h) when is_nil(h), do: nil
  def decode_maybe_hex!(h) when is_binary(h), do: decode_hex!(h)

  api(:decode_hex_number!, "Decode a hex quantity string into a big-endian integer, raising on invalid input.",
    params: [
      b: [kind: :value, description: "Hex string with optional `0x` prefix representing an unsigned big-endian integer."]
    ],
    returns: %{
      type: :integer,
      description: "Unsigned integer inverse of `encode_quantity/1`."
    },
    errors: [invalid_hex: "Raised as `Cartouche.Hex.InvalidHex` when decoding fails."],
    composes_with: [:decode_hex_number, :encode_quantity]
  )

  @doc """
  Parses hex value as a big-endian integer. Raises if invalid.

  ## Examples

    iex> Cartouche.Hex.decode_hex_number!("0xaabb")
    0xaabb

    iex> Cartouche.Hex.decode_hex_number!("0xgggg")
    ** (Cartouche.Hex.InvalidHex) invalid hex number: "0xgggg"
  """
  @spec decode_hex_number!(String.t()) :: integer() | no_return()
  def decode_hex_number!(b) do
    case decode_hex_number(b) do
      {:ok, x} ->
        x

      :invalid_hex ->
        raise InvalidHex, "invalid hex number: \"#{b}\""
    end
  end

  api(:decode_maybe_hex_number!, "Decode a hex quantity string into an integer, preserving `nil` inputs.",
    params: [
      b: [
        kind: :value,
        description: "Hex string with optional `0x` prefix representing an unsigned big-endian integer, or `nil`."
      ]
    ],
    returns: %{type: :integer_or_nil, description: "Unsigned integer value, or `nil` when input is `nil`."},
    errors: [invalid_hex: "Raised as `Cartouche.Hex.InvalidHex` when a non-nil input cannot be decoded."],
    composes_with: [:decode_hex_number!]
  )

  @doc """
  Parses a hex value as a big-endian integer if not nil, otherwise returns `nil`.

  Useful for JSON-RPC fields that are absent on pre-fork blocks (e.g.
  `blobGasUsed` / `blobGasPrice` on pre-Cancun receipts).

  ## Examples

    iex> Cartouche.Hex.decode_maybe_hex_number!("0xaabb")
    0xaabb

    iex> Cartouche.Hex.decode_maybe_hex_number!(nil)
    nil
  """
  @spec decode_maybe_hex_number!(String.t() | nil) :: integer() | nil | no_return()
  def decode_maybe_hex_number!(b) when is_nil(b), do: nil
  def decode_maybe_hex_number!(b) when is_binary(b), do: decode_hex_number!(b)

  api(:decode_hex_input!, "Normalize either a `0x` hex string or already-raw binary into raw bytes.",
    params: [
      hex: [
        kind: :value,
        description:
          "Either a `0x`-prefixed hex string or raw binary bytes; bare non-prefixed strings are treated as raw bytes, not decoded hex."
      ]
    ],
    returns: %{
      type: :raw_binary,
      description: "Raw binary bytes; `0x` strings are decoded, while already-raw binaries pass through unchanged."
    },
    errors: [invalid_hex: "Raised as `Cartouche.Hex.InvalidHex` when a `0x`-prefixed input cannot be decoded."],
    composes_with: [:decode_hex!]
  )

  @doc ~S"""
  Decodes hex, allowing it to either be `"0x..."` or a raw binary.

  Note: a hex-printed string, in this case, must start with `0x`,
        otherwise it will be interpreted as its ASCII values.

  ## Examples

      iex> Cartouche.Hex.decode_hex_input!("0x55")
      <<0x55>>

      iex> Cartouche.Hex.decode_hex_input!(<<0x55>>)
      <<0x55>>
  """
  @spec decode_hex_input!(String.t() | binary()) :: t()
  def decode_hex_input!("0x" <> _ = hex), do: decode_hex!(hex)
  def decode_hex_input!(hex) when is_binary(hex), do: hex

  api(:decode_hex_number, "Decode a hex quantity string into a big-endian integer without raising on invalid input.",
    params: [
      b: [kind: :value, description: "Hex string with optional `0x` prefix representing an unsigned big-endian integer."]
    ],
    returns: %{
      type: :ok_or_invalid_hex,
      description: "`{:ok, integer}` inverse of `encode_quantity/1`, or `:invalid_hex` when decoding fails."
    },
    composes_with: [:decode_hex, :encode_quantity]
  )

  @doc """
  Parses hex value as a big-endian integer.

  ## Examples

      iex> Cartouche.Hex.decode_hex_number("0xaabb")
      {:ok, 0xaabb}

      iex> Cartouche.Hex.decode_hex_number("0xgggg")
      :invalid_hex
  """
  @spec decode_hex_number(String.t()) :: {:ok, integer()} | :invalid_hex
  def decode_hex_number(b) do
    with {:ok, x} <- decode_hex(b), do: {:ok, :binary.decode_unsigned(x)}
  end

  api(:encode_hex, "Encode raw binary bytes as a lowercase `0x`-prefixed hex string.",
    params: [
      b: [
        kind: :value,
        description:
          "Raw binary bytes; do not pass an already-encoded hex string unless you intend to encode its ASCII bytes."
      ]
    ],
    returns: %{
      type: :hex_string,
      description: "Lowercase `0x`-prefixed hex string; inverse of `decode_hex!/1` and successful `decode_hex/1` results."
    },
    composes_with: [:decode_hex!, :decode_hex]
  )

  @doc """
  Encodes a given value as a lowercase hex string, starting with `0x`.

  ## Examples

    iex> Cartouche.Hex.encode_hex(<<0xaa, 0xbb>>)
    "0xaabb"
  """
  @spec encode_hex(t()) :: String.t()
  def encode_hex(b) when is_binary(b), do: "0x" <> Base.encode16(b, case: :lower)

  api(:to_hex, "Alias for `encode_hex/1` that encodes raw binary bytes as lowercase `0x` hex.",
    params: [
      b: [
        kind: :value,
        description:
          "Raw binary bytes; do not pass an already-encoded hex string unless you intend to encode its ASCII bytes."
      ]
    ],
    returns: %{
      type: :hex_string,
      description: "Lowercase `0x`-prefixed hex string; inverse of `from_hex!/1` for binary inputs."
    },
    composes_with: [:encode_hex, :from_hex!]
  )

  @doc """
  Alias for `encode_hex`.

  ## Examples

    iex> Cartouche.Hex.to_hex(<<0xaa, 0xbb>>)
    "0xaabb"
  """
  @spec to_hex(t()) :: String.t()
  def to_hex(b), do: encode_hex(b)

  api(:encode_big_hex, "Encode raw binary bytes as an uppercase `0x`-prefixed hex string.",
    params: [
      hex: [kind: :value, description: "Raw binary bytes to hex-encode in uppercase."]
    ],
    returns: %{
      type: :hex_string,
      description: "Uppercase `0x`-prefixed hex string; decodable by `decode_hex!/1` because decoding accepts mixed case."
    },
    composes_with: [:decode_hex!]
  )

  @doc ~S"""
  Encodes hex, in CAPITALS.

  ## Examples

    iex> Cartouche.Hex.encode_big_hex(<<0xcc, 0xdd>>)
    "0xCCDD"
  """
  @spec encode_big_hex(binary()) :: String.t()
  def encode_big_hex(hex) when is_binary(hex), do: "0x" <> Base.encode16(hex)

  api(:encode_short_hex, "Encode raw bytes or an integer as uppercase `0x` hex without leading zeros.",
    params: [
      hex: [kind: :value, description: "Raw binary bytes or non-negative integer to encode as a compact hex quantity."]
    ],
    returns: %{
      type: :hex_string,
      description: "Uppercase `0x`-prefixed hex string with leading zero nibbles stripped; `0` encodes as `0x0`."
    },
    composes_with: [:decode_hex_number!]
  )

  @doc ~S"""
  Encodes hex, striping any leading zeros.

  ## Examples

    iex> Cartouche.Hex.encode_short_hex(<<0xc>>)
    "0xC"

    iex> Cartouche.Hex.encode_short_hex(12)
    "0xC"

    iex> Cartouche.Hex.encode_short_hex(<<0x0>>)
    "0x0"
  """
  @spec encode_short_hex(binary() | integer()) :: String.t()
  def encode_short_hex(hex) when is_binary(hex) do
    enc = Base.encode16(hex)

    "0x" <>
      case String.replace_leading(enc, "0", "") do
        "" ->
          "0"

        els ->
          els
      end
  end

  def encode_short_hex(v) when is_integer(v), do: encode_short_hex(:binary.encode_unsigned(v))

  api(:encode_quantity, "Encode a non-negative integer as a JSON-RPC quantity string.",
    params: [
      n: [kind: :value, description: "Non-negative integer to encode as a JSON-RPC QUANTITY."]
    ],
    returns: %{
      type: :json_rpc_quantity,
      description: "Lowercase `0x`-prefixed quantity with no leading zeros; inverse of `decode_hex_number!/1`."
    },
    composes_with: [:decode_hex_number!, :decode_hex_number]
  )

  @doc """
  Encodes a non-negative integer as a JSON-RPC "quantity" string.

  Lowercase hex with `0x` prefix and no leading zeros. `0` becomes `"0x0"`.

  This matches the JSON-RPC spec for the `QUANTITY` type used in
  `eth_getBlockByNumber`, `eth_getBalance`, `eth_call` block params, etc.

  ## Examples

      iex> Cartouche.Hex.encode_quantity(0)
      "0x0"

      iex> Cartouche.Hex.encode_quantity(55)
      "0x37"

      iex> Cartouche.Hex.encode_quantity(24_975_978)
      "0x17d1a6a"
  """
  @spec encode_quantity(non_neg_integer()) :: String.t()
  def encode_quantity(0), do: "0x0"

  def encode_quantity(n) when is_integer(n) and n > 0, do: "0x" <> (n |> Integer.to_string(16) |> String.downcase())

  api(:pad, "Left-pad a raw binary with zero bytes to an exact byte length.",
    params: [
      bin: [kind: :value, description: "Raw binary bytes to left-pad."],
      size: [kind: :value, description: "Target byte length; must be greater than or equal to the input byte size."]
    ],
    returns: %{type: :raw_binary, description: "Raw binary of exactly `size` bytes, with zero bytes prepended as needed."}
  )

  @doc ~S"""
  Pads a binary to a given length.

  ## Examples

      iex> Cartouche.Hex.pad(<<1, 2>>, 2)
      <<1, 2>>

      iex> Cartouche.Hex.pad(<<1, 2>>, 4)
      <<0, 0, 1, 2>>

      iex> Cartouche.Hex.pad(<<1, 2>>, 1)
      ** (FunctionClauseError) no function clause matching in Cartouche.Hex.pad/2
  """
  @spec pad(binary(), pos_integer()) :: binary()
  def pad(bin, size) when size > byte_size(bin) do
    padding_len_bits = (size - byte_size(bin)) * 8
    <<0::size(padding_len_bits)>> <> bin
  end

  def pad(bin, size) when size == byte_size(bin), do: bin

  api(:encode_bytes, "Encode an integer as fixed-width raw bytes, left-padded with zeros.",
    params: [
      b: [kind: :value, description: "Integer amount to encode, or `nil` to preserve missing optional values."],
      size: [kind: :value, description: "Target byte length of the encoded binary."]
    ],
    returns: %{
      type: :raw_binary_or_nil,
      description: "Fixed-width raw binary bytes suitable for `encode_hex/1`, or `nil` when input is `nil`."
    },
    composes_with: [:pad, :encode_hex]
  )

  @doc ~S"""
  Encodes a number as a binary of a fixed byte length, left-padded with zeros.

  ## Examples

      iex> Cartouche.Hex.encode_bytes(257, 4)
      <<0, 0, 1, 1>>

      iex> Cartouche.Hex.encode_bytes(nil, 4)
      nil
  """
  @spec encode_bytes(integer() | nil, pos_integer()) :: binary() | nil
  def encode_bytes(nil, _), do: nil
  def encode_bytes(b, size), do: pad(:binary.encode_unsigned(b), size)

  api(:nibbles, "Split raw binary bytes into high/low 4-bit nibbles.",
    params: [
      v: [kind: :value, description: "Raw binary bytes whose nibbles should be listed."]
    ],
    returns: %{
      type: :nibble_list,
      description: "List of integers in `0..15`, two entries per input byte, in original byte order."
    }
  )

  @doc ~S"""
  Returns the nibbles of a binary as a list.

  ## Examples

      iex> Cartouche.Hex.nibbles(<<0xF5, 0xE6, 0xD0>>)
      [0xF, 0x5, 0xE, 0x6, 0xD, 0x0]
  """
  @spec nibbles(binary()) :: [0..15]
  def nibbles(v), do: Enum.reverse(do_nibbles(v, []))

  @spec do_nibbles(binary(), [0..15]) :: [0..15]
  defp do_nibbles(<<>>, acc), do: acc
  defp do_nibbles(<<high::4, low::4, rest::binary>>, acc), do: do_nibbles(rest, [low, high | acc])

  api(:encode_address, "Encode 20 raw Ethereum address bytes as an EIP-55 checksummed address string.",
    params: [
      b: [
        kind: :value,
        description: "Exactly 20 raw Ethereum address bytes; do not pass an already-encoded address string."
      ]
    ],
    returns: %{
      type: :ethereum_address_hex,
      description: "EIP-55 mixed-case `0x` address string; inverse of `decode_address!/1` for valid address bytes."
    },
    errors: [invalid_hex: "Raised as `Cartouche.Hex.InvalidHex` when input is not exactly 20 bytes."],
    composes_with: [:decode_address!, :checksum_address]
  )

  @doc """
  Encodes a binary as a checksummed Ethereum address.

  ## Examples

    iex> Cartouche.Hex.encode_address(<<0xaa, 0xbb, 0xcc, 0::136>>)
    "0xaABbcC0000000000000000000000000000000000"

    iex> Cartouche.Hex.encode_address(<<55>>)
    ** (Cartouche.Hex.InvalidHex) Expected 20-byte address for in `Cartouche.Hex.encode_address/1`
  """
  @spec encode_address(t()) :: String.t()
  def encode_address(<<_::160>> = b), do: checksum_address(encode_hex(b))

  def encode_address(_), do: raise(InvalidHex, "Expected 20-byte address for in `Cartouche.Hex.encode_address/1`")

  api(:checksum_address, "Apply EIP-55 checksum casing to an Ethereum address.",
    params: [
      address: [
        kind: :value,
        description: "Either a 20-byte raw address binary or a 42-character `0x`-prefixed hex address string."
      ]
    ],
    returns: %{type: :ethereum_address_hex, description: "EIP-55 mixed-case `0x` address string."},
    composes_with: [:decode_hex!, :encode_big_hex]
  )

  @doc ~S"""
  Checksums an Ethereum address per [EIP-55](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-55.md).

  The result is a string-encoded (mixed-case) version of the address.

  ## Examples

      iex> Cartouche.Hex.checksum_address("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed")
      "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"

      iex> Cartouche.Hex.checksum_address("0xFB6916095CA1DF60BB79CE92CE3EA74C37C5D359")
      "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359"

      iex> Cartouche.Hex.checksum_address("0xdbf03b407c01e7cd3cbea99509d93f8dddc8c6fb")
      "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB"

      iex> Cartouche.Hex.checksum_address("0xd1220a0cf47c7b9be7a2e6ba89f429762e7b9adb")
      "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb"
  """
  @spec checksum_address(String.t() | <<_::160>>) :: String.t()
  def checksum_address("0x" <> _ = address) when byte_size(address) == 42, do: checksum_address(decode_hex!(address))

  def checksum_address(address) when is_binary(address) and byte_size(address) == 20 do
    # EIP-55 hashes the *string* form of the address, then cases each nibble
    # of the address based on the matching nibble of the hash.
    "0x" <> address_enc = encode_big_hex(address)
    hash = Cartouche.Hash.keccak(String.downcase(address_enc))

    lower = {?0, ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?a, ?b, ?c, ?d, ?e, ?f}
    upper = {?0, ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?A, ?B, ?C, ?D, ?E, ?F}

    res =
      for {nibble, hash_val} <- Enum.zip(nibbles(address), nibbles(hash)), into: [] do
        casing = if hash_val >= 8, do: upper, else: lower
        elem(casing, nibble)
      end

    "0x" <> to_string(res)
  end

  api(:to_address, "Alias for `encode_address/1` that encodes 20 raw address bytes as EIP-55 `0x` hex.",
    params: [
      b: [
        kind: :value,
        description: "Exactly 20 raw Ethereum address bytes; do not pass an already-encoded address string."
      ]
    ],
    returns: %{
      type: :ethereum_address_hex,
      description: "EIP-55 mixed-case `0x` address string; inverse of `decode_address!/1`."
    },
    composes_with: [:encode_address, :decode_address!]
  )

  @doc """
  Alias for `encode_address`.

  ## Examples

    iex> Cartouche.Hex.to_address(<<0xaa, 0xbb, 0xcc, 0::136>>)
    "0xaABbcC0000000000000000000000000000000000"
  """
  @spec to_address(t()) :: String.t()
  def to_address(b), do: encode_address(b)

  api(:encode_hex_result, "Encode the binary inside a successful result tuple while preserving all other terms.",
    params: [
      b: [kind: :value, description: "Either `{:ok, raw_binary}` to encode, or any other term to return unchanged."]
    ],
    returns: %{
      type: :term,
      description: "`{:ok, lowercase_0x_hex}` for successful binary tuples, otherwise the original input term unchanged."
    },
    composes_with: [:encode_hex]
  )

  @doc """
  If input is a tuple `{:ok, x}` then returns a tuple `{:ok, hex}`
  where `hex = encode(x)`. Otherwise, returns its input unchanged.

  ## Examples

      iex> Cartouche.Hex.encode_hex_result({:ok, <<0xaa, 0xbb>>})
      {:ok, "0xaabb"}

      iex> Cartouche.Hex.encode_hex_result({:error, 55})
      {:error, 55}
  """
  @spec encode_hex_result({:ok, t()} | term()) :: {:ok, String.t()} | term()
  def encode_hex_result({:ok, b}) when is_binary(b), do: {:ok, encode_hex(b)}
  def encode_hex_result(els), do: els

  api(:maybe_encode_hex, "Encode raw binary bytes as lowercase `0x` hex, preserving `nil` inputs.",
    params: [
      b: [kind: :value, description: "Raw binary bytes to encode, or `nil`."]
    ],
    returns: %{
      type: :hex_string_or_nil,
      description:
        "Lowercase `0x`-prefixed hex string that can be decoded by `decode_maybe_hex!/1`, or `nil` when input is `nil`."
    },
    composes_with: [:encode_hex, :decode_maybe_hex!]
  )

  @doc """
  If input is non-`nil`, returns input encoded as a hex string. Otherwise,
  returns `nil`.

  ## Examples

    iex> Cartouche.Hex.maybe_encode_hex(<<0xaa, 0xbb>>)
    "0xaabb"

    iex> Cartouche.Hex.maybe_encode_hex(nil)
    nil
  """
  @spec maybe_encode_hex(t() | nil) :: String.t() | nil
  def maybe_encode_hex(b) when is_nil(b), do: nil
  def maybe_encode_hex(b) when is_binary(b), do: encode_hex(b)

  # Core function to decode hex
  @spec decode_hex_(String.t()) :: {:ok, t()} | :invalid_hex
  defp decode_hex_("0x" <> b) when is_binary(b), do: decode_hex_(b)

  defp decode_hex_(b) when is_binary(b) do
    hex_padded =
      if rem(byte_size(b), 2) == 1 do
        "0" <> b
      else
        b
      end

    case Base.decode16(hex_padded, case: :mixed) do
      {:ok, _} = res ->
        res

      :error ->
        :invalid_hex
    end
  end

  @doc false
  @spec deep_encode_binaries(term()) :: term()
  def deep_encode_binaries(x) when is_binary(x), do: to_hex(x)
  def deep_encode_binaries(l) when is_list(l), do: Enum.map(l, &deep_encode_binaries/1)

  def deep_encode_binaries(t) when is_tuple(t), do: List.to_tuple(Enum.map(Tuple.to_list(t), &deep_encode_binaries/1))

  def deep_encode_binaries(els), do: els
end
