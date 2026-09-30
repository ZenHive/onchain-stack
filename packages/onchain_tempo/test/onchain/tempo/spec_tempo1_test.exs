defmodule Onchain.Tempo.SpecTempo1Test do
  # Guards TEMPO-1: 0x76/0x78 encoding lives in the tempo-primitives crate, not in
  # hand-written Elixir. The scan walks the AST, so docs and doctest strings that
  # mention "0x76" or RLP never count; only code does.
  use ExUnit.Case, async: true

  @package_root Path.expand("../../..", __DIR__)

  # spec-tags: TEMPO-1
  describe "TEMPO-1 native encoding" do
    test "no Elixir source under lib/ builds RLP or a 0x76/0x78 envelope by hand" do
      files = Path.wildcard(Path.join(@package_root, "lib/**/*.ex"))
      assert files != []

      hits =
        for file <- files, hit <- encoding_hits(File.read!(file)) do
          "#{Path.relative_to(file, @package_root)}: #{hit}"
        end

      assert hits == []
    end

    test "the onchain_tempo crate exists and depends on tempo-primitives" do
      cargo = File.read!(Path.join(@package_root, "native/onchain_tempo/Cargo.toml"))

      assert cargo =~ ~r/^name\s*=\s*"onchain_tempo"/m
      assert cargo =~ ~r/^tempo-primitives\s*=/m
    end

    test "the scan trips on each forbidden shape (negative control)" do
      positives = [
        ~S|ExRLP.encode([1, 2])|,
        ~S|Some.RLP.encode(fields)|,
        ~S|<<0x76>> <> payload|,
        ~S|<<0x78, rest::binary>>|,
        ~S|<<118, rest::binary>>|,
        ~S|"0x76" <> Base.encode16(rlp)|,
        ~S|"0x78" <> hex|
      ]

      for source <- positives do
        assert encoding_hits(source) != [], "scan missed: #{source}"
      end
    end

    test "the scan ignores docs, doctests and plain hex strings" do
      source = ~S'''
      defmodule Doc do
        @doc """
            iex> deserialize("0x76" <> valid_rlp_hex)
        RLP-encoded 0x76 envelope, fee payer domain 0x78.
        """
        def type, do: %{"type" => "0x76"}
        def hex(bytes), do: "0x" <> Base.encode16(bytes)
      end
      '''

      assert encoding_hits(source) == []
    end
  end

  defp encoding_hits(source) do
    {:ok, ast} = Code.string_to_quoted(source)

    {_ast, hits} =
      Macro.prewalk(ast, [], fn node, acc ->
        case forbidden(node) do
          nil -> {node, acc}
          hit -> {node, [hit | acc]}
        end
      end)

    Enum.reverse(hits)
  end

  defp forbidden({{:., _, [{:__aliases__, _, parts}, fun]}, _, _}) do
    if Enum.any?(parts, &(&1 in [:ExRLP, :RLP])), do: "#{Enum.join(parts, ".")}.#{fun}"
  end

  defp forbidden({:<<>>, _, [first | _]}) do
    if envelope_byte?(first), do: "binary starting with a 0x76/0x78 type byte"
  end

  defp forbidden({:<>, _, [prefix, _]}) when prefix in ["0x76", "0x78"], do: "#{prefix} prefix concatenation"

  defp forbidden(_node), do: nil

  defp envelope_byte?({:"::", _, [value, _type]}), do: envelope_byte?(value)
  defp envelope_byte?(value), do: value in [0x76, 0x78]
end
