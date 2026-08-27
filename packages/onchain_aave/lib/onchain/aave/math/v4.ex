defmodule Onchain.Aave.Math.V4 do
  @moduledoc """
  Aave V4 integer-native math ports.

  V4 split the V3 half-up WadRay helpers into explicit down/up variants. These
  functions preserve the deployed Solidity formulas for valid non-overflowing
  inputs while relying on BEAM arbitrary-precision integers instead of uint256
  overflow reverts.

  Source: `aave/aave-v4` `src/libraries/math/{WadRayMath,MathUtils}.sol` and
  `src/spoke/libraries/LiquidationLogic.sol`.
  """

  alias Onchain.Aave.Math

  @wad 1_000_000_000_000_000_000
  @ray 1_000_000_000_000_000_000_000_000_000
  @percentage_factor 10_000
  @health_factor_liquidation_threshold 1_000_000_000_000_000_000

  defguardp is_liquidation_input(
              health_factor_for_max_bonus,
              liquidation_bonus_factor,
              health_factor,
              max_liquidation_bonus
            )
            when is_integer(health_factor_for_max_bonus) and health_factor_for_max_bonus >= 0 and
                   health_factor_for_max_bonus < @health_factor_liquidation_threshold and
                   is_integer(liquidation_bonus_factor) and liquidation_bonus_factor >= 0 and
                   is_integer(health_factor) and health_factor >= 0 and
                   health_factor < @health_factor_liquidation_threshold and is_integer(max_liquidation_bonus) and
                   max_liquidation_bonus >= @percentage_factor

  @doc "Multiply two wad-scaled integers, rounding down."
  @spec wad_mul_down(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def wad_mul_down(a, b) when is_integer(a) and is_integer(b) and a >= 0 and b >= 0 do
    div(a * b, @wad)
  end

  @doc "Multiply two wad-scaled integers, rounding up."
  @spec wad_mul_up(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def wad_mul_up(a, b) when is_integer(a) and is_integer(b) and a >= 0 and b >= 0 do
    div_up(a * b, @wad)
  end

  @doc "Divide two wad-scaled integers, rounding down."
  @spec wad_div_down(non_neg_integer(), pos_integer()) :: non_neg_integer()
  def wad_div_down(a, b) when is_integer(a) and is_integer(b) and a >= 0 and b > 0 do
    div(a * @wad, b)
  end

  @doc "Divide two wad-scaled integers, rounding up."
  @spec wad_div_up(non_neg_integer(), pos_integer()) :: non_neg_integer()
  def wad_div_up(a, b) when is_integer(a) and is_integer(b) and a >= 0 and b > 0 do
    div_up(a * @wad, b)
  end

  @doc "Multiply two ray-scaled integers, rounding down."
  @spec ray_mul_down(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def ray_mul_down(a, b) when is_integer(a) and is_integer(b) and a >= 0 and b >= 0 do
    div(a * b, @ray)
  end

  @doc "Multiply two ray-scaled integers, rounding up."
  @spec ray_mul_up(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def ray_mul_up(a, b) when is_integer(a) and is_integer(b) and a >= 0 and b >= 0 do
    div_up(a * b, @ray)
  end

  @doc "Divide two ray-scaled integers, rounding down."
  @spec ray_div_down(non_neg_integer(), pos_integer()) :: non_neg_integer()
  def ray_div_down(a, b) when is_integer(a) and is_integer(b) and a >= 0 and b > 0 do
    div(a * @ray, b)
  end

  @doc "Divide two ray-scaled integers, rounding up."
  @spec ray_div_up(non_neg_integer(), pos_integer()) :: non_neg_integer()
  def ray_div_up(a, b) when is_integer(a) and is_integer(b) and a >= 0 and b > 0 do
    div_up(a * @ray, b)
  end

  @doc "Cast an integer to wad scale by multiplying by 10^18."
  @spec to_wad(non_neg_integer()) :: non_neg_integer()
  def to_wad(a) when is_integer(a) and a >= 0 do
    a * @wad
  end

  @doc "Cast an integer to ray scale by multiplying by 10^27."
  @spec to_ray(non_neg_integer()) :: non_neg_integer()
  def to_ray(a) when is_integer(a) and a >= 0 do
    a * @ray
  end

  @doc "Remove wad precision, rounding down."
  @spec from_wad_down(non_neg_integer()) :: non_neg_integer()
  def from_wad_down(a) when is_integer(a) and a >= 0 do
    div(a, @wad)
  end

  @doc "Remove ray precision, rounding up."
  @spec from_ray_up(non_neg_integer()) :: non_neg_integer()
  def from_ray_up(a) when is_integer(a) and a >= 0 do
    div_up(a, @ray)
  end

  @doc "Convert basis points to wad scale."
  @spec bps_to_wad(non_neg_integer()) :: non_neg_integer()
  def bps_to_wad(a) when is_integer(a) and a >= 0 do
    a * div(@wad, @percentage_factor)
  end

  @doc "Convert basis points to ray scale."
  @spec bps_to_ray(non_neg_integer()) :: non_neg_integer()
  def bps_to_ray(a) when is_integer(a) and a >= 0 do
    a * div(@ray, @percentage_factor)
  end

  @doc "Round a ray value up to the nearest whole ray."
  @spec round_ray_up(non_neg_integer()) :: non_neg_integer()
  def round_ray_up(a) when is_integer(a) and a >= 0 do
    div_up(a, @ray) * @ray
  end

  @doc """
  Calculate V4 linear interest between two timestamps at a ray-scaled rate.

  The linear-interest formula is unchanged between Aave V3 and V4
  (`MathUtils.calculateLinearInterest`) — delegates to
  `Onchain.Aave.Math.calculate_linear_interest/3` rather than duplicating it.
  """
  @spec calculate_linear_interest(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          non_neg_integer()
  def calculate_linear_interest(rate, last_update_timestamp, current_timestamp)
      when is_integer(rate) and rate >= 0 and is_integer(last_update_timestamp) and last_update_timestamp >= 0 and
             is_integer(current_timestamp) and current_timestamp >= last_update_timestamp do
    Math.calculate_linear_interest(rate, last_update_timestamp, current_timestamp)
  end

  @doc "Return the smaller of two non-negative integers."
  @spec min(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def min(a, b) when is_integer(a) and is_integer(b) and a >= 0 and b >= 0 do
    Kernel.min(a, b)
  end

  @doc "Subtract with a floor at zero."
  @spec zero_floor_sub(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def zero_floor_sub(a, b) when is_integer(a) and is_integer(b) and a >= 0 and b >= 0 and a > b do
    a - b
  end

  def zero_floor_sub(a, b) when is_integer(a) and is_integer(b) and a >= 0 and b >= 0 do
    0
  end

  @doc "Add a signed integer to a non-negative integer, rejecting underflow."
  @spec add(non_neg_integer(), integer()) :: non_neg_integer()
  def add(a, b) when is_integer(a) and is_integer(b) and a >= 0 and b >= 0 do
    a + b
  end

  def add(a, b) when is_integer(a) and is_integer(b) and a >= 0 and b < 0 and a >= -b do
    a + b
  end

  @doc "Divide two integers, rounding up."
  @spec div_up(non_neg_integer(), pos_integer()) :: non_neg_integer()
  def div_up(a, b) when is_integer(a) and is_integer(b) and a >= 0 and b > 0 do
    div(a, b) + if(rem(a, b) > 0, do: 1, else: 0)
  end

  @doc "Multiply two integers and divide by a third, rounding down."
  @spec mul_div_down(non_neg_integer(), non_neg_integer(), pos_integer()) :: non_neg_integer()
  def mul_div_down(a, b, c) when is_integer(a) and is_integer(b) and is_integer(c) and a >= 0 and b >= 0 and c > 0 do
    div(a * b, c)
  end

  @doc "Multiply two integers and divide by a third, rounding up."
  @spec mul_div_up(non_neg_integer(), non_neg_integer(), pos_integer()) :: non_neg_integer()
  def mul_div_up(a, b, c) when is_integer(a) and is_integer(b) and is_integer(c) and a >= 0 and b >= 0 and c > 0 do
    div_up(a * b, c)
  end

  @doc "Calculate V4's liquidation bonus from health-factor and bonus parameters."
  @spec calculate_liquidation_bonus(
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: non_neg_integer()
  def calculate_liquidation_bonus(
        health_factor_for_max_bonus,
        liquidation_bonus_factor,
        health_factor,
        max_liquidation_bonus
      )
      when is_liquidation_input(
             health_factor_for_max_bonus,
             liquidation_bonus_factor,
             health_factor,
             max_liquidation_bonus
           ) and health_factor <= health_factor_for_max_bonus do
    max_liquidation_bonus
  end

  def calculate_liquidation_bonus(
        health_factor_for_max_bonus,
        liquidation_bonus_factor,
        health_factor,
        max_liquidation_bonus
      )
      when is_liquidation_input(
             health_factor_for_max_bonus,
             liquidation_bonus_factor,
             health_factor,
             max_liquidation_bonus
           ) do
    min_liquidation_bonus =
      percent_mul_down(max_liquidation_bonus - @percentage_factor, liquidation_bonus_factor) +
        @percentage_factor

    min_liquidation_bonus +
      mul_div_down(
        max_liquidation_bonus - min_liquidation_bonus,
        @health_factor_liquidation_threshold - health_factor,
        @health_factor_liquidation_threshold - health_factor_for_max_bonus
      )
  end

  @spec percent_mul_down(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  defp percent_mul_down(value, percentage) when is_integer(value) and is_integer(percentage) do
    div(value * percentage, @percentage_factor)
  end
end
