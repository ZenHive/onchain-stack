defmodule Onchain.Aerodrome.Bindings.LpSugarTest do
  use ExUnit.Case, async: true

  alias Onchain.ABI
  alias Onchain.Aerodrome.Bindings.Abi
  alias Onchain.Aerodrome.Bindings.LpSugar
  alias Onchain.Aerodrome.Fixtures
  alias Onchain.Aerodrome.Types.Lp
  alias Onchain.Aerodrome.Types.Position
  alias Onchain.Aerodrome.Types.Swap
  alias Onchain.Aerodrome.Types.Token
  alias Onchain.Aerodrome.TypesCase

  defmodule FixtureAdapter do
    @moduledoc false

    @spec run(Req.Request.t()) :: {Req.Request.t(), Req.Response.t()}
    def run(request) do
      reply = Req.Request.get_private(request, :lp_sugar_reply)
      reply.(request)
    end
  end

  @reads [
    {"all.page0", :all, Lp},
    {"all.page1", :all, Lp},
    {"all.tail", :all, Lp},
    {"all.filtered_short", :all, Lp},
    {"forSwaps", :for_swaps, Swap},
    {"positions.short", :positions, Position},
    {"positionsByFactory", :positions_by_factory, Position},
    {"positionsUnstakedConcentrated", :positions_unstaked_concentrated, Position},
    {"tokens", :tokens, Token}
  ]

  for {id, function, module} <- @reads do
    test "#{function} encodes the captured call and decodes #{id} positionally" do
      fixture = Fixtures.load("lp_sugar." <> unquote(id))
      assert {:ok, [raw_rows]} = Fixtures.decode(fixture)
      opts = fixture_opts(fixture)

      assert {:ok, rows} = apply(LpSugar, unquote(function), fixture["args"] ++ [opts])
      assert length(rows) == fixture["row_count"]

      for {raw, row} <- Enum.zip(raw_rows, rows) do
        assert row.__struct__ == unquote(module)
        TypesCase.assert_one_to_one(unquote(module), abi_target(fixture), raw, row)
      end
    end
  end

  test "count decodes the captured unfiltered pool count" do
    fixture = Fixtures.load("lp_sugar.count")
    assert {:ok, [expected]} = Fixtures.decode(fixture)
    assert {:ok, ^expected} = LpSugar.count(fixture_opts(fixture))
  end

  test "alm_estimate_amounts returns the three captured amounts as a tuple" do
    fixture = Fixtures.load("lp_sugar.almEstimateAmounts")
    assert {:ok, [[first, second, third]]} = Fixtures.decode(fixture)

    assert {:ok, {^first, ^second, ^third}} =
             apply(LpSugar, :alm_estimate_amounts, fixture["args"] ++ [fixture_opts(fixture)])
  end

  test "all_pages reaches count despite short and empty filtered pages" do
    {opts, count, short} = filtered_scan()
    [limit, 0, filter] = short["args"]
    assert {:ok, [raw]} = Fixtures.decode(short)
    assert length(raw) < limit
    assert {:ok, rows} = LpSugar.all_pages(filter, opts)

    offsets = Enum.to_list(0..(count - 1)//limit)
    assert_scan(offsets, limit, count)
    # The replay deliberately inserts an empty page after the captured short
    # page. Later offsets reuse its payload; they are not new live captures.
    expected_page = Enum.map(raw, &Lp.from_raw/1)
    assert rows == expected_page |> List.duplicate(length(offsets) - 1) |> Enum.concat()
  end

  test "naive stop-when-length(page)-is-less-than-limit UNDER-COUNTS the filtered fixture replay" do
    {opts, count, short} = filtered_scan()
    [limit, 0, filter] = short["args"]
    assert {:ok, complete} = LpSugar.all_pages(filter, opts)
    assert_scan(Enum.to_list(0..(count - 1)//limit), limit, count)

    {naive, final_offset} = naive_short_page_scan(limit, 0, filter, opts)
    assert length(naive) == short["row_count"]
    assert length(naive) < length(complete)
    assert final_offset < count
    assert_receive {:page, 0}
    refute_receive {:page, _offset}
  end

  test "positions enumeration continues past the captured empty short page" do
    fixture = Fixtures.load("lp_sugar.positions.short")
    [limit, 0, account] = fixture["args"]
    count = pool_count()
    assert fixture["row_count"] < limit
    later = position_response("positions")

    opts =
      scan_opts("positions", fn offset ->
        if offset == 0, do: fixture["response"], else: later
      end)

    assert {:ok, rows} = LpSugar.paginate(count, limit, &LpSugar.positions(limit, &1, account, opts))
    offsets = Enum.to_list(0..(count - 1)//limit)
    assert_scan(offsets, limit, count)
    assert length(rows) == length(offsets) - 1
    assert Enum.all?(rows, &match?(%Position{id: 42, tick_lower: -60}, &1))
  end

  test "nonempty position payloads decode through all three reads" do
    for {id, function} <- [
          {"positions.short", :positions},
          {"positionsByFactory", :positions_by_factory},
          {"positionsUnstakedConcentrated", :positions_unstaked_concentrated}
        ] do
      fixture = Fixtures.load("lp_sugar." <> id)
      fixture = Map.put(fixture, "response", position_response(fixture["function"]))

      assert {:ok, [%Position{} = position]} =
               apply(LpSugar, function, fixture["args"] ++ [fixture_opts(fixture)])

      TypesCase.assert_one_to_one(Position, abi_target(fixture), position_row(), position)
    end
  end

  test "pagination handles zero count, exact multiples, and preserves page order" do
    assert {:ok, []} = LpSugar.paginate(0, 500, fn _ -> flunk("zero count must not fetch") end)

    assert {:ok, [0, 1, 2, 3]} =
             LpSugar.paginate(4, 2, fn offset ->
               send(self(), {:page, offset})
               {:ok, [offset, offset + 1]}
             end)

    assert_scan([0, 2], 2, 4)
  end

  test "all_pages obeys an explicit smaller limit without changing the filter" do
    {opts, count, short} = filtered_scan(200)
    assert {:ok, _rows} = LpSugar.all_pages(List.last(short["args"]), Keyword.put(opts, :limit, 200))
    assert_scan(Enum.to_list(0..(count - 1)//200), 200, count)
  end

  test "invalid pagination limits fail before any RPC call" do
    for limit <- [0, -1, 501, 1.5, nil] do
      assert {:error, {:invalid_limit, ^limit}} = LpSugar.all_pages(0, limit: limit)
    end
  end

  test "count errors and later-page RPC errors propagate without partial success" do
    error = %{"code" => -32_000, "message" => "execution reverted"}
    opts = rpc_opts(fn _data -> %{"error" => error} end)
    assert {:error, {:rpc_error, %{code: -32_000}}} = LpSugar.all_pages(0, opts)

    short = Fixtures.load("lp_sugar.all.filtered_short")
    count = Fixtures.load("lp_sugar.count")

    opts =
      rpc_opts(fn
        "0x06661abd" ->
          %{"result" => count["response"]}

        data ->
          [_limit, offset, _filter] = arguments("all", data)
          send(self(), {:page, offset})
          if offset == 0, do: %{"result" => short["response"]}, else: %{"error" => error}
      end)

    assert {:error, {:rpc_error, %{code: -32_000}}} = LpSugar.all_pages(3, opts)
    assert_receive {:page, 0}
    assert_receive {:page, 500}
    refute_receive {:page, _offset}
  end

  test "malformed responses, unsupported networks, and bad addresses return tagged errors" do
    assert {:error, {:decode_error, _}} = LpSugar.count(rpc_opts(fn _ -> %{"result" => "0x01"} end))
    assert {:error, {:unsupported_network, :ethereum}} = LpSugar.count(network: :ethereum)
    assert {:error, {:invalid_address, _}} = LpSugar.positions(200, 0, "bad")
    assert {:error, {:invalid_address, _}} = LpSugar.positions_by_factory(200, 0, <<1::160>>, "bad")
    assert {:error, {:invalid_address, _}} = LpSugar.positions_unstaked_concentrated(200, 0, "bad")
    assert {:error, {:invalid_address, _}} = LpSugar.tokens(10, 0, <<1::160>>, ["bad"])
    assert {:error, {:invalid_address, _}} = LpSugar.alm_estimate_amounts("bad", 1, 1)
  end

  # The fixture's captured `signature` is the overload the eth_call actually
  # hit, so it is what the ABI entry must be resolved by.
  defp abi_target(fixture) do
    [name, args] =
      fixture
      |> Map.fetch!("signature")
      |> String.trim_trailing(")")
      |> String.split("(", parts: 2)

    assert name == fixture["function"]
    {"lp_sugar.json", name, input_types(args)}
  end

  defp input_types(""), do: []
  defp input_types(args), do: String.split(args, ",")

  defp fixture_opts(fixture) do
    rpc_opts(fn data ->
      assert String.downcase(data) == fixture["calldata"]
      %{"result" => fixture["response"]}
    end)
  end

  defp rpc_opts(reply) do
    block = Fixtures.manifest()["block_number"]
    address = Fixtures.load("lp_sugar.count")["address"]

    adapter = fn req ->
      request = req.body |> IO.iodata_to_binary() |> Jason.decode!()
      assert %{"method" => "eth_call", "params" => [call, block_hex]} = request
      assert String.downcase(call["to"]) == String.downcase(address)
      assert String.to_integer(String.replace_prefix(block_hex, "0x", ""), 16) == block
      response = Map.merge(%{"jsonrpc" => "2.0", "id" => request["id"]}, reply.(call["data"]))
      {req, Req.Response.new(status: 200, body: Jason.encode!(response))}
    end

    [
      rpc_url: "http://stub.invalid",
      block: block,
      req_options: [
        adapter: FixtureAdapter,
        plugins: [fn request -> Req.Request.put_private(request, :lp_sugar_reply, adapter) end]
      ]
    ]
  end

  defp filtered_scan(limit \\ 500) do
    short = Fixtures.load("lp_sugar.all.filtered_short")
    count = Fixtures.load("lp_sugar.count")
    filter = List.last(short["args"])

    opts =
      rpc_opts(fn
        "0x06661abd" ->
          %{"result" => count["response"]}

        data ->
          assert [^limit, offset, ^filter] = arguments("all", data)
          send(self(), {:page, offset})
          response = if offset == limit, do: encode_return("all", [[]]), else: short["response"]
          %{"result" => response}
      end)

    {opts, pool_count(), short}
  end

  defp scan_opts(function, page) do
    rpc_opts(fn data ->
      [_limit, offset | _args] = arguments(function, data)
      send(self(), {:page, offset})
      %{"result" => page.(offset)}
    end)
  end

  defp arguments(function, "0x" <> <<_selector::binary-size(8), payload::binary>>) do
    {:ok, signature} = Abi.signature("lp_sugar.json", function)
    types = String.replace_prefix(signature, function, "")
    assert {:ok, args} = ABI.decode_response(types, "0x" <> payload)
    args
  end

  defp assert_scan(offsets, limit, count) do
    for offset <- offsets, do: assert_receive({:page, ^offset})
    refute_receive {:page, _offset}
    assert List.last(offsets) < count
    assert List.last(offsets) + limit >= count
  end

  defp pool_count do
    {:ok, [count]} = Fixtures.decode(Fixtures.load("lp_sugar.count"))
    count
  end

  defp naive_short_page_scan(limit, offset, filter, opts) do
    {:ok, page} = LpSugar.all(limit, offset, filter, opts)

    if length(page) < limit do
      {page, offset + limit}
    else
      {rest, final_offset} = naive_short_page_scan(limit, offset + limit, filter, opts)
      {page ++ rest, final_offset}
    end
  end

  defp position_row do
    {42, <<1::160>>, 100, 10, 7, 8, 3, 4, 1, 2, 9, -60, 60, 1, 2, <<0::160>>, 0, <<0::160>>}
  end

  defp position_response(function), do: encode_return(function, [[position_row()]])

  defp encode_return(function, values) do
    {:ok, types} = Abi.return_type("lp_sugar.json", function)
    {:ok, "0x" <> <<_selector::binary-size(8), payload::binary>>} = ABI.encode_call("fixture" <> types, values)
    "0x" <> payload
  end
end
