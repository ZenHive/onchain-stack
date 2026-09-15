defmodule Mix.Tasks.Aerodrome.CaptureFixtures do
  @shortdoc "Capture pinned-block Sugar eth_call fixtures"

  @moduledoc """
  Captures live `eth_call` response hex for every Sugar read at one pinned Base
  block and writes `test/fixtures/aerodrome/`.

  This is a **dev workflow**, not part of `mix ci`. The gate exercises the
  committed fixtures plus the offline loader with zero network.

  Every call is pinned with an explicit block number. `--block` is required: a
  capture at `latest` is not a fixture.

      mix aerodrome.capture_fixtures --block 36800000
      mix aerodrome.capture_fixtures --block 36800000 --rpc-url https://mainnet.base.org

  `BASE_RPC_URL` is used when `--rpc-url` is omitted, falling back to
  `https://mainnet.base.org`. `captured_at` is the block timestamp so two runs
  at the same block produce byte-identical files.
  """

  use Mix.Task

  alias Onchain.Aerodrome.Bindings.Abi
  alias Onchain.Aerodrome.Contracts

  @requirements ["app.start"]

  @chain_id 8453
  @default_rpc "https://mainnet.base.org"
  @default_out "test/fixtures/aerodrome"
  @zero "0x0000000000000000000000000000000000000000"
  @max_lps 500
  @max_positions 200
  @empty <<0::160>>

  @lp_token0 7
  @lp_token1 10
  @lp_factory 18
  @lp_alm 30
  @lp_root 31

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    args
    |> parse_cli!()
    |> capture()
  end

  @doc "Capture and write fixtures. Accepts `:block`, `:rpc_url`, `:out`, and RPC stubs."
  @spec capture(keyword()) :: :ok
  def capture(opts) do
    block = required_block!(opts)
    rpc_url = opts[:rpc_url] || System.get_env("BASE_RPC_URL") || @default_rpc
    out_dir = opts[:out] || @default_out
    ctx = context(opts, block, rpc_url, out_dir)

    Mix.shell().info("capturing Sugar fixtures at block #{block} via #{rpc_url}")

    ctx
    |> assert_chain!()
    |> put_captured_at!()
    |> capture_sugar()
    |> write!()
  end

  @doc "Pretty-print JSON with a trailing newline. Insertion-ordered maps stay stable."
  @spec encode_json(term()) :: String.t()
  def encode_json(term), do: Jason.encode!(term, pretty: true) <> "\n"

  @doc "Write `manifest.json` and one file per fixture into `dir`."
  @spec write_files!(Path.t(), map(), [map()]) :: :ok
  def write_files!(dir, manifest, fixtures) do
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "manifest.json"), encode_json(manifest))

    Enum.each(fixtures, fn fixture ->
      File.write!(Path.join(dir, fixture["id"] <> ".json"), encode_json(fixture))
    end)
  end

  defp parse_cli!(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args, strict: [block: :integer, rpc_url: :string, out: :string])

    if invalid != [] do
      Mix.raise("invalid arguments: #{inspect(invalid)}")
    end

    opts
  end

  defp required_block!(opts) do
    case Keyword.get(opts, :block) do
      block when is_integer(block) and block >= 0 ->
        block

      _other ->
        Mix.raise("--block N is required; a fixture captured at latest is not a fixture")
    end
  end

  defp context(opts, block, rpc_url, out_dir) do
    rpc_opts = [
      rpc_url: rpc_url,
      timeout: Keyword.get(opts, :timeout, 180_000),
      retry: false
    ]

    %{
      block: block,
      rpc_url: rpc_url,
      out_dir: out_dir,
      fixtures: [],
      lps: [],
      pool_count: nil,
      eth_call:
        Keyword.get(opts, :eth_call, fn _contract, _function, _args, address, data, pinned ->
          live_eth_call(address, data, pinned, rpc_opts)
        end),
      raw_call:
        Keyword.get(opts, :raw_call, fn address, data, pinned ->
          live_eth_call(address, data, pinned, rpc_opts)
        end),
      chain_id: Keyword.get(opts, :chain_id, fn -> Onchain.RPC.chain_id(rpc_opts) end),
      get_block: Keyword.get(opts, :get_block, fn n -> Onchain.RPC.get_block_by_number(n, rpc_opts) end)
    }
  end

  defp assert_chain!(ctx) do
    case ctx.chain_id.() do
      {:ok, @chain_id} ->
        ctx

      {:ok, other} ->
        Mix.raise("expected chain_id #{@chain_id} (Base), got #{inspect(other)}")

      {:error, reason} ->
        Mix.raise("eth_chainId failed: #{inspect(reason)}")
    end
  end

  defp put_captured_at!(ctx) do
    case ctx.get_block.(ctx.block) do
      {:ok, %{timestamp: ts}} when is_integer(ts) ->
        Map.put(ctx, :captured_at, DateTime.to_iso8601(DateTime.from_unix!(ts)))

      {:ok, other} ->
        Mix.raise("eth_getBlockByNumber #{ctx.block} missing timestamp: #{inspect(other)}")

      {:error, reason} ->
        Mix.raise("eth_getBlockByNumber #{ctx.block} failed: #{inspect(reason)}")
    end
  end

  defp capture_sugar(ctx) do
    ctx
    |> capture_lp_pages()
    |> capture_filtered_short!()
    |> capture_for_swaps()
    |> capture_ve()
    |> capture_positions!()
    |> capture_tokens()
    |> capture_alm!()
    |> capture_rewards()
    |> capture_relay()
    |> capture_token_safes()
  end

  defp capture_lp_pages(ctx) do
    {ctx, [count], _fixture} = record(ctx, "lp_sugar.count", :lp_sugar, "count", [])
    ctx = Map.put(ctx, :pool_count, count)

    {ctx, [page0], _} = record(ctx, "lp_sugar.all.page0", :lp_sugar, "all", [@max_lps, 0, 0])
    {ctx, [page1], _} = record(ctx, "lp_sugar.all.page1", :lp_sugar, "all", [@max_lps, @max_lps, 0])

    tail_offset = max(count - 50, 2 * @max_lps)
    {ctx, [tail], _} = record(ctx, "lp_sugar.all.tail", :lp_sugar, "all", [50, tail_offset, 0])

    Map.put(ctx, :lps, page0 ++ page1 ++ tail)
  end

  defp capture_filtered_short!(ctx) do
    limit = @max_lps

    case find_short_all(ctx, limit) do
      {offset, filter, hex, meta, n} ->
        Mix.shell().info("short all(#{limit}, #{offset}, #{filter}) -> #{n} rows")

        append_fixture(
          ctx,
          fixture(ctx, "lp_sugar.all.filtered_short", meta, hex, [limit, offset, filter], n)
        )

      nil ->
        Mix.raise(
          "no all(#{limit}, offset, non_zero_filter) page returned fewer than #{limit} rows with offset+limit < count (#{ctx.pool_count})"
        )
    end
  end

  defp find_short_all(ctx, limit) do
    Enum.find_value(search_offsets(ctx.pool_count, limit), &short_all_at_offset(ctx, limit, &1))
  end

  defp short_all_at_offset(ctx, limit, offset) do
    Enum.find_value([3, 2, 1, 5, 4], fn filter ->
      {hex, [rows], meta} = invoke(ctx, :lp_sugar, "all", [limit, offset, filter])
      n = Enum.count_until(rows, limit)
      if n < limit, do: {offset, filter, hex, meta, n}
    end)
  end

  defp capture_for_swaps(ctx) do
    {ctx, _decoded, _fixture} = record(ctx, "lp_sugar.forSwaps", :lp_sugar, "forSwaps", [50, 0])
    ctx
  end

  defp capture_ve(ctx) do
    {ctx, [nfts], _fixture} = record(ctx, "ve_sugar.all", :ve_sugar, "all", [10, 0])

    case nfts do
      [nft | _] when is_tuple(nft) and tuple_size(nft) >= 2 ->
        id = elem(nft, 0)
        account_hex = Onchain.Hex.encode(elem(nft, 1))

        ctx
        |> Map.merge(%{venft_id: id, account: account_hex})
        |> then(&elem(record(&1, "ve_sugar.byAccount", :ve_sugar, "byAccount", [account_hex]), 0))
        |> then(&elem(record(&1, "ve_sugar.byId", :ve_sugar, "byId", [id]), 0))

      _other ->
        Mix.raise("ve_sugar.all returned no NFTs; cannot derive byAccount/byId arguments")
    end
  end

  defp capture_positions!(ctx) do
    {ctx, [rows], _fixture} =
      record(ctx, "lp_sugar.positions.short", :lp_sugar, "positions", [@max_positions, 0, ctx.account])

    n = Enum.count_until(rows, @max_positions)

    ctx =
      if n < @max_positions and @max_positions < ctx.pool_count do
        Mix.shell().info("positions short page: #{n} < #{@max_positions}, pools remaining")
        ctx
      else
        Mix.raise(
          "positions(#{@max_positions}, 0, #{ctx.account}) returned #{n} rows; need row_count < limit with more pools past the offset (count=#{ctx.pool_count})"
        )
      end

    factory = lp_hex(ctx.lps, @lp_factory) || Contracts.address!(:pool_factory)

    {ctx, _decoded, _fixture} =
      record(ctx, "lp_sugar.positionsByFactory", :lp_sugar, "positionsByFactory", [
        @max_positions,
        0,
        ctx.account,
        factory
      ])

    {ctx, _decoded, _unstaked} =
      record(ctx, "lp_sugar.positionsUnstakedConcentrated", :lp_sugar, "positionsUnstakedConcentrated", [
        @max_positions,
        0,
        ctx.account
      ])

    ctx
  end

  defp capture_tokens(ctx) do
    token0 = lp_hex(ctx.lps, @lp_token0) || @zero
    token1 = lp_hex(ctx.lps, @lp_token1) || @zero
    args = [10, 0, ctx.account, [token0, token1]]
    ctx = Map.merge(ctx, %{token0: token0, token1: token1})

    {ctx, _decoded, _} = record(ctx, "lp_sugar.tokens", :lp_sugar, "tokens", args)
    {ctx, _decoded, _} = record(ctx, "token_sugar.tokens", :token_sugar, "tokens", args)
    ctx
  end

  defp capture_alm!(ctx) do
    wrapper = lp_hex(ctx.lps, @lp_alm) || discover_alm_wrapper(ctx)

    case wrapper do
      nil ->
        Mix.raise("no ALM wrapper from captured LPs or alm_core.managedPositionAt; cannot call almEstimateAmounts")

      wrapper ->
        {ctx, _decoded, _} =
          record(ctx, "lp_sugar.almEstimateAmounts", :lp_sugar, "almEstimateAmounts", [
            wrapper,
            1_000_000_000_000_000_000,
            1_000_000_000_000_000_000
          ])

        ctx
    end
  end

  defp discover_alm_wrapper(ctx) do
    Mix.shell().info("no ALM wrapper in first #{length(ctx.lps)} LPs; reading alm_core.managedPositionAt(1)")

    factory = Contracts.address!(:alm_factory)
    {:ok, core_call} = Onchain.ABI.encode_call("core()", [])

    with {:ok, core_hex} <- ctx.raw_call.(factory, core_call, ctx.block),
         {:ok, [core]} <- Onchain.ABI.decode_response("(address)", core_hex),
         {:ok, at_call} <- Onchain.ABI.encode_call("managedPositionAt(uint256)", [1]),
         {:ok, at_hex} <- ctx.raw_call.(Onchain.Hex.encode(core), at_call, ctx.block),
         {:ok, [pos]} <-
           Onchain.ABI.decode_response(
             "((uint32,uint24,address,address,uint256[],bytes,bytes,bytes))",
             at_hex
           ),
         owner when owner != @empty <- elem(pos, 2) do
      Onchain.Hex.encode(owner)
    else
      _other -> nil
    end
  end

  defp capture_rewards(ctx) do
    pool = lp_hex(ctx.lps, 0) || @zero
    root = lp_hex(ctx.lps, @lp_root) || pool

    {ctx, _decoded, _} = record(ctx, "rewards_sugar.epochsLatest", :rewards_sugar, "epochsLatest", [5, 0])

    {ctx, _decoded, _} =
      record(ctx, "rewards_sugar.epochsByAddress", :rewards_sugar, "epochsByAddress", [5, 0, pool])

    {ctx, _decoded, _} =
      record(ctx, "rewards_sugar.rewards", :rewards_sugar, "rewards", [10, 0, ctx.venft_id])

    {ctx, _decoded, _} =
      record(ctx, "rewards_sugar.rewardsByAddress", :rewards_sugar, "rewardsByAddress", [ctx.venft_id, pool])

    {ctx, _decoded, _} = record(ctx, "rewards_sugar.forRoot", :rewards_sugar, "forRoot", [root])
    ctx
  end

  defp capture_relay(ctx) do
    {ctx, _decoded, _} = record(ctx, "relay_sugar.all", :relay_sugar, "all", [ctx.account])
    {ctx, _decoded, _} = record(ctx, "relay_sugar.registries", :relay_sugar, "registries", [0])
    ctx
  end

  defp capture_token_safes(ctx) do
    token = ctx.token0
    {ctx, _decoded, _} = record(ctx, "token_sugar.safe_balance_of", :token_sugar, "safe_balance_of", [token, ctx.account])
    {ctx, _decoded, _} = record(ctx, "token_sugar.safe_decimals", :token_sugar, "safe_decimals", [token])
    {ctx, _decoded, _} = record(ctx, "token_sugar.safe_symbol", :token_sugar, "safe_symbol", [token])
    ctx
  end

  defp write!(ctx) do
    manifest = %{
      "block_number" => ctx.block,
      "chain_id" => @chain_id,
      "captured_at" => ctx.captured_at,
      "rpc_endpoint" => ctx.rpc_url,
      "fixtures" => Enum.map(ctx.fixtures, & &1["id"])
    }

    write_files!(ctx.out_dir, manifest, ctx.fixtures)
    Mix.shell().info("wrote #{length(ctx.fixtures)} fixtures + manifest to #{ctx.out_dir}")
    :ok
  end

  defp record(ctx, id, contract, function, args) do
    {hex, decoded, meta} = invoke(ctx, contract, function, args)
    fixture = fixture(ctx, id, meta, hex, args, row_count(decoded))
    {append_fixture(ctx, fixture), decoded, fixture}
  end

  defp invoke(ctx, contract, function, args) do
    address = Contracts.address!(contract)
    abi_file = "#{contract}.json"
    {:ok, signature} = Abi.signature(abi_file, function)
    {:ok, return_type} = Abi.return_type(abi_file, function)
    {:ok, calldata} = Onchain.ABI.encode_call(signature, Enum.map(args, &abi_arg/1))

    Mix.shell().info("#{id_hint(contract, function, args)} block=#{ctx.block}")

    hex =
      case ctx.eth_call.(contract, function, args, address, calldata, ctx.block) do
        {:ok, result} when is_binary(result) -> result
        {:error, reason} -> Mix.raise("eth_call #{signature} failed: #{inspect(reason)}")
      end

    decoded =
      case Onchain.ABI.decode_response(return_type, hex) do
        {:ok, values} -> values
        {:error, reason} -> Mix.raise("decode #{signature} failed: #{inspect(reason)}")
      end

    meta = %{
      address: address,
      signature: signature,
      calldata: calldata,
      contract: contract,
      function: function
    }

    {hex, decoded, meta}
  end

  defp fixture(ctx, id, meta, hex, args, rows) do
    [
      {"id", id},
      {"contract", Atom.to_string(meta.contract)},
      {"address", meta.address},
      {"function", meta.function},
      {"signature", meta.signature},
      {"args", args},
      {"block_number", ctx.block},
      {"calldata", meta.calldata},
      {"response", hex},
      {"row_count", rows}
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp append_fixture(ctx, fixture), do: %{ctx | fixtures: ctx.fixtures ++ [fixture]}

  defp row_count([rows]) when is_list(rows), do: length(rows)
  defp row_count(_decoded), do: nil

  defp abi_arg(n) when is_integer(n), do: n
  defp abi_arg(<<"0x", _::binary>> = hex), do: Onchain.Hex.decode!(hex)
  defp abi_arg(list) when is_list(list), do: Enum.map(list, &abi_arg/1)

  defp lp_hex(rows, index) do
    Enum.find_value(rows, fn
      row when is_tuple(row) and tuple_size(row) > index ->
        case elem(row, index) do
          @empty -> nil
          <<_::binary-size(20)>> = addr -> Onchain.Hex.encode(addr)
          _other -> nil
        end

      _other ->
        nil
    end)
  end

  defp search_offsets(count, limit) when is_integer(count) and count > limit do
    Enum.take(0..(count - limit - 1)//limit, 6)
  end

  defp search_offsets(_count, _limit), do: []

  defp id_hint(contract, function, args), do: "#{contract}.#{function}#{inspect(args)}"

  defp live_eth_call(address, data, block, rpc_opts) do
    retry_transient(
      fn -> Onchain.RPC.eth_call(address, data, Keyword.put(rpc_opts, :block, block)) end,
      8
    )
  end

  defp retry_transient(fun, attempts_left) do
    case fun.() do
      {:ok, _hex} = ok ->
        Process.sleep(400)
        ok

      {:error, reason} = err ->
        if attempts_left > 0 and transient_rpc?(reason) do
          Process.sleep((9 - attempts_left) * 2_000)
          retry_transient(fun, attempts_left - 1)
        else
          err
        end
    end
  end

  defp transient_rpc?({:rpc_error, %{status: status}}) when status in [429, 502, 503], do: true
  defp transient_rpc?({:rpc_error, %{code: -32_016}}), do: true
  defp transient_rpc?(_reason), do: false
end
