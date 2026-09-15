defmodule Onchain.Aerodrome.ReachArchitectureTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Architecture

  @moduletag :tmp_dir

  test "analytics and math reject external network calls", %{tmp_dir: dir} do
    for caller <- ["Analytics.Probe", "Math", "Math.Probe"],
        call <- [
          "Onchain.RPC.eth_call(address, data, opts)",
          "Onchain.Contract.call(address, data, [], opts)",
          "Onchain.Multicall.aggregate3(data, opts)",
          "Req.get(address)",
          ":httpc.request(address)"
        ] do
      assert [%{type: :forbidden_call}] =
               violations(dir, "Onchain.Aerodrome.#{caller}", """
               def probe(address, data, opts), do: #{call}
               """)
    end
  end

  test "analytics cannot reach aliased bindings", %{tmp_dir: dir} do
    assert [%{type: :forbidden_dependency, caller_layer: :analytics, callee_layer: :bindings}] =
             violations(dir, "Onchain.Aerodrome.Analytics.Probe", """
             alias Onchain.Aerodrome.Bindings.Probe
             def probe(value), do: Probe.call(value)
             """)
  end

  test "bindings can construct types", %{tmp_dir: dir} do
    assert [] =
             violations(dir, "Onchain.Aerodrome.Bindings.Probe", """
             alias Onchain.Aerodrome.Types.Probe
             def probe, do: %Probe{}
             def explicit_struct, do: Probe.__struct__()
             """)
  end

  test "types cannot reach base", %{tmp_dir: dir} do
    assert [%{type: :forbidden_dependency, caller_layer: :types, callee_layer: :base}] =
             violations(dir, "Onchain.Aerodrome.Types.Probe", """
             def probe, do: Onchain.Aerodrome.Contracts.constants()
             """)
  end

  test "analytics and math can reach constants", %{tmp_dir: dir} do
    for caller <- ["Analytics.Probe", "Math", "Math.Probe"] do
      assert [] =
               violations(dir, "Onchain.Aerodrome.#{caller}", """
               def probe, do: Onchain.Aerodrome.Contracts.constants()
               """)
    end
  end

  test "fixture generators can reach the network", %{tmp_dir: dir} do
    assert [] =
             violations(dir, "Mix.Tasks.Aerodrome.FixtureProbe", """
             def probe(address, data, opts), do: Onchain.RPC.eth_call(address, data, opts)
             """)
  end

  defp violations(dir, module, body) do
    path = Path.join(dir, "probe.ex")
    File.write!(path, "defmodule #{module} do\n#{body}\nend\n")
    {config, []} = Code.eval_file(Path.expand("../.reach.exs", __DIR__))
    project = Reach.Project.from_sources([path], plugins: [])
    Architecture.run(project, config).violations
  end
end
