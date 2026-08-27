defmodule Onchain.Address do
  @moduledoc """
  Ethereum address validation, checksumming, and comparison.

  Curated 7-function API wrapping `Cartouche.Hex` with flexible input handling
  (hex strings or 20-byte binaries) and normalized error tuples.

  ## Error Format

  All failable functions return `{:error, {:invalid_address, input}}` where `input`
  is the original value that failed validation. Bang variants raise `Cartouche.Hex.InvalidHex`.

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `validate/1` | Any input → 20-byte binary |
  | `valid?/1` | Check if input is a valid address |
  | `checksum/1` | EIP-55 checksummed hex string |
  | `checksum!/1` | EIP-55 checksummed hex string (raises) |
  | `normalize/1` | Lowercase 0x-prefixed hex string |
  | `equal?/2` | Compare two addresses (any format) |
  | `zero?/1` | Check if address is the zero address |
  """

  use Descripex, namespace: "/address"

  @address_size 20
  @zero_address <<0::160>>

  # --- validate ---

  api(:validate, "Validate and normalize an address to a 20-byte binary.",
    params: [
      input: [kind: :value, description: "Hex string (with or without 0x) or 20-byte binary"]
    ],
    returns: %{
      type: "{:ok, <<20 bytes>>} | {:error, {:invalid_address, input}}",
      description: "Validated 20-byte binary address"
    }
  )

  @spec validate(term()) :: {:ok, <<_::160>>} | {:error, {:invalid_address, term()}}
  def validate(input) do
    case to_binary(input) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, {:invalid_address, input}}
    end
  end

  # --- valid? ---

  api(:valid?, "Check whether the input is a valid Ethereum address.",
    params: [
      input: [kind: :value, description: "Value to check"]
    ],
    returns: %{type: :boolean, description: "true if valid 20-byte address"}
  )

  @spec valid?(term()) :: boolean()
  def valid?(input) do
    match?({:ok, _}, validate(input))
  end

  # --- checksum ---

  api(:checksum, "Return the EIP-55 checksummed hex string for an address.",
    params: [
      input: [kind: :value, description: "Hex string (with or without 0x) or 20-byte binary"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, {:invalid_address, input}}",
      description: "EIP-55 checksummed address",
      example: "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
    }
  )

  @spec checksum(term()) :: {:ok, String.t()} | {:error, {:invalid_address, term()}}
  def checksum(input) do
    case to_binary(input) do
      {:ok, binary} -> {:ok, Cartouche.Hex.checksum_address(binary)}
      :error -> {:error, {:invalid_address, input}}
    end
  end

  # --- checksum! ---

  api(:checksum!, "Return the EIP-55 checksummed hex string. Raises on invalid input.",
    params: [
      input: [kind: :value, description: "Hex string (with or without 0x) or 20-byte binary"]
    ],
    returns: %{
      type: :string,
      description: "EIP-55 checksummed address",
      example: "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
    }
  )

  @spec checksum!(term()) :: String.t()
  def checksum!(input) do
    case to_binary(input) do
      {:ok, binary} -> Cartouche.Hex.checksum_address(binary)
      :error -> raise Cartouche.Hex.InvalidHex, "invalid address: #{inspect(input)}"
    end
  end

  # --- normalize ---

  api(:normalize, "Return a lowercase 0x-prefixed hex string for an address.",
    params: [
      input: [kind: :value, description: "Hex string (with or without 0x) or 20-byte binary"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, {:invalid_address, input}}",
      description: "Lowercase hex address",
      example: "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"
    }
  )

  @spec normalize(term()) :: {:ok, String.t()} | {:error, {:invalid_address, term()}}
  def normalize(input) do
    case to_binary(input) do
      {:ok, binary} -> {:ok, Onchain.Hex.encode(binary)}
      :error -> {:error, {:invalid_address, input}}
    end
  end

  # --- equal? ---

  api(:equal?, "Compare two addresses for equality, regardless of format.",
    params: [
      a: [kind: :value, description: "First address (hex string or 20-byte binary)"],
      b: [kind: :value, description: "Second address (hex string or 20-byte binary)"]
    ],
    returns: %{type: :boolean, description: "true if both resolve to the same 20-byte address"}
  )

  @spec equal?(term(), term()) :: boolean()
  def equal?(a, b) do
    with {:ok, bin_a} <- to_binary(a),
         {:ok, bin_b} <- to_binary(b) do
      bin_a == bin_b
    else
      _ -> false
    end
  end

  # --- zero? ---

  api(:zero?, "Check if an address is the zero address (0x0000...0000).",
    params: [
      input: [kind: :value, description: "Hex string or 20-byte binary"]
    ],
    returns: %{type: :boolean, description: "true if the zero address"}
  )

  @spec zero?(term()) :: boolean()
  def zero?(input) do
    match?({:ok, @zero_address}, to_binary(input))
  end

  # --- Private helpers ---

  # Normalizes any valid address input to a 20-byte binary.
  # Accepts: 20-byte binary, 0x-prefixed hex, or bare hex string.
  defp to_binary(bin) when is_binary(bin) and byte_size(bin) == @address_size do
    {:ok, bin}
  end

  defp to_binary(hex) when is_binary(hex) do
    case Onchain.Hex.decode(hex) do
      {:ok, bin} when byte_size(bin) == @address_size -> {:ok, bin}
      _ -> :error
    end
  end

  defp to_binary(_other), do: :error
end
