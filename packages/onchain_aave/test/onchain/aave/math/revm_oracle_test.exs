defmodule Onchain.Aave.Math.RevmOracleTest do
  @moduledoc """
  Live revm differential: Elixir vs pinned official Aave wrapper bytecode.
  """

  use ExUnit.Case, async: false

  alias Onchain.Aave.MathDomains
  alias Onchain.Aave.MathOracle
  alias Onchain.RPCCase

  @moduletag :integration
  @moduletag :math_revm
  @moduletag timeout: :infinity

  setup_all do
    url = RPCCase.rpc_url!()
    goldens = MathOracle.load_goldens!()
    v3_opts = MathOracle.revm_opts(:v3, url)
    v4_opts = MathOracle.revm_opts(:v4, url)
    {:ok, goldens: goldens, v3_opts: v3_opts, v4_opts: v4_opts}
  end

  test "domain vectors match pinned bytecode and committed goldens", ctx do
    mismatches =
      Enum.reduce(MathDomains.bytecode_vectors(), [], fn vector, acc ->
        opts = if(vector.protocol == :v3, do: ctx.v3_opts, else: ctx.v4_opts)
        elixir = MathOracle.apply_elixir(vector.protocol, vector.op, vector.args)
        golden = MathOracle.golden_expected(ctx.goldens, vector)

        case MathOracle.call_revm(vector.protocol, vector.op, vector.args, opts) do
          {:ok, revm} ->
            if elixir == revm and revm == golden do
              acc
            else
              [{vector.protocol, vector.op, vector.args, elixir, revm, golden} | acc]
            end

          {:error, reason} ->
            [{:revm_error, vector.protocol, vector.op, vector.args, reason} | acc]
        end
      end)

    assert mismatches == [], "revm/elixir/golden divergence: #{inspect(mismatches)}"
  end
end
