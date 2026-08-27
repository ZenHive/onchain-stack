defmodule Cartouche.Base58 do
  @moduledoc """
  Base58 encoding and decoding using the Bitcoin/Solana alphabet.

  This is plain Base58, NOT Base58Check (no version prefix or checksum).
  Used by Solana for public keys (addresses) and transaction signatures.

  If you `use Cartouche.Base58`, you get the `~B58` sigil for compile-time
  Base58-to-binary decoding.

  ## Examples

      iex> Cartouche.Base58.encode(<<0, 0, 0>>)
      "111"

      iex> Cartouche.Base58.encode(<<0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x20, 0x57, 0x6f, 0x72, 0x6c, 0x64, 0x21>>)
      "2NEpo7TZRRrLZSi2U"

      iex> Cartouche.Base58.decode("2NEpo7TZRRrLZSi2U")
      {:ok, "Hello World!"}

      iex> Cartouche.Base58.decode("abc0def")
      {:error, {:invalid_character, "0"}}
  """

  use Descripex, namespace: "/base58"

  defmacro __using__(_opts) do
    quote do
      import Cartouche.Base58, only: [sigil_B58: 2]

      require Cartouche.Base58
    end
  end

  @doc ~S"""
  Handles the sigil `~B58` for compile-time Base58 decoding.

  Decodes a Base58 string to binary at compile time, raising on
  invalid input. Uses uppercase `B58` because Elixir multi-character
  sigils require uppercase letters.

  ## Examples

      iex> use Cartouche.Base58
      iex> ~B58[11111111111111111111111111111111]
      <<0::256>>

      iex> use Cartouche.Base58
      iex> ~B58[TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA]
      <<6, 221, 246, 225, 215, 101, 161, 147, 217, 203, 225, 70, 206, 235, 121, 172, 28, 180, 133, 237, 95, 91, 55, 145, 58, 140, 245, 133, 126, 255, 0, 169>>
  """
  defmacro sigil_B58(term, _modifiers)

  # Elixir requires sigil names to start with a single uppercase letter (sigil_FOO);
  # credo's snake_case rule is incompatible with the language spec for sigils.
  # credo:disable-for-next-line Credo.Check.Readability.FunctionNames
  defmacro sigil_B58({:<<>>, _meta, [string]}, _modifiers) when is_binary(string) do
    Cartouche.Base58.decode!(string)
  end

  @alphabet ~c"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

  # O(1) index → char lookup
  @alphabet_tuple List.to_tuple(@alphabet)

  # O(1) char → index lookup
  @decode_map for {char, idx} <- Enum.with_index(@alphabet), into: %{}, do: {char, idx}

  api(:encode, "Encode raw binary bytes as a plain Base58 string.",
    params: [
      binary: [kind: :value, description: "Raw binary bytes to encode with the Bitcoin/Solana Base58 alphabet."]
    ],
    returns: %{
      type: :base58_string,
      description:
        "Plain Base58 string; `decode/1` reverses it back to the original binary, preserving leading zero bytes as leading `1` characters."
    },
    composes_with: [:decode]
  )

  @doc """
  Encode a binary to a Base58 string.

  Each leading zero byte in the input produces a `"1"` character in the output.

  ## Examples

      iex> Cartouche.Base58.encode(<<>>)
      ""

      iex> Cartouche.Base58.encode(<<0>>)
      "1"

      iex> Cartouche.Base58.encode(<<0x61>>)
      "2g"
  """
  @spec encode(binary()) :: String.t()
  def encode(<<>>), do: ""

  def encode(binary) when is_binary(binary) do
    leading = count_leading_zeros(binary, 0)
    prefix = String.duplicate("1", leading)

    case :binary.decode_unsigned(binary) do
      0 -> prefix
      n -> prefix <> encode_int(n, [])
    end
  end

  @spec encode_int(non_neg_integer(), iodata()) :: binary()
  defp encode_int(0, acc), do: IO.iodata_to_binary(acc)

  defp encode_int(n, acc) do
    encode_int(div(n, 58), [elem(@alphabet_tuple, rem(n, 58)) | acc])
  end

  @spec count_leading_zeros(binary(), non_neg_integer()) :: non_neg_integer()
  defp count_leading_zeros(<<0, rest::binary>>, n), do: count_leading_zeros(rest, n + 1)
  defp count_leading_zeros(_, n), do: n

  api(:decode, "Decode a plain Base58 string to raw binary bytes.",
    params: [
      string: [kind: :value, description: "Base58 string using the Bitcoin/Solana alphabet; this is not Base58Check."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, binary}` with the raw decoded bytes that `encode/1` can encode again, or `{:error, {:invalid_character, char}}` for non-Base58 input."
    },
    composes_with: [:encode, :decode!]
  )

  @doc """
  Decode a Base58 string to a binary.

  Returns `{:ok, binary}` on success, or `{:error, {:invalid_character, char}}` if the
  string contains characters outside the Base58 alphabet.

  ## Examples

      iex> Cartouche.Base58.decode("")
      {:ok, <<>>}

      iex> Cartouche.Base58.decode("1")
      {:ok, <<0>>}

      iex> Cartouche.Base58.decode("2g")
      {:ok, <<0x61>>}
  """
  @spec decode(String.t()) :: {:ok, binary()} | {:error, {:invalid_character, String.t()}}
  def decode(<<>>), do: {:ok, <<>>}

  def decode(string) when is_binary(string) do
    {leading, rest} = count_leading_ones(string, 0)
    prefix = :binary.copy(<<0>>, leading)

    case decode_chars(rest, 0) do
      {:ok, 0} -> {:ok, prefix}
      {:ok, n} -> {:ok, prefix <> :binary.encode_unsigned(n)}
      error -> error
    end
  end

  api(:decode!, "Decode a plain Base58 string to raw binary bytes, raising on invalid input.",
    params: [
      string: [kind: :value, description: "Base58 string using the Bitcoin/Solana alphabet; this is not Base58Check."]
    ],
    returns: %{
      type: :binary,
      description: "Raw decoded bytes that `encode/1` can encode back to the same Base58 string."
    },
    errors: [argument_error: "Raised when the string contains a character outside the Base58 alphabet."],
    composes_with: [:encode, :decode]
  )

  @doc """
  Decode a Base58 string to a binary, raising on invalid input.

  ## Examples

      iex> Cartouche.Base58.decode!("2g")
      <<0x61>>
  """
  @spec decode!(String.t()) :: binary()
  def decode!(string) do
    case decode(string) do
      {:ok, binary} -> binary
      {:error, reason} -> raise ArgumentError, "invalid Base58: #{inspect(reason)}"
    end
  end

  @spec count_leading_ones(binary(), non_neg_integer()) :: {non_neg_integer(), binary()}
  defp count_leading_ones(<<"1", rest::binary>>, n), do: count_leading_ones(rest, n + 1)
  defp count_leading_ones(rest, n), do: {n, rest}

  @spec decode_chars(binary(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, {:invalid_character, String.t()}}
  defp decode_chars(<<>>, acc), do: {:ok, acc}

  defp decode_chars(<<c, rest::binary>>, acc) do
    case Map.fetch(@decode_map, c) do
      {:ok, val} -> decode_chars(rest, acc * 58 + val)
      :error -> {:error, {:invalid_character, <<c>>}}
    end
  end
end
