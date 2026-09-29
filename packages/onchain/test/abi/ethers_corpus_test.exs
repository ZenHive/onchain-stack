defmodule ABI.EthersCorpusTest do
  @moduledoc """
  Independent-oracle assertions against the vendored
  `@ethersproject/testcases` corpus.

  Every expected byte string here was recorded by the ethers.js project from
  `solc`-compiled contract output. Nothing in this file is produced by
  hieroglyph, and no assertion round-trips through `decode(encode(x))` — a
  disagreement between this library and Solidity fails the run even when the
  library is perfectly self-consistent.

  The four corpus files cover four independent surfaces:

    * `contract-interface` / `contract-interface-abi2` — `ABI.encode/2` and
      `ABI.decode/3` against the contract's own returned ABI encoding
      (head/tail offsets, length words, padding, nested tuples and arrays).
    * `contract-signatures` — `ABI.method_id/1` against `solc`'s selector.
    * `contract-events` — `ABI.encode_event_topics/2`, the event `data`
      payload, and `ABI.decode_event/4` against real emitted logs.

  Provenance and filter criteria:
  `test/support/fixtures/ethers/PROVENANCE.md`.
  """

  use ExUnit.Case, async: true

  alias ABI.EthersCorpus, as: Corpus
  alias ABI.FunctionSelector

  # Every other assertion in this file is `assert compare(...) == []`, and
  # `compare/2` folds an empty corpus to `[]`. A fixture that was truncated,
  # emptied, or silently re-filtered would therefore pass every test in the
  # file while asserting nothing at all. PROVENANCE.md pins the exact vendored
  # counts; this pins them in the suite, so the oracle cannot go vacuous
  # without failing.
  describe "corpus integrity" do
    test "each vendored file holds the vector count PROVENANCE.md records" do
      counts =
        Map.new(
          ["contract-interface", "contract-interface-abi2", "contract-signatures", "contract-events"],
          &{&1, length(Corpus.load(&1))}
        )

      assert counts == %{
               "contract-interface" => 443,
               "contract-interface-abi2" => 368,
               "contract-signatures" => 376,
               "contract-events" => 414
             }
    end
  end

  describe "encode/2 against solc-recorded return data" do
    for corpus <- ["contract-interface", "contract-interface-abi2"] do
      test "#{corpus}: every vector encodes byte-for-byte" do
        assert compare(unquote(corpus), fn vector ->
                 encoded =
                   vector["types"]
                   |> Corpus.selector()
                   |> ABI.encode(args(vector))
                   |> Corpus.to_hex()

                 {encoded, vector["result"]}
               end) == []
      end

      test "#{corpus}: every vector decodes to the recorded arguments" do
        assert compare(unquote(corpus), fn vector ->
                 decoded =
                   vector["types"]
                   |> Corpus.decode_selector()
                   |> ABI.decode(Corpus.from_hex(vector["result"]))

                 {decoded, values(vector)}
               end) == []
      end
    end
  end

  describe "method_id/1 against solc-recorded selectors" do
    test "every signature hashes to the recorded 4-byte selector" do
      assert compare("contract-signatures", fn vector ->
               {Corpus.to_hex(ABI.method_id(vector["signature"])), vector["sigHash"]}
             end) == []
    end
  end

  describe "events against solc-emitted logs" do
    test "encode_event_topics/2 reproduces the emitted topic list" do
      assert compare("contract-events", fn vector ->
               topics =
                 vector["abi"]
                 |> FunctionSelector.parse_specification_item()
                 |> ABI.encode_event_topics(indexed_values(vector))
                 |> Enum.map(&Corpus.to_hex/1)

               {topics, vector["topics"]}
             end) == []
    end

    test "non-indexed parameters encode to the emitted log data" do
      assert compare("contract-events", fn vector ->
               {types, raw} = non_indexed(vector)

               data =
                 types
                 |> Corpus.selector()
                 |> ABI.encode(Corpus.args(types, raw))
                 |> Corpus.to_hex()

               {data, vector["data"]}
             end) == []
    end

    test "decode_event/4 recovers the emitted parameter values" do
      assert compare("contract-events", fn vector ->
               selector = FunctionSelector.parse_specification_item(vector["abi"])
               topics = Enum.map(vector["topics"], &Corpus.from_hex/1)
               data = Corpus.from_hex(vector["data"])

               {:ok, _name, decoded} = ABI.decode_event(selector, data, topics)

               {decoded, expected_decode(vector, topics)}
             end) == []
    end
  end

  # Runs `check` over every vector in `corpus` and returns only the
  # disagreements, so a failure names the offending vectors instead of
  # stopping at the first one.
  @spec compare(String.t(), (map() -> {term(), term()})) :: [map()]
  defp compare(corpus, check) do
    corpus
    |> Corpus.load()
    |> Enum.flat_map(fn vector ->
      case check.(vector) do
        {same, same} -> []
        {got, want} -> [%{name: vector["name"], got: got, want: want}]
      end
    end)
  end

  @spec args(map()) :: [tuple()]
  defp args(vector), do: Corpus.args(vector["types"], vector["values"])

  @spec values(map()) :: [term()]
  defp values(vector), do: Corpus.coerce_all(vector["types"], vector["values"])

  # A corpus vector marks non-indexed parameters with JSON `null` rather than
  # `false`, so truthiness — not `== true` — is the test.
  @spec parameters(map()) :: [{String.t(), term(), term(), boolean()}]
  defp parameters(vector) do
    Enum.zip([
      vector["types"],
      vector["values"],
      vector["indexed"],
      vector["hashed"]
    ])
  end

  @spec indexed_values(map()) :: [term()]
  defp indexed_values(vector) do
    vector
    |> parameters()
    |> Enum.filter(fn {_type, _value, indexed, _hashed} -> indexed end)
    |> Enum.map(fn {type, value, _indexed, _hashed} -> coerce(type, value) end)
  end

  @spec non_indexed(map()) :: {[String.t()], [term()]}
  defp non_indexed(vector) do
    vector
    |> parameters()
    |> Enum.reject(fn {_type, _value, indexed, _hashed} -> indexed end)
    |> Enum.map(fn {type, value, _indexed, _hashed} -> {type, value} end)
    |> Enum.unzip()
  end

  # The expected decode result, built from the corpus alone: an indexed
  # reference type survives in the log only as its topic hash, which
  # `ABI.decode_event/4` surfaces as `{:indexed_hash, topic}`.
  @spec expected_decode(map(), [binary()]) :: map()
  defp expected_decode(vector, topics) do
    indexed = if vector["abi"]["anonymous"], do: topics, else: tl(topics)

    {decoded, _rest} =
      vector
      |> parameters()
      |> Enum.map_reduce(indexed, &expected_value/2)

    vector["abi"]["inputs"]
    |> Enum.map(& &1["name"])
    |> Enum.zip(decoded)
    |> Map.new()
  end

  @spec expected_value({String.t(), term(), term(), boolean()}, [binary()]) ::
          {term(), [binary()]}
  defp expected_value({type, value, indexed, hashed}, topics) do
    cond do
      indexed && hashed -> {{:indexed_hash, hd(topics)}, tl(topics)}
      indexed -> {coerce(type, value), tl(topics)}
      true -> {coerce(type, value), topics}
    end
  end

  @spec coerce(String.t(), term()) :: term()
  defp coerce(type, value) do
    [%{type: parsed}] = Corpus.parse_types([type])

    Corpus.coerce(parsed, value)
  end
end
