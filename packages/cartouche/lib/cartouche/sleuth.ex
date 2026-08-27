defmodule Cartouche.Sleuth do
  @moduledoc ~S"""
  Sleuth allows you to run a contract call as a single
  `eth_call` call.

  Note: Cartouche.Contract.Sleuth generated from `mix cartouche.gen --prefix cartouche/contract ./priv/Sleuth.json`
  """
  use Descripex, namespace: "/ethereum/sleuth"
  use Cartouche.Hex

  alias Cartouche.Contract.Sleuth

  @sleuth_address ~h[0xFd946Bf25C47A1Bff567B28bA78a961bf78FF9d2]

  api(:query, "Run a Sleuth contract query and return decoded values without ABI type annotations.",
    params: [
      bytecode: [kind: :value, description: "Raw contract bytecode to deploy in the simulated `eth_call`."],
      query: [kind: :value, description: "ABI-encoded calldata sent to the deployed bytecode."],
      selector: [kind: :value, description: "ABI function selector describing how to decode the returned bytes."],
      opts: [kind: :value, default: [], description: "Keyword options forwarded to RPC plus Sleuth decode controls."]
    ],
    opts: [
      sleuth_address: [
        kind: :value,
        default: "0xFd946Bf25C47A1Bff567B28bA78a961bf78FF9d2",
        description: "20-byte address of the Sleuth helper contract."
      ],
      decode_binaries: [
        kind: :value,
        default: true,
        description: "Whether decoded binary/address ABI values remain raw binaries."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, decoded}` with postprocessed ABI return values, or `{:error, reason}` on RPC/decode failure."
    }
  )

  @doc """
  Runs a Sleuth contract query: deploys `bytecode` on-chain via `eth_call`
  with `query` calldata and decodes the result against `selector`. Returns
  the decoded values without struct annotations.
  """
  @spec query(binary(), binary(), ABI.FunctionSelector.t(), Keyword.t()) ::
          {:ok, term()} | {:error, String.t()}
  def query(bytecode, query, selector, opts \\ []), do: query_internal(bytecode, query, selector, false, opts)

  api(:query_annotated, "Run a Sleuth query and tag each decoded return value with its ABI type.",
    params: [
      bytecode: [kind: :value, description: "Raw contract bytecode to deploy in the simulated `eth_call`."],
      query: [kind: :value, description: "ABI-encoded calldata sent to the deployed bytecode."],
      selector: [kind: :value, description: "ABI function selector describing how to decode the returned bytes."],
      opts: [kind: :value, default: [], description: "Keyword options forwarded to RPC plus Sleuth decode controls."]
    ],
    opts: [
      sleuth_address: [
        kind: :value,
        default: "0xFd946Bf25C47A1Bff567B28bA78a961bf78FF9d2",
        description: "20-byte address of the Sleuth helper contract."
      ],
      decode_binaries: [
        kind: :value,
        default: true,
        description: "Whether decoded binary/address ABI values remain raw binaries."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, decoded}` where decoded values include ABI type tags, or `{:error, reason}` on RPC/decode failure."
    },
    composes_with: [:query]
  )

  @doc """
  Same as `query/4`, but tags each decoded value with its ABI type for
  callers that need both type and value (e.g. when re-encoding).
  """
  @spec query_annotated(binary(), binary(), ABI.FunctionSelector.t(), Keyword.t()) ::
          {:ok, term()} | {:error, String.t()}
  def query_annotated(bytecode, query, selector, opts \\ []), do: query_internal(bytecode, query, selector, true, opts)

  api(:query_by, "Run a Sleuth query using a generated contract module's bytecode, calldata encoder, and selector.",
    params: [
      mod: [
        kind: :value,
        description: "Generated contract module that exposes `bytecode/0`, `encode_<fun>/0`, and `<fun>_selector/0`."
      ],
      fun: [
        kind: :value,
        default: :query,
        description: "Generated function name used to derive encoder and selector function names."
      ],
      opts: [kind: :value, default: [], description: "Keyword options forwarded to the Sleuth query and RPC call."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, decoded}` from the generated contract query, or `{:error, reason}` on RPC/decode failure."
    },
    composes_with: [:query]
  )

  @doc """
  Convenience wrapper that derives bytecode, query calldata, and selector
  from a generated contract module. Resolves `mod.bytecode/0`,
  `mod.encode_<fun>/0`, and `mod.<fun>_selector/0` and forwards the rest
  to `query/4`.
  """
  @spec query_by(module(), atom() | Keyword.t()) :: {:ok, term()} | {:error, String.t()}
  def query_by(mod, fun) when is_atom(mod) and is_atom(fun), do: query_by(mod, fun, [])
  def query_by(mod, opts) when is_atom(mod) and is_list(opts), do: query_by(mod, :query, opts)

  @doc """
  Single-argument form of `query_by/2`: defaults `fun` to `:query` and
  `opts` to `[]`.
  """
  @spec query_by(module()) :: {:ok, term()} | {:error, String.t()}
  def query_by(mod), do: query_by(mod, :query, [])

  @doc """
  Three-argument form of `query_by/2`: explicit `fun` and `opts`.
  """
  @spec query_by(module(), atom(), Keyword.t()) :: {:ok, term()} | {:error, String.t()}
  def query_by(mod, fun, opts) when is_atom(mod) and is_atom(fun) and is_list(opts) do
    bytecode = try_apply(mod, :bytecode, [])
    # `fun` is a developer-supplied atom (already in the atom table); the derived
    # function names must already exist as atoms because the generated contract
    # module compiled them. `String.to_existing_atom/1` keeps an attacker-supplied
    # `fun` from filling the atom table (BEAM cap ~1M, never GC'd) — cold names
    # surface as the same RuntimeError shape that `try_apply/3` raises so callers
    # see a uniform "function does not exist" failure.
    query_val = try_apply(mod, existing_function_atom("encode_" <> to_string(fun), 0), [])
    selector = try_apply(mod, existing_function_atom(to_string(fun) <> "_selector", 0), [])

    query_internal(bytecode, query_val, selector, false, opts)
  end

  @spec existing_function_atom(String.t(), non_neg_integer()) :: atom()
  defp existing_function_atom(name, arity) do
    String.to_existing_atom(name)
  rescue
    ArgumentError ->
      reraise "Sleuth module does not define required \"#{name}/#{arity}\" function",
              __STACKTRACE__
  end

  @spec query_internal(binary(), binary(), ABI.FunctionSelector.t(), boolean(), Keyword.t()) ::
          {:ok, term()} | {:error, String.t()}
  defp query_internal(bytecode, query, selector, annotated, opts) when is_binary(bytecode) and is_list(opts) do
    {sleuth_address, opts} = Keyword.pop(opts, :sleuth_address, @sleuth_address)
    {decode_binaries, rpc_opts} = Keyword.pop(opts, :decode_binaries, true)

    with {:ok, query_res_bytes} <-
           Sleuth.call_query(sleuth_address, bytecode, query, rpc_opts),
         {:ok, query_res} <- try_decode_bytes(query_res_bytes),
         {:ok, res} <- try_decode(query_res, selector, false) do
      {:ok,
       postprocess(res, selector.returns,
         annotated: annotated,
         decode_binaries: decode_binaries,
         be_obvious: false
       )}
    end
  end

  api(:query_v2, "Run a Sleuth query with the full decode option set exposed.",
    params: [
      bytecode: [kind: :value, description: "Raw contract bytecode to deploy in the simulated `eth_call`."],
      query: [kind: :value, description: "ABI-encoded calldata sent to the deployed bytecode."],
      selector: [kind: :value, description: "ABI function selector describing how to decode the returned bytes."],
      opts: [
        kind: :value,
        default: [],
        description: "Keyword options forwarded to RPC plus extended Sleuth decode controls."
      ]
    ],
    opts: [
      annotated: [kind: :value, default: false, description: "Whether each decoded value is returned with its ABI type."],
      decode_binaries: [
        kind: :value,
        default: true,
        description: "Whether decoded binary/address ABI values remain raw binaries."
      ],
      decode_structs: [
        kind: :value,
        default: true,
        description: "Whether ABI tuple returns are decoded as structs/maps when possible."
      ],
      named_returns: [kind: :value, default: false, description: "Whether named ABI returns are emitted as named pairs."],
      sleuth_address: [
        kind: :value,
        default: "0xFd946Bf25C47A1Bff567B28bA78a961bf78FF9d2",
        description: "20-byte address of the Sleuth helper contract."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, decoded}` with postprocessing controlled by opts, or `{:error, reason}` on RPC/decode failure."
    },
    composes_with: [:query]
  )

  @doc """
  Variant of `query/4` that exposes the full set of decode options
  (`:annotated`, `:decode_binaries`, `:decode_structs`, `:named_returns`,
  `:sleuth_address`) as keyword opts. Returns results with named-return
  annotations when configured.
  """
  @spec query_v2(binary(), binary(), ABI.FunctionSelector.t(), Keyword.t()) ::
          {:ok, term()} | {:error, String.t()}
  def query_v2(bytecode, query, selector, opts \\ []) do
    {annotated, opts} = Keyword.pop(opts, :annotated, false)
    {sleuth_address, opts} = Keyword.pop(opts, :sleuth_address, @sleuth_address)
    {decode_binaries, opts} = Keyword.pop(opts, :decode_binaries, true)
    {decode_structs, opts} = Keyword.pop(opts, :decode_structs, true)
    {named_returns, rpc_opts} = Keyword.pop(opts, :named_returns, false)

    with {:ok, query_res_bytes} <-
           Sleuth.call_query(sleuth_address, bytecode, query, rpc_opts),
         {:ok, query_res} <- try_decode_bytes(query_res_bytes),
         {:ok, res} <- try_decode(query_res, selector, decode_structs, named_returns) do
      {:ok,
       postprocess(res, selector.returns,
         annotated: annotated,
         decode_binaries: decode_binaries,
         named_returns: named_returns,
         be_obvious: true
       )}
    end
  end

  @spec try_decode_bytes(binary()) :: {:ok, binary()} | {:error, String.t()}
  defp try_decode_bytes(bytes) do
    [decoded] = ABI.decode("(bytes)", bytes)
    {:ok, decoded}
  rescue
    # `ABI.decode/2` raises on malformed wire bytes and the `[decoded] =`
    # match raises `MatchError` when the outer tuple arity differs; both
    # become an `{:error, _}` rather than crashing the query.
    e in [ArgumentError, MatchError, FunctionClauseError, RuntimeError, KeyError, Protocol.UndefinedError] ->
      {:error, "error decoding bytes: #{inspect(e)}"}
  end

  @spec try_decode(binary(), ABI.FunctionSelector.t(), boolean(), boolean()) ::
          {:ok, [term()]} | {:error, String.t()}
  defp try_decode(query_res, selector, decode_structs, named_returns \\ false) do
    if decode_structs, do: preintern_decode_struct_atoms(selector.returns)
    # `named_returns: true` flows through `name_keyword/1`, which uses
    # `String.to_existing_atom/1`; preintern the top-level return-field
    # atoms here so cold names surface as the existing INE-17
    # `{:error, "error decoding: ..."}` shape rather than crashing
    # postprocess with `ArgumentError`.
    if named_returns, do: preintern_named_return_atoms(selector.returns)

    {:ok,
     ABI.decode(
       %ABI.FunctionSelector{types: selector.returns},
       query_res,
       decode_structs: decode_structs
     )}
  rescue
    # `ABI.decode/3` raises on selector/return mismatches and malformed bytes;
    # surface as an `{:error, _}` for the caller instead of crashing.
    e in [ArgumentError, MatchError, FunctionClauseError, RuntimeError, KeyError, Protocol.UndefinedError] ->
      {:error, "error decoding: #{inspect(e)}"}
  end

  @spec preintern_decode_struct_atoms(term()) :: :ok
  defp preintern_decode_struct_atoms(types) when is_list(types), do: Enum.each(types, &preintern_type_atoms/1)
  defp preintern_decode_struct_atoms(_), do: :ok

  # `named_returns: true` only atomizes the *top-level* return field names
  # (via `name_keyword/1`); nested struct fields are not. Narrower than
  # `preintern_decode_struct_atoms/1` to avoid rejecting selectors that
  # decode_structs=false would have left as plain maps.
  @spec preintern_named_return_atoms(term()) :: :ok
  defp preintern_named_return_atoms(returns) when is_list(returns) do
    Enum.each(returns, fn
      %{name: name} -> preintern_name_atom(name)
      _ -> :ok
    end)
  end

  defp preintern_named_return_atoms(_), do: :ok

  @spec preintern_type_atoms(term()) :: :ok
  defp preintern_type_atoms(%{name: name, type: type}) do
    preintern_name_atom(name)
    preintern_type_atoms(type)
  end

  defp preintern_type_atoms({:tuple, types}) when is_list(types), do: Enum.each(types, &preintern_type_atoms/1)
  defp preintern_type_atoms({:array, type}), do: preintern_type_atoms(type)
  defp preintern_type_atoms({:array, type, _size}), do: preintern_type_atoms(type)
  defp preintern_type_atoms(_), do: :ok

  # hieroglyph 1.4.0 requires decode_structs field atoms to exist already.
  # Runtime selectors may be caller-supplied, so only generated/trusted code may
  # create atoms; this boundary validates that the required atoms already exist.
  @spec preintern_name_atom(term()) :: :ok
  defp preintern_name_atom(name) when is_binary(name) and name != "" do
    atom_name = Macro.underscore(name)

    case existing_atom(atom_name) do
      {:ok, _atom} ->
        :ok

      :error ->
        raise ArgumentError,
              "decode_structs requires pre-existing return-field atom #{inspect(atom_name)}; " <>
                "load a generated contract module or pass decode_structs: false for dynamic selectors"
    end
  end

  defp preintern_name_atom(_), do: :ok

  @spec existing_atom(String.t()) :: {:ok, atom()} | :error
  defp existing_atom(atom_name) do
    {:ok, String.to_existing_atom(atom_name)}
  rescue
    ArgumentError -> :error
  end

  # NOTE: decode_structs weirdly also does dynamic return types with named
  # returns, which interacts poorly with our named_returns opt.
  #
  # so we have to take the unordered map, and re-order the values by
  # referencing the ordering of the named_types.
  #
  # A postprocessed ABI value: scalars decode to integers/booleans/binaries,
  # arrays to lists, tuples/named-returns to tuples or string/atom-keyed maps,
  # and — under `annotated: true` — to `{type, value}` pairs. Recursive because
  # arrays and tuples nest. Narrower than `term()`: ABI has no atom/float/pid
  # values, so those are excluded.
  @typep decoded_value ::
           integer()
           | boolean()
           | binary()
           | [decoded_value()]
           | tuple()
           | map()

  # The type descriptor postprocess folds over: a single ABI return type, a list
  # of named return types, or `:anonymous`/`nil` for selectors without returns —
  # exactly the shape of `ABI.FunctionSelector.t().returns`.
  @typep returns_spec ::
           ABI.FunctionSelector.type()
           | [ABI.FunctionSelector.argument_type()]
           | :anonymous
           | nil

  @spec postprocess(decoded_value(), returns_spec(), Keyword.t()) :: decoded_value()
  defp postprocess(results, named_types, opts) when is_map(results) and is_list(named_types) do
    results_values =
      Enum.map(named_types, fn %{name: name} ->
        {_, v} = Enum.find(results, fn {k, _} -> to_string(k) == Macro.underscore(name) end)
        v
      end)

    postprocess(results_values, named_types, opts)
  end

  defp postprocess(results, named_types, opts) when is_list(results) and is_list(named_types) do
    be_obvious = Keyword.get(opts, :be_obvious, false)
    named_returns = Keyword.get(opts, :named_returns, false)

    results
    |> Enum.zip(named_types)
    |> Enum.map(fn {it, t} -> {t.name, postprocess(it, t.type, opts)} end)
    |> then(fn
      processed_results when not be_obvious ->
        case processed_results do
          [] ->
            []

          [{nil, result}] ->
            result

          [{"", result}] ->
            result

          [_more | _than_one] = processed_results ->
            processed_results
            |> Enum.with_index()
            |> Map.new(&with_indexed_name/1)
        end

      processed_results when be_obvious ->
        obvious_results(processed_results, named_returns)
    end)
  end

  defp postprocess(item, {:tuple, named_types}, opts) when is_tuple(item) and is_list(named_types) do
    item
    |> Tuple.to_list()
    |> Enum.zip(named_types)
    |> Map.new(fn {item, %{type: type, name: name}} ->
      {name, postprocess(item, type, opts)}
    end)
  end

  defp postprocess(item, {:tuple, named_types}, opts) when is_map(item) and is_list(named_types) do
    Map.new(item, fn {k, v} ->
      %{type: type} =
        Enum.find(named_types, fn %{name: name} -> Macro.underscore(name) == to_string(k) end)

      {k, postprocess(v, type, opts)}
    end)
  end

  defp postprocess(item, {:array, type}, opts) when is_list(item) do
    Enum.map(item, &postprocess(&1, type, opts))
  end

  defp postprocess(item, {:array, type, _}, opts) when is_list(item), do: postprocess(item, {:array, type}, opts)

  defp postprocess(item, type, opts) do
    item_encoded =
      if Keyword.get(opts, :decode_binaries, true) do
        item
      else
        case type do
          :address -> to_hex(item)
          :bytes -> to_hex(item)
          {:bytes, _size} -> to_hex(item)
          _nonbinary_scalar -> item
        end
      end

    if Keyword.get(opts, :annotated, false) do
      {type, item_encoded}
    else
      item_encoded
    end
  end

  @spec try_apply(module(), atom(), [term()]) :: term() | no_return()
  defp try_apply(mod, fun, args) do
    apply(mod, fun, args)
  rescue
    # Only an undefined/unexported function is reframed as the "does not define
    # required …" error; any other exception raised *inside* an existing
    # generated function propagates unchanged so real bugs aren't masked.
    UndefinedFunctionError ->
      reraise "Sleuth module #{mod} does not define required \"#{fun}/#{length(args)}\" function",
              __STACKTRACE__
  end

  @spec with_indexed_name({{String.t() | nil, term()}, non_neg_integer()}) :: {String.t(), term()}
  defp with_indexed_name({{name, it}, i}), do: {fallback_name(name, i), it}

  @spec fallback_name(String.t() | nil, non_neg_integer()) :: String.t()
  defp fallback_name(nil, i), do: "var#{i}"
  defp fallback_name("", i), do: "var#{i}"
  defp fallback_name(name, _i), do: name

  @spec to_named_pair({String.t() | nil, term()}) :: {atom(), term()}
  defp to_named_pair({name, v}), do: {name_keyword(name), v}

  # `String.to_existing_atom/1` keeps attacker-supplied selector field
  # names from filling the BEAM atom table. `query_v2/4` preinterns the
  # top-level return-field atoms via `preintern_named_return_atoms/1`
  # before reaching here, so any name we see has already been validated;
  # the rescue is a defense-in-depth against future call paths that
  # might bypass the preintern step.
  @spec name_keyword(String.t() | nil) :: atom()
  defp name_keyword(nil), do: :__unnamed__
  defp name_keyword(""), do: :__unnamed__

  defp name_keyword(name) do
    String.to_existing_atom(Macro.underscore(name))
  rescue
    ArgumentError ->
      reraise ArgumentError,
              "decode_structs requires pre-existing return-field atom #{inspect(Macro.underscore(name))}; " <>
                "load a generated contract module or pass named_returns: false for dynamic selectors",
              __STACKTRACE__
  end

  @spec obvious_results([{String.t() | nil, term()}], boolean()) :: [term()] | [{atom(), term()}]
  defp obvious_results(processed_results, true), do: Enum.map(processed_results, &to_named_pair/1)
  defp obvious_results(processed_results, false), do: Enum.map(processed_results, fn {_, v} -> v end)
end
