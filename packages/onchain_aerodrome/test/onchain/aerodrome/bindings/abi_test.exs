defmodule Onchain.Aerodrome.Bindings.AbiTest do
  use ExUnit.Case, async: true

  alias ABI.FunctionSelector
  alias Onchain.Aerodrome.Bindings.Abi

  @abi_dir Application.app_dir(:onchain_aerodrome, "priv/abis")
  @files Path.wildcard(Path.join(@abi_dir, "*.json"))

  test "every captured function agrees with the independent JSON ABI parser and encoder" do
    assert Enum.count(@files) == 9

    for path <- @files,
        function <- path |> File.read!() |> Jason.decode!(),
        function["type"] == "function" do
      selector = FunctionSelector.parse_specification_item(function)
      independent_signature = FunctionSelector.encode(selector)
      file = Path.basename(path)

      assert {:ok, signature} = Abi.signature(file, independent_signature)
      assert signature == independent_signature

      params = Enum.map(selector.types, &sample/1)
      assert {:ok, "0x" <> calldata} = Onchain.ABI.encode_call(independent_signature, params)
      <<expected_selector::binary-size(8), _::binary>> = calldata
      <<actual_selector::binary-size(4), _::binary>> = ExKeccak.hash_256(signature)
      assert Base.encode16(actual_selector, case: :lower) == expected_selector

      assert {:ok, return_type} = Abi.return_type(file, independent_signature)
      assert return_type == FunctionSelector.encode(%FunctionSelector{types: selector.returns})

      # A named selector makes hieroglyph encode the outer argument tuple.
      payload =
        ABI.encode(
          %{selector | function: "fixture", types: selector.returns},
          Enum.map(selector.returns, &sample/1)
        )

      <<_selector::binary-size(4), encoded::binary>> = payload

      assert {:ok, _values} = Onchain.ABI.decode_response(return_type, Onchain.Hex.encode(encoded)),
             "#{file}: #{independent_signature}"
    end
  end

  test "deployed all uses three inputs and fixed arrays retain their sizes" do
    assert {:ok, "all(uint256,uint256,uint256)"} = Abi.signature("lp_sugar.json", "all")
    assert {:ok, "(uint256[3])"} = Abi.return_type("lp_sugar.json", "almEstimateAmounts")
    assert {:ok, "(address[3])"} = Abi.return_type("rewards_sugar.json", "forRoot")
  end

  test "unknown and overloaded lookups fail explicitly" do
    assert {:error, :unknown_file} = Abi.signature("missing.json", "all")
    assert {:error, :unknown_function} = Abi.return_type("lp_sugar.json", "missing")
    assert {:error, :ambiguous_function} = Abi.signature("pool_factory.json", "getPool")
    assert {:error, :ambiguous_function} = Abi.return_type("pool_factory.json", "getPool")

    assert {:ok, "getPool(address,address,bool)"} =
             Abi.signature("pool_factory.json", "getPool(address,address,bool)")
  end

  test "positional decode accepts the pinned live tick-zero golden response" do
    # priv/abis/README.md probe 11: getSqrtRatioAtTick(0) = 2^96.
    golden = "0x0000000000000000000000000000000000000001000000000000000000000000"
    assert {:ok, type} = Abi.return_type("slipstream_helper.json", "getSqrtRatioAtTick")

    assert {:ok, [79_228_162_514_264_337_593_543_950_336]} =
             Onchain.ABI.decode_response(type, golden)
  end

  test "named decoding raises for a field atom that has never been interned" do
    field = "aerodrome_uninterned_" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    assert_raise ArgumentError, fn -> String.to_existing_atom(field) end

    signature = "(uint256 " <> field <> ")"
    data = <<42::unsigned-size(256)>>
    assert [42] = ABI.decode(signature, data)
    assert {:ok, [42]} = Onchain.ABI.decode_response(signature, Onchain.Hex.encode(data))

    assert_raise ArgumentError, ~r/decode_structs: true requires/, fn ->
      ABI.decode(signature, data, decode_structs: true)
    end
  end

  @tag :tmp_dir
  @tag timeout: 120_000
  test "changing each captured external resource triggers Mix recompilation", %{tmp_dir: dir} do
    File.mkdir_p!(Path.join(dir, "lib/onchain/aerodrome/bindings"))
    File.mkdir_p!(Path.join(dir, "priv"))
    File.cp_r!(@abi_dir, Path.join(dir, "priv/abis"))

    File.cp!(
      Path.expand("../../../../lib/onchain/aerodrome/bindings/abi.ex", __DIR__),
      Path.join(dir, "lib/onchain/aerodrome/bindings/abi.ex")
    )

    File.write!(Path.join(dir, "mix.exs"), """
    defmodule AbiRecompileProbe.MixProject do
      use Mix.Project
      def project, do: [app: :onchain_aerodrome, version: "0.0.0"]
    end
    """)

    assert compile_probe(dir) =~ "Compiling 1 file"
    refute compile_probe(dir) =~ "Compiling 1 file"

    for path <- @files do
      resource = Path.join(dir, "priv/abis/" <> Path.basename(path))
      File.touch!(resource, System.os_time(:second) - 10)
      refute compile_probe(dir) =~ "Compiling 1 file"

      # Elixir 1.20 compares content digests; a timestamp-only touch is a no-op.
      File.write!(resource, File.read!(resource) <> "\n")
      assert compile_probe(dir) =~ "Compiling 1 file"
    end

    resources = :attributes |> Abi.__info__() |> Keyword.get_values(:external_resource) |> List.flatten()
    assert Enum.sort(resources) == Enum.sort(@files)
  end

  defp compile_probe(dir) do
    paths = ["-pa", Application.app_dir(:jason, "ebin")]

    {output, status} =
      System.cmd("elixir", paths ++ ["-S", "mix", "compile", "--no-deps-check", "--no-prune-code-paths"],
        cd: dir,
        env: [{"MIX_ENV", "test"}, {"ERL_FLAGS", "+S 2:2"}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    output
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
