defmodule ABI.EthersCorpus do
  @moduledoc """
  Loader for the vendored `@ethersproject/testcases` vector corpus.

  The corpus is an **independent oracle**: every expected value in it was
  recorded from `solc`-compiled contract output by the ethers.js project, not
  produced by this library. Assertions built on it therefore fail when
  hieroglyph and Solidity disagree, which a `decode(encode(x)) == x` round trip
  cannot detect.

  Provenance, license, and the filter criteria that produced the vendored
  subset are recorded in `test/support/fixtures/ethers/PROVENANCE.md` and
  `docs/abi-verification-ledger.md`.

  ## Value shape

  Fixture values are plain JSON — integers as decimal strings, `bytesN` /
  `bytes` / `address` as `0x`-prefixed hex, `bool` as a JSON boolean, `string`
  as a JSON string, arrays and tuples as JSON arrays. `coerce/2` turns them
  into the Elixir terms `ABI.encode/2` expects, driven by the parsed Solidity
  type rather than by the JSON shape.
  """

  alias ABI.FunctionSelector

  @fixture_dir Path.join(__DIR__, "fixtures/ethers")

  @doc """
  Loads one vendored corpus file by base name (for example `"contract-events"`).
  """
  @spec load(String.t()) :: [map()]
  def load(name) do
    @fixture_dir
    |> Path.join(name <> ".json")
    |> File.read!()
    |> Jason.decode!()
  end

  @doc """
  Parses a list of corpus type strings into `ABI.FunctionSelector` argument maps.

  The corpus spells tuples as `tuple(a,b)`; hieroglyph's grammar spells them
  `(a,b)`. Nesting is handled by the plain textual rewrite because `tuple(`
  only ever appears immediately before a tuple's opening parenthesis.
  """
  @spec parse_types([String.t()]) :: [FunctionSelector.argument_type()]
  def parse_types(types) do
    arguments = Enum.map_join(types, ",", &String.replace(&1, "tuple(", "("))
    signature = "f(" <> arguments <> ")"

    %FunctionSelector{types: parsed} = FunctionSelector.decode(signature)

    parsed
  end

  @doc """
  Builds an unnamed, tuple-wrapped selector over the corpus types.

  The Solidity ABI spec encodes a function's argument list as the tuple of its
  arguments (`abi-spec.html#formal-specification-of-the-encoding`), so a
  top-level dynamic argument carries a head offset. `ABI.encode/2` reproduces
  that only when the types are wrapped in an explicit tuple — the bare
  `%FunctionSelector{function: nil, types: [...]}` form documented on
  `ABI.TypeEncoder.encode_raw/2` concatenates each type in place instead.

  Encoding against this selector produces the ABI encoding of the argument
  list with no 4-byte method ID, which is exactly what the corpus records in
  its `result` and event `data` fields.
  """
  @spec selector([String.t()]) :: FunctionSelector.t()
  def selector(types), do: %FunctionSelector{function: nil, types: [%{type: {:tuple, parse_types(types)}}]}

  @doc """
  Coerces a corpus vector's values into the single-tuple argument list that
  `selector/1` expects.
  """
  @spec args([String.t()], [term()]) :: [tuple()]
  def args(types, values), do: [List.to_tuple(coerce_all(types, values))]

  @doc """
  Builds the selector for the decode direction.

  `ABI.decode/3` wraps `function_selector.types` in the argument tuple itself,
  so the decode side takes the bare type list where `selector/1` (the encode
  side) takes it pre-wrapped.
  """
  @spec decode_selector([String.t()]) :: FunctionSelector.t()
  def decode_selector(types), do: %FunctionSelector{function: nil, types: parse_types(types)}

  @doc """
  Coerces one JSON corpus value into the Elixir term for `type`.

  Integers arrive as decimal strings in the `contract-interface` corpora and as
  ethers `BigNumber` hex strings (`"0x2a"`, `"-0x2a"`) in `contract-events`;
  both spellings are accepted.
  """
  @spec coerce(FunctionSelector.type(), term()) :: term()
  def coerce({:uint, _size}, value) when is_binary(value), do: to_integer(value)
  def coerce({:int, _size}, value) when is_binary(value), do: to_integer(value)
  def coerce(:bool, value) when is_boolean(value), do: value
  def coerce(:string, value) when is_binary(value), do: value
  def coerce(:bytes, value) when is_binary(value), do: from_hex(value)
  def coerce({:bytes, _size}, value) when is_binary(value), do: from_hex(value)
  def coerce(:address, value) when is_binary(value), do: from_hex(value)

  def coerce({:array, type}, values) when is_list(values), do: Enum.map(values, &coerce(type, &1))

  def coerce({:array, type, _count}, values) when is_list(values), do: Enum.map(values, &coerce(type, &1))

  def coerce({:tuple, types}, values) when is_list(values) do
    types
    |> Enum.zip(values)
    |> Enum.map(fn {%{type: type}, value} -> coerce(type, value) end)
    |> List.to_tuple()
  end

  @doc """
  Coerces a corpus vector's whole value list against its type list.
  """
  @spec coerce_all([String.t()], [term()]) :: [term()]
  def coerce_all(types, values) do
    types
    |> parse_types()
    |> Enum.zip(values)
    |> Enum.map(fn {%{type: type}, value} -> coerce(type, value) end)
  end

  @spec to_integer(String.t()) :: integer()
  defp to_integer("-0x" <> rest), do: -String.to_integer(rest, 16)
  defp to_integer("0x" <> rest), do: String.to_integer(rest, 16)
  defp to_integer(decimal), do: String.to_integer(decimal)

  @doc """
  Decodes a `0x`-prefixed corpus hex string into raw bytes.
  """
  @spec from_hex(String.t()) :: binary()
  def from_hex("0x" <> rest), do: Base.decode16!(rest, case: :mixed)

  @doc """
  Renders raw bytes as a `0x`-prefixed lowercase hex string.
  """
  @spec to_hex(binary()) :: String.t()
  def to_hex(bytes), do: "0x" <> Base.encode16(bytes, case: :lower)
end
