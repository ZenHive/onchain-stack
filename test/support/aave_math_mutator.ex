defmodule Onchain.Aave.MathMutator do
  @moduledoc false

  # Reproducible generated + domain mutation campaign against the Solidity
  # golden oracle. Mutants are compiled in-memory; tracked sources are never
  # overwritten.

  alias Onchain.Aave.MathDomains
  alias Onchain.Aave.MathOracle

  @math_v3 Path.expand("../../lib/onchain/aave/math.ex", __DIR__)
  @math_v4 Path.expand("../../lib/onchain/aave/math/v4.ex", __DIR__)

  @arith [:+, :-, :*]
  @compare [:<, :>, :<=, :>=, :==]

  @type mutant :: %{
          id: String.t(),
          source: :generated | :domain,
          protocol: MathOracle.protocol(),
          kind: atom(),
          description: String.t(),
          apply: (map() -> term())
        }

  @type verdict :: :killed | :survived

  @spec campaign(map()) :: [map()]
  def campaign(goldens) do
    Enum.map(mutants(), &evaluate(&1, goldens))
  end

  @spec mutants() :: [mutant()]
  def mutants do
    domain_mutants() ++ generated_mutants()
  end

  @spec canary() :: mutant()
  def canary do
    ray = MathDomains.ray()

    %{
      id: "canary.v3.ray_mul.floor_instead_of_half_up",
      source: :domain,
      protocol: :v3,
      kind: :rounding,
      description: "ray_mul floors (drops HALF_RAY) instead of round-half-up",
      apply: fn %{op: :ray_mul, args: [a, b]} -> div(a * b, ray) end
    }
  end

  @spec domain_mutants() :: [mutant()]
  def domain_mutants do
    ray = MathDomains.ray()
    wad = MathDomains.wad()
    half_ray = MathDomains.half_ray()
    year = MathDomains.seconds_per_year()
    hf = MathDomains.hf_liq()
    bps = MathDomains.percentage_factor()

    [
      canary(),
      %{
        id: "domain.v3.ray_mul.always_up",
        source: :domain,
        protocol: :v3,
        kind: :rounding,
        description: "ray_mul adds RAY-1 (almost always up) instead of HALF_RAY",
        apply: fn %{op: :ray_mul, args: [a, b]} -> div(a * b + ray - 1, ray) end
      },
      %{
        id: "domain.v3.wad_mul.floor",
        source: :domain,
        protocol: :v3,
        kind: :rounding,
        description: "wad_mul floors instead of round-half-up",
        apply: fn %{op: :wad_mul, args: [a, b]} -> div(a * b, wad) end
      },
      %{
        id: "domain.v3.ray_to_wad.half_down",
        source: :domain,
        protocol: :v3,
        kind: :rounding,
        description: "ray_to_wad rounds the exact midpoint down",
        apply: fn %{op: :ray_to_wad, args: [a]} ->
          ratio = MathDomains.wad_ray_ratio()
          quotient = div(a, ratio)
          remainder = rem(a, ratio)
          if remainder <= div(ratio, 2), do: quotient, else: quotient + 1
        end
      },
      %{
        id: "domain.v3.linear.leap_year",
        source: :domain,
        protocol: :v3,
        kind: :arithmetic,
        description: "calculate_linear_interest uses 365.25 days per year",
        apply: fn %{op: :calculate_linear_interest, args: [rate, last, current]} ->
          ray + div(rate * (current - last), 31_557_600)
        end
      },
      %{
        id: "domain.v3.ray_div.drop_half",
        source: :domain,
        protocol: :v3,
        kind: :rounding,
        description: "ray_div drops the half-divisor term",
        apply: fn %{op: :ray_div, args: [a, b]} -> div(a * ray, b) end
      },
      %{
        id: "domain.v4.wad_mul_up.as_down",
        source: :domain,
        protocol: :v4,
        kind: :rounding,
        description: "wad_mul_up uses floor division",
        apply: fn %{op: :wad_mul_up, args: [a, b]} -> div(a * b, wad) end
      },
      %{
        id: "domain.v4.div_up.as_down",
        source: :domain,
        protocol: :v4,
        kind: :rounding,
        description: "div_up floors instead of rounding up",
        apply: fn %{op: :div_up, args: [a, b]} -> div(a, b) end
      },
      %{
        id: "domain.v4.zero_floor_sub.no_clamp",
        source: :domain,
        protocol: :v4,
        kind: :clamp,
        description: "zero_floor_sub subtracts without flooring at zero",
        apply: fn %{op: :zero_floor_sub, args: [a, b]} -> a - b end
      },
      %{
        id: "domain.v4.min.as_max",
        source: :domain,
        protocol: :v4,
        kind: :comparison,
        description: "min returns the larger argument",
        apply: fn %{op: :min, args: [a, b]} -> Kernel.max(a, b) end
      },
      %{
        id: "domain.v4.liq.exclusive_max_bonus",
        source: :domain,
        protocol: :v4,
        kind: :comparison,
        description: "calculate_liquidation_bonus uses < instead of <= at the max-bonus boundary",
        apply: fn %{op: :calculate_liquidation_bonus, args: [hf_max, factor, health, max_bonus]} ->
          if health < hf_max do
            max_bonus
          else
            min_bonus = div((max_bonus - bps) * factor, bps) + bps

            min_bonus +
              div((max_bonus - min_bonus) * (hf - health), hf - hf_max)
          end
        end
      },
      %{
        id: "domain.v3.ray_mul.half_constant_as_wad",
        source: :domain,
        protocol: :v3,
        kind: :arithmetic,
        description: "ray_mul uses HALF_WAD instead of HALF_RAY",
        apply: fn %{op: :ray_mul, args: [a, b]} ->
          div(a * b + MathDomains.half_wad(), ray)
        end
      },
      %{
        id: "domain.v3.compound.linear",
        source: :domain,
        protocol: :v3,
        kind: :arithmetic,
        description: "calculate_compounded_interest collapses to the linear formula",
        apply: fn %{op: :calculate_compounded_interest, args: [rate, last, current]} ->
          ray + div(rate * (current - last), year)
        end
      },
      %{
        id: "domain.v4.ray_mul_down.as_half_up",
        source: :domain,
        protocol: :v4,
        kind: :rounding,
        description: "ray_mul_down uses V3 half-up instead of floor",
        apply: fn %{op: :ray_mul_down, args: [a, b]} -> div(a * b + half_ray, ray) end
      }
    ]
  end

  @spec generated_mutants() :: [mutant()]
  def generated_mutants do
    generate_from_file(:v3, @math_v3) ++ generate_from_file(:v4, @math_v4)
  end

  @spec evaluate(mutant(), map()) :: map()
  def evaluate(mutant, goldens) do
    vectors = oracle_vectors(mutant)

    {verdict, evidence} =
      Enum.reduce_while(vectors, {:survived, "agreed with every Solidity golden"}, fn vector, _ ->
        case run_mutant(mutant, goldens, vector) do
          :agree -> {:cont, {:survived, "agreed with every Solidity golden"}}
          {:disagree, detail} -> {:halt, {:killed, detail}}
          {:raised, detail} -> {:halt, {:killed, detail}}
        end
      end)

    classification =
      if verdict == :survived do
        classify_survivor(mutant)
      end

    %{
      id: mutant.id,
      source: mutant.source,
      protocol: mutant.protocol,
      kind: mutant.kind,
      description: mutant.description,
      verdict: verdict,
      evidence: evidence,
      classification: classification
    }
  end

  @spec generate_from_file(MathOracle.protocol(), String.t()) :: [mutant()]
  defp generate_from_file(protocol, path) do
    source = File.read!(path)
    ast = Sourceror.parse_string!(source)

    site_count =
      ast |> walk_bodies(0, fn node, acc -> {node, acc + if(mutable_site?(node), do: 1, else: 0)} end) |> elem(1)

    for index <- 0..(site_count - 1)//1 do
      {mutated_ast, info} = apply_site(ast, index)
      mutated_source = Sourceror.to_string(mutated_ast)
      module_name = "Onchain.Aave.MathMutant#{protocol}#{index}"

      %{
        id: "generated.#{protocol}.#{index}.#{info.kind}.#{info.from}->#{info.to}",
        source: :generated,
        protocol: protocol,
        kind: info.kind,
        description: "#{info.from} -> #{info.to} at site #{index}",
        apply: compiled_apply(protocol, module_name, mutated_source)
      }
    end
  end

  @spec compiled_apply(MathOracle.protocol(), String.t(), String.t()) :: (map() -> term())
  defp compiled_apply(protocol, module_name, mutated_source) do
    original = target_source_name(protocol)
    namespaced = String.replace(mutated_source, "defmodule #{original} do", "defmodule #{module_name} do", global: false)

    namespaced =
      String.replace(
        namespaced,
        ~s(use Descripex, namespace: "/aave/math"),
        ~s(use Descripex, namespace: "/aave/math_mutant/#{module_name}")
      )

    fn vector ->
      mod = compile_mutant!(module_name, namespaced)
      MathOracle.apply_module(mod, vector.protocol, vector.op, vector.args)
    end
  end

  @spec compile_mutant!(String.t(), String.t()) :: module()
  defp compile_mutant!(module_name, source) do
    mod = Module.concat(Elixir, module_name)

    if :erlang.function_exported(mod, :module_info, 0) do
      mod
    else
      compiled = Code.compile_string(source, module_name <> ".ex")

      case List.keyfind(compiled, mod, 0) do
        {^mod, _bin} -> mod
        nil -> raise "mutant #{module_name} did not compile to #{inspect(mod)}"
      end
    end
  end

  @spec target_source_name(MathOracle.protocol()) :: String.t()
  defp target_source_name(:v3), do: "Onchain.Aave.Math"
  defp target_source_name(:v4), do: "Onchain.Aave.Math.V4"

  @spec oracle_vectors(mutant()) :: [MathOracle.vector()]
  defp oracle_vectors(%{source: :domain, protocol: protocol, apply: apply_fun} = mutant) do
    applicable =
      Enum.filter(MathDomains.bytecode_vectors(), fn vector ->
        vector.protocol == protocol and domain_applies?(apply_fun, vector)
      end)

    if applicable == [] do
      Enum.filter(MathDomains.bytecode_vectors(), &(&1.protocol == mutant.protocol))
    else
      applicable
    end
  end

  defp oracle_vectors(%{source: :generated, protocol: protocol}) do
    Enum.filter(MathDomains.bytecode_vectors(), &(&1.protocol == protocol))
  end

  @spec run_mutant(mutant(), map(), MathOracle.vector()) :: :agree | {:disagree, String.t()} | {:raised, String.t()}
  defp run_mutant(mutant, goldens, vector) do
    expected = MathOracle.golden_expected(goldens, vector)

    actual = mutant.apply.(vector)

    if actual == expected do
      :agree
    else
      {:disagree, "#{vector.op} #{inspect(vector.args)} mutant=#{inspect(actual)} golden=#{expected}"}
    end
  rescue
    exception ->
      {:raised, :error |> Exception.format(exception) |> String.split("\n") |> hd()}
  end

  @spec classify_survivor(mutant()) :: map()
  defp classify_survivor(%{id: id}) do
    {bucket, evidence} = survivor_bucket(id)
    %{bucket: bucket, evidence: evidence}
  end

  @spec domain_applies?((map() -> term()), MathOracle.vector()) :: boolean()
  defp domain_applies?(fun, vector) do
    fun.(vector)
    true
  rescue
    FunctionClauseError -> false
  end

  # Only mutants listed here may survive. A generic "< vs <=" classifier would
  # rubber-stamp a missing equality vector as equivalent.
  @equivalent_survivors %{
    "domain.v4.liq.exclusive_max_bonus" =>
      "at health == health_factor_for_max_bonus the interpolation term is exact (numerator == denominator), so < vs <= both return max_bonus"
  }

  @spec survivor_bucket(String.t()) :: {:equivalent | :gap, String.t()}
  defp survivor_bucket(id) do
    case Map.fetch(@equivalent_survivors, id) do
      {:ok, evidence} ->
        {:equivalent, evidence}

      :error ->
        {:gap, "survivor has no equivalent/unreachable evidence — close with a vector"}
    end
  end

  @spec apply_site(Macro.t(), non_neg_integer()) :: {Macro.t(), map()}
  defp apply_site(ast, index) do
    {new_ast, acc} =
      walk_bodies(ast, %{index: 0, target: index, info: nil}, fn node, acc ->
        if mutable_site?(node) and acc.index == acc.target do
          {mutated, info} = mutate_node(node)
          {mutated, %{acc | index: acc.index + 1, info: info}}
        else
          {node, %{acc | index: acc.index + if(mutable_site?(node), do: 1, else: 0)}}
        end
      end)

    {new_ast, acc.info || %{kind: :unknown, from: "?", to: "?"}}
  end

  @spec walk_bodies(Macro.t(), term(), (Macro.t(), term() -> {Macro.t(), term()})) :: {Macro.t(), term()}
  defp walk_bodies(ast, acc, fun), do: walk_any(ast, acc, fun)

  @spec walk_any(term(), term(), (Macro.t(), term() -> {Macro.t(), term()})) :: {term(), term()}
  defp walk_any({:defguardp, _, _} = node, acc, _fun), do: {node, acc}
  defp walk_any({:defguard, _, _} = node, acc, _fun), do: {node, acc}

  defp walk_any({def_kind, meta, args}, acc, fun) when def_kind in [:def, :defp] do
    {args, acc} = walk_def_args(args, acc, fun)
    {{def_kind, meta, args}, acc}
  end

  defp walk_any(list, acc, fun) when is_list(list) do
    Enum.map_reduce(list, acc, fn item, acc -> walk_any(item, acc, fun) end)
  end

  defp walk_any({form, meta, args}, acc, fun) when is_list(args) do
    {args, acc} = walk_any(args, acc, fun)
    {{form, meta, args}, acc}
  end

  defp walk_any({left, right}, acc, fun) do
    {left, acc} = walk_any(left, acc, fun)
    {right, acc} = walk_any(right, acc, fun)
    {{left, right}, acc}
  end

  defp walk_any(other, acc, _fun), do: {other, acc}

  @spec walk_def_args(list(), term(), (Macro.t(), term() -> {Macro.t(), term()})) :: {list(), term()}
  defp walk_def_args([{:when, wmeta, [head, guard]}, body], acc, fun) do
    {body, acc} = mutate_do_block(body, acc, fun)
    {[{:when, wmeta, [head, guard]}, body], acc}
  end

  defp walk_def_args([head, body], acc, fun) do
    {body, acc} = mutate_do_block(body, acc, fun)
    {[head, body], acc}
  end

  defp walk_def_args(args, acc, fun) do
    walk_any(args, acc, fun)
  end

  @spec mutate_do_block(term(), term(), (Macro.t(), term() -> {Macro.t(), term()})) :: {term(), term()}
  defp mutate_do_block(kw, acc, fun) when is_list(kw) do
    Enum.map_reduce(kw, acc, fn
      {:do, body}, acc ->
        {body, acc} = Macro.prewalk(body, acc, fun)
        {{:do, body}, acc}

      {{:__block__, _, [:do]} = key, body}, acc ->
        {body, acc} = Macro.prewalk(body, acc, fun)
        {{key, body}, acc}

      other, acc ->
        {other, acc}
    end)
  end

  defp mutate_do_block(other, acc, _fun), do: {other, acc}

  @spec mutable_site?(Macro.t()) :: boolean()
  defp mutable_site?({op, _meta, args}) when op in @arith or op in @compare do
    is_list(args) and length(args) == 2
  end

  defp mutable_site?({:., _, [{:__aliases__, _, [:Kernel]}, :min]}), do: false

  defp mutable_site?({{:., _, [{:__aliases__, _, [:Kernel]}, :min]}, _, args}) when is_list(args) do
    true
  end

  defp mutable_site?({:{}, _, _}), do: false
  defp mutable_site?(_), do: false

  @spec mutate_node(Macro.t()) :: {Macro.t(), map()}
  defp mutate_node({:+, meta, args}) do
    {{:-, meta, args}, %{kind: :arithmetic, from: "+", to: "-"}}
  end

  defp mutate_node({:-, meta, args}) do
    {{:+, meta, args}, %{kind: :arithmetic, from: "-", to: "+"}}
  end

  defp mutate_node({:*, meta, args}) do
    {{:+, meta, args}, %{kind: :arithmetic, from: "*", to: "+"}}
  end

  defp mutate_node({:<, meta, args}) do
    {{:<=, meta, args}, %{kind: :comparison, from: "<", to: "<="}}
  end

  defp mutate_node({:<=, meta, args}) do
    {{:<, meta, args}, %{kind: :comparison, from: "<=", to: "<"}}
  end

  defp mutate_node({:>, meta, args}) do
    {{:>=, meta, args}, %{kind: :comparison, from: ">", to: ">="}}
  end

  defp mutate_node({:>=, meta, args}) do
    {{:>, meta, args}, %{kind: :comparison, from: ">=", to: ">"}}
  end

  defp mutate_node({:==, meta, args}) do
    {{:!=, meta, args}, %{kind: :comparison, from: "==", to: "!="}}
  end

  defp mutate_node({{:., dot_meta, [{:__aliases__, alias_meta, [:Kernel]}, :min]}, meta, args}) do
    {{{:., dot_meta, [{:__aliases__, alias_meta, [:Kernel]}, :max]}, meta, args},
     %{kind: :clamp, from: "Kernel.min", to: "Kernel.max"}}
  end

  defp mutate_node(other) do
    {other, %{kind: :unknown, from: "?", to: "?"}}
  end
end
