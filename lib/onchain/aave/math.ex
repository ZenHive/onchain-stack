defmodule Onchain.Aave.Math do
  @moduledoc """
  Aave V3 math — `Decimal.t()` display conversions plus integer-native WadRayMath
  and MathUtils ports.

  Two layers:

  ## Layer 1 — Raw integer → `Decimal.t()` (human display)

  Aave smart contracts return raw integers at various scales. These functions
  centralize the conversions so all consumers use the same math.

  | Function | Exponent | Aave Usage |
  |----------|----------|------------|
  | `to_usd/1` | 10^8 | Oracle prices, base currency values |
  | `to_ltv/1` | 10^4 | LTV ratios, liquidation thresholds (basis points) |
  | `to_health_factor/1` | 10^18 | `getUserAccountData` health factor |
  | `to_ray/1` | 10^27 | Interest rates (variable/stable borrow) |
  | `to_wad/1` | 10^18 | Scaled token amounts (18-decimal tokens) |

  All `to_*` functions are pure, guard-protected, accept integers, and return
  `Decimal.t()`. Each delegates to `Onchain.Decimal.div_pow10/2`.

  ## Layer 2 — Fixed-point arithmetic (WadRayMath / MathUtils)

  Integer-in / integer-out ports of Aave's Solidity libraries, preserving the
  exact round-half-up semantics. Inputs and outputs are `non_neg_integer()` values
  implicitly at ray (10^27) or wad (10^18) scale — the same representation the
  on-chain contracts use. This makes revm cross-validation straightforward:
  pass the same uint256 inputs, compare outputs bit-exact.

  | Function | Solidity equivalent |
  |----------|---------------------|
  | `ray_mul/2` | `WadRayMath.rayMul` |
  | `ray_div/2` | `WadRayMath.rayDiv` |
  | `wad_mul/2` | `WadRayMath.wadMul` |
  | `wad_div/2` | `WadRayMath.wadDiv` |
  | `ray_to_wad/1` | `WadRayMath.rayToWad` |
  | `wad_to_ray/1` | `WadRayMath.wadToRay` |
  | `calculate_linear_interest/3` | `MathUtils.calculateLinearInterest` |
  | `calculate_compounded_interest/3` | `MathUtils.calculateCompoundedInterest` |

  ### Rounding semantics

  `ray_mul` / `wad_mul` / `ray_div` / `wad_div` / `ray_to_wad` round half-up
  via Solidity's "add half the divisor, then floor-divide" idiom — e.g.
  `ray_mul(a, b) = div(a * b + HALF_RAY, RAY)`. BEAM's `div/2` truncates toward
  zero, which equals floor for non-negative operands (enforced by guards).
  `wad_to_ray/1` multiplies exactly (no rounding needed).

  BEAM integers are arbitrary-precision, so there is no uint256 overflow revert
  to mirror. In realistic Aave inputs the products sit ~20 orders of magnitude
  below 2^256 (upstream caps on reserve supply and borrow rate), so divergence
  from Solidity's revert path is unreachable for valid callers.

  ### calculate_compounded_interest

  Follows Aave's current polynomial approximation of `e^(rate * exp / seconds_per_year)`:
  `x + rayMul(x, x/2 + rayMul(x, x/6))` where `x = rate * exp / seconds_per_year`.
  The approximation slightly undercharges borrowers and underpays LPs vs. the
  ideal compound-interest formula; the trade-off is bounded error for massive
  gas savings, and is what the deployed protocol uses.

  ### Signature deviation from Solidity

  Solidity's `calculateLinearInterest(rate, lastUpdateTimestamp)` and
  `calculateCompoundedInterest(rate, lastUpdateTimestamp)` take `block.timestamp`
  implicitly. Off-chain we don't have `block.timestamp`, so the ports require
  `current_timestamp` as a third argument. Task 41's revm cross-validation
  pins `block.timestamp` in the EVM env to match.

  ### Source

  Ported from [aave-dao/aave-v3-origin](https://github.com/aave-dao/aave-v3-origin)
  at commit `1e3d70c4151a94166ebc59e2eaa4aff6e6ba6978` (`src/contracts/protocol/libraries/math/{WadRayMath,MathUtils}.sol`).
  """

  use Descripex, namespace: "/aave/math"

  # --- Decimal display conversions ---
  @usd_exponent 8
  @ltv_exponent 4
  @health_factor_exponent 18
  @ray_exponent 27
  @wad_exponent 18

  # --- WadRayMath constants (uint256 fixed-point scales) ---
  @ray 1_000_000_000_000_000_000_000_000_000
  @half_ray 500_000_000_000_000_000_000_000_000
  @wad 1_000_000_000_000_000_000
  @half_wad 500_000_000_000_000_000
  @wad_ray_ratio 1_000_000_000
  @half_wad_ray_ratio 500_000_000

  # --- MathUtils constants ---
  @seconds_per_year 31_536_000

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

  # --- ray_mul ---

  api(:ray_mul, "Multiply two ray-scaled (10^27) integers, rounding half-up.",
    params: [
      a: [kind: :value, description: "Ray-scaled uint256 integer"],
      b: [kind: :value, description: "Ray-scaled uint256 integer"]
    ],
    returns: %{
      type: "non_neg_integer()",
      description: "a * b in ray, rounded half-up via add-half-then-floor-divide",
      example:
        "ray_mul(1_000_000_000_000_000_000_000_000_000, 2_000_000_000_000_000_000_000_000_000) == 2_000_000_000_000_000_000_000_000_000"
    }
  )

  @spec ray_mul(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def ray_mul(a, b) when is_integer(a) and is_integer(b) and a >= 0 and b >= 0 do
    div(a * b + @half_ray, @ray)
  end

  # --- ray_div ---

  api(:ray_div, "Divide two ray-scaled (10^27) integers, rounding half-up.",
    params: [
      a: [kind: :value, description: "Ray-scaled uint256 dividend"],
      b: [kind: :value, description: "Ray-scaled uint256 divisor (non-zero)"]
    ],
    returns: %{
      type: "non_neg_integer()",
      description: "a / b in ray, rounded half-up via add-half-divisor-then-floor-divide",
      example: "ray_div(ray, 2 * ray) == div(ray, 2)"
    }
  )

  @spec ray_div(non_neg_integer(), pos_integer()) :: non_neg_integer()
  def ray_div(a, b) when is_integer(a) and is_integer(b) and a >= 0 and b > 0 do
    div(a * @ray + div(b, 2), b)
  end

  # --- wad_mul ---

  api(:wad_mul, "Multiply two wad-scaled (10^18) integers, rounding half-up.",
    params: [
      a: [kind: :value, description: "Wad-scaled uint256 integer"],
      b: [kind: :value, description: "Wad-scaled uint256 integer"]
    ],
    returns: %{
      type: "non_neg_integer()",
      description: "a * b in wad, rounded half-up via add-half-then-floor-divide"
    }
  )

  @spec wad_mul(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def wad_mul(a, b) when is_integer(a) and is_integer(b) and a >= 0 and b >= 0 do
    div(a * b + @half_wad, @wad)
  end

  # --- wad_div ---

  api(:wad_div, "Divide two wad-scaled (10^18) integers, rounding half-up.",
    params: [
      a: [kind: :value, description: "Wad-scaled uint256 dividend"],
      b: [kind: :value, description: "Wad-scaled uint256 divisor (non-zero)"]
    ],
    returns: %{
      type: "non_neg_integer()",
      description: "a / b in wad, rounded half-up via add-half-divisor-then-floor-divide"
    }
  )

  @spec wad_div(non_neg_integer(), pos_integer()) :: non_neg_integer()
  def wad_div(a, b) when is_integer(a) and is_integer(b) and a >= 0 and b > 0 do
    div(a * @wad + div(b, 2), b)
  end

  # --- ray_to_wad ---

  api(:ray_to_wad, "Cast a ray-scaled (10^27) integer down to wad (10^18), rounding half-up.",
    params: [
      a: [kind: :value, description: "Ray-scaled uint256 integer"]
    ],
    returns: %{
      type: "non_neg_integer()",
      description: "a rescaled to wad, rounded half-up at the wad_ray_ratio (10^9) midpoint"
    }
  )

  @spec ray_to_wad(non_neg_integer()) :: non_neg_integer()
  def ray_to_wad(a) when is_integer(a) and a >= 0 do
    quotient = div(a, @wad_ray_ratio)
    remainder = rem(a, @wad_ray_ratio)

    if remainder < @half_wad_ray_ratio do
      quotient
    else
      quotient + 1
    end
  end

  # --- wad_to_ray ---

  api(:wad_to_ray, "Cast a wad-scaled (10^18) integer up to ray (10^27). Exact, no rounding.",
    params: [
      a: [kind: :value, description: "Wad-scaled uint256 integer"]
    ],
    returns: %{
      type: "non_neg_integer()",
      description: "a rescaled to ray (a * 10^9)"
    }
  )

  @spec wad_to_ray(non_neg_integer()) :: non_neg_integer()
  def wad_to_ray(a) when is_integer(a) and a >= 0 do
    a * @wad_ray_ratio
  end

  # --- calculate_linear_interest ---

  api(
    :calculate_linear_interest,
    "Compute the linear-interest factor (in ray) accumulated between two timestamps at a given ray-scaled rate.",
    params: [
      rate: [kind: :value, description: "Annual interest rate in ray (10^27 scale)"],
      last_update_timestamp: [kind: :value, description: "Unix-second timestamp of the last accrual"],
      current_timestamp: [kind: :value, description: "Unix-second timestamp to accrue to (>= last_update_timestamp)"]
    ],
    returns: %{
      type: "non_neg_integer()",
      description: "Ray-scaled linear interest factor: RAY + rate * (current - last) / SECONDS_PER_YEAR",
      example: "calculate_linear_interest(rate, t, t) == ray (zero elapsed => factor = 1)"
    }
  )

  @spec calculate_linear_interest(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          non_neg_integer()
  def calculate_linear_interest(rate, last_update_timestamp, current_timestamp)
      when is_integer(rate) and rate >= 0 and is_integer(last_update_timestamp) and last_update_timestamp >= 0 and
             is_integer(current_timestamp) and current_timestamp >= last_update_timestamp do
    @ray + div(rate * (current_timestamp - last_update_timestamp), @seconds_per_year)
  end

  # --- calculate_compounded_interest ---

  api(
    :calculate_compounded_interest,
    "Compute the compounded-interest factor (in ray) accumulated between two timestamps at a given ray-scaled rate via Aave's polynomial approximation.",
    params: [
      rate: [kind: :value, description: "Annual interest rate in ray (10^27 scale)"],
      last_update_timestamp: [kind: :value, description: "Unix-second timestamp of the last accrual"],
      current_timestamp: [kind: :value, description: "Unix-second timestamp to accrue to (>= last_update_timestamp)"]
    ],
    returns: %{
      type: "non_neg_integer()",
      description:
        "Ray-scaled compounded interest factor. Slightly undercharges borrowers / underpays LPs vs. the ideal e^x formula — matches deployed protocol exactly."
    }
  )

  @spec calculate_compounded_interest(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          non_neg_integer()
  def calculate_compounded_interest(rate, last_update_timestamp, current_timestamp)
      when is_integer(rate) and rate >= 0 and is_integer(last_update_timestamp) and last_update_timestamp >= 0 and
             is_integer(current_timestamp) and current_timestamp >= last_update_timestamp do
    exp = current_timestamp - last_update_timestamp

    if exp == 0 do
      @ray
    else
      x = div(rate * exp, @seconds_per_year)
      @ray + x + ray_mul(x, div(x, 2) + ray_mul(x, div(x, 6)))
    end
  end
end
