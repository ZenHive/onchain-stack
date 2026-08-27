defmodule Onchain.Hex do
  @moduledoc """
  Hex encoding/decoding for Ethereum data.

  Curated 7-function API delegating to `Cartouche.Hex` with normalized error tuples
  and descripex self-description. All hex strings use the `0x` prefix convention.

  ## Error Format

  All failable functions return `{:error, {:invalid_hex, input}}` where `input`
  is the original value that failed to decode. Bang variants raise
  `Cartouche.Hex.InvalidHex`.

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `decode/1` | Hex string → binary |
  | `decode!/1` | Hex string → binary (raises) |
  | `encode/1` | Binary → hex string |
  | `to_integer/1` | Hex string → integer |
  | `to_integer!/1` | Hex string → integer (raises) |
  | `from_integer/1` | Integer → compact hex string |
  | `valid?/1` | Check if string is valid hex |
  """

  use Descripex, namespace: "/hex"

  # Matches 0x-prefixed (including bare 0x = empty bytes) or bare hex with ≥1 digit
  @hex_pattern ~r/^(0x[0-9a-fA-F]*|[0-9a-fA-F]+)$/

  # --- decode ---

  api(:decode, "Decode a hex string to raw binary.",
    params: [
      hex_string: [kind: :value, description: "Hex string with or without 0x prefix"]
    ],
    returns: %{type: "{:ok, binary} | {:error, {:invalid_hex, input}}", description: "Decoded binary bytes"}
  )

  @spec decode(String.t()) :: {:ok, binary()} | {:error, {:invalid_hex, String.t()}}
  def decode(hex_string) do
    case Cartouche.Hex.decode_hex(hex_string) do
      {:ok, binary} -> {:ok, binary}
      _error -> {:error, {:invalid_hex, hex_string}}
    end
  end

  # --- decode! ---

  api(:decode!, "Decode a hex string to raw binary. Raises on invalid input.",
    params: [
      hex_string: [kind: :value, description: "Hex string with or without 0x prefix"]
    ],
    returns: %{type: :binary, description: "Decoded binary bytes"}
  )

  @spec decode!(String.t()) :: binary()
  defdelegate decode!(hex_string), to: Cartouche.Hex, as: :decode_hex!

  # --- encode ---

  api(:encode, "Encode raw binary to a 0x-prefixed lowercase hex string.",
    params: [
      binary: [kind: :value, description: "Raw binary bytes to encode"]
    ],
    returns: %{type: :string, description: "0x-prefixed lowercase hex string", example: "0xaabb"}
  )

  @spec encode(binary()) :: String.t()
  defdelegate encode(binary), to: Cartouche.Hex, as: :encode_hex

  # --- to_integer ---

  api(:to_integer, "Decode a hex string to a non-negative integer.",
    params: [
      hex_string: [kind: :value, description: "Hex string with or without 0x prefix"]
    ],
    returns: %{
      type: "{:ok, non_neg_integer} | {:error, {:invalid_hex, input}}",
      description: "Big-endian decoded integer"
    }
  )

  @spec to_integer(String.t()) :: {:ok, non_neg_integer()} | {:error, {:invalid_hex, String.t()}}
  def to_integer(hex_string) when hex_string in ["", "0x"], do: {:error, {:invalid_hex, hex_string}}

  def to_integer(hex_string) do
    case Cartouche.Hex.decode_hex_number(hex_string) do
      {:ok, n} -> {:ok, n}
      _error -> {:error, {:invalid_hex, hex_string}}
    end
  end

  # --- to_integer! ---

  api(:to_integer!, "Decode a hex string to a non-negative integer. Raises on invalid input.",
    params: [
      hex_string: [kind: :value, description: "Hex string with or without 0x prefix"]
    ],
    returns: %{type: :non_neg_integer, description: "Big-endian decoded integer"}
  )

  @spec to_integer!(String.t()) :: non_neg_integer()
  defdelegate to_integer!(hex_string), to: Cartouche.Hex, as: :decode_hex_number!

  # --- from_integer ---

  api(:from_integer, "Encode a non-negative integer as a compact 0x-prefixed hex string.",
    params: [
      n: [kind: :value, description: "Non-negative integer to encode"]
    ],
    returns: %{type: :string, description: "Compact lowercase hex string (no leading zeros)", example: "0xff"}
  )

  @spec from_integer(non_neg_integer()) :: String.t()
  def from_integer(n) when is_integer(n) and n >= 0 do
    n |> Cartouche.Hex.encode_short_hex() |> String.downcase()
  end

  # --- valid? ---

  api(:valid?, "Check whether a string is valid hex (with or without 0x prefix).",
    params: [
      input: [kind: :value, description: "Value to check"]
    ],
    returns: %{type: :boolean, description: "true if valid hex string with at least one hex digit"}
  )

  @spec valid?(term()) :: boolean()
  def valid?(input) when is_binary(input), do: Regex.match?(@hex_pattern, input)
  def valid?(_input), do: false
end
