defmodule ABI do
  @moduledoc """
  Documentation for ABI, the function interface language for Solidity.
  Generally, the ABI describes how to take binary Ethereum and transform
  it to or from types that Solidity understands.

  ## Agent Discovery

  Use `ABI.describe/0..2` for progressive API discovery:

      ABI.describe()                    # Level 1: all annotated modules
      ABI.describe(:abi)                # Level 2: functions in this module
      ABI.describe(:abi, :encode)       # Level 3: full contract for encode/2

  A static `api_manifest.json` covering every public function is emitted by
  `mix descripex.manifest --app hieroglyph` (a dedicated `mix
  hieroglyph.manifest` wrapper ships in 1.2.0 alongside Phase 3 of the agent
  economy work — see CHANGELOG). Downstream consumers may diff that manifest
  across hieroglyph version bumps as a contract-stability check.
  """

  use Descripex, namespace: "/abi"

  use Descripex.Discoverable,
    modules: [
      ABI,
      ABI.Event,
      ABI.FunctionSelector,
      ABI.TypeEncoder,
      ABI.TypeDecoder,
      ABI.Math
    ]

  alias ABI.Event
  alias ABI.FunctionSelector
  alias ABI.Math
  alias ABI.Parser
  alias ABI.TypeDecoder
  alias ABI.TypeDecoder.StrictViolation
  alias ABI.TypeEncoder

  api(:encode, "Encodes the given data into the function signature or tuple signature.",
    params: [
      function_signature: [
        kind: :value,
        description:
          "Either a raw signature string (for example, transfer(address,uint256)) or a pre-parsed ABI.FunctionSelector struct."
      ],
      data: [
        kind: :value,
        description: "List of values to encode, in argument order. Tuples or maps are accepted for struct-typed args."
      ]
    ],
    returns: %{
      type: :binary,
      description:
        "ABI-encoded calldata. Selector-prefixed when the signature has a function name; raw payload otherwise (for example, tuple-only signatures used to encode return values)."
    }
  )

  @doc """
  Encodes the given data into the function signature or tuple signature.

  In place of a signature, you can also pass one of the `ABI.FunctionSelector` structs returned from `parse_specification/1`.

  ## Examples

      iex> ABI.encode("(uint256)", [{10}])
      ...> |> Base.encode16(case: :lower)
      "000000000000000000000000000000000000000000000000000000000000000a"

      iex> ABI.encode("baz(uint,address)", [50, <<1::160>>])
      ...> |> Base.encode16(case: :lower)
      "a291add600000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000001"

      iex> ABI.encode("price(string)", ["BAT"])
      ...> |> Base.encode16(case: :lower)
      "fe2c6198000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000034241540000000000000000000000000000000000000000000000000000000000"

      iex> ABI.encode("baz(uint8)", [9999])
      ** (RuntimeError) Data overflow encoding uint, data `9999` cannot fit in 8 bits

      iex> ABI.encode("(uint,address)", [{50, <<1::160>>}])
      ...> |> Base.encode16(case: :lower)
      "00000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000001"

      iex> ABI.encode("(string)", [{"Ether Token"}])
      ...> |> Base.encode16(case: :lower)
      "0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000b457468657220546f6b656e000000000000000000000000000000000000000000"

      iex> ABI.encode("((uint256,uint256),string)", [{{0x11, 0x22}, "Ether Token"}])
      ...> |> Base.encode16(case: :lower)
      "000000000000000000000000000000000000000000000000000000000000001100000000000000000000000000000000000000000000000000000000000000220000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000b457468657220546f6b656e000000000000000000000000000000000000000000"

      iex> ABI.encode("((uint256,(uint256,uint256)),string)", [{{0x11, {0x22, 0x33}}, "Ether Token"}])
      ...> |> Base.encode16(case: :lower)
      "0000000000000000000000000000000000000000000000000000000000000011000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000000000000000000000000330000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000b457468657220546f6b656e000000000000000000000000000000000000000000"

      iex> ABI.encode("(string)", [{String.duplicate("1234567890", 10)}])
      ...> |> Base.encode16(case: :lower)
      "000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000643132333435363738393031323334353637383930313233343536373839303132333435363738393031323334353637383930313233343536373839303132333435363738393031323334353637383930313233343536373839303132333435363738393000000000000000000000000000000000000000000000000000000000"

      iex> File.read!("priv/dog.abi.json")
      ...> |> Jason.decode!
      ...> |> ABI.parse_specification
      ...> |> Enum.find(&(&1.function == "bark")) # bark(address,bool)
      ...> |> ABI.encode([<<1::160>>, true])
      ...> |> Base.encode16(case: :lower)
      "b85d0bd200000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001"
  """
  @spec encode(binary() | FunctionSelector.t(), [any()]) :: binary()
  def encode(function_signature, data) when is_binary(function_signature) do
    encode(Parser.parse!(function_signature), data)
  end

  def encode(%FunctionSelector{} = function_selector, data) do
    TypeEncoder.encode(data, function_selector)
  end

  api(:encode_call, "Encodes args into selector-prefixed calldata for a named function.",
    params: [
      signature_or_selector: [
        kind: :value,
        description: "Either a raw signature string or a pre-parsed ABI.FunctionSelector struct."
      ],
      data: [
        kind: :value,
        description: "List of values to encode, in argument order."
      ],
      opts: [
        kind: :value,
        description: "Reserved keyword options; currently unused."
      ]
    ],
    returns: %{
      type: :binary,
      description: "Full calldata bytes: 4-byte method ID followed by ABI-encoded args."
    },
    composes_with: [:decode_call]
  )

  @doc """
  Encodes args into selector-prefixed calldata for a named function.

  This is the encode-side counterpart to `decode_call/3`: pass a signature or
  `ABI.FunctionSelector`, plus the argument list, and receive the full
  transaction calldata blob.

  ## Examples

      iex> ABI.encode_call("transfer(address,uint256)", [<<1::160>>, 100])
      ...> |> Base.encode16(case: :lower)
      "a9059cbb00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000064"

      iex> ABI.encode_call(%ABI.FunctionSelector{function: nil, types: []}, [])
      ** (ArgumentError) encode_call/3 requires a function name; use encode/2 for payload-only data
  """
  @spec encode_call(binary() | FunctionSelector.t(), [any()], keyword()) ::
          binary()
  def encode_call(signature_or_selector, data, opts \\ [])

  def encode_call(signature, data, opts) when is_binary(signature) do
    encode_call(FunctionSelector.decode(signature), data, opts)
  end

  def encode_call(%FunctionSelector{function: nil}, _data, _opts) do
    raise ArgumentError,
          "encode_call/3 requires a function name; use encode/2 for payload-only data"
  end

  def encode_call(%FunctionSelector{} = function_selector, data, _opts) do
    encode(function_selector, data)
  end

  api(
    :encode_constructor,
    "Encodes constructor arguments for contract deployment (no selector prefix).",
    params: [
      selector: [
        kind: :value,
        description:
          "A pre-parsed ABI.FunctionSelector with function_type: :constructor (constructors have no name, so no signature-string form is accepted). Typically obtained from parse_specification/1 by finding the :constructor entry."
      ],
      data: [
        kind: :value,
        description: "List of constructor argument values, in declaration order."
      ]
    ],
    returns: %{
      type: :binary,
      description:
        "ABI-encoded constructor args with NO 4-byte selector prefix. Concatenate contract_bytecode <> encoded_args to form deploy calldata. Empty-args constructors return the empty binary."
    },
    composes_with: [:decode, :parse_specification]
  )

  @doc """
  Encodes constructor arguments for contract deployment.

  Constructors have no selector — deploy calldata is `contract_bytecode <>
  encoded_args`, so this returns the ABI-encoded args with **no** 4-byte prefix
  (unlike `encode_call/3`). The caller concatenates the bytecode. Mirrors viem's
  `encodeDeployData`, scoped to just the args blob.

  Only accepts a `%ABI.FunctionSelector{function_type: :constructor}` — pass the
  `:constructor` entry from `parse_specification/1`. A non-constructor selector
  raises `ArgumentError`. Round-trips through `decode/3` against the
  constructor's parsed types.

  ## Examples

      iex> [selector] =
      ...>   ABI.parse_specification([%{
      ...>     "type" => "constructor",
      ...>     "stateMutability" => "nonpayable",
      ...>     "inputs" => [%{"name" => "supply", "type" => "uint256"}]
      ...>   }])
      iex> ABI.encode_constructor(selector, [1000])
      ...> |> Base.encode16(case: :lower)
      "00000000000000000000000000000000000000000000000000000000000003e8"

      iex> selector = %ABI.FunctionSelector{function_type: :constructor, types: []}
      iex> ABI.encode_constructor(selector, [])
      ""

      iex> selector = %ABI.FunctionSelector{function: "transfer", function_type: :function, types: []}
      iex> ABI.encode_constructor(selector, [])
      ** (ArgumentError) encode_constructor/2 requires a constructor selector (function_type: :constructor)
  """
  @spec encode_constructor(FunctionSelector.t(), [any()]) :: binary()
  def encode_constructor(selector, data)

  def encode_constructor(%FunctionSelector{function_type: :constructor} = selector, data) do
    TypeEncoder.encode_raw([List.to_tuple(data)], [%{type: {:tuple, selector.types}}])
  end

  def encode_constructor(%FunctionSelector{}, _data) do
    raise ArgumentError,
          "encode_constructor/2 requires a constructor selector (function_type: :constructor)"
  end

  api(:method_id, "Returns the 4-byte function selector (method ID) for a function signature.",
    params: [
      signature: [
        kind: :value,
        description:
          "Either a raw signature string (for example, transfer(address,uint256)) or a pre-parsed ABI.FunctionSelector struct."
      ]
    ],
    returns: %{
      type: :binary,
      description:
        "First 4 bytes of keccak256(canonical_signature). Returns the empty binary for selectors with function: nil (raw-tuple selectors used for return-value decoding)."
    },
    composes_with: [:encode, :decode_call]
  )

  @doc """
  Returns the 4-byte function selector (method ID) for a function signature.

  The selector is `keccak256(canonical_signature)` truncated to its first 4
  bytes. Returns `<<>>` for selectors with no `function` name (anonymous /
  raw-tuple selectors used for return-value decoding).

  ## Examples

      iex> ABI.method_id("transfer(address,uint256)") |> Base.encode16(case: :lower)
      "a9059cbb"

      iex> ABI.method_id("deposit()") |> Base.encode16(case: :lower)
      "d0e30db0"

      iex> ABI.method_id(%ABI.FunctionSelector{function: "deposit", types: []}) |> Base.encode16(case: :lower)
      "d0e30db0"

      iex> ABI.method_id(%ABI.FunctionSelector{function: nil, types: [%{type: {:uint, 256}}]})
      ""
  """
  @spec method_id(binary() | FunctionSelector.t()) :: binary()
  def method_id(signature) when is_binary(signature) do
    method_id(Parser.parse!(signature))
  end

  def method_id(%FunctionSelector{function: nil}), do: <<>>

  def method_id(%FunctionSelector{} = function_selector) do
    <<id::binary-size(4), _::binary>> =
      function_selector
      |> FunctionSelector.encode()
      |> Math.kec()

    id
  end

  api(:decode, "Decodes the given data based on the function or tuple signature.",
    params: [
      function_signature: [
        kind: :value,
        description: "Either a raw signature string or a pre-parsed ABI.FunctionSelector struct."
      ],
      data: [
        kind: :value,
        description:
          "ABI-encoded payload bytes (no 4-byte selector prefix). Use decode_call/3 for selector-prefixed calldata."
      ],
      opts: [
        kind: :value,
        description:
          "Keyword options. decode_structs: true returns a map keyed by snake_case atoms derived from parameter names instead of a list. strict: true rejects non-canonical padding, trailing bytes, and dynamic length overruns with {:error, {:strict_violation, detail}}. Field-name atoms must already exist in the VM atom table — reference them in your code (e.g., a module attribute or compile-time list) before calling, otherwise decode raises ArgumentError. This bounds atom creation to your declared field set."
      ]
    ],
    returns: %{
      type: :union,
      description:
        "List of decoded values in argument order; or a map keyed by snake_case field atoms when decode_structs: true is set and every parameter has a non-empty name."
    }
  )

  @doc """
  Decodes the given data based on the function or tuple
  signature.

  In place of a signature, you can also pass one of the `ABI.FunctionSelector` structs returned from `parse_specification/1`.

  ## Options

    * `:decode_structs` — when `true`, returns a map keyed by snake_case atoms
      derived from each parameter's name (instead of the default list).
      Field-name atoms must already exist in the VM atom table — `decode/3`
      calls `String.to_existing_atom/1` and raises `ArgumentError` when an
      atom has not been interned. See the README "Pre-interning atoms for
      `decode_structs: true`" section for the one-liner migration.
    * `:strict` — when `true`, rejects non-canonical bool/uint/int padding,
      trailing bytes after the declared payload, and string/bytes length
      prefixes that exceed the available data. Strict failures return
      `{:error, {:strict_violation, detail}}`.

  ## Examples

      iex> ABI.decode("baz(uint,address)", "00000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000001" |> Base.decode16!(case: :lower))
      [50, <<1::160>>]

      iex> ABI.decode("(address[])", "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000" |> Base.decode16!(case: :lower))
      [[]]

      iex> ABI.decode("(uint256)", "000000000000000000000000000000000000000000000000000000000000000a" |> Base.decode16!(case: :lower))
      [10]

      iex> ABI.decode("(string)", "0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000b457468657220546f6b656e000000000000000000000000000000000000000000" |> Base.decode16!(case: :lower))
      ["Ether Token"]

      iex> ABI.decode("((uint256,uint256),string)", "000000000000000000000000000000000000000000000000000000000000001100000000000000000000000000000000000000000000000000000000000000220000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000b457468657220546f6b656e000000000000000000000000000000000000000000" |> Base.decode16!(case: :lower))
      [{0x11, 0x22}, "Ether Token"]

      iex> ABI.decode("((uint256,(uint256,uint256)),string)", "0000000000000000000000000000000000000000000000000000000000000011000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000000000000000000000000330000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000b457468657220546f6b656e000000000000000000000000000000000000000000" |> Base.decode16!(case: :lower))
      [{0x11, {0x22, 0x33}}, "Ether Token"]

      iex> File.read!("priv/dog.abi.json")
      ...> |> Jason.decode!
      ...> |> ABI.parse_specification
      ...> |> Enum.find(&(&1.function == "bark")) # bark(address,bool)
      ...> |> ABI.decode("00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001" |> Base.decode16!(case: :lower))
      [<<1::160>>, true]

      iex> ABI.decode("(uint256 a,bool b)", "000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000001" |> Base.decode16!(case: :lower), decode_structs: true)
      %{a: 10, b: true}
  """
  @spec decode(binary() | FunctionSelector.t(), binary(), keyword()) ::
          [any()] | map() | {:error, {:strict_violation, term()}}
  def decode(function_signature, data, opts \\ [])

  def decode(function_signature, data, opts) when is_binary(function_signature) do
    decode(FunctionSelector.decode(function_signature), data, opts)
  end

  def decode(%FunctionSelector{} = function_selector, data, opts) do
    [res] = TypeDecoder.decode_raw(data, [%{type: {:tuple, function_selector.types}}], opts)

    if is_tuple(res) do
      Tuple.to_list(res)
    else
      res
    end
  rescue
    e in StrictViolation -> {:error, {:strict_violation, e.detail}}
  end

  api(
    :decode_call,
    "Decodes selector-prefixed calldata (4-byte method ID + ABI-encoded args) and verifies the selector matches.",
    params: [
      signature_or_selector: [
        kind: :value,
        description:
          "Either a raw signature string or a pre-parsed ABI.FunctionSelector struct. The first 4 bytes of calldata are checked against this selector."
      ],
      calldata: [
        kind: :value,
        description:
          "Full selector-prefixed calldata bytes. Must be at least 4 bytes; first 4 bytes are the method ID and the remainder is the ABI-encoded payload."
      ],
      opts: [
        kind: :value,
        description: "Keyword options forwarded to decode/3, including strict: true."
      ]
    ],
    returns: %{
      type: :tuple,
      description:
        "Tagged tuple. Selector match returns {:ok, decoded} where decoded matches decode/3's shape; selector errors return {:error, reason}. A malformed payload still raises (same contract as decode/3)."
    },
    errors: [
      calldata_too_short: "Fewer than 4 bytes provided.",
      selector_mismatch: "First 4 bytes do not match the expected selector.",
      no_function_name: "Selector has function: nil — there is no selector to verify against; use decode/3 directly.",
      strict_violation: "strict: true rejected a non-canonical payload."
    ],
    composes_with: [:decode, :method_id]
  )

  @doc """
  Decodes selector-prefixed calldata (4-byte method ID followed by ABI-encoded
  args) and verifies the prefix matches the expected selector.

  Symmetric counterpart to `encode/2`, which produces selector-prefixed
  output. Use `decode/2` for payload-only data (return values, or calldata
  that has already been routed by selector).

  Returns:

  * `{:ok, decoded}` — selector matched; `decoded` is the same shape `decode/3` returns
  * `{:error, :calldata_too_short}` — fewer than 4 bytes provided
  * `{:error, :selector_mismatch}` — first 4 bytes don't match the expected selector
  * `{:error, :no_function_name}` — the selector has `function: nil`, so there's no
    selector to verify against; use `decode/3` with the payload directly
  * `{:error, {:strict_violation, detail}}` — `strict: true` rejected a
    non-canonical payload

  > #### Note {: .info}
  >
  > Only the *selector* check is wrapped in `{:error, _}`. When the selector
  > matches but the payload is malformed (truncated or wrongly-typed bytes),
  > the underlying `decode/3` still raises — same contract as calling
  > `decode/3` directly.

  ## Examples

      iex> calldata = ABI.encode("transfer(address,uint256)", [<<1::160>>, 100])
      iex> ABI.decode_call("transfer(address,uint256)", calldata)
      {:ok, [<<1::160>>, 100]}

      iex> ABI.decode_call("deposit()", <<0xd0, 0xe3, 0x0d, 0xb0>>)
      {:ok, []}

      iex> ABI.decode_call("transfer(address,uint256)", <<0xde, 0xad, 0xbe, 0xef>>)
      {:error, :selector_mismatch}

      iex> ABI.decode_call("transfer(address,uint256)", <<0xa9, 0x05>>)
      {:error, :calldata_too_short}

      iex> ABI.decode_call(%ABI.FunctionSelector{function: nil, types: []}, <<0::32>>)
      {:error, :no_function_name}
  """
  @typep decode_call_error ::
           :calldata_too_short
           | :selector_mismatch
           | :no_function_name
           | {:strict_violation, term()}

  @spec decode_call(binary() | FunctionSelector.t(), binary(), keyword()) ::
          {:ok, [any()] | map()} | {:error, decode_call_error()}
  def decode_call(signature_or_selector, calldata, opts \\ [])

  def decode_call(signature, calldata, opts) when is_binary(signature) do
    decode_call(FunctionSelector.decode(signature), calldata, opts)
  end

  def decode_call(%FunctionSelector{function: nil}, _calldata, _opts) do
    {:error, :no_function_name}
  end

  def decode_call(%FunctionSelector{}, calldata, _opts) when byte_size(calldata) < 4 do
    {:error, :calldata_too_short}
  end

  def decode_call(%FunctionSelector{} = function_selector, calldata, opts) do
    expected = method_id(function_selector)
    <<actual::binary-size(4), payload::binary>> = calldata

    if actual == expected do
      case decode(function_selector, payload, opts) do
        {:error, {:strict_violation, _detail}} = error -> error
        decoded -> {:ok, decoded}
      end
    else
      {:error, :selector_mismatch}
    end
  end

  api(:encode_error, "Encodes args into selector-prefixed revert data for a named custom error.",
    params: [
      signature_or_selector: [
        kind: :value,
        description: "Either a raw signature string or a pre-parsed ABI.FunctionSelector struct."
      ],
      data: [
        kind: :value,
        description: "List of values to encode, in argument order."
      ],
      opts: [
        kind: :value,
        description: "Reserved keyword options; currently unused."
      ]
    ],
    returns: %{
      type: :binary,
      description: "Full revert data bytes: 4-byte error selector followed by ABI-encoded args."
    },
    composes_with: [:decode_error]
  )

  @doc """
  Encodes args into selector-prefixed revert data for a Solidity 0.8.4+ custom error.

  This is the encode-side counterpart to `decode_error/2`: pass an error signature or
  `ABI.FunctionSelector`, plus the argument list, and receive the full revert data blob.

  ## Examples

      iex> ABI.encode_error("InsufficientBalance(uint256,uint256)", [10, 100])
      ...> |> Base.encode16(case: :lower)
      "cf479181000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000064"

      iex> ABI.encode_error(%ABI.FunctionSelector{function: nil, types: []}, [])
      ** (ArgumentError) encode_error/3 requires a function name; use encode/2 for payload-only data
  """
  @spec encode_error(binary() | FunctionSelector.t(), [any()], keyword()) ::
          binary()
  def encode_error(signature_or_selector, data, opts \\ [])

  def encode_error(signature, data, opts) when is_binary(signature) do
    encode_error(FunctionSelector.decode(signature), data, opts)
  end

  def encode_error(%FunctionSelector{function: nil}, _data, _opts) do
    raise ArgumentError,
          "encode_error/3 requires a function name; use encode/2 for payload-only data"
  end

  def encode_error(%FunctionSelector{} = function_selector, data, _opts) do
    encode(function_selector, data)
  end

  api(
    :decode_error,
    "Decodes selector-prefixed revert data against known custom-error definitions, plus the Solidity built-in Error(string)/Panic(uint256) errors.",
    params: [
      revert_data: [
        kind: :value,
        description:
          "Selector-prefixed revert payload (4-byte error ID + ABI-encoded args), e.g. the data field returned by a Solidity 0.8.4+ custom-error revert."
      ],
      error_definitions: [
        kind: :value,
        description:
          "List of candidate error signatures, each either a raw signature string (\"InsufficientBalance(uint256,uint256)\") or a pre-parsed ABI.FunctionSelector. The first definition whose 4-byte selector matches revert_data[0..3] is used to decode the payload. The built-in Error(string) (0x08c379a0) and Panic(uint256) (0x4e487b71) errors are recognized implicitly as a fallback, so they resolve even when this list is empty; a user definition colliding with a built-in selector still wins."
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Keyword options forwarded to decode/3, including strict: true."
      ]
    ],
    returns: %{
      type: :tuple,
      description:
        "Tagged tuple. {:ok, %{error: name, args: decoded}} when a definition or built-in matches; {:error, reason} otherwise. A malformed payload after a selector match still raises (same contract as decode/3)."
    },
    errors: [
      calldata_too_short: "Fewer than 4 bytes provided.",
      no_match: "No definition or built-in selector matched revert_data[0..3].",
      strict_violation: "strict: true rejected a non-canonical payload."
    ],
    composes_with: [:decode, :method_id]
  )

  @doc """
  Decodes selector-prefixed revert data against a list of known custom-error
  definitions.

  Solidity 0.8.4 introduced
  [custom errors](https://soliditylang.org/blog/2021/04/21/custom-errors/);
  when a contract reverts with `revert MyError(arg1, arg2)`, the revert data is
  `keccak256("MyError(type1,type2)")[0..3] ++ abi.encode(arg1, arg2)` — exactly
  the same shape as a call's selector-prefixed calldata.

  This helper mirrors `decode_call/3` for that shape: try each candidate error
  signature against the revert's 4-byte prefix, decode the payload using
  whichever matches first.

  ## Built-in errors

  Every Solidity revert path emits one of two compiler-defined errors, so they
  are recognized implicitly — no caller needs to register them, and they resolve
  even when `error_definitions` is `[]`:

  * `Error(string)` — selector `0x08c379a0`. The standard `require`/`revert`
    reason string. Decodes to `%{error: "Error", args: [reason]}`.
  * `Panic(uint256)` — selector `0x4e487b71`. The 0.8.x `assert`/arithmetic
    panic. Decodes to `%{error: "Panic", args: [code]}`, where `code` is the
    integer panic code. The standard codes are:

    | Code   | Meaning                                                     |
    |--------|-------------------------------------------------------------|
    | `0x01` | `assert` evaluated to `false`                               |
    | `0x11` | arithmetic overflow or underflow                            |
    | `0x12` | division or modulo by zero                                  |
    | `0x32` | array access out of bounds                                  |

  A user-supplied definition whose selector collides with a built-in still wins:
  `error_definitions` is consulted first, and the built-ins are only a fallback.

  Mirrors viem's `decodeErrorResult`, which resolves `Error`/`Panic` implicitly.

  Returns:

  * `{:ok, %{error: name, args: decoded}}` — the first definition matching the
    4-byte selector, or a built-in error when none does. `name` is the error's
    function name; `decoded` matches `decode/3`'s shape (a list of args)
  * `{:error, :calldata_too_short}` — fewer than 4 bytes provided
  * `{:error, :no_match}` — no definition or built-in selector matched
  * `{:error, {:strict_violation, detail}}` — `strict: true` rejected a
    non-canonical payload

  > #### Note {: .info}
  >
  > Only the *selector* match is wrapped in `{:error, _}`. When a selector
  > matches but the payload is malformed, the underlying `decode/3` still
  > raises — same contract as `decode_call/3`.

  ## Examples

      iex> revert_data = ABI.encode("InsufficientBalance(uint256,uint256)", [10, 100])
      iex> ABI.decode_error(revert_data, ["InsufficientBalance(uint256,uint256)"])
      {:ok, %{error: "InsufficientBalance", args: [10, 100]}}

      iex> revert_data = ABI.encode("Unauthorized(address)", [<<1::160>>])
      iex> ABI.decode_error(revert_data, [
      ...>   "InsufficientBalance(uint256,uint256)",
      ...>   "Unauthorized(address)"
      ...> ])
      {:ok, %{error: "Unauthorized", args: [<<1::160>>]}}

      iex> revert_data = ABI.encode("Error(string)", ["insufficient balance"])
      iex> ABI.decode_error(revert_data, [])
      {:ok, %{error: "Error", args: ["insufficient balance"]}}

      iex> revert_data = ABI.encode("Panic(uint256)", [0x11])
      iex> ABI.decode_error(revert_data, [])
      {:ok, %{error: "Panic", args: [17]}}

      iex> ABI.decode_error(<<0xde, 0xad, 0xbe, 0xef>>, ["NotFound()"])
      {:error, :no_match}

      iex> ABI.decode_error(<<0xa9, 0x05>>, ["NotFound()"])
      {:error, :calldata_too_short}
  """
  @typep decode_error_error ::
           :calldata_too_short | :no_match | {:strict_violation, term()}

  # Compiler-defined Solidity errors, recognized implicitly. Selectors are the
  # first 4 bytes of keccak256 of the canonical signature.
  @built_in_errors %{
    <<0x08, 0xC3, 0x79, 0xA0>> => "Error(string)",
    <<0x4E, 0x48, 0x7B, 0x71>> => "Panic(uint256)"
  }

  @spec decode_error(binary(), [binary() | FunctionSelector.t()], keyword()) ::
          {:ok, %{error: String.t() | nil, args: [any()] | map()}}
          | {:error, decode_error_error()}
  def decode_error(revert_data, error_definitions, opts \\ [])

  def decode_error(revert_data, _error_definitions, _opts) when byte_size(revert_data) < 4 do
    {:error, :calldata_too_short}
  end

  def decode_error(revert_data, error_definitions, opts) when is_list(error_definitions) do
    <<actual::binary-size(4), payload::binary>> = revert_data

    selectors = Enum.map(error_definitions, &normalize_error_definition/1)

    case Enum.find(selectors, fn sel -> method_id(sel) == actual end) do
      nil ->
        decode_built_in_error(actual, payload, opts)

      %FunctionSelector{} = sel ->
        decode_error_args(sel, payload, opts)
    end
  end

  @spec decode_error_args(FunctionSelector.t(), binary(), keyword()) ::
          {:ok, %{error: String.t() | nil, args: [any()] | map()}}
          | {:error, {:strict_violation, term()}}
  defp decode_error_args(sel, payload, opts) do
    case decode(sel, payload, opts) do
      {:error, {:strict_violation, _detail}} = error -> error
      decoded -> {:ok, %{error: sel.function, args: decoded}}
    end
  end

  # Falls back to the compiler-defined Error(string)/Panic(uint256) errors when
  # no user definition matched. Only reached after error_definitions misses, so
  # a colliding user definition always wins.
  @spec decode_built_in_error(binary(), binary(), keyword()) ::
          {:ok, %{error: String.t(), args: [any()]}}
          | {:error, :no_match | {:strict_violation, term()}}
  defp decode_built_in_error(actual, payload, opts) do
    case @built_in_errors do
      %{^actual => signature} ->
        sel = Parser.parse!(signature)
        decode_error_args(sel, payload, opts)

      _ ->
        {:error, :no_match}
    end
  end

  # An error definition: a signature string or a pre-parsed selector.
  @typep error_definition :: String.t() | FunctionSelector.t()

  @spec normalize_error_definition(error_definition()) :: FunctionSelector.t()
  defp normalize_error_definition(sig) when is_binary(sig), do: Parser.parse!(sig)
  defp normalize_error_definition(%FunctionSelector{} = sel), do: sel

  api(
    :encode_packed,
    "Encodes values using Solidity's non-standard packed mode (abi.encodePacked).",
    params: [
      signature_or_selector: [
        kind: :value,
        description:
          ~s{Signature string with a function name (e.g. "leaf(address,uint256)") or a pre-parsed FunctionSelector. The name is ignored in packed mode but is required by the parser to flatten the type list. Paren-only signatures like "(address,uint256)" parse as a single struct argument and raise per the spec.}
      ],
      values: [
        kind: :value,
        description:
          "List of values in argument order. Tuple/struct types and nested arrays raise ArgumentError — Solidity's spec does not define their packed encoding."
      ]
    ],
    returns: %{
      type: :binary,
      description:
        "Tightly-packed bytes per the Solidity spec — types <32 bytes concatenated without padding, dynamic types in-place without length prefix, array elements padded to 32 bytes. Never selector-prefixed; not decodable (the spec is ambiguous in the presence of multiple dynamic args)."
    },
    composes_with: [:method_id]
  )

  @doc """
  Encodes a list of values using Solidity's
  [non-standard packed mode](https://docs.soliditylang.org/en/stable/abi-spec.html#non-standard-packed-mode).

  Used primarily for `keccak256(abi.encodePacked(...))` Merkle leaves and
  signature schemes; never used for actual function calls (the spec defines
  no decoding function — encoding is ambiguous with multiple dynamic args).

  Tuple/struct values and nested arrays raise `ArgumentError` — the spec
  does not define their packed encoding.

  > #### Warning {: .warning}
  >
  > If both `a` and `b` are dynamic types, `abi.encodePacked(a, b)` is
  > ambiguous: `abi.encodePacked("a", "bc") == abi.encodePacked("ab", "c")`.
  > Do not feed multiple dynamic args into packed-mode signature schemes
  > without controlling for that collision.

  ## Examples

      iex> ABI.encode_packed("foo(int16,bytes1,uint16,string)", [-1, <<0x42>>, 3, "Hello, world!"])
      ...> |> Base.encode16(case: :lower)
      "ffff42000348656c6c6f2c20776f726c6421"

      iex> ABI.encode_packed("leaf(address,uint256)", [<<1::160>>, 100])
      ...> |> Base.encode16(case: :lower)
      "00000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000064"

      iex> ABI.encode_packed("foo(uint8[])", [[1, 2, 3]])
      ...> |> Base.encode16(case: :lower)
      "000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000003"
  """
  @spec encode_packed(binary() | FunctionSelector.t(), [any()]) :: binary()
  def encode_packed(signature_or_selector, values)

  def encode_packed(signature, values) when is_binary(signature) do
    encode_packed(Parser.parse!(signature), values)
  end

  def encode_packed(%FunctionSelector{types: types}, values) do
    TypeEncoder.encode_packed(values, types)
  end

  api(:decode_event, "Decodes an event from raw log data and indexed topics.",
    params: [
      function_signature: [
        kind: :value,
        description: "Either a raw event signature string or a pre-parsed ABI.FunctionSelector struct."
      ],
      data: [
        kind: :value,
        description: "Non-indexed event data — the data field of the Ethereum log."
      ],
      topics: [
        kind: :value,
        description:
          "List of 32-byte topic hashes (the topics field of the log). topics[0] is verified against the event signature unless check_event_signature: false is passed."
      ],
      opts: [
        kind: :value,
        description:
          "Keyword options. check_event_signature: false skips the topics[0] verification (useful when topics[0] has already been stripped)."
      ]
    ],
    returns: %{
      type: :tuple,
      description:
        "Tagged tuple. {:ok, event_name, args_map} on success; {:error, reason} on signature mismatch, topic-count mismatch, or malformed non-indexed payload. Indexed reference-type params decode as {:indexed_hash, <<32 bytes>>} per the Solidity spec."
    },
    errors: [
      event_signature_mismatch:
        "topics[0] did not match keccak256(canonical_signature). Payload: %{expected: <<32 bytes>>, got: <<32 bytes>>}.",
      topics_length_mismatch:
        "Number of topics did not match the indexed-parameter count (plus the implicit topics[0] slot when check_event_signature: true). Payload: %{got: integer, expected: integer}.",
      malformed_data:
        "Non-indexed payload failed to decode (truncated, wrong types, or otherwise inconsistent with function_selector.types). Payload: human-readable message string."
    ],
    composes_with: [:event_signature]
  )

  @doc """
  Decodes an event, including indexed and non-indexed data.

  Returns:

  * `{:ok, event_name, args_map}` on success
  * `{:error, {:event_signature_mismatch, %{expected: _, got: _}}}` — `topics[0]` did
    not match `keccak256(canonical_signature)`
  * `{:error, {:topics_length_mismatch, %{got: _, expected: _}}}` — topic count did not
    match the indexed-parameter count (plus the implicit `topics[0]` slot when
    `check_event_signature: true`)
  * `{:error, {:malformed_data, message}}` — non-indexed payload failed to decode
    (truncated, wrong types, or otherwise inconsistent with `function_selector.types`)

  ## Examples

      iex> ABI.decode_event(
      ...>   "Transfer(address indexed from, address indexed to, uint256 amount)",
      ...>   ~h[0x00000000000000000000000000000000000000000000000000000004a817c800],
      ...>   [
      ...>     ~h[0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef],
      ...>     ~h[0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
      ...>     ~h[0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea]
      ...>   ]
      ...> )
      {:ok,
        "Transfer", %{
          "amount" => 20000000000,
          "from" => ~h[0xb2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
          "to" => ~h[0x7795126b3ae468f44c901287de98594198ce38ea]
      }}

      iex> ABI.decode_event(
      ...>   "Transfer(address indexed from, address indexed to, uint256 amount)",
      ...>   ~h[0x00000000000000000000000000000000000000000000000000000004a817c800],
      ...>   [
      ...>     ~h[0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
      ...>     ~h[0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea]
      ...>   ],
      ...>   check_event_signature: false
      ...> )
      {:ok,
        "Transfer", %{
          "amount" => 20000000000,
          "from" => ~h[0xb2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
          "to" => ~h[0x7795126b3ae468f44c901287de98594198ce38ea]
      }}

      iex> ABI.decode_event(
      ...>   %ABI.FunctionSelector{
      ...>     function: "Transfer",
      ...>     types: [
      ...>       %{type: :address, name: "from", indexed: true},
      ...>       %{type: :address, name: "to", indexed: true},
      ...>       %{type: {:uint, 256}, name: "amount"},
      ...>     ]
      ...>   },
      ...>   ~h[0x00000000000000000000000000000000000000000000000000000004a817c800],
      ...>   [
      ...>     ~h[0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef],
      ...>     ~h[0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
      ...>     ~h[0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea]
      ...>   ]
      ...> )
      {:ok,
        "Transfer", %{
          "amount" => 20000000000,
          "from" => ~h[0xb2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
          "to" => ~h[0x7795126b3ae468f44c901287de98594198ce38ea]
      }}
  """
  @spec decode_event(
          binary() | FunctionSelector.t(),
          binary(),
          [binary()],
          keyword()
        ) :: {:ok, String.t() | nil, map()} | {:error, Event.decode_error()}
  def decode_event(function_signature, data, topics, opts \\ [])

  def decode_event(function_signature, data, topics, opts) when is_binary(function_signature) do
    decode_event(FunctionSelector.decode(function_signature), data, topics, opts)
  end

  def decode_event(%FunctionSelector{} = function_selector, data, topics, opts) do
    Event.decode_event(data, topics, function_selector, opts)
  end

  api(:encode_event_topics, "Builds an eth_getLogs topic filter list from an event signature and indexed values.",
    params: [
      function_signature: [
        kind: :value,
        description: "Either a raw event signature string or a pre-parsed ABI.FunctionSelector struct."
      ],
      indexed_values: [
        kind: :value,
        description: "Prefix list of indexed argument values in event order. Use :any to leave a topic slot unfiltered."
      ]
    ],
    returns: %{
      type: :list,
      description:
        "Topic filter list for eth_getLogs. Non-anonymous events include topics[0] = event_signature/1; anonymous events parsed from JSON ABI omit that slot."
    },
    composes_with: [:decode_event, :event_signature]
  )

  @doc """
  Builds an `eth_getLogs` topic filter list for indexed event arguments.

  Pass indexed argument values in event order. Use `:any` for an unfiltered
  indexed slot. Indexed value types encode as 32-byte topics; indexed
  reference types encode as `keccak256` hashes of their in-place event
  encoding.

  ## Examples

      iex> ABI.encode_event_topics(
      ...>   "Transfer(address indexed from,address indexed to,uint256 amount)",
      ...>   [~h[0xb2b7c1795f19fbc28fda77a95e59edbb8b3709c8], :any]
      ...> )
      [
        ~h[0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef],
        ~h[0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
        :any
      ]
  """
  @spec encode_event_topics(binary() | FunctionSelector.t(), [any() | :any]) ::
          [binary() | :any]
  def encode_event_topics(function_signature, indexed_values) when is_binary(function_signature) do
    encode_event_topics(FunctionSelector.decode(function_signature), indexed_values)
  end

  def encode_event_topics(%FunctionSelector{} = function_selector, indexed_values) do
    Event.encode_event_topics(function_selector, indexed_values)
  end

  api(:event_signature, "Returns the 32-byte topic hash for an event signature.",
    params: [
      function_signature: [
        kind: :value,
        description: "Either a raw event signature string or a pre-parsed ABI.FunctionSelector struct."
      ]
    ],
    returns: %{
      type: :binary,
      description: "32-byte keccak256(canonical_event_signature). On Ethereum logs this is the topics[0] hash."
    },
    composes_with: [:decode_event]
  )

  @doc """
  Returns the signature for an event.

  ## Examples

      iex> ABI.event_signature("Transfer(address indexed from, address indexed to, uint256 amount)")
      ...> |> Base.encode16(case: :lower)
      "ddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
  """
  @spec event_signature(binary() | FunctionSelector.t()) :: binary()
  def event_signature(function_signature) when is_binary(function_signature) do
    event_signature(FunctionSelector.decode(function_signature))
  end

  def event_signature(%FunctionSelector{} = function_selector) do
    Event.event_signature(function_selector)
  end

  api(
    :format_abi_item,
    "Renders a FunctionSelector as its canonical Solidity signature string.",
    params: [
      function_selector: [
        kind: :value,
        description:
          "A pre-parsed ABI.FunctionSelector struct — a function, error, event, or anonymous (constructor/fallback) fragment."
      ]
    ],
    returns: %{
      type: :string,
      description:
        "Canonical \"name(type1,type2,...)\" string. Tuple types expand to parenthesized member lists ((uint256,address)) and arrays render with []/[N] suffixes. Anonymous fragments (function: nil) format without a leading name."
    },
    composes_with: [:parse_specification, :method_id, :event_signature]
  )

  @doc """
  Renders an `ABI.FunctionSelector` as its canonical Solidity signature string.

  This is the general-purpose formatter behind `method_id/1` and
  `event_signature/1` (both hash this exact string): it reuses
  `ABI.FunctionSelector.encode/1` — the shared sig-builder — so the formatted
  output can never drift from what gets hashed. First consumers are the
  `api_manifest.json` CI artifact and error/log messages that would otherwise
  inspect raw structs.

  Tuple types expand to parenthesized member lists (`(uint256,address)`) and
  arrays render with `[]` / `[N]` suffixes. Anonymous fragments (constructor,
  fallback) carry `function: nil` and format without a leading name. Mirrors
  viem's `formatAbiItem` and round-trips with `FunctionSelector.decode/1` — the
  produced string re-parses to the same types.

  ## Examples

      iex> ABI.parse_specification([%{"type" => "function", "name" => "transfer", "inputs" => [%{"name" => "to", "type" => "address"}, %{"name" => "amount", "type" => "uint256"}]}])
      ...> |> hd()
      ...> |> ABI.format_abi_item()
      "transfer(address,uint256)"

      iex> ABI.format_abi_item(%ABI.FunctionSelector{
      ...>   function: "swap",
      ...>   types: [
      ...>     %{type: {:tuple, [%{type: :address}, %{type: {:uint, 256}}]}},
      ...>     %{type: {:array, {:uint, 256}}},
      ...>     %{type: {:array, :address, 3}}
      ...>   ]
      ...> })
      "swap((address,uint256),uint256[],address[3])"

      iex> ABI.format_abi_item(%ABI.FunctionSelector{function: nil, function_type: :constructor, types: [%{type: {:uint, 8}}]})
      "(uint8)"
  """
  @spec format_abi_item(FunctionSelector.t()) :: String.t()
  def format_abi_item(%FunctionSelector{} = function_selector) do
    FunctionSelector.encode(function_selector)
  end

  api(
    :get_abi_item,
    "Finds an ABI fragment by name with optional input-type disambiguation for overloads.",
    params: [
      abi: [
        kind: :value,
        description: "Parsed ABI specification — the list returned by parse_specification/1."
      ],
      name: [
        kind: :value,
        description: "Fragment name to match against FunctionSelector.function."
      ],
      arg_types: [
        kind: :value,
        description:
          "Optional list of internal input types (e.g. [:address, {:uint, 256}]) matching FunctionSelector.types type fields. Pass nil when the name is unique or to surface {:ambiguous, _} on overloads."
      ]
    ],
    returns: %{
      type: :union,
      description:
        "{:ok, %FunctionSelector{}} on a unique match (by name alone, or name + arg_types). {:error, :not_found} when nothing matches. {:error, {:ambiguous, selectors}} when multiple fragments share the name and arg_types is nil or still ambiguous."
    },
    errors: [
      not_found: "No fragment matches the given name (and arg types, when provided).",
      ambiguous:
        "Multiple fragments share the name; pass arg_types listing each input's internal type atom to pick the overload."
    ],
    composes_with: [:parse_specification]
  )

  @doc """
  Finds an ABI fragment by name in a parsed specification list.

  Operates on the output of `parse_specification/1`. When several fragments
  share a name (Solidity overloads, or a function and event with the same
  label), pass `arg_types` — a list of internal type atoms matching each
  input's `type` field (e.g. `[:address, {:uint, 256}]`) — to select the
  intended overload. Mirrors viem's `getAbiItem`.

  ## Examples

      iex> abi =
      ...>   ABI.parse_specification([
      ...>     %{"type" => "function", "name" => "transfer", "inputs" => [
      ...>       %{"type" => "address"},
      ...>       %{"type" => "uint256"}
      ...>     ]}
      ...>   ])
      iex> {:ok, %ABI.FunctionSelector{function: "transfer"}} = ABI.get_abi_item(abi, "transfer", nil)

      iex> abi =
      ...>   ABI.parse_specification([
      ...>     %{"type" => "function", "name" => "pick", "inputs" => [%{"type" => "uint256"}]},
      ...>     %{"type" => "function", "name" => "pick", "inputs" => [
      ...>       %{"type" => "uint256"},
      ...>       %{"type" => "address"}
      ...>     ]}
      ...>   ])
      iex> {:error, {:ambiguous, _}} = ABI.get_abi_item(abi, "pick", nil)
      iex> {:ok, %ABI.FunctionSelector{types: [%{type: {:uint, 256}}, %{type: :address}]}} =
      ...>   ABI.get_abi_item(abi, "pick", [{:uint, 256}, :address])

      iex> abi = ABI.parse_specification([%{"type" => "function", "name" => "only", "inputs" => []}])
      iex> ABI.get_abi_item(abi, "missing", nil)
      {:error, :not_found}
  """
  @spec get_abi_item([FunctionSelector.t()], String.t(), [FunctionSelector.type()] | nil) ::
          {:ok, FunctionSelector.t()}
          | {:error, :not_found}
          | {:error, {:ambiguous, [FunctionSelector.t()]}}
  def get_abi_item(abi, name, arg_types) when is_list(abi) and is_binary(name) do
    abi
    |> Enum.filter(fn %FunctionSelector{function: fun} -> fun == name end)
    |> resolve_abi_item_matches(arg_types)
  end

  @spec resolve_abi_item_matches([FunctionSelector.t()], [FunctionSelector.type()] | nil) ::
          {:ok, FunctionSelector.t()}
          | {:error, :not_found}
          | {:error, {:ambiguous, [FunctionSelector.t()]}}
  defp resolve_abi_item_matches([], _arg_types), do: {:error, :not_found}

  defp resolve_abi_item_matches(matches, arg_types) when is_list(arg_types) do
    matches
    |> Enum.filter(&(input_types(&1) == arg_types))
    |> resolve_abi_item_matches(nil)
  end

  defp resolve_abi_item_matches([selector], nil), do: {:ok, selector}
  defp resolve_abi_item_matches(matches, nil), do: {:error, {:ambiguous, matches}}

  @spec input_types(FunctionSelector.t()) :: [FunctionSelector.type()]
  defp input_types(%FunctionSelector{types: types}), do: Enum.map(types, & &1.type)

  api(
    :parse_specification,
    "Parses an ABI specification document into a list of ABI.FunctionSelector structs.",
    params: [
      doc: [
        kind: :value,
        description:
          "ABI specification as a list of maps — typically produced by JSON-decoding a contract's .abi.json file. Every entry is parsed into a FunctionSelector, including non-function entries (constructor, fallback, receive, error, event) — distinguish via the :function_type field."
      ]
    ],
    returns: %{
      type: :list,
      description: "List of ABI.FunctionSelector structs — one per entry in the input doc, regardless of :function_type."
    }
  )

  @doc """
  Parses the given ABI specification document into an array of `ABI.FunctionSelector`s.

  Every entry in the document is parsed — including constructor, fallback,
  receive, error, and event entries — and returned with its `function_type`
  field set accordingly. Filter by that field if you only want plain
  function entries.

  This function can be used in combination with a JSON parser, e.g. [`Jason`](https://hex.pm/packages/jason), to parse ABI specification JSON files.

  ## Examples

      iex> File.read!("priv/dog.abi.json")
      ...> |> Jason.decode!
      ...> |> ABI.parse_specification
      [%ABI.FunctionSelector{function: "bark", function_type: :function, state_mutability: :nonpayable, returns: [], types: [%{name: "at", type: :address}, %{name: "loudly", type: :bool}]},
       %ABI.FunctionSelector{function: "rollover", function_type: :function, state_mutability: :nonpayable, returns: [%{name: "is_a_good_boy", type: :bool}], types: []}]

      iex> [%{
      ...>   "constant" => true,
      ...>   "inputs" => [
      ...>     %{"name" => "at", "type" => "address"},
      ...>     %{"name" => "loudly", "type" => "bool"}
      ...>   ],
      ...>   "name" => "bark",
      ...>   "outputs" => [],
      ...>   "payable" => false,
      ...>   "stateMutability" => "pure",
      ...>   "type" => "function"
      ...> }]
      ...> |> ABI.parse_specification
      [
        %ABI.FunctionSelector{function: "bark", function_type: :function, state_mutability: :pure, returns: [], types: [
          %{type: :address, name: "at"},
          %{type: :bool, name: "loudly"}
        ]}
      ]

      iex> [%{
      ...>   "inputs" => [
      ...>      %{"name" => "_numProposals", "type" => "uint8"}
      ...>   ],
      ...>   "payable" => false,
      ...>   "stateMutability" => "nonpayable",
      ...>   "type" => "constructor"
      ...> }]
      ...> |> ABI.parse_specification
      [%ABI.FunctionSelector{function: nil, function_type: :constructor, state_mutability: :nonpayable, types: [%{name: "_numProposals", type: {:uint, 8}}], returns: nil}]

      iex> ABI.decode("(string)", "000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000643132333435363738393031323334353637383930313233343536373839303132333435363738393031323334353637383930313233343536373839303132333435363738393031323334353637383930313233343536373839303132333435363738393000000000000000000000000000000000000000000000000000000000" |> Base.decode16!(case: :lower))
      [String.duplicate("1234567890", 10)]

      iex> [%{
      ...>   "payable" => false,
      ...>   "stateMutability" => "nonpayable",
      ...>   "type" => "fallback"
      ...> }]
      ...> |> ABI.parse_specification
      [%ABI.FunctionSelector{function: nil, function_type: :fallback, state_mutability: :nonpayable, returns: nil, types: []}]
  """
  @spec parse_specification([map()]) :: [FunctionSelector.t()]
  def parse_specification(doc) do
    doc
    |> Enum.map(&FunctionSelector.parse_specification_item/1)
    |> Enum.filter(& &1)
  end
end
