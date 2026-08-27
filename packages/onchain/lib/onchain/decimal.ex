defmodule Onchain.Decimal do
  @moduledoc """
  Decimal precision helpers for Ethereum token amounts.

  Ethereum stores token amounts as raw integers with a separate decimal count
  (18 for ETH, 6 for USDC, 8 for WBTC). This module converts between raw
  integers and `Decimal.t()` values.

  All functions are pure math with guards — they cannot fail with valid input
  types, so there are no error tuples or bang variants.

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `to_decimal/2` | Raw integer + decimal places → `Decimal.t()` |
  | `div_pow10/2` | Value / 10^n → `Decimal.t()` (general math op) |
  | `to_basis_points/1` | Decimal ratio → integer basis points |
  """

  use Descripex, namespace: "/decimal"

  # --- to_decimal ---

  api(:to_decimal, "Convert a raw token integer to a Decimal with the given decimal places.",
    params: [
      value: [kind: :value, description: "Raw integer token amount (e.g. wei for ETH)"],
      decimals: [
        kind: :value,
        description: "Number of decimal places for the token (18 for ETH, 6 for USDC, 8 for WBTC)"
      ]
    ],
    returns: %{
      type: "Decimal.t()",
      description: "Human-readable token amount",
      example: "Decimal.new(\"1.5\") for 1.5 ETH"
    }
  )

  @spec to_decimal(integer(), non_neg_integer()) :: Decimal.t()
  def to_decimal(value, decimals) when is_integer(value) and is_integer(decimals) and decimals >= 0 do
    div_pow10(value, decimals)
  end

  # --- div_pow10 ---

  api(:div_pow10, "Divide a value by 10^n. General-purpose power-of-10 division.",
    params: [
      value: [kind: :value, description: "Integer or Decimal value to divide"],
      n: [kind: :value, description: "Power of 10 to divide by"]
    ],
    returns: %{
      type: "Decimal.t()",
      description: "Result of value / 10^n"
    }
  )

  @spec div_pow10(integer() | Decimal.t(), non_neg_integer()) :: Decimal.t()
  def div_pow10(value, n) when is_integer(value) and is_integer(n) and n >= 0 do
    value
    |> Decimal.new()
    |> Decimal.div(Decimal.new(Integer.pow(10, n)))
  end

  def div_pow10(%Decimal{} = value, n) when is_integer(n) and n >= 0 do
    Decimal.div(value, Decimal.new(Integer.pow(10, n)))
  end

  # --- to_basis_points ---

  api(:to_basis_points, "Convert a decimal ratio to integer basis points (truncated toward zero).",
    params: [
      ratio: [
        kind: :value,
        description: "Decimal ratio (e.g. Decimal.new(\"0.005\") for 50 basis points)"
      ]
    ],
    returns: %{
      type: :integer,
      description: "Basis points as integer (1 bp = 0.0001)",
      example: "50 for a 0.5% rate"
    }
  )

  @bps_multiplier Decimal.new(10_000)

  @spec to_basis_points(Decimal.t()) :: integer()
  def to_basis_points(%Decimal{} = ratio) do
    ratio
    |> Decimal.mult(@bps_multiplier)
    |> Decimal.round(0, :down)
    |> Decimal.to_integer()
  end
end
