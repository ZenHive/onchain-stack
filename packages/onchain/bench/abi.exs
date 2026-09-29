alias ABI, as: Alloy
alias ABI.Bench.Legacy
alias ABI.FunctionSelector

# ONCHAIN_BUILD=1 mix compile --force
# mix run --no-start bench/abi.exs
Enum.each(~w(type_encoder type_decoder event abi), &Code.require_file("legacy/#{&1}.ex", __DIR__))

transfer = FunctionSelector.decode("transfer(address,uint256)")
transfer_values = [<<0x42::160>>, 1_000_000_000_000_000_000]

aggregate = FunctionSelector.decode("aggregate3((bool,bytes)[])")
results = for i <- 1..500, do: {rem(i, 7) != 0, <<i::256, i * 2::256>>}
aggregate_payload = Legacy.TypeEncoder.encode_raw([{results}], [%{type: {:tuple, aggregate.types}}])

nested = FunctionSelector.decode("nested((uint256,(address,string)[],bytes32)[],uint256[3])")

nested_values = [
  for(i <- 1..20, do: {i, [{<<i::160>>, "entry #{i}"}, {<<i + 1::160>>, "nested value"}], <<i::256>>}),
  [1, 2, 3]
]

transfer_event = FunctionSelector.decode("Transfer(address indexed from,address indexed to,uint256 value)")
topic0 = ABI.Event.event_signature(transfer_event)
logs = for i <- 1..10_000, do: {<<i::256>>, [topic0, <<i::256>>, <<i + 1::256>>]}

workloads = %{
  "ERC-20 transfer encode" => {
    fn -> Legacy.encode(transfer, transfer_values) end,
    fn -> Alloy.encode(transfer, transfer_values) end
  },
  "aggregate3 decode (500 results)" => {
    fn -> Legacy.decode(aggregate, aggregate_payload) end,
    fn -> Alloy.decode(aggregate, aggregate_payload) end
  },
  "Transfer event decode (single log)" => {
    fn ->
      {data, topics} = hd(logs)
      Legacy.Event.decode_event(data, topics, transfer_event)
    end,
    fn ->
      {data, topics} = hd(logs)
      Alloy.decode_event(transfer_event, data, topics)
    end
  },
  "Transfer event decode (10000 logs)" => {
    fn -> Enum.map(logs, fn {data, topics} -> Legacy.decode_event(transfer_event, data, topics) end) end,
    fn -> ABI.Event.decode_events(logs, transfer_event) end
  },
  "nested tuple/array encode" => {
    fn -> Legacy.encode(nested, nested_values) end,
    fn -> Alloy.encode(nested, nested_values) end
  }
}

Enum.each(workloads, fn {name, {old, alloy}} ->
  if old.() != alloy.(), do: raise("candidate output differs: #{name}")
end)

jobs =
  Map.new(
    for {name, {old, alloy}} <- workloads,
        {backend, fun} <- [{"old", old}, {"alloy", alloy}],
        do: {"#{name} / #{backend}", fun}
  )

compile_costs =
  Map.new(
    [
      {"ERC-20", transfer, :function},
      {"Transfer", transfer_event, :event},
      {"aggregate3", aggregate, :function},
      {"nested", nested, :function}
    ],
    fn {name, selector, kind} ->
      types =
        if kind == :event do
          {indexed, body} = Enum.split_with(selector.types, &Map.get(&1, :indexed, false))
          [%{type: {:tuple, [%{type: {:bytes, 32}} | indexed]}}, %{type: {:tuple, body}}]
        else
          selector.types
        end

      {microseconds, _} =
        :timer.tc(fn ->
          ABI.Native.compile(FunctionSelector.encode(%FunctionSelector{types: types}), <<>>)
        end)

      {name, %{one_time_compile_us: microseconds}}
    end
  )

suite = Benchee.run(jobs, time: 3, warmup: 1, memory_time: 1, print: [configuration: true])

measurements =
  Map.new(suite.scenarios, fn scenario ->
    {scenario.name,
     %{
       ips: scenario.run_time_data.statistics.ips,
       average_ns: scenario.run_time_data.statistics.average,
       memory_bytes: scenario.memory_usage_data.statistics.average
     }}
  end)

{indexed, body} = Enum.split_with(transfer_event.types, &Map.get(&1, :indexed, false))
event_types = [%{type: {:tuple, [%{type: {:bytes, 32}} | indexed]}}, %{type: {:tuple, body}}]
{event_data, event_topics} = hd(logs)

phases =
  Map.new(
    [
      {"ERC-20 transfer encode", :raw_encode, [%{type: {:tuple, transfer.types}}], {List.to_tuple(transfer_values)}},
      {"nested tuple/array encode", :raw_encode, [%{type: {:tuple, nested.types}}], {List.to_tuple(nested_values)}},
      {"aggregate3 decode (500 results)", :decode, aggregate.types, aggregate_payload},
      {"Transfer event decode (single log)", :event, event_types, {event_topics, event_data}}
    ],
    fn {name, operation, types, value} ->
      resource = ABI.Alloy.schema(types)

      samples =
        for _ <- 1..1000 do
          {:ok, {_result, {input, alloy, output}}} = ABI.Native.abi(:profile, resource, {operation, value})
          {input, alloy, output}
        end

      {name,
       %{
         term_decode_ns: Enum.sum_by(samples, &elem(&1, 0)) / 1000,
         alloy_ns: Enum.sum_by(samples, &elem(&1, 1)) / 1000,
         term_encode_ns: Enum.sum_by(samples, &elem(&1, 2)) / 1000
       }}
    end
  )

report = %{
  elixir: System.version(),
  otp: System.otp_release(),
  schedulers: System.schedulers_online(),
  measurements: measurements,
  compile_costs: compile_costs,
  native_phase_averages: phases,
  phase_note:
    "1000 instrumented calls; excludes Elixir validation/normalization/cache and scheduler handoff; alloy phase includes payload preflight.",
  cache: "warm; resource compilation and metadata cached per selector",
  memory_note: "Benchee measures BEAM process allocation, not Rust heap allocation."
}

File.write!("bench/results.json", Jason.encode!(report, pretty: true) <> "\n")

regressions =
  Enum.filter(Map.keys(workloads), fn name ->
    measurements["#{name} / alloy"].average_ns > 2 * measurements["#{name} / old"].average_ns
  end)

if regressions != [] do
  IO.puts(:stderr, "REPORT: exceeds 2x slowdown: #{Enum.join(regressions, ", ")}.")
  IO.puts("Benchmarks are reporting only; continue migration and report phase costs.")
end
