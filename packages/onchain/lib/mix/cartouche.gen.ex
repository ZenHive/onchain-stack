defmodule Mix.Tasks.Cartouche.Gen do
  @shortdoc "Generates wrapper modules from Solidity artifacts or ABI files"

  @moduledoc ~S"""
  `cartouche.gen` generates wrapper modules from Solidity artifacts.

  This module will auto-generate code that can be used to easily call into
  a contract. You can pass in either the ABI output or the full Solidity
  output. If you pass in the Solidity artifacts, you'll get wrappers for
  the bytecode.

  For example, `some_contract.ex`

  ```elixir
  defmodule SomeContract do
    use Cartouche.Hex

    def contract_name do
      "SomeContract"
    end

    def encode_some_function(val) do
      ABI.encode("some_function(uint256)", [val])
    end

    def execute_some_function(contract, val, opts \\ []) do
      Cartouche.RPC.execute_trx(contract, encode_some_function(val), opts)
    end

    def bytecode(), do: ~h[0x...]

    def deployed_bytecode(), do: ~h[0x...]
  end
  ```

  These stubs are useful, since you can easily then call:

  ```iex
  {:ok, tx_id} = Contract.SomeContract.execute_some_function(addr, 55, priority_fee: {55, :gwei})
  ```


  🐉🌊🌊🌊🌊🌊🐉   HERE BE DRAGONS    🐉🌊🌊🌊🌊🌊🐉


  # Usage

  `mix cartouche.gen "out/**/*.json"`

   * `--prefix`: Prefix for the outputed modules
     - E.g. `my_app` -> `MyApp.SomeContract` in `my_app/some_contract.ex`
     - E.g. `my_app/contract` -> `MyApp.Contract.SomeContract` in `my_app/contract/some_contract.ex`
   * `--out`: Out directory, e.g. `lib/my_app/` [default `lib/`]
  """

  use Mix.Task
  use Cartouche.Hex

  require Logger

  @doc_purposes %{
    encode: "Encodes ABI calldata",
    encode_event: "Encodes ABI event data",
    prepare: "Prepares a transaction",
    build_trx: "Builds an eth_call transaction",
    call: "Calls a contract function",
    estimate_gas: "Estimates gas for a contract function",
    execute: "Executes a contract transaction",
    exec_vm: "Executes deployed bytecode in the local VM",
    exec_vm_raw: "Executes deployed bytecode in the local VM and returns raw returndata",
    selector: "Returns the ABI function selector",
    event_selector: "Returns the ABI event selector",
    decode_event: "Decodes ABI event topics and data",
    decode_call: "Decodes ABI calldata",
    decode_error: "Decodes ABI revert data"
  }

  @unlinked_library_marker ~r/_{2}\$[[:xdigit:]]{34}\$_{2}/

  # Exceptions `ABI.FunctionSelector.parse_specification_item/1` raises on
  # malformed-but-plausible solc ABI JSON, established by probing hieroglyph
  # directly (see the matching describe block in test/mix/cartouche_gen_test.exs):
  #
  #   * ArgumentError          — a type the grammar accepts but ABI doesn't implement (fixed128x18)
  #   * FunctionClauseError    — an unrecognized/missing/non-string "type", at the item or input level
  #   * MatchError             — an inner type string the lexer can't tokenize, or `tuple` with no components
  #   * Protocol.UndefinedError — "inputs"/"outputs" present but JSON null (the `Map.get/3` default
  #                               only applies when the key is ABSENT, so nil reaches Enum.map/2)
  #
  # Shared by all three call sites so the set can't drift between them. A parse
  # failure is warned-and-skipped, never fatal: one malformed item must not abort
  # generation for the whole artifact.
  @parse_specification_errors [ArgumentError, FunctionClauseError, MatchError, Protocol.UndefinedError]

  defmodule InvalidFileError do
    @moduledoc false
    defexception message: "invalid file error"
  end

  # The contract name isn't obvious from the output-json file, thus we look either by
  # trying to find it in the metadata settings or AST [below]
  defp get_contract_name_by_metadata(abi) do
    metadata =
      case get_in(abi, ["metadata"]) do
        nil ->
          nil

        m when is_binary(m) ->
          Jason.decode!(m)

        els ->
          els
      end

    case get_in(metadata, ["settings", "compilationTarget"]) do
      nil ->
        nil

      contracts ->
        case Enum.to_list(contracts) do
          [{_k, v} | _rest] ->
            v

          _ ->
            nil
        end
    end
  end

  # Search the AST for the module name from the output-json
  defp get_contract_name_by_ast(abi) do
    %{"sourceUnit" => _, "absolutePath" => absolute_path} = abi["ast"]

    absolute_path
    |> String.split("/")
    |> List.last()
    |> case do
      nil ->
        nil

      file_name ->
        file_name
        |> String.split(".", parts: 2)
        |> List.first()
    end
  end

  # Solidity functions are allowed to overlap with different arugment types, but this
  # would break any Elixir functions, which are not allowed to do that. Thus, we walk
  # the abi from the output-json and see if there are duplicate functions with the
  # same name. If so, we rename any latter by postpending `_aabbccdd` (the function
  # signture) at the end of the function name. The first one doesn't have the prefix,
  # but we could make this more complex to rename all of them if there are any dupes;
  # it would just require two passes.
  defp rename_dups(abis) do
    {abis, _} = Enum.reduce(abis, {[], []}, &accumulate_named_abi/2)
    Enum.reverse(abis)
  end

  defp accumulate_named_abi(abi, {acc, seen}) do
    fn_sel =
      try do
        ABI.FunctionSelector.parse_specification_item(abi)
      rescue
        e in @parse_specification_errors ->
          Logger.warning("Ignoring due to failed parse: #{inspect(abi)}")
          Logger.error(e)

          {:error, e}
      end

    case {fn_sel, abi["name"]} do
      {{:error, _exception}, _} -> {[abi | acc], seen}
      {_, nil} -> {[abi | acc], seen}
      {fs, name} -> dedup_named_abi(abi, name, fs, acc, seen)
    end
  end

  @spec dedup_named_abi(map(), String.t(), ABI.FunctionSelector.t(), [map()], [{String.t(), String.t()}]) ::
          {[map()], [{String.t(), String.t()}]}
  defp dedup_named_abi(abi, name, fn_sel, acc, seen) do
    # Key collision detection on Macro.underscore/1 — the exact normalization the
    # generated identifiers use (see function_names/1). String.downcase/1 misses
    # camelCase/snake_case pairs like getValue + get_value: they have different
    # selectors and downcase differently ("getvalue" vs "get_value"), so neither
    # the skip nor the rename below would fire, yet both underscore to "get_value"
    # and emit a shadowed encode_get_value/N clause.
    underscored_name = Macro.underscore(name)

    abi_enc_signature = ABI.method_id(fn_sel)
    "0x" <> abi_sig = Cartouche.Hex.encode_hex(abi_enc_signature)
    seen_tuple = {underscored_name, abi_sig}

    if Enum.member?(seen, seen_tuple) do
      {acc, seen}
    else
      abi_new = maybe_rename_dup_fn(abi, name, underscored_name, abi_sig, seen)
      {[abi_new | acc], [{underscored_name, abi_sig} | seen]}
    end
  end

  defp maybe_rename_dup_fn(abi, name, underscored_name, abi_sig, seen) do
    if Enum.member?(Enum.map(seen, fn {n, _} -> n end), underscored_name) do
      Map.put(abi, "fn_name", "#{name}_#{abi_sig}")
    else
      abi
    end
  end

  # Function to take the abi from the output-json and output function defs (e.g. encode and execute)
  defp get_encode_calls(full_abi, has_bytecode, has_deployed_bytecode) do
    abi_items = full_abi["abi"] || []
    renamed_abis = rename_dups(abi_items)
    has_errors = Enum.any?(renamed_abis, &(&1["type"] == "error"))

    {fns, decoders, events, errors} =
      Enum.reduce(renamed_abis, {[], [], [], []}, fn abi, acc ->
        merge_encode_call_result(acc, get_encode_call(abi, has_bytecode, has_deployed_bytecode, has_errors))
      end)

    decoders =
      [build_generic_decode_call_annotations()] ++
        Enum.reverse(decoders, [build_generic_decode_call_fallback_fn()])

    errors =
      [build_generic_decode_error_annotations()] ++ Enum.reverse(errors, [build_generic_decode_error_fallback_fn()])

    events =
      [build_generic_decode_event_annotations()] ++ Enum.reverse(events, [build_generic_decode_event_fallback_fn()])

    flatten_quote_blocks(fns ++ decoders ++ events ++ errors)
  end

  @spec flatten_quote_blocks([Macro.t()]) :: [Macro.t()]
  defp flatten_quote_blocks(quoted) do
    Enum.flat_map(quoted, fn
      {:__block__, _, statements} -> statements
      statement -> [statement]
    end)
  end

  defp merge_encode_call_result({acc_fns, acc_decoders, acc_events, acc_errors}, result) do
    case result do
      {functions, generic_call_decoder, nil, nil} ->
        {acc_fns ++ functions, [generic_call_decoder | acc_decoders], acc_events, acc_errors}

      {functions, nil, generic_event_fn, nil} ->
        {acc_fns ++ functions, acc_decoders, [generic_event_fn | acc_events], acc_errors}

      {functions, nil, nil, generic_error_fn} ->
        {acc_fns ++ functions, acc_decoders, acc_events, [generic_error_fn | acc_errors]}

      nil ->
        {acc_fns, acc_decoders, acc_events, acc_errors}
    end
  end

  # Parses the ABI spec and generates the functions (encode and execute) if we can parse
  # the ABI spec. We've recently updated our ABI parsing library that this doesn't fail
  # nearly as often as it used to (e.g. it can handle tuples)
  defp get_encode_call(abi, has_bytecode, has_deployed_bytecode, has_errors) do
    fn_selector =
      try do
        ABI.FunctionSelector.parse_specification_item(abi)
      rescue
        _e in @parse_specification_errors ->
          Logger.warning("Ignoring due to failed parse: #{inspect(abi)}")
          nil
      end

    case fn_selector do
      %ABI.FunctionSelector{function: name} = fs when not is_nil(name) ->
        encode_function_call(fs, abi["fn_name"] || name, has_bytecode, has_deployed_bytecode, has_errors)

      %ABI.FunctionSelector{function_type: function_type} = fs ->
        encode_function_call(fs, to_string(function_type), has_bytecode, has_deployed_bytecode, has_errors)

      _ ->
        Logger.warning("Ignoring function due to missing name")
        nil
    end
  end

  # Generate the encode and execute functions. This is ... complex (read: hacky)
  defp encode_function_call(selector, fn_name, has_bytecode, has_deployed_bytecode, has_errors) do
    names = function_names(fn_name)
    argument_types = derive_argument_types(selector)
    {execute_arguments, encode_arguments, execute_values, encode_values} = build_argument_specs(argument_types)
    sig = signature_data(selector)
    return_types = normalize_return_types(selector.returns)

    if abort?(execute_arguments, selector, has_bytecode) do
      Logger.warning("Ignoring function #{selector.function} due to unknown argument")
      nil
    else
      ctx = %{
        names: names,
        execute_arguments: execute_arguments,
        encode_arguments: encode_arguments,
        execute_values: execute_values,
        encode_values: encode_values,
        input_types: argument_types,
        return_types: return_types,
        sig: sig,
        selector: selector,
        has_errors: has_errors
      }

      select_emitted_fns(selector, has_deployed_bytecode, build_function_quotes(ctx))
    end
  end

  # sobelow_skip ["DOS.StringToAtom"]
  defp function_names(fn_name) do
    underscored = Macro.underscore(fn_name)

    %{
      encode: String.to_atom("encode_#{underscored}"),
      encode_event: String.to_atom("encode_#{underscored}_event"),
      build_trx: String.to_atom("build_trx_#{underscored}"),
      call: String.to_atom("call_#{underscored}"),
      estimate_gas: String.to_atom("estimate_gas_#{underscored}"),
      execute: String.to_atom("execute_#{underscored}"),
      prepare: String.to_atom("prepare_#{underscored}"),
      selector: String.to_atom("#{underscored}_selector"),
      event_selector: String.to_atom("#{underscored}_event_selector"),
      decode_event: String.to_atom("decode_#{underscored}_event"),
      decode_error: String.to_atom("decode_#{underscored}_error"),
      decode_call: String.to_atom("decode_#{underscored}_call"),
      exec_vm: String.to_atom("exec_vm_#{underscored}"),
      exec_vm_raw: String.to_atom("exec_vm_#{underscored}_raw")
    }
  end

  defp derive_argument_types(%{function_type: t}) when t in [:fallback, :receive] do
    [%{type: :bytes, name: "data"}]
  end

  defp derive_argument_types(selector), do: selector.types

  # We are returning 4 values and will do a double unzip here so we can return
  # them from one function but get 4 separate lists.
  defp build_argument_specs(argument_types) do
    {args, vals} =
      argument_types
      |> Enum.with_index(&build_argument_spec/2)
      |> Enum.unzip()

    {execute_arguments, encode_arguments} = Enum.unzip(args)
    {execute_values, encode_values} = Enum.unzip(vals)
    {execute_arguments, encode_arguments, execute_values, encode_values}
  end

  defp build_argument_spec(argument_type, index) do
    if Map.has_key?(argument_type, :name) do
      name = arg_name(argument_type, index)
      names = tuple_field_names(argument_type.type)

      if struct_argument?(names) do
        build_struct_argument_spec(name, names)
      else
        build_simple_argument_spec(name)
      end
    else
      {{nil, nil}, {nil, nil}}
    end
  end

  @spec arg_name(map(), non_neg_integer()) :: String.t()
  defp arg_name(argument_type, index) do
    case Map.get(argument_type, :name) do
      nil -> "var#{index}"
      "" -> "var#{index}"
      els -> String.trim_leading(els, "_")
    end
  end

  defp tuple_field_names({:tuple, tuple_types}), do: Enum.map(tuple_types, &Map.get(&1, :name))
  defp tuple_field_names(_), do: [nil]

  defp struct_argument?(names) do
    not Enum.member?(names, nil) and not Enum.member?(names, "")
  end

  # For a struct, we make the arguments a map keyed by field name. We need to
  # pass them as a `{tuple}` to the encode function (positional), and we need
  # to underscore unused vars to silence compiler warnings.
  #
  # HERE BE DRAGONS 🐉🌊🌊🌊🌊🌊🐉
  # sobelow_skip ["DOS.StringToAtom"]
  @spec build_struct_argument_spec(String.t(), [String.t()]) ::
          {{Macro.t(), Macro.t()}, {Macro.t(), Macro.t()}}
  defp build_struct_argument_spec(name, names) do
    underscored = Macro.underscore(name)
    name_var = Macro.var(String.to_atom(underscored), __MODULE__)
    encode_unused_name_var = Macro.var(String.to_atom("_" <> underscored), __MODULE__)

    encode_els = Enum.map(names, &name_value_pair/1)
    execute_els_unused = Enum.map(names, &unused_name_value_pair/1)
    encode_value_inners = Enum.map(names, &positional_value/1)

    encode_argument =
      quote do
        unquote(encode_unused_name_var) = %{unquote_splicing(encode_els)}
      end

    execute_argument =
      quote do
        unquote(name_var) = %{unquote_splicing(execute_els_unused)}
      end

    encode_value =
      quote do
        {unquote_splicing(encode_value_inners)}
      end

    {{execute_argument, encode_argument}, {name_var, encode_value}}
  end

  # sobelow_skip ["DOS.StringToAtom"]
  defp build_simple_argument_spec(name) do
    var = Macro.var(String.to_atom(Macro.underscore(name)), __MODULE__)
    {{var, var}, {var, var}}
  end

  # sobelow_skip ["DOS.StringToAtom"]
  defp name_value_pair(el) do
    el_atom = String.to_atom(Macro.underscore(el))
    el_var = Macro.var(el_atom, __MODULE__)

    quote do
      {unquote(el_atom), unquote(el_var)}
    end
  end

  # sobelow_skip ["DOS.StringToAtom"]
  @spec unused_name_value_pair(String.t()) :: Macro.t()
  defp unused_name_value_pair(el) do
    underscored = Macro.underscore(el)
    el_atom = String.to_atom(underscored)
    el_atom_unused = String.to_atom("_" <> underscored)
    el_var_unused = Macro.var(el_atom_unused, __MODULE__)

    quote do
      {unquote(el_atom), unquote(el_var_unused)}
    end
  end

  # sobelow_skip ["DOS.StringToAtom"]
  defp positional_value(el) do
    el_atom = String.to_atom(Macro.underscore(el))
    el_var = Macro.var(el_atom, __MODULE__)

    quote do
      unquote(el_var)
    end
  end

  @spec signature_data(ABI.FunctionSelector.t()) :: %{
          abi: binary(),
          abi_enc_signature_list: [byte()],
          abi_enc_signature_hex: Macro.t(),
          signature_list: [byte()],
          error_name: String.t() | nil
        }
  defp signature_data(selector) do
    abi = ABI.FunctionSelector.encode(selector)
    abi_enc_signature = ABI.method_id(selector)

    signature = Cartouche.Hash.keccak(abi)

    abi_enc_signature_list = :erlang.binary_to_list(abi_enc_signature)
    abi_enc_signature_hex_base = Cartouche.Hex.encode_hex(abi_enc_signature)

    abi_enc_signature_hex =
      quote do
        _signature = hex!(unquote(abi_enc_signature_hex_base))
      end

    %{
      abi: abi,
      abi_enc_signature_list: abi_enc_signature_list,
      abi_enc_signature_hex: abi_enc_signature_hex,
      signature_list: :erlang.binary_to_list(signature),
      error_name: selector.function
    }
  end

  defp abort?(execute_arguments, selector, has_bytecode) do
    Enum.member?(execute_arguments, nil) or
      (selector.function_type == :constructor and not has_bytecode)
  end

  defp build_function_quotes(ctx) do
    %{
      encode_fn: build_encode_fn(ctx),
      prepare_fn: build_prepare_fn(ctx),
      build_trx_fn: build_build_trx_fn(ctx),
      call_fn: build_call_fn(ctx),
      estimate_gas_fn: build_estimate_gas_fn(ctx),
      execute_fn: build_execute_fn(ctx),
      exec_vm_fn: build_exec_vm_fn(ctx),
      exec_vm_raw_fn: build_exec_vm_raw_fn(ctx),
      selector_fn: build_selector_fn(ctx),
      event_selector_fn: build_event_selector_fn(ctx),
      decode_event_fn: build_decode_event_fn(ctx),
      decode_call_fn: build_decode_call_fn(ctx),
      decode_error_fn: build_decode_error_fn(ctx),
      generic_decode_call_fn: build_generic_decode_call_fn(ctx),
      generic_error_fn: build_generic_error_fn(ctx),
      generic_event_fn: build_generic_event_fn(ctx)
    }
  end

  defp build_encode_fn(%{selector: %{function_type: :constructor}} = ctx) do
    %{
      names: names,
      encode_arguments: encode_arguments,
      encode_values: encode_values,
      input_types: input_types,
      sig: sig
    } = ctx

    spec_args = spec_args(input_types)
    doc = doc_for(:encode, names.encode, sig.abi)

    quote do
      @doc unquote(doc)
      @spec unquote(spec_call(names.encode, spec_args)) :: binary()
      def unquote(names.encode)(unquote_splicing(encode_arguments)) do
        bytecode() <> ABI.encode(unquote(sig.abi), [{unquote_splicing(encode_values)}])
      end
    end
  end

  defp build_encode_fn(%{selector: %{function_type: t}} = ctx) when t in [:fallback, :receive] do
    %{names: names, encode_arguments: encode_arguments, input_types: input_types} = ctx
    spec_args = spec_args(input_types)
    doc = doc_for(:encode, names.encode, "#{t}(bytes)")

    quote do
      @doc unquote(doc)
      @spec unquote(spec_call(names.encode, spec_args)) :: binary()
      def unquote(names.encode)(unquote_splicing(encode_arguments)) do
        (unquote_splicing(encode_arguments))
      end
    end
  end

  defp build_encode_fn(%{selector: %{function_type: :event}} = ctx) do
    %{
      names: names,
      encode_arguments: encode_arguments,
      encode_values: encode_values,
      input_types: input_types,
      sig: sig
    } = ctx

    spec_args = spec_args(input_types)
    doc = doc_for(:encode_event, names.encode_event, sig.abi)

    quote do
      @doc unquote(doc)
      @spec unquote(spec_call(names.encode_event, spec_args)) :: binary()
      def unquote(names.encode_event)(unquote_splicing(encode_arguments)) do
        ABI.encode(unquote(names.event_selector)(), unquote(encode_values))
      end
    end
  end

  defp build_encode_fn(ctx) do
    %{
      names: names,
      encode_arguments: encode_arguments,
      encode_values: encode_values,
      input_types: input_types,
      sig: sig
    } = ctx

    spec_args = spec_args(input_types)
    doc = doc_for(:encode, names.encode, sig.abi)

    quote do
      @doc unquote(doc)
      @spec unquote(spec_call(names.encode, spec_args)) :: binary()
      def unquote(names.encode)(unquote_splicing(encode_arguments)) do
        ABI.encode(unquote(names.selector)(), unquote(encode_values))
      end
    end
  end

  defp build_prepare_fn(%{selector: %{function_type: :constructor}} = ctx) do
    %{
      names: names,
      execute_arguments: execute_arguments,
      execute_values: execute_values,
      input_types: input_types,
      sig: sig
    } = ctx

    spec_args = spec_args(input_types) ++ [opts_spec()]
    doc = doc_for(:prepare, names.prepare, sig.abi)

    quote do
      @doc unquote(doc)
      @spec unquote(spec_call(names.prepare, spec_args)) ::
              {:ok, Cartouche.Transaction.V1.t() | Cartouche.Transaction.V2.t()} | {:error, term()}
      def unquote(names.prepare)(unquote_splicing(execute_arguments), opts \\ []) do
        Cartouche.RPC.prepare_trx(
          <<0::256>>,
          unquote(names.encode)(unquote_splicing(execute_values)),
          opts
        )
      end
    end
  end

  defp build_prepare_fn(ctx) do
    %{
      names: names,
      execute_arguments: execute_arguments,
      execute_values: execute_values,
      input_types: input_types,
      sig: sig
    } = ctx

    spec_args = [address_spec() | spec_args(input_types)] ++ [opts_spec()]
    doc = doc_for(:prepare, names.prepare, sig.abi)

    quote do
      @doc unquote(doc)
      @spec unquote(spec_call(names.prepare, spec_args)) ::
              {:ok, Cartouche.Transaction.V1.t() | Cartouche.Transaction.V2.t()} | {:error, term()}
      def unquote(names.prepare)(contract, unquote_splicing(execute_arguments), opts \\ []) do
        Cartouche.RPC.prepare_trx(
          contract,
          unquote(names.encode)(unquote_splicing(execute_values)),
          opts
        )
      end
    end
  end

  defp build_build_trx_fn(ctx) do
    %{
      names: names,
      execute_arguments: execute_arguments,
      execute_values: execute_values,
      input_types: input_types,
      sig: sig
    } = ctx

    spec_args = [address_spec() | spec_args(input_types)]
    doc = doc_for(:build_trx, names.build_trx, sig.abi)

    quote do
      @doc unquote(doc)
      @spec unquote(spec_call(names.build_trx, spec_args)) :: Cartouche.Transaction.Call.t()
      def unquote(names.build_trx)(contract, unquote_splicing(execute_arguments)) do
        %Call{
          destination: contract,
          data: unquote(names.encode)(unquote_splicing(execute_values))
        }
      end
    end
  end

  defp build_call_fn(ctx) do
    %{
      names: names,
      execute_arguments: execute_arguments,
      execute_values: execute_values,
      input_types: input_types,
      sig: sig
    } = ctx

    spec_args = [address_spec() | spec_args(input_types)] ++ [opts_spec()]
    doc = doc_for(:call, names.call, sig.abi)

    quote do
      @doc unquote(doc)
      @spec unquote(spec_call(names.call, spec_args)) :: {:ok, binary()} | {:error, term()}
      def unquote(names.call)(contract, unquote_splicing(execute_arguments), opts \\ []) do
        Cartouche.RPC.call_trx(
          unquote(names.build_trx)(contract, unquote_splicing(execute_values)),
          opts
        )
      end
    end
  end

  defp build_estimate_gas_fn(ctx) do
    %{
      names: names,
      execute_arguments: execute_arguments,
      execute_values: execute_values,
      input_types: input_types,
      sig: sig
    } = ctx

    spec_args = [address_spec() | spec_args(input_types)] ++ [opts_spec()]
    doc = doc_for(:estimate_gas, names.estimate_gas, sig.abi)

    quote do
      @doc unquote(doc)
      @spec unquote(spec_call(names.estimate_gas, spec_args)) :: {:ok, non_neg_integer()} | {:error, term()}
      def unquote(names.estimate_gas)(contract, unquote_splicing(execute_arguments), opts \\ []) do
        Cartouche.RPC.estimate_gas(
          unquote(names.build_trx)(contract, unquote_splicing(execute_values)),
          opts
        )
      end
    end
  end

  defp build_execute_fn(%{selector: %{function_type: :constructor}} = ctx) do
    %{
      names: names,
      execute_arguments: execute_arguments,
      execute_values: execute_values,
      input_types: input_types,
      sig: sig
    } = ctx

    spec_args = spec_args(input_types) ++ [opts_spec()]
    doc = doc_for(:execute, names.execute, sig.abi)

    quote do
      @doc unquote(doc)
      @spec unquote(spec_call(names.execute, spec_args)) :: {:ok, binary()} | {:error, term()}
      def unquote(names.execute)(unquote_splicing(execute_arguments), opts \\ []) do
        Cartouche.RPC.execute_trx(
          <<0::256>>,
          unquote(names.encode)(unquote_splicing(execute_values)),
          opts
        )
      end
    end
  end

  defp build_execute_fn(ctx) do
    %{
      names: names,
      execute_arguments: execute_arguments,
      execute_values: execute_values,
      input_types: input_types,
      sig: sig
    } = ctx

    spec_args = [address_spec() | spec_args(input_types)] ++ [opts_spec()]
    doc = doc_for(:execute, names.execute, sig.abi)

    quote do
      @doc unquote(doc)
      @spec unquote(spec_call(names.execute, spec_args)) :: {:ok, binary()} | {:error, term()}
      def unquote(names.execute)(contract, unquote_splicing(execute_arguments), opts \\ []) do
        Cartouche.RPC.execute_trx(
          contract,
          unquote(names.encode)(unquote_splicing(execute_values)),
          opts
        )
      end
    end
  end

  defp build_exec_vm_fn(ctx) do
    %{
      names: names,
      execute_arguments: execute_arguments,
      execute_values: execute_values,
      input_types: input_types,
      return_types: return_types,
      sig: sig
    } = ctx

    spec_args = spec_args(input_types) ++ [opts_spec()]
    doc = doc_for(:exec_vm, names.exec_vm, sig.abi)
    return_spec = exec_vm_return_spec(return_types)

    quote do
      @doc unquote(doc)
      @spec unquote(spec_call(names.exec_vm, spec_args)) :: unquote(return_spec)
      def unquote(names.exec_vm)(unquote_splicing(execute_arguments), exec_opts \\ []) do
        case Cartouche.VM.exec_call(
               deployed_bytecode(),
               unquote(names.encode)(unquote_splicing(execute_values)),
               exec_opts
             ) do
          {:ok, return_data} ->
            preintern_return_atoms!(unquote(names.selector)().returns)

            case ABI.decode(
                   %ABI.FunctionSelector{types: unquote(names.selector)().returns},
                   return_data,
                   decode_structs: true
                 ) do
              m when is_map(m) -> {:ok, m}
              [decoded] -> {:ok, decoded}
              els -> {:ok, els}
            end

          {:revert, revert_data} ->
            case apply(__MODULE__, :decode_error, [revert_data]) do
              {:ok, error, data} -> {:revert, error, data}
              :not_found -> {:revert, "Unknown", revert_data}
            end
        end
      end
    end
  end

  # `decode_structs: true` (hieroglyph 1.4+) resolves ABI return-field names via
  # `String.to_existing_atom/1` at decode time, so those atoms must already be
  # interned. A generated module owns a *bounded* field set, fully known from the
  # ABI at generation time — so we compute the atoms here (one controlled
  # `String.to_atom/1` over operator-supplied ABI, never on consumer input) and
  # emit them as a compile-time literal the BEAM interns when the module loads.
  # This replaces the previous runtime walk, which shipped an unbounded-looking
  # `String.to_atom/1` into every generated contract (flagged at each consumer).
  @spec build_preintern_return_atoms_fns([atom()]) :: [Macro.t()]
  defp build_preintern_return_atoms_fns(field_atoms) do
    [
      quote do
        @decode_field_atoms unquote(field_atoms)
        @spec preintern_return_atoms!(term()) :: [atom()]
        defp preintern_return_atoms!(_returns), do: @decode_field_atoms
      end
    ]
  end

  # Collect, at generation time, every ABI return-field name atom a module's
  # `decode_structs: true` decode can produce — the same recursion the old
  # runtime walk performed (named fields, recursing through tuples and arrays),
  # but resolved once over the contract's own ABI.
  @spec collect_return_field_atoms(map()) :: [atom()]
  defp collect_return_field_atoms(abi_map) do
    (abi_map["abi"] || [])
    |> Enum.flat_map(&selector_return_field_atoms/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec selector_return_field_atoms(map()) :: [atom()]
  defp selector_return_field_atoms(abi_item) do
    %ABI.FunctionSelector{returns: returns} = ABI.FunctionSelector.parse_specification_item(abi_item)
    field_name_atoms(normalize_return_types(returns))
  rescue
    _ in @parse_specification_errors -> []
  end

  @spec field_name_atoms([map()] | term()) :: [atom()]
  defp field_name_atoms(types) when is_list(types), do: Enum.flat_map(types, &field_name_atom/1)
  defp field_name_atoms(_), do: []

  @spec field_name_atom(map() | term()) :: [atom()]
  defp field_name_atom(%{name: name, type: type}), do: name_to_atom(name) ++ type_field_name_atoms(type)
  defp field_name_atom(_), do: []

  @spec name_to_atom(term()) :: [atom()]
  defp name_to_atom(name) when is_binary(name) and name != "", do: [String.to_atom(Macro.underscore(name))]
  defp name_to_atom(_), do: []

  @spec type_field_name_atoms(term()) :: [atom()]
  defp type_field_name_atoms({:tuple, types}), do: field_name_atoms(types)
  defp type_field_name_atoms({:array, type}), do: type_field_name_atoms(type)
  defp type_field_name_atoms({:array, type, _size}), do: type_field_name_atoms(type)
  defp type_field_name_atoms(_), do: []

  defp build_exec_vm_raw_fn(ctx) do
    %{
      names: names,
      execute_arguments: execute_arguments,
      execute_values: execute_values,
      input_types: input_types,
      sig: sig
    } = ctx

    spec_args = spec_args(input_types) ++ [opts_spec()]
    doc = doc_for(:exec_vm_raw, names.exec_vm_raw, sig.abi)

    quote do
      @doc unquote(doc)
      @spec unquote(spec_call(names.exec_vm_raw, spec_args)) :: {:ok, binary()} | {:revert, binary()}
      def unquote(names.exec_vm_raw)(unquote_splicing(execute_arguments), exec_opts \\ []) do
        Cartouche.VM.exec_call(
          deployed_bytecode(),
          unquote(names.encode)(unquote_splicing(execute_values)),
          exec_opts
        )
      end
    end
  end

  @spec build_selector_fn(%{
          :names => map(),
          :selector => ABI.FunctionSelector.t(),
          :sig => map(),
          optional(atom()) => any()
        }) :: Macro.t()
  defp build_selector_fn(%{names: names, selector: selector, sig: sig}) do
    doc = doc_for(:selector, names.selector, sig.abi)

    quote do
      @doc unquote(doc)
      @spec unquote(names.selector)() :: ABI.FunctionSelector.t()
      def unquote(names.selector)() do
        unquote(Macro.escape(selector))
      end
    end
  end

  @spec build_event_selector_fn(%{
          :names => map(),
          :selector => ABI.FunctionSelector.t(),
          :sig => map(),
          optional(atom()) => any()
        }) :: Macro.t()
  defp build_event_selector_fn(%{names: names, selector: selector, sig: sig}) do
    doc = doc_for(:event_selector, names.event_selector, sig.abi)

    quote do
      @doc unquote(doc)
      @spec unquote(names.event_selector)() :: ABI.FunctionSelector.t()
      def unquote(names.event_selector)() do
        unquote(Macro.escape(selector))
      end
    end
  end

  @spec build_decode_event_fn(%{
          :names => map(),
          :sig => map(),
          optional(atom()) => any()
        }) :: Macro.t()
  defp build_decode_event_fn(%{names: names, sig: sig}) do
    doc = doc_for(:decode_event, names.decode_event, sig.abi)

    quote do
      @doc unquote(doc)
      @spec unquote(names.decode_event)([binary()], binary()) ::
              {:ok, String.t() | nil, map()} | {:error, term()}
      def unquote(names.decode_event)(topics, data) when is_list(topics) do
        unquote(sig.abi_enc_signature_hex)
        ABI.Event.decode_event(data, topics, unquote(names.event_selector)())
      end
    end
  end

  @spec build_decode_call_fn(%{
          :names => map(),
          :input_types => [ABI.FunctionSelector.argument_type()],
          :sig => map(),
          optional(atom()) => any()
        }) :: Macro.t()
  defp build_decode_call_fn(%{names: names, input_types: input_types, sig: sig}) do
    doc = doc_for(:decode_call, names.decode_call, sig.abi)
    input_spec = abi_decode_return_spec(input_types)

    quote do
      @doc unquote(doc)
      @spec unquote(names.decode_call)(binary()) :: unquote(input_spec)
      def unquote(names.decode_call)(<<unquote_splicing(sig.abi_enc_signature_list)>> <> calldata) do
        unquote(sig.abi_enc_signature_hex)
        ABI.decode(unquote(names.selector)(), calldata)
      end
    end
  end

  @spec build_decode_error_fn(%{
          :names => map(),
          :input_types => [ABI.FunctionSelector.argument_type()],
          :sig => map(),
          optional(atom()) => any()
        }) :: Macro.t()
  defp build_decode_error_fn(%{names: names, input_types: input_types, sig: sig}) do
    doc = doc_for(:decode_error, names.decode_error, sig.abi)
    # An error decoder decodes the error's *input* params (Solidity errors carry
    # inputs, never returns), so its return spec comes from `input_types` — the
    # same source `build_decode_call_fn` uses. Keying off `return_types` here
    # emitted `:: []` for every error decoder, since `selector.returns` is nil
    # for errors (e.g. `decode_stumble_error/1` for `Stumble(uint256)`).
    decoded_spec = abi_decode_return_spec(input_types)

    quote do
      @doc unquote(doc)
      @spec unquote(names.decode_error)(binary()) :: unquote(decoded_spec)
      def unquote(names.decode_error)(<<unquote_splicing(sig.abi_enc_signature_list)>> <> error) do
        unquote(sig.abi_enc_signature_hex)
        ABI.decode(unquote(names.selector)(), error)
      end
    end
  end

  @spec build_generic_decode_call_fn(%{
          :names => map(),
          :sig => map(),
          optional(atom()) => any()
        }) :: Macro.t()
  defp build_generic_decode_call_fn(%{names: names, sig: sig}) do
    quote do
      def decode_call(<<unquote_splicing(sig.abi_enc_signature_list)>> <> _ = calldata) do
        unquote(sig.abi_enc_signature_hex)
        {:ok, unquote(sig.error_name), unquote(names.decode_call)(calldata)}
      end
    end
  end

  @spec build_generic_error_fn(%{
          :names => map(),
          :sig => map(),
          optional(atom()) => any()
        }) :: Macro.t()
  defp build_generic_error_fn(%{names: names, sig: sig}) do
    quote do
      def decode_error(<<unquote_splicing(sig.abi_enc_signature_list)>> <> _ = error) do
        unquote(sig.abi_enc_signature_hex)
        {:ok, unquote(sig.error_name), unquote(names.decode_error)(error)}
      end
    end
  end

  @spec build_generic_event_fn(%{
          :names => map(),
          :sig => map(),
          optional(atom()) => any()
        }) :: Macro.t()
  defp build_generic_event_fn(%{names: names, sig: sig}) do
    quote do
      def decode_event([<<unquote_splicing(sig.signature_list)>> | _] = topics, data) do
        unquote(names.decode_event)(topics, data)
      end
    end
  end

  @spec build_generic_decode_call_annotations() :: Macro.t()
  defp build_generic_decode_call_annotations do
    quote do
      @doc "Decodes ABI calldata and dispatches to the matching generated call decoder."
      @spec decode_call(binary()) :: {:ok, String.t() | nil, term()} | :not_found
    end
  end

  @spec build_generic_decode_call_fallback_fn() :: Macro.t()
  defp build_generic_decode_call_fallback_fn do
    quote do
      def decode_call(_), do: :not_found
    end
  end

  @spec build_generic_decode_error_annotations() :: Macro.t()
  defp build_generic_decode_error_annotations do
    quote do
      @doc "Decodes ABI revert data and dispatches to the matching generated error decoder."
      @spec decode_error(binary()) :: {:ok, String.t() | nil, term()} | :not_found
    end
  end

  @spec build_generic_decode_error_fallback_fn() :: Macro.t()
  defp build_generic_decode_error_fallback_fn do
    quote do
      def decode_error(_), do: :not_found
    end
  end

  @spec build_generic_decode_event_annotations() :: Macro.t()
  defp build_generic_decode_event_annotations do
    quote do
      @doc "Decodes ABI event topics and data with the matching generated event decoder."
      @spec decode_event([binary()], binary()) :: {:ok, String.t() | nil, map()} | {:error, term()} | :not_found
    end
  end

  @spec build_generic_decode_event_fallback_fn() :: Macro.t()
  defp build_generic_decode_event_fallback_fn do
    quote do
      def decode_event(_, _), do: :not_found
    end
  end

  @spec spec_args([ABI.FunctionSelector.argument_type()]) :: [Macro.t()]
  defp spec_args(types), do: Enum.map(types, &abi_argument_spec/1)

  @spec abi_argument_spec(ABI.FunctionSelector.argument_type()) :: Macro.t()
  defp abi_argument_spec(%{type: type}), do: abi_type_spec(type)

  # ABI.FunctionSelector.t().returns is officially `type() | [argument_type()] | nil`
  # (deps/hieroglyph/lib/abi/function_selector.ex:51), so the bare-type clause is
  # part of the supported contract. The current upstream parser only emits nil or a
  # list, which makes dialyzer narrow this clause to dead — suppress the narrowing
  # rather than delete a clause that the public type still admits.
  @dialyzer {:no_match, normalize_return_types: 1}
  @spec normalize_return_types(ABI.FunctionSelector.type() | [ABI.FunctionSelector.argument_type()] | nil) ::
          [ABI.FunctionSelector.argument_type()]
  defp normalize_return_types(nil), do: []
  defp normalize_return_types(types) when is_list(types), do: types
  defp normalize_return_types(type), do: [%{type: type}]

  @spec abi_decode_return_spec([ABI.FunctionSelector.argument_type()]) :: Macro.t()
  defp abi_decode_return_spec([]), do: []

  defp abi_decode_return_spec([type]) do
    type
    |> abi_argument_spec()
    |> List.wrap()
  end

  defp abi_decode_return_spec(types) do
    types
    |> Enum.map(&abi_argument_spec/1)
    |> union_list_spec()
  end

  @spec exec_vm_return_spec([ABI.FunctionSelector.argument_type()]) :: Macro.t()
  defp exec_vm_return_spec([]) do
    quote do
      {:ok, []} | {:revert, String.t(), term()}
    end
  end

  defp exec_vm_return_spec([type]) do
    value_spec = abi_argument_spec(type)

    quote do
      {:ok, unquote(value_spec)} | {:revert, String.t(), term()}
    end
  end

  defp exec_vm_return_spec(types) do
    value_spec = abi_decode_return_spec(types)

    quote do
      {:ok, unquote(value_spec)} | {:revert, String.t(), term()}
    end
  end

  @spec union_list_spec([Macro.t()]) :: Macro.t()
  defp union_list_spec(specs), do: [union_spec(specs)]

  @spec union_spec([Macro.t()]) :: Macro.t()
  defp union_spec([spec]), do: spec
  defp union_spec([spec | rest]), do: {:|, [], [spec, union_spec(rest)]}

  @spec abi_type_spec(ABI.FunctionSelector.type()) :: Macro.t()
  defp abi_type_spec({:uint, _}), do: quote(do: non_neg_integer())
  defp abi_type_spec({:int, _}), do: quote(do: integer())
  defp abi_type_spec(:bool), do: quote(do: boolean())
  defp abi_type_spec(:address), do: address_spec()
  defp abi_type_spec(:bytes), do: quote(do: binary())
  defp abi_type_spec({:bytes, size}), do: {:<<>>, [], [{:"::", [], [{:_, [], Elixir}, size * 8]}]}
  defp abi_type_spec(:string), do: quote(do: String.t())
  defp abi_type_spec(:function), do: quote(do: <<_::192>>)
  defp abi_type_spec({:array, type}), do: quote(do: [unquote(abi_type_spec(type))])
  defp abi_type_spec({:array, type, _size}), do: quote(do: [unquote(abi_type_spec(type))])

  defp abi_type_spec({:tuple, types}) do
    types
    |> Enum.map(&abi_argument_spec/1)
    |> tuple_or_map_spec(types)
  end

  # sobelow_skip ["DOS.StringToAtom"]
  @spec tuple_or_map_spec([Macro.t()], [ABI.FunctionSelector.argument_type()]) :: Macro.t()
  defp tuple_or_map_spec(specs, types) do
    tuple_spec = {:{}, [], specs}

    if named_tuple?(types) do
      keyword_specs =
        Enum.map(types, fn %{name: name, type: type} ->
          {String.to_atom(Macro.underscore(name)), abi_type_spec(type)}
        end)

      quote do
        %{unquote_splicing(keyword_specs)} | unquote(tuple_spec)
      end
    else
      tuple_spec
    end
  end

  @spec named_tuple?([ABI.FunctionSelector.argument_type()]) :: boolean()
  defp named_tuple?(types) do
    Enum.all?(types, fn type ->
      name = Map.get(type, :name)
      is_binary(name) and name != ""
    end)
  end

  @spec address_spec() :: Macro.t()
  defp address_spec, do: quote(do: <<_::160>>)

  @spec opts_spec() :: Macro.t()
  defp opts_spec, do: quote(do: Keyword.t())

  @spec spec_call(atom(), [Macro.t()]) :: Macro.t()
  defp spec_call(name, args), do: {name, [], args}

  @spec doc_for(atom(), atom(), binary()) :: String.t()
  defp doc_for(kind, generated_name, signature) do
    "#{Map.fetch!(@doc_purposes, kind)} for `#{generated_name}/#{signature}`."
  end

  defp select_emitted_fns(%{function_type: :error}, _has_deployed_bytecode, fns) do
    {[fns.selector_fn, fns.encode_fn, fns.decode_error_fn], nil, nil, fns.generic_error_fn}
  end

  defp select_emitted_fns(%{function_type: :event}, _has_deployed_bytecode, fns) do
    {[fns.event_selector_fn, fns.encode_fn, fns.decode_event_fn], nil, fns.generic_event_fn, nil}
  end

  defp select_emitted_fns(%{function_type: t}, _has_deployed_bytecode, fns)
       when t in [:constructor, :fallback, :receive] do
    {[fns.encode_fn, fns.prepare_fn, fns.execute_fn], nil, nil, nil}
  end

  defp select_emitted_fns(%{state_mutability: :pure}, true, fns) do
    {[
       fns.selector_fn,
       fns.encode_fn,
       fns.prepare_fn,
       fns.build_trx_fn,
       fns.call_fn,
       fns.estimate_gas_fn,
       fns.execute_fn,
       fns.decode_call_fn,
       fns.exec_vm_fn,
       fns.exec_vm_raw_fn
     ], fns.generic_decode_call_fn, nil, nil}
  end

  defp select_emitted_fns(_selector, _has_deployed_bytecode, fns) do
    {[
       fns.selector_fn,
       fns.encode_fn,
       fns.prepare_fn,
       fns.build_trx_fn,
       fns.call_fn,
       fns.estimate_gas_fn,
       fns.execute_fn,
       fns.decode_call_fn
     ], fns.generic_decode_call_fn, nil, nil}
  end

  # Generate the bytecode function
  # Note: I wanted to use ~h[] syntax, but generating that was being weird.
  defp get_bytecode(abi) do
    bytecode = get_in(abi, ["bytecode", "object"]) || get_in(abi, ["bin"])

    if blank_bytecode?(bytecode) do
      []
    else
      [
        quote do
          @doc "Returns the contract init bytecode."
          @spec bytecode() :: binary()
          def bytecode, do: hex!(unquote(bytecode))
        end
      ]
    end
  end

  # Generate the deployed bytecode function
  defp get_deployed_bytecode(abi) do
    deployed_bytecode =
      get_in(abi, ["deployedBytecode", "object"]) || get_in(abi, ["bin-runtime"])

    if blank_bytecode?(deployed_bytecode) do
      []
    else
      [
        quote do
          @doc "Returns the contract deployed bytecode."
          @spec deployed_bytecode() :: binary()
          def deployed_bytecode, do: hex!(unquote(deployed_bytecode))
        end
      ]
    end
  end

  @spec get_abi(map()) :: [Macro.t()]
  defp get_abi(abi) do
    abi_items = abi["abi"] || []

    [
      quote do
        @doc "Returns the contract ABI entries."
        @spec abi() :: [map()]
        def abi, do: unquote(Macro.escape(abi_items))
      end
    ]
  end

  # Treat nil, empty/whitespace strings, and "0x"/"0x"+whitespace as missing
  # bytecode. Foundry emits "0x" for interfaces with no on-chain bytecode
  # (e.g. Hardhat's IConsole), and `is_nil` alone wouldn't catch those —
  # leaving callers to compile-encode <<>> as if it were real code.
  defp blank_bytecode?(nil), do: true

  defp blank_bytecode?(s) when is_binary(s) do
    trimmed = String.trim(s)

    cond do
      trimmed == "" -> true
      unlinked_library_bytecode?(trimmed) -> true
      String.starts_with?(trimmed, "0x") -> trimmed |> String.replace_prefix("0x", "") |> String.trim() == ""
      true -> false
    end
  end

  defp blank_bytecode?(_), do: false

  defp unlinked_library_bytecode?(bytecode) do
    Regex.match?(@unlinked_library_marker, bytecode)
  end

  # The crux of it. Builds the entire module with function declarations, etc
  # based on the output-json "abi" of a given Solidity contract.
  defp build_module(prefix, out, abi_map) do
    contract_name = get_contract_name_by_metadata(abi_map) || get_contract_name_by_ast(abi_map)
    if is_nil(contract_name), do: raise("did not find contract name")

    prefix_parts =
      prefix
      |> String.split("/")
      |> Enum.filter(fn x -> String.length(x) > 0 end)

    prefix_mod = Enum.map(prefix_parts, &Macro.camelize/1)

    module_name =
      String.to_atom(Enum.join(List.flatten(["Elixir", prefix_mod, contract_name]), "."))

    file_name =
      Path.join(
        List.flatten([
          out,
          prefix_parts,
          "#{Macro.underscore(contract_name)}.ex"
        ])
      )

    abi_decl = abi_map |> get_abi() |> flatten_quote_blocks()
    bytecode_decl = abi_map |> get_bytecode() |> flatten_quote_blocks()
    deployed_bytecode_decl = abi_map |> get_deployed_bytecode() |> flatten_quote_blocks()
    has_bytecode = not Enum.empty?(bytecode_decl)
    has_deployed_bytecode = not Enum.empty?(deployed_bytecode_decl)
    encode_call_decl = get_encode_calls(abi_map, has_bytecode, has_deployed_bytecode)

    preintern_return_atoms_decl =
      if uses_preintern_return_atoms?(encode_call_decl) do
        build_preintern_return_atoms_fns(collect_return_field_atoms(abi_map))
      else
        []
      end

    quote_result =
      quote do
        defmodule unquote(module_name) do
          @moduledoc false
          use Cartouche.Hex

          alias Cartouche.Transaction.Call

          @doc "Returns the contract name."
          @spec contract_name() :: String.t()
          def contract_name, do: unquote(contract_name)

          unquote_splicing(abi_decl)
          unquote_splicing(encode_call_decl)
          unquote_splicing(bytecode_decl)
          unquote_splicing(deployed_bytecode_decl)
          unquote_splicing(preintern_return_atoms_decl)
        end
      end

    contents =
      quote_result
      |> annotate_internal_defs()
      |> Macro.to_string()
      |> strip_zero_arity_def_parens()

    {file_name, contents}
  end

  @spec uses_preintern_return_atoms?(Macro.t() | [Macro.t()]) :: boolean()
  defp uses_preintern_return_atoms?(quoted) do
    {_quoted, used?} =
      Macro.prewalk(quoted, false, fn
        {:preintern_return_atoms!, _, _} = node, _used? -> {node, true}
        node, used? -> {node, used?}
      end)

    used?
  end

  # Macro-time `def unquote(name)()` requires the trailing parens for the AST to
  # form a valid function-name shape, but the formatted output then trips
  # Credo's ParenthesesOnZeroArityDefs. Strip empty parens from `def`/`defp`
  # lines as a post-process — text-level only, def-line-anchored.
  defp strip_zero_arity_def_parens(source) do
    Regex.replace(~r/^(\s*defp?\s+[a-z_][a-zA-Z0-9_!?]*)\(\)/m, source, "\\1")
  end

  # Template builders annotate generated public functions directly with ABI-aware
  # docs/specs. This post-pass only fills specs for generated private helpers.
  defp annotate_internal_defs({:defmodule, dm_meta, [name, [do: do_block]]}) do
    {:defmodule, dm_meta, [name, [do: annotate_block(do_block)]]}
  end

  defp annotate_block({:__block__, b_meta, stmts}) do
    {new_stmts, _seen} = Enum.flat_map_reduce(stmts, MapSet.new(), &annotate_stmt/2)
    {:__block__, b_meta, new_stmts}
  end

  defp annotate_block(single_stmt) do
    {stmts, _seen} = annotate_stmt(single_stmt, MapSet.new())

    case stmts do
      [single] -> single
      many -> {:__block__, [], many}
    end
  end

  defp annotate_stmt({:defp, _, [head, _body]} = def_ast, seen) do
    case extract_name_arity(head) do
      nil ->
        {[def_ast], seen}

      key ->
        if MapSet.member?(seen, key) do
          {[def_ast], seen}
        else
          {name, arity} = key
          {build_annotations(name, arity) ++ [def_ast], MapSet.put(seen, key)}
        end
    end
  end

  defp annotate_stmt({:alias, _, _} = alias_ast, seen), do: {[alias_ast], seen}

  defp annotate_stmt(other, seen), do: {[other], seen}

  defp extract_name_arity({:when, _, [inner, _guard]}), do: extract_name_arity(inner)
  defp extract_name_arity({name, _, args}) when is_atom(name) and is_list(args), do: {name, length(args)}
  defp extract_name_arity({name, _, _ctx}) when is_atom(name), do: {name, 0}
  defp extract_name_arity(_), do: nil

  defp build_annotations(name, arity) do
    spec_args = List.duplicate({:term, [], []}, arity)
    spec_call = {name, [], spec_args}
    spec_ret = {:term, [], []}

    [{:@, [], [{:spec, [], [{:"::", [], [spec_call, spec_ret]}]}]}]
  end

  # Gets the output-json of all included Solidity files to auto-generate.
  defp get_json_out(patterns) do
    patterns
    |> Enum.flat_map(fn pattern -> Path.wildcard(pattern) end)
    |> Enum.map(fn filename -> {filename, File.read!(filename)} end)
    |> Enum.map(fn {filename, contents} -> {filename, Jason.decode!(contents)} end)
    |> Enum.map(fn {filename, contents} ->
      cond do
        is_map(contents) and Map.has_key?(contents, "abi") ->
          # Normal Soidity output
          contents

        is_list(contents) ->
          # Just an ABI, convert to Solidity
          %{
            "abi" => contents,
            "metadata" => %{
              "settings" => %{
                "compilationTarget" => %{
                  filename => Macro.camelize(Path.basename(filename, ".json"))
                }
              }
            }
          }

        true ->
          raise InvalidFileError, "Invalid Solidity output or ABI in `#{filename}`"
      end
    end)
  end

  @doc false
  def run(args) do
    case OptionParser.parse(args, strict: [prefix: :string, out: :string]) do
      {opts, [_ | _] = patterns, []} ->
        prefix = Keyword.get(opts, :prefix, "")
        out = Keyword.get(opts, :out, "lib/")

        patterns
        |> get_json_out()
        |> Enum.map(fn abi_map -> build_module(prefix, out, abi_map) end)
        |> Enum.each(fn {path, contents} ->
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, Code.format_string!(contents) ++ "\n")
          Logger.info("Generated #{path}")
        end)

      _ ->
        raise "usage: mix cartouche.gen --prefix [prefix] --out [out=lib/] [patterns]"
    end
  end
end
