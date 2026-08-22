defmodule Onchain.Aave.MathDomains do
  @moduledoc false

  # Property domains for every public V3/V4 math operation. Classes: zero, unit,
  # boundary, overflow-adjacent, rounding-sensitive. Bytecode ops are later
  # filled from pinned Solidity via revm; display ops use documented scales.

  alias Onchain.Aave.MathOracle

  @ray 1_000_000_000_000_000_000_000_000_000
  @half_ray 500_000_000_000_000_000_000_000_000
  @wad 1_000_000_000_000_000_000
  @half_wad 500_000_000_000_000_000
  @wad_ray_ratio 1_000_000_000
  @seconds_per_year 31_536_000
  @percentage_factor 10_000
  @hf_liq 1_000_000_000_000_000_000
  @max_ray 10_000 * @ray
  @max_wad 10_000 * @wad
  @max_rate 10 * @ray
  @max_elapsed 10 * @seconds_per_year

  @type class :: :zero | :unit | :boundary | :overflow_adjacent | :rounding
  @type vector :: MathOracle.vector()

  @spec ray() :: pos_integer()
  def ray, do: @ray

  @spec wad() :: pos_integer()
  def wad, do: @wad

  @spec half_ray() :: pos_integer()
  def half_ray, do: @half_ray

  @spec half_wad() :: pos_integer()
  def half_wad, do: @half_wad

  @spec wad_ray_ratio() :: pos_integer()
  def wad_ray_ratio, do: @wad_ray_ratio

  @spec seconds_per_year() :: pos_integer()
  def seconds_per_year, do: @seconds_per_year

  @spec percentage_factor() :: pos_integer()
  def percentage_factor, do: @percentage_factor

  @spec hf_liq() :: pos_integer()
  def hf_liq, do: @hf_liq

  @spec max_ray() :: pos_integer()
  def max_ray, do: @max_ray

  @spec max_wad() :: pos_integer()
  def max_wad, do: @max_wad

  @spec max_rate() :: pos_integer()
  def max_rate, do: @max_rate

  @spec max_elapsed() :: pos_integer()
  def max_elapsed, do: @max_elapsed

  @spec public_ops() :: [{MathOracle.protocol(), MathOracle.op()}]
  def public_ops do
    [
      {:v3, :to_usd},
      {:v3, :to_ltv},
      {:v3, :to_health_factor},
      {:v3, :to_ray},
      {:v3, :to_wad},
      {:v3, :ray_mul},
      {:v3, :ray_div},
      {:v3, :wad_mul},
      {:v3, :wad_div},
      {:v3, :ray_to_wad},
      {:v3, :wad_to_ray},
      {:v3, :calculate_linear_interest},
      {:v3, :calculate_compounded_interest},
      {:v4, :wad_mul_down},
      {:v4, :wad_mul_up},
      {:v4, :wad_div_down},
      {:v4, :wad_div_up},
      {:v4, :ray_mul_down},
      {:v4, :ray_mul_up},
      {:v4, :ray_div_down},
      {:v4, :ray_div_up},
      {:v4, :to_wad},
      {:v4, :to_ray},
      {:v4, :from_wad_down},
      {:v4, :from_ray_up},
      {:v4, :bps_to_wad},
      {:v4, :bps_to_ray},
      {:v4, :round_ray_up},
      {:v4, :calculate_linear_interest},
      {:v4, :min},
      {:v4, :zero_floor_sub},
      {:v4, :add},
      {:v4, :div_up},
      {:v4, :mul_div_down},
      {:v4, :mul_div_up},
      {:v4, :calculate_liquidation_bonus}
    ]
  end

  @spec vectors() :: [vector()]
  def vectors do
    last = 1_700_000_000
    hf_max = div(@hf_liq, 2)

    flatten([
      display_vectors(),
      pair(:v3, :ray_mul, [
        {[0, 0], :zero},
        {[0, @ray], :zero},
        {[@ray, 0], :zero},
        {[@ray, @ray], :unit},
        {[@ray, 2 * @ray], :unit},
        {[1, @half_ray], :rounding},
        {[1, @half_ray - 1], :rounding},
        {[1, @half_ray + 1], :rounding},
        {[div(@ray, 2), div(@ray, 2)], :rounding},
        {[@ray - 1, @ray - 1], :boundary},
        {[@max_ray, @ray], :overflow_adjacent}
      ]),
      pair(:v3, :ray_div, [
        {[0, @ray], :zero},
        {[0, 123], :zero},
        {[@ray, @ray], :unit},
        {[2 * @ray, @ray], :unit},
        {[1, 3], :rounding},
        {[1, 2], :rounding},
        {[@ray - 1, 2 * @ray], :boundary},
        {[@max_ray, 1], :overflow_adjacent}
      ]),
      pair(:v3, :wad_mul, [
        {[0, 0], :zero},
        {[0, @wad], :zero},
        {[@wad, 0], :zero},
        {[@wad, @wad], :unit},
        {[1, @half_wad], :rounding},
        {[1, @half_wad - 1], :rounding},
        {[1, @half_wad + 1], :rounding},
        {[div(@wad, 2), div(@wad, 2)], :rounding},
        {[@wad - 1, @wad - 1], :boundary},
        {[@max_wad, @wad], :overflow_adjacent}
      ]),
      pair(:v3, :wad_div, [
        {[0, @wad], :zero},
        {[0, 123], :zero},
        {[@wad, @wad], :unit},
        {[2 * @wad, @wad], :unit},
        {[1, 3], :rounding},
        {[1, 2], :rounding},
        {[@wad - 1, 2 * @wad], :boundary},
        {[@max_wad, 1], :overflow_adjacent}
      ]),
      unary(:v3, :ray_to_wad, [
        {[0], :zero},
        {[@ray], :unit},
        {[div(@wad_ray_ratio, 2)], :rounding},
        {[div(@wad_ray_ratio, 2) - 1], :rounding},
        {[div(@wad_ray_ratio, 2) + 1], :rounding},
        {[2 * @ray - 1], :boundary},
        {[@max_ray], :overflow_adjacent}
      ]),
      unary(:v3, :wad_to_ray, [
        {[0], :zero},
        {[1], :unit},
        {[@wad], :unit},
        {[div(@wad, 2)], :rounding},
        {[@wad - 1], :boundary},
        {[@max_wad], :overflow_adjacent}
      ]),
      interest(:v3, :calculate_linear_interest, last),
      interest(:v3, :calculate_compounded_interest, last),
      pair(:v4, :wad_mul_down, v4_wad_mul_pairs()),
      pair(:v4, :wad_mul_up, v4_wad_mul_pairs()),
      pair(:v4, :wad_div_down, v4_wad_div_pairs()),
      pair(:v4, :wad_div_up, v4_wad_div_pairs()),
      pair(:v4, :ray_mul_down, v4_ray_mul_pairs()),
      pair(:v4, :ray_mul_up, v4_ray_mul_pairs()),
      pair(:v4, :ray_div_down, v4_ray_div_pairs()),
      pair(:v4, :ray_div_up, v4_ray_div_pairs()),
      unary(:v4, :to_wad, [
        {[0], :zero},
        {[1], :unit},
        {[3], :rounding},
        {[@wad - 1], :boundary},
        {[@wad], :overflow_adjacent}
      ]),
      unary(:v4, :to_ray, [
        {[0], :zero},
        {[1], :unit},
        {[3], :rounding},
        {[@wad - 1], :boundary},
        {[@wad], :overflow_adjacent}
      ]),
      unary(:v4, :from_wad_down, [
        {[0], :zero},
        {[@wad], :unit},
        {[3 * @wad + @wad - 1], :rounding},
        {[@wad - 1], :boundary},
        {[@max_wad + @wad - 1], :overflow_adjacent}
      ]),
      unary(:v4, :from_ray_up, [
        {[0], :zero},
        {[@ray], :unit},
        {[3 * @ray + 1], :rounding},
        {[@ray - 1], :boundary},
        {[@max_ray + @ray - 1], :overflow_adjacent}
      ]),
      unary(:v4, :bps_to_wad, [
        {[0], :zero},
        {[1], :unit},
        {[125], :rounding},
        {[@percentage_factor], :boundary},
        {[1_000_000], :overflow_adjacent}
      ]),
      unary(:v4, :bps_to_ray, [
        {[0], :zero},
        {[1], :unit},
        {[125], :rounding},
        {[@percentage_factor], :boundary},
        {[1_000_000], :overflow_adjacent}
      ]),
      unary(:v4, :round_ray_up, [
        {[0], :zero},
        {[@ray], :unit},
        {[3 * @ray + 1], :rounding},
        {[@ray - 1], :boundary},
        {[@max_ray + 1], :overflow_adjacent}
      ]),
      interest(:v4, :calculate_linear_interest, last),
      pair(:v4, :min, [
        {[0, 0], :zero},
        {[0, 5], :zero},
        {[3, 5], :unit},
        {[5, 3], :unit},
        {[4, 4], :boundary},
        {[1, 2], :rounding},
        {[@max_ray, @max_ray - 1], :overflow_adjacent}
      ]),
      pair(:v4, :zero_floor_sub, [
        {[0, 0], :zero},
        {[0, 5], :zero},
        {[5, 3], :unit},
        {[9, 4], :rounding},
        {[5, 5], :boundary},
        {[3, 5], :boundary},
        {[@max_ray, 1], :overflow_adjacent}
      ]),
      pair(:v4, :add, [
        {[0, 0], :zero},
        {[5, 3], :unit},
        {[5, -3], :unit},
        {[7, -3], :rounding},
        {[3, -3], :boundary},
        {[@max_wad, 1], :overflow_adjacent}
      ]),
      pair(:v4, :div_up, [
        {[0, 1], :zero},
        {[0, 7], :zero},
        {[4, 2], :unit},
        {[1, 3], :rounding},
        {[7, 3], :rounding},
        {[1, 1], :boundary},
        {[@max_wad, 2], :overflow_adjacent}
      ]),
      triple(:v4, :mul_div_down, [
        {[0, 5, 3], :zero},
        {[10, 2, 5], :unit},
        {[7, 3, 5], :rounding},
        {[1, 1, 1], :boundary},
        {[@max_wad, 2, 2], :overflow_adjacent}
      ]),
      triple(:v4, :mul_div_up, [
        {[0, 5, 3], :zero},
        {[10, 2, 5], :unit},
        {[7, 3, 5], :rounding},
        {[1, 1, 1], :boundary},
        {[@max_wad, 2, 2], :overflow_adjacent}
      ]),
      [
        vec(:v4, :calculate_liquidation_bonus, [hf_max, 5_000, hf_max, 11_000], :boundary),
        vec(:v4, :calculate_liquidation_bonus, [hf_max, 5_000, hf_max - 1, 11_000], :unit),
        vec(
          :v4,
          :calculate_liquidation_bonus,
          [hf_max, 5_000, div(3 * @hf_liq, 4), 11_000],
          :rounding
        ),
        vec(
          :v4,
          :calculate_liquidation_bonus,
          [900_000_000_000_000_000, 2_500, 950_000_000_000_000_000, 10_800],
          :rounding
        ),
        vec(:v4, :calculate_liquidation_bonus, [hf_max, 0, div(3 * @hf_liq, 4), 11_000], :zero),
        vec(:v4, :calculate_liquidation_bonus, [hf_max, 5_000, @hf_liq - 1, 11_000], :overflow_adjacent)
      ]
    ])
  end

  @spec bytecode_vectors() :: [vector()]
  def bytecode_vectors, do: Enum.filter(vectors(), &MathOracle.bytecode_op?(&1.protocol, &1.op))

  @spec display_vectors() :: [vector()]
  def display_vectors do
    [
      vec(:v3, :to_usd, [0], :zero),
      vec(:v3, :to_usd, [100_000_000], :unit),
      vec(:v3, :to_usd, [1], :rounding),
      vec(:v3, :to_usd, [99_999_999], :boundary),
      vec(:v3, :to_usd, [250_000_000_000], :overflow_adjacent),
      vec(:v3, :to_ltv, [0], :zero),
      vec(:v3, :to_ltv, [10_000], :unit),
      vec(:v3, :to_ltv, [1], :rounding),
      vec(:v3, :to_ltv, [8_000], :boundary),
      vec(:v3, :to_ltv, [1_000_000], :overflow_adjacent),
      vec(:v3, :to_health_factor, [0], :zero),
      vec(:v3, :to_health_factor, [@wad], :unit),
      vec(:v3, :to_health_factor, [1], :rounding),
      vec(:v3, :to_health_factor, [@wad - 1], :boundary),
      vec(:v3, :to_health_factor, [10 * @wad], :overflow_adjacent),
      vec(:v3, :to_ray, [0], :zero),
      vec(:v3, :to_ray, [@ray], :unit),
      vec(:v3, :to_ray, [1], :rounding),
      vec(:v3, :to_ray, [@ray - 1], :boundary),
      vec(:v3, :to_ray, [10 * @ray], :overflow_adjacent),
      vec(:v3, :to_wad, [0], :zero),
      vec(:v3, :to_wad, [@wad], :unit),
      vec(:v3, :to_wad, [1], :rounding),
      vec(:v3, :to_wad, [@wad - 1], :boundary),
      vec(:v3, :to_wad, [10 * @wad], :overflow_adjacent)
    ]
  end

  @spec required_classes() :: [class()]
  def required_classes, do: [:zero, :unit, :boundary, :overflow_adjacent, :rounding]

  @spec coverage_by_op() :: %{optional({MathOracle.protocol(), MathOracle.op()}) => MapSet.t()}
  def coverage_by_op do
    Enum.reduce(vectors(), %{}, fn %{protocol: protocol, op: op, class: class}, acc ->
      key = {protocol, op}
      Map.update(acc, key, MapSet.new([class]), &MapSet.put(&1, class))
    end)
  end

  @spec v4_wad_mul_pairs() :: [{[integer()], class()}]
  defp v4_wad_mul_pairs do
    [
      {[0, 0], :zero},
      {[0, @wad], :zero},
      {[@wad, @wad], :unit},
      {[1, @wad - 1], :rounding},
      {[3 * @wad, 5 * @wad], :unit},
      {[@wad - 1, @wad - 1], :boundary},
      {[@max_wad, @wad], :overflow_adjacent}
    ]
  end

  @spec v4_wad_div_pairs() :: [{[integer()], class()}]
  defp v4_wad_div_pairs do
    [
      {[0, @wad], :zero},
      {[@wad, @wad], :unit},
      {[1, 2], :rounding},
      {[1, 3], :rounding},
      {[2 * @wad, @wad], :unit},
      {[@wad - 1, 2], :boundary},
      {[@max_wad, 1], :overflow_adjacent}
    ]
  end

  @spec v4_ray_mul_pairs() :: [{[integer()], class()}]
  defp v4_ray_mul_pairs do
    [
      {[0, 0], :zero},
      {[0, @ray], :zero},
      {[@ray, @ray], :unit},
      {[1, @ray - 1], :rounding},
      {[3 * @ray, 5 * @ray], :unit},
      {[@ray - 1, @ray - 1], :boundary},
      {[@max_ray, @ray], :overflow_adjacent}
    ]
  end

  @spec v4_ray_div_pairs() :: [{[integer()], class()}]
  defp v4_ray_div_pairs do
    [
      {[0, @ray], :zero},
      {[@ray, @ray], :unit},
      {[1, 2], :rounding},
      {[1, 3], :rounding},
      {[2 * @ray, @ray], :unit},
      {[@ray - 1, 2], :boundary},
      {[@max_ray, 1], :overflow_adjacent}
    ]
  end

  @spec interest(MathOracle.protocol(), MathOracle.op(), non_neg_integer()) :: [vector()]
  defp interest(protocol, op, last) do
    [
      vec(protocol, op, [0, last, last], :zero),
      vec(protocol, op, [0, last, last + @seconds_per_year], :zero),
      vec(protocol, op, [5 * div(@ray, 100), last, last], :unit),
      vec(protocol, op, [5 * div(@ray, 100), last, last + @seconds_per_year], :unit),
      vec(protocol, op, [5 * div(@ray, 100), last, last + 1], :rounding),
      vec(protocol, op, [5 * div(@ray, 100), last, last + div(@seconds_per_year, 2)], :rounding),
      vec(protocol, op, [@ray, last, last + 12 * 86_400], :boundary),
      vec(protocol, op, [@max_rate, last, last + @max_elapsed], :overflow_adjacent)
    ]
  end

  @spec pair(MathOracle.protocol(), MathOracle.op(), [{[integer()], class()}]) :: [vector()]
  defp pair(protocol, op, pairs) do
    Enum.map(pairs, fn {args, class} -> vec(protocol, op, args, class) end)
  end

  @spec unary(MathOracle.protocol(), MathOracle.op(), [{[integer()], class()}]) :: [vector()]
  defp unary(protocol, op, pairs), do: pair(protocol, op, pairs)

  @spec triple(MathOracle.protocol(), MathOracle.op(), [{[integer()], class()}]) :: [vector()]
  defp triple(protocol, op, pairs), do: pair(protocol, op, pairs)

  @spec vec(MathOracle.protocol(), MathOracle.op(), [integer()], class()) :: vector()
  defp vec(protocol, op, args, class) do
    %{protocol: protocol, op: op, args: args, class: class}
  end

  @spec flatten([term()]) :: [vector()]
  defp flatten(list), do: List.flatten(list)
end
