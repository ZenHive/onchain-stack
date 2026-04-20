defmodule Onchain.Aave.Math do
  @moduledoc """
  Aave V3 raw integer → `Decimal.t()` conversions.

  Aave smart contracts return raw integers at various scales. This module
  centralizes the conversions so all consumers use the same math.

  ## Functions

  | Function | Exponent | Aave Usage |
  |----------|----------|------------|
  | `to_usd/1` | 10^8 | Oracle prices, base currency values |
  | `to_ltv/1` | 10^4 | LTV ratios, liquidation thresholds (basis points) |
  | `to_health_factor/1` | 10^18 | `getUserAccountData` health factor |
  | `to_ray/1` | 10^27 | Interest rates (variable/stable borrow) |
  | `to_wad/1` | 10^18 | Scaled token amounts (18-decimal tokens) |

  All functions are pure, guard-protected, accept integers, and return `Decimal.t()`.
  Each delegates to `Onchain.Decimal.div_pow10/2` with the appropriate exponent.
  """

  use Descripex, namespace: "/aave/math"

  @usd_exponent 8
  @ltv_exponent 4
  @health_factor_exponent 18
  @ray_exponent 27
  @wad_exponent 18

  # --- to_usd ---

  api(:to_usd, "Convert Aave oracle price or base currency value (10^8 scale) to Decimal.",
    params: [
      value: [kind: :value, description: "Raw integer from Aave oracle or base currency field"]
    ],
    returns: %{
      type: "Decimal.t()",
      description: "USD value",
      example: "123_456_789 → Decimal.new(\"1.23456789\")"
    }
  )

  @spec to_usd(integer()) :: Decimal.t()
  def to_usd(value) when is_integer(value) do
    Onchain.Decimal.div_pow10(value, @usd_exponent)
  end

  # --- to_ltv ---

  api(:to_ltv, "Convert Aave basis-point value (10^4 scale) to Decimal ratio.",
    params: [
      value: [kind: :value, description: "Raw integer LTV ratio or liquidation threshold (basis points)"]
    ],
    returns: %{
      type: "Decimal.t()",
      description: "Ratio between 0 and 1",
      example: "8000 → Decimal.new(\"0.8\")"
    }
  )

  @spec to_ltv(integer()) :: Decimal.t()
  def to_ltv(value) when is_integer(value) do
    Onchain.Decimal.div_pow10(value, @ltv_exponent)
  end

  # --- to_health_factor ---

  api(:to_health_factor, "Convert Aave health factor (10^18 scale) to Decimal.",
    params: [
      value: [kind: :value, description: "Raw integer health factor from getUserAccountData"]
    ],
    returns: %{
      type: "Decimal.t()",
      description: "Health factor (> 1 means not liquidatable)",
      example: "1_500_000_000_000_000_000 → Decimal.new(\"1.5\")"
    }
  )

  @spec to_health_factor(integer()) :: Decimal.t()
  def to_health_factor(value) when is_integer(value) do
    Onchain.Decimal.div_pow10(value, @health_factor_exponent)
  end

  # --- to_ray ---

  api(:to_ray, "Convert Aave ray value (10^27 scale) to Decimal.",
    params: [
      value: [kind: :value, description: "Raw integer interest rate in ray units"]
    ],
    returns: %{
      type: "Decimal.t()",
      description: "Decimal interest rate",
      example: "100_000_000_000_000_000_000_000_000 (10^26) → Decimal.new(\"0.1\")"
    }
  )

  @spec to_ray(integer()) :: Decimal.t()
  def to_ray(value) when is_integer(value) do
    Onchain.Decimal.div_pow10(value, @ray_exponent)
  end

  # --- to_wad ---

  api(:to_wad, "Convert wad value (10^18 scale) to Decimal.",
    params: [
      value: [kind: :value, description: "Raw integer scaled token amount in wad units"]
    ],
    returns: %{
      type: "Decimal.t()",
      description: "Decimal token amount",
      example: "1_000_000_000_000_000_000 (10^18) → Decimal.new(\"1.0\")"
    }
  )

  @spec to_wad(integer()) :: Decimal.t()
  def to_wad(value) when is_integer(value) do
    Onchain.Decimal.div_pow10(value, @wad_exponent)
  end
end
