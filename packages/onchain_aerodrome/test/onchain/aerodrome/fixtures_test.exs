defmodule Onchain.Aerodrome.FixturesTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias ABI.FunctionSelector
  alias Mix.Tasks.Aerodrome.CaptureFixtures
  alias Onchain.Aerodrome.Fixtures

  @abi_dir Application.app_dir(:onchain_aerodrome, "priv/abis")

  @required_functions %{
    "lp_sugar" =>
      ~w(all count forSwaps positions positionsByFactory positionsUnstakedConcentrated tokens almEstimateAmounts),
    "rewards_sugar" => ~w(epochsLatest epochsByAddress rewards rewardsByAddress forRoot),
    "ve_sugar" => ~w(all byAccount byId),
    "relay_sugar" => ~w(all registries),
    "token_sugar" => ~w(tokens safe_balance_of safe_decimals safe_symbol)
  }

  describe "committed fixtures" do
    test "manifest records the pinned Base block, chain, timestamp, and endpoint" do
      manifest = Fixtures.manifest()

      assert is_integer(manifest["block_number"]) and manifest["block_number"] > 0
      assert manifest["chain_id"] == 8453
      assert {:ok, %DateTime{}, _offset} = DateTime.from_iso8601(manifest["captured_at"])
      assert is_binary(manifest["rpc_endpoint"]) and manifest["rpc_endpoint"] != ""
      assert manifest["fixtures"] == Fixtures.ids()
    end

    test "every fixture file's recorded block matches the manifest" do
      block = Fixtures.manifest()["block_number"]

      for fixture <- Fixtures.load_all() do
        assert fixture["block_number"] == block, fixture["id"]
        refute fixture["block_number"] in ["latest", nil]
      end
    end

    test "fixtures cover every required Sugar read" do
      by_contract =
        Fixtures.load_all()
        |> Enum.group_by(& &1["contract"], & &1["function"])
        |> Map.new(fn {contract, functions} -> {contract, MapSet.new(functions)} end)

      for {contract, names} <- @required_functions do
        have = Map.get(by_contract, contract, MapSet.new())
        missing = MapSet.difference(MapSet.new(names), have)
        assert missing == MapSet.new(), "#{contract} missing #{inspect(MapSet.to_list(missing))}"
      end

      all_pages =
        Enum.filter(Fixtures.load_all(), fn fixture ->
          fixture["contract"] == "lp_sugar" and fixture["function"] == "all" and
            Enum.at(fixture["args"], 2) == 0
        end)

      assert match?([_, _ | _], all_pages)
    end

    test "one all(500, offset, non_zero_filter) page is shorter than 500 with pools remaining" do
      manifest = Fixtures.manifest()
      count = count_fixture()
      short = Fixtures.load("lp_sugar.all.filtered_short")

      assert short["function"] == "all"
      [limit, offset, filter] = short["args"]
      assert limit == 500
      assert filter > 0
      assert offset + limit < count
      assert short["block_number"] == manifest["block_number"]

      # The short page is proven from the committed hex, not from the recorded
      # `row_count` — a capture that mis-reported the count would otherwise
      # satisfy the very assertion task 8's pagination test depends on.
      assert {:ok, [rows]} = Fixtures.decode(short)
      assert length(rows) == short["row_count"]
      assert length(rows) < limit
    end

    test "positions short page is shorter than its limit with pools remaining past the offset" do
      count = count_fixture()
      fixture = Fixtures.load("lp_sugar.positions.short")

      assert fixture["function"] == "positions"
      [limit, offset, _account] = fixture["args"]
      assert offset + limit < count

      assert {:ok, [rows]} = Fixtures.decode(fixture)
      assert length(rows) == fixture["row_count"]
      assert length(rows) < limit
    end

    test "offline decode of every fixture succeeds" do
      for fixture <- Fixtures.load_all() do
        assert {:ok, _decoded} = Fixtures.decode(fixture), fixture["id"]
      end
    end

    test "captured Lp.type takes -1, 0, and positive values" do
      types =
        for fixture <- Fixtures.load_all(),
            fixture["contract"] == "lp_sugar",
            fixture["function"] == "all",
            {:ok, [rows]} <- [Fixtures.decode(fixture)],
            row <- rows,
            is_tuple(row) and tuple_size(row) > 4 do
          elem(row, 4)
        end

      assert -1 in types
      assert 0 in types
      assert Enum.any?(types, &(&1 > 0))
    end
  end

  describe "writer" do
    @tag :tmp_dir
    test "encode_json and write_files! are byte-identical across two runs", %{tmp_dir: dir} do
      manifest = %{
        "block_number" => 1,
        "chain_id" => 8453,
        "captured_at" => "2026-01-01T00:00:00Z",
        "rpc_endpoint" => "http://stub",
        "fixtures" => ["lp_sugar.count"]
      }

      fixture = %{
        "id" => "lp_sugar.count",
        "contract" => "lp_sugar",
        "address" => "0x69dD9db6d8f8E7d83887A704f447b1a584b599A1",
        "function" => "count",
        "signature" => "count()",
        "args" => [],
        "block_number" => 1,
        "calldata" => "0x06661abd",
        "response" => "0x" <> String.duplicate("0", 64)
      }

      a = Path.join(dir, "a")
      b = Path.join(dir, "b")
      CaptureFixtures.write_files!(a, manifest, [fixture])
      CaptureFixtures.write_files!(b, manifest, [fixture])

      assert_same_tree(a, b)
      assert CaptureFixtures.encode_json(manifest) == CaptureFixtures.encode_json(manifest)
    end
  end

  describe "nonempty decode witnesses" do
    test "the separate manifest pins real nonempty responses and their input selectors" do
      manifest = Fixtures.load("nonempty/manifest")
      assert manifest["chain_id"] == 8453
      assert manifest["block_number"] == 51_348_944
      assert manifest["rpc_endpoint"] == "https://mainnet.base.org"

      assert manifest["fixtures"] == ["lp_sugar.positions", "rewards_sugar.rewardsByAddress"]

      for id <- manifest["fixtures"] do
        fixture = Fixtures.load("nonempty/" <> id)
        assert fixture["block_number"] == manifest["block_number"]
        assert {:ok, [rows]} = Fixtures.decode(fixture)
        assert [_ | _] = rows
        assert length(rows) == fixture["row_count"]

        args =
          Enum.map(fixture["args"], fn
            "0x" <> _ = address -> Onchain.Hex.decode!(address)
            integer -> integer
          end)

        assert {:ok, data} = Onchain.ABI.encode_call(fixture["signature"], args)
        assert String.downcase(data) == fixture["calldata"]
      end
    end

    test "missing or invalid selectors fail before RPC" do
      assert_raise Mix.Error, ~r/--position-account/, fn ->
        CaptureFixtures.run(["--nonempty", "--block", "1"])
      end

      for {key, value, message} <- [
            {:position_account, "bad", ~r/--position-account/},
            {:position_offset, -1, ~r/--position-offset/},
            {:reward_venft_id, nil, ~r/--reward-venft-id/},
            {:reward_pool, "bad", ~r/--reward-pool/}
          ] do
        opts = "unused" |> nonempty_opts() |> Keyword.put(key, value)
        assert_raise Mix.Error, message, fn -> CaptureFixtures.capture(opts) end
      end
    end

    @tag :tmp_dir
    test "explicit selectors reproduce both fixtures without changing the original collection", %{tmp_dir: dir} do
      opts = nonempty_opts(dir)
      capture_io(fn -> assert :ok = CaptureFixtures.capture(opts) end)

      for id <- ["lp_sugar.positions", "rewards_sugar.rewardsByAddress"] do
        captured = dir |> Path.join(id <> ".json") |> File.read!() |> Jason.decode!()
        original = Fixtures.load("nonempty/" <> id)
        assert captured["args"] == original["args"]
        assert captured["response"] == original["response"]
        assert captured["row_count"] == original["row_count"]
      end

      assert {:ok, [[]]} = Fixtures.decode(Fixtures.load("lp_sugar.positions.short"))
      assert {:ok, [[]]} = Fixtures.decode(Fixtures.load("rewards_sugar.rewardsByAddress"))
    end

    @tag :tmp_dir
    test "either empty response rejects the whole capture before any file is written", %{tmp_dir: dir} do
      for function <- ["positions", "rewardsByAddress"] do
        out = Path.join(dir, function)
        opts = nonempty_opts(out)
        positive = Keyword.fetch!(opts, :eth_call)

        opts =
          Keyword.put(opts, :eth_call, fn contract, name, args, address, data, block ->
            if name == function do
              # ABI encoding of one empty dynamic array: offset then zero length.
              {:ok, Onchain.Hex.encode(<<32::256, 0::256>>)}
            else
              positive.(contract, name, args, address, data, block)
            end
          end)

        capture_io(fn ->
          assert_raise Mix.Error, ~r/returned no rows/, fn -> CaptureFixtures.capture(opts) end
        end)

        refute File.exists?(out)
      end
    end
  end

  describe "capture Mix task" do
    test "run/1 refuses a missing --block so latest cannot sneak in" do
      assert_raise Mix.Error, ~r/--block N is required/, fn ->
        CaptureFixtures.run([])
      end
    end

    test "the task lives under lib/mix/tasks/" do
      assert File.exists?(Path.join(File.cwd!(), "lib/mix/tasks/aerodrome.capture_fixtures.ex"))
    end

    @tag :tmp_dir
    test "two stubbed captures at the same block write byte-identical files", %{tmp_dir: dir} do
      opts = stub_opts(Path.join(dir, "first"))

      # The task narrates every call through `Mix.shell()`; capture_io/1 keeps
      # ~30 lines of stub chatter out of the gate output. Process-local, so it
      # stays safe under `async: true`.
      capture_io(fn ->
        assert :ok = CaptureFixtures.capture(opts)
        assert :ok = CaptureFixtures.capture(Keyword.put(opts, :out, Path.join(dir, "second")))
      end)

      assert_same_tree(Path.join(dir, "first"), Path.join(dir, "second"))

      manifest = dir |> Path.join("first/manifest.json") |> File.read!() |> Jason.decode!()
      assert manifest["block_number"] == 12_345_678
      assert manifest["chain_id"] == 8453
      assert manifest["captured_at"] == DateTime.to_iso8601(DateTime.from_unix!(1_700_000_000))
    end
  end

  defp count_fixture do
    assert {:ok, [count]} = Fixtures.decode(Fixtures.load("lp_sugar.count"))
    count
  end

  defp nonempty_opts(out) do
    [limit, offset, account] = Fixtures.load("nonempty/lp_sugar.positions")["args"]
    [venft_id, pool] = Fixtures.load("nonempty/rewards_sugar.rewardsByAddress")["args"]
    assert limit == 200

    out
    |> stub_opts()
    |> Keyword.merge(
      nonempty: true,
      position_account: account,
      position_offset: offset,
      reward_venft_id: venft_id,
      reward_pool: pool,
      eth_call: fn contract, function, args, _address, data, _block ->
        fixture = Fixtures.load("nonempty/#{contract}.#{function}")
        assert args == fixture["args"]
        assert data == fixture["calldata"]
        {:ok, fixture["response"]}
      end
    )
  end

  defp assert_same_tree(a, b) do
    files_a = a |> Path.join("*.json") |> Path.wildcard() |> Enum.map(&Path.basename/1) |> Enum.sort()
    files_b = b |> Path.join("*.json") |> Path.wildcard() |> Enum.map(&Path.basename/1) |> Enum.sort()
    assert files_a == files_b

    for name <- files_a do
      assert File.read!(Path.join(a, name)) == File.read!(Path.join(b, name)), name
    end
  end

  defp stub_opts(out) do
    [
      block: 12_345_678,
      rpc_url: "http://stub.invalid",
      out: out,
      chain_id: fn -> {:ok, 8453} end,
      get_block: fn 12_345_678 -> {:ok, %{timestamp: 1_700_000_000}} end,
      eth_call: fn contract, function, args, _address, _data, block ->
        assert is_integer(block) and block == 12_345_678
        {:ok, encode_stub(contract, function, args)}
      end
    ]
  end

  defp encode_stub(contract, function, args) do
    values = stub_values(contract, function, args)
    item = abi_function("#{contract}.json", function)
    selector = FunctionSelector.parse_specification_item(item)

    payload = ABI.encode(%{selector | function: "fixture", types: selector.returns}, values)
    <<_selector::binary-size(4), encoded::binary>> = payload
    Onchain.Hex.encode(encoded)
  end

  defp stub_values(:lp_sugar, "count", []), do: [2_500]

  defp stub_values(:lp_sugar, "all", [500, 0, 0]), do: [[lp_row(-1, <<10::160>>), lp_row(0, <<0::160>>)]]
  defp stub_values(:lp_sugar, "all", [500, 500, 0]), do: [[lp_row(100, <<0::160>>)]]
  defp stub_values(:lp_sugar, "all", [_limit, _offset, 0]), do: [[lp_row(50, <<0::160>>)]]
  defp stub_values(:lp_sugar, "all", [500, _offset, filter]) when filter > 0, do: [[lp_row(0, <<0::160>>)]]

  defp stub_values(:ve_sugar, "all", _) do
    nft = ve_nft(7, <<9::160>>)
    [[nft]]
  end

  defp stub_values(:ve_sugar, "byId", _), do: [ve_nft(7, <<9::160>>)]

  defp stub_values(contract, function, _args) do
    item = abi_function("#{contract}.json", function)
    selector = FunctionSelector.parse_specification_item(item)
    Enum.map(selector.returns, &sample/1)
  end

  defp lp_row(type, alm) do
    base = sample({:tuple, lp_tuple_types()})
    base |> put_elem(4, type) |> put_elem(30, alm)
  end

  defp ve_nft(id, account) do
    base = sample({:tuple, ve_tuple_types()})
    base |> put_elem(0, id) |> put_elem(1, account)
  end

  defp lp_tuple_types do
    [%{type: {:array, {:tuple, fields}}}] =
      "lp_sugar.json" |> abi_function("all") |> FunctionSelector.parse_specification_item() |> Map.fetch!(:returns)

    fields
  end

  defp ve_tuple_types do
    [%{type: {:array, {:tuple, fields}}}] =
      "ve_sugar.json" |> abi_function("all") |> FunctionSelector.parse_specification_item() |> Map.fetch!(:returns)

    fields
  end

  defp abi_function(file, name) do
    @abi_dir
    |> Path.join(file)
    |> File.read!()
    |> Jason.decode!()
    |> Enum.find(&(&1["type"] == "function" and &1["name"] == name))
  end

  defp sample(%{type: type}), do: sample(type)
  defp sample({:uint, _}), do: 1
  defp sample({:int, _}), do: -1
  defp sample(:address), do: <<1::160>>
  defp sample(:bool), do: true
  defp sample(:string), do: "Sugar"
  defp sample(:bytes), do: <<1, 2>>
  defp sample({:bytes, size}), do: :binary.copy(<<1>>, size)
  defp sample({:array, type}), do: [sample(type)]
  defp sample({:array, type, size}), do: List.duplicate(sample(type), size)
  defp sample({:tuple, types}), do: types |> Enum.map(&sample/1) |> List.to_tuple()
end
