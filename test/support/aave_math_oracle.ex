defmodule Onchain.Aave.MathOracle do
  @moduledoc false

  # Independent checker for Aave V3/V4 math: pinned official Solidity bytecode
  # executed through onchain_evm/revm, plus documented display-scale conversions.
  # Production `Onchain.Aave.Math` is never used to produce expected values.

  alias Onchain.Aave.Math
  alias Onchain.Aave.Math.V4
  alias Onchain.Aave.MathDomains
  alias Onchain.ABI
  alias Onchain.EVM

  @fixtures_dir Path.expand("../fixtures", __DIR__)
  @goldens_path Path.join(@fixtures_dir, "math_oracle_vectors.json")
  @ledger_path Path.join(@fixtures_dir, "math_verification_ledger.json")

  @v3_address "0x000000000000000000000000000000000000beef"
  @v4_address "0x000000000000000000000000000000000000b0b0"

  @type protocol :: :v3 | :v4
  @type op :: atom()
  @type vector :: %{protocol: protocol(), op: op(), args: [integer()], class: atom()}

  @spec ledger_path() :: String.t()
  def ledger_path, do: @ledger_path

  @spec fixtures_dir() :: String.t()
  def fixtures_dir, do: @fixtures_dir

  @spec wrapper_address(protocol()) :: String.t()
  def wrapper_address(:v3), do: @v3_address
  def wrapper_address(:v4), do: @v4_address

  @spec load_wrapper!(protocol()) :: %{bin_hex: String.t(), meta: map(), address: String.t()}
  def load_wrapper!(protocol) do
    {bin_name, meta_name} =
      case protocol do
        :v3 -> {"wad_ray_wrapper.bin", "wad_ray_wrapper.json"}
        :v4 -> {"v4_math_wrapper.bin", "v4_math_wrapper.json"}
      end

    bin_hex = @fixtures_dir |> Path.join(bin_name) |> File.read!() |> String.trim()
    meta = @fixtures_dir |> Path.join(meta_name) |> File.read!() |> Jason.decode!()
    expected_sha = meta["wrapper"]["bin_sha256"]
    actual_sha = bin_hex |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

    if expected_sha != actual_sha do
      raise """
      #{bin_name} checksum mismatch!
        expected: #{expected_sha}
        actual:   #{actual_sha}

      Regenerate fixtures — see test/fixtures/README.md.
      """
    end

    %{bin_hex: bin_hex, meta: meta, address: wrapper_address(protocol)}
  end

  @spec revm_opts(protocol(), String.t()) :: keyword()
  def revm_opts(protocol, rpc_url) do
    wrapper = load_wrapper!(protocol)

    [
      rpc_url: rpc_url,
      block: "latest",
      state_overrides: %{wrapper.address => %{"code" => "0x" <> wrapper.bin_hex}}
    ]
  end

  @spec signature(protocol(), op()) :: String.t()
  def signature(:v3, :ray_mul), do: "rayMul(uint256,uint256)"
  def signature(:v3, :ray_div), do: "rayDiv(uint256,uint256)"
  def signature(:v3, :wad_mul), do: "wadMul(uint256,uint256)"
  def signature(:v3, :wad_div), do: "wadDiv(uint256,uint256)"
  def signature(:v3, :ray_to_wad), do: "rayToWad(uint256)"
  def signature(:v3, :wad_to_ray), do: "wadToRay(uint256)"
  def signature(:v3, :calculate_linear_interest), do: "calculateLinearInterestAt(uint256,uint256,uint256)"
  def signature(:v3, :calculate_compounded_interest), do: "calculateCompoundedInterest(uint256,uint256,uint256)"
  def signature(:v4, :wad_mul_down), do: "wadMulDown(uint256,uint256)"
  def signature(:v4, :wad_mul_up), do: "wadMulUp(uint256,uint256)"
  def signature(:v4, :wad_div_down), do: "wadDivDown(uint256,uint256)"
  def signature(:v4, :wad_div_up), do: "wadDivUp(uint256,uint256)"
  def signature(:v4, :ray_mul_down), do: "rayMulDown(uint256,uint256)"
  def signature(:v4, :ray_mul_up), do: "rayMulUp(uint256,uint256)"
  def signature(:v4, :ray_div_down), do: "rayDivDown(uint256,uint256)"
  def signature(:v4, :ray_div_up), do: "rayDivUp(uint256,uint256)"
  def signature(:v4, :to_wad), do: "toWad(uint256)"
  def signature(:v4, :to_ray), do: "toRay(uint256)"
  def signature(:v4, :from_wad_down), do: "fromWadDown(uint256)"
  def signature(:v4, :from_ray_up), do: "fromRayUp(uint256)"
  def signature(:v4, :bps_to_wad), do: "bpsToWad(uint256)"
  def signature(:v4, :bps_to_ray), do: "bpsToRay(uint256)"
  def signature(:v4, :round_ray_up), do: "roundRayUp(uint256)"
  def signature(:v4, :calculate_linear_interest), do: "calculateLinearInterestAt(uint256,uint256,uint256)"
  def signature(:v4, :min), do: "min(uint256,uint256)"
  def signature(:v4, :zero_floor_sub), do: "zeroFloorSub(uint256,uint256)"
  def signature(:v4, :add), do: "add(uint256,int256)"
  def signature(:v4, :div_up), do: "divUp(uint256,uint256)"
  def signature(:v4, :mul_div_down), do: "mulDivDown(uint256,uint256,uint256)"
  def signature(:v4, :mul_div_up), do: "mulDivUp(uint256,uint256,uint256)"
  def signature(:v4, :calculate_liquidation_bonus), do: "calculateLiquidationBonus(uint256,uint256,uint256,uint256)"

  @spec bytecode_op?(protocol(), op()) :: boolean()
  def bytecode_op?(protocol, op) do
    not (protocol == :v3 and op in [:to_usd, :to_ltv, :to_health_factor, :to_ray, :to_wad])
  end

  @spec call_revm(protocol(), op(), [integer()], keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def call_revm(protocol, op, args, opts) do
    address = wrapper_address(protocol)
    calldata = ABI.encode_call!(signature(protocol, op), args)

    case EVM.simulate_call(address, calldata, opts) do
      {:ok, hex} ->
        [value] = ABI.decode_response!("(uint256)", hex)
        {:ok, value}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec apply_elixir(protocol(), op(), [integer()]) :: integer() | Decimal.t()
  def apply_elixir(protocol, op, args), do: apply_module(target_module(protocol), protocol, op, args)

  @spec apply_module(module(), protocol(), op(), [integer()]) :: integer() | Decimal.t()
  def apply_module(mod, :v3, :to_usd, [value]), do: mod.to_usd(value)
  def apply_module(mod, :v3, :to_ltv, [value]), do: mod.to_ltv(value)
  def apply_module(mod, :v3, :to_health_factor, [value]), do: mod.to_health_factor(value)
  def apply_module(mod, :v3, :to_ray, [value]), do: mod.to_ray(value)
  def apply_module(mod, :v3, :to_wad, [value]), do: mod.to_wad(value)
  def apply_module(mod, :v3, :ray_mul, [a, b]), do: mod.ray_mul(a, b)
  def apply_module(mod, :v3, :ray_div, [a, b]), do: mod.ray_div(a, b)
  def apply_module(mod, :v3, :wad_mul, [a, b]), do: mod.wad_mul(a, b)
  def apply_module(mod, :v3, :wad_div, [a, b]), do: mod.wad_div(a, b)
  def apply_module(mod, :v3, :ray_to_wad, [a]), do: mod.ray_to_wad(a)
  def apply_module(mod, :v3, :wad_to_ray, [a]), do: mod.wad_to_ray(a)

  def apply_module(mod, :v3, :calculate_linear_interest, [rate, last, current]),
    do: mod.calculate_linear_interest(rate, last, current)

  def apply_module(mod, :v3, :calculate_compounded_interest, [rate, last, current]),
    do: mod.calculate_compounded_interest(rate, last, current)

  def apply_module(mod, :v4, :wad_mul_down, [a, b]), do: mod.wad_mul_down(a, b)
  def apply_module(mod, :v4, :wad_mul_up, [a, b]), do: mod.wad_mul_up(a, b)
  def apply_module(mod, :v4, :wad_div_down, [a, b]), do: mod.wad_div_down(a, b)
  def apply_module(mod, :v4, :wad_div_up, [a, b]), do: mod.wad_div_up(a, b)
  def apply_module(mod, :v4, :ray_mul_down, [a, b]), do: mod.ray_mul_down(a, b)
  def apply_module(mod, :v4, :ray_mul_up, [a, b]), do: mod.ray_mul_up(a, b)
  def apply_module(mod, :v4, :ray_div_down, [a, b]), do: mod.ray_div_down(a, b)
  def apply_module(mod, :v4, :ray_div_up, [a, b]), do: mod.ray_div_up(a, b)
  def apply_module(mod, :v4, :to_wad, [a]), do: mod.to_wad(a)
  def apply_module(mod, :v4, :to_ray, [a]), do: mod.to_ray(a)
  def apply_module(mod, :v4, :from_wad_down, [a]), do: mod.from_wad_down(a)
  def apply_module(mod, :v4, :from_ray_up, [a]), do: mod.from_ray_up(a)
  def apply_module(mod, :v4, :bps_to_wad, [a]), do: mod.bps_to_wad(a)
  def apply_module(mod, :v4, :bps_to_ray, [a]), do: mod.bps_to_ray(a)
  def apply_module(mod, :v4, :round_ray_up, [a]), do: mod.round_ray_up(a)

  def apply_module(mod, :v4, :calculate_linear_interest, [rate, last, current]),
    do: mod.calculate_linear_interest(rate, last, current)

  def apply_module(mod, :v4, :min, [a, b]), do: mod.min(a, b)
  def apply_module(mod, :v4, :zero_floor_sub, [a, b]), do: mod.zero_floor_sub(a, b)
  def apply_module(mod, :v4, :add, [a, b]), do: mod.add(a, b)
  def apply_module(mod, :v4, :div_up, [a, b]), do: mod.div_up(a, b)
  def apply_module(mod, :v4, :mul_div_down, [a, b, c]), do: mod.mul_div_down(a, b, c)
  def apply_module(mod, :v4, :mul_div_up, [a, b, c]), do: mod.mul_div_up(a, b, c)

  def apply_module(mod, :v4, :calculate_liquidation_bonus, [a, b, c, d]), do: mod.calculate_liquidation_bonus(a, b, c, d)

  @spec target_module(protocol()) :: module()
  def target_module(:v3), do: Math
  def target_module(:v4), do: V4

  @spec display_expected(op(), [integer()]) :: Decimal.t()
  def display_expected(:to_usd, [value]), do: scale_div(value, 100_000_000)
  def display_expected(:to_ltv, [value]), do: scale_div(value, 10_000)
  def display_expected(:to_health_factor, [value]), do: scale_div(value, 1_000_000_000_000_000_000)
  def display_expected(:to_ray, [value]), do: scale_div(value, 1_000_000_000_000_000_000_000_000_000)
  def display_expected(:to_wad, [value]), do: scale_div(value, 1_000_000_000_000_000_000)

  @spec load_goldens!() :: map()
  def load_goldens! do
    @goldens_path |> File.read!() |> Jason.decode!()
  end

  @spec golden_expected(map(), vector()) :: integer()
  def golden_expected(goldens, %{protocol: protocol, op: op, args: args}) do
    key = golden_key(protocol, op, args)

    case goldens[key] do
      nil -> raise "missing golden for #{key}"
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
    end
  end

  @spec golden_key(protocol(), op(), [integer()]) :: String.t()
  def golden_key(protocol, op, args) do
    "#{protocol}.#{op}:" <> Enum.map_join(args, ",", &Integer.to_string/1)
  end

  @spec dump_goldens!(map()) :: :ok
  def dump_goldens!(goldens) do
    File.write!(@goldens_path, Jason.encode!(goldens, pretty: true) <> "\n")
  end

  @spec generate_goldens!(String.t()) :: map()
  def generate_goldens!(rpc_url) do
    v3_opts = revm_opts(:v3, rpc_url)
    v4_opts = revm_opts(:v4, rpc_url)

    goldens =
      Enum.reduce(MathDomains.bytecode_vectors(), %{}, fn vector, acc ->
        opts = if vector.protocol == :v3, do: v3_opts, else: v4_opts

        case call_revm(vector.protocol, vector.op, vector.args, opts) do
          {:ok, value} ->
            Map.put(acc, golden_key(vector.protocol, vector.op, vector.args), Integer.to_string(value))

          {:error, reason} ->
            raise """
            revm failed while generating goldens for #{vector.protocol}.#{vector.op}
              args:   #{inspect(vector.args)}
              reason: #{inspect(reason)}
            """
        end
      end)

    dump_goldens!(goldens)
    goldens
  end

  @spec scale_div(integer(), pos_integer()) :: Decimal.t()
  defp scale_div(value, scale) do
    Decimal.div(Decimal.new(value), Decimal.new(scale))
  end
end
