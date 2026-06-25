defmodule Onchain.Contract.Generator do
  @moduledoc """
  Compile-time contract codegen macro.

  Reads a Solidity ABI (from `.sol` source, ABI JSON string, or ABI JSON file)
  at compile time via `Onchain.Solidity`, then generates typed Elixir functions
  for every contract function found in the ABI.

  ## Usage

      defmodule MyApp.ERC20 do
        use Onchain.Contract.Generator,
          abi_json: File.read!("priv/abis/erc20.json")
      end

      defmodule MyApp.Pool do
        use Onchain.Contract.Generator,
          sol: File.read!("priv/contracts/IPool.sol")
      end

      defmodule MyApp.UiPool do
        use Onchain.Contract.Generator,
          sol_file: "priv/contracts/real/aave/IUiPoolDataProviderV3.sol"
      end

  ## Generated Functions

  For each ABI function, generates:

  - **Read functions** (`view`/`pure`): `fn_name(contract, ...params, opts \\\\ [])`
    delegates to `Onchain.Contract.call/5`
  - **Write functions** (`nonpayable`/`payable`): `fn_name(contract, ...params, opts)`
    encodes calldata via `Onchain.ABI.encode_call/2` and delegates to
    `Onchain.Signer.send_transaction/3`
  - **Bang variants**: `fn_name!` that raises on error
  - **`__contract_abi__/0`**: returns the full parsed ABI map

  ## Address Validation

  Parameters with Solidity type `address` are validated via
  `Onchain.Address.validate/1` before being passed to the ABI encoder.

  ## Overload Disambiguation

  When multiple Solidity functions share the same name but differ in parameter
  count, generated Elixir function names are suffixed with input type names
  to avoid arity collisions. For example, `transfer(address,uint256)` and
  `transfer(address,address,uint256)` become `transfer/3` and
  `transfer_address/4` (suffixed with the disambiguating extra param type).

  ## Options

  Provide one of the following source options. If multiple are given, the first
  match in this order is used (the rest are ignored):

  - `:sol` — raw Solidity source code as a string (e.g., `File.read!("priv/contracts/IPool.sol")`)
  - `:sol_file` — path to a `.sol` file, resolved relative to the calling module's source directory
  - `:abi_json` — ABI as a JSON string (e.g., `File.read!("priv/abis/erc20.json")`)
  - `:abi_file` — path to an ABI JSON file, passed as-is to `File.read/1`
    (use an absolute path or a path relative to the project root / CWD)

  Additional options (only valid with `:sol_file`):

  - `:remappings` — a list of Foundry-style remapping strings
    (e.g., `["@aave/core-v3/=lib/aave-v3-core/"]`)
  - `:root_contract` — name of the contract or interface to extract when the file
    contains multiple definitions (e.g., `"IPoolV3"`)

  ## .sol Extras

  When using `sol:` source:

  - **Struct modules**: nested `defmodule` with `@enforce_keys`, `defstruct`,
    and `from_raw/1` for each struct definition
  - **Enum constants**: module attributes `@enum_name_variant index` for each
    enum variant
  - **NatSpec docs**: `@doc` pulled from `/// @notice` comments
  """

  @doc false
  defmacro __using__(opts) do
    quote do
      @before_compile {Onchain.Contract.Generator, :__before_compile__}
      Module.put_attribute(__MODULE__, :__contract_opts__, unquote(opts))
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    opts = Module.get_attribute(env.module, :__contract_opts__)
    %{abi: abi, is_sol: is_sol, external_files: external_files} = resolve_contract_input(opts, env)

    Enum.each(external_files, fn file ->
      Module.put_attribute(env.module, :external_resource, file)
    end)

    functions = abi.functions
    {read_fns, write_fns} = split_by_mutability(functions)
    disambiguated = disambiguate(functions)

    moduledoc = generate_moduledoc(disambiguated, read_fns, write_fns)
    abi_fn = generate_abi_fn(abi)
    dialyzer_annotations = generate_dialyzer(disambiguated)
    enum_attrs = if is_sol, do: generate_enum_fns(abi), else: []
    struct_modules = if is_sol, do: generate_struct_modules(abi, env.module), else: []
    fn_asts = Enum.flat_map(disambiguated, &generate_function(&1, is_sol))

    quote do
      @moduledoc unquote(moduledoc)
      unquote_splicing(dialyzer_annotations)
      unquote_splicing(enum_attrs)
      unquote_splicing(struct_modules)
      unquote_splicing(fn_asts)
      unquote(abi_fn)
    end
  end

  # --- ABI Resolution ---

  @doc false
  @spec resolve_abi(keyword()) :: Onchain.Solidity.parsed_abi()
  def resolve_abi(opts) do
    resolve_contract_input(opts, nil).abi
  end

  @doc false
  # Resolves compile-time contract inputs, including real Solidity file graphs.
  @spec resolve_contract_input(keyword(), Macro.Env.t() | nil) ::
          %{abi: Onchain.Solidity.parsed_abi(), is_sol: boolean(), external_files: [String.t()]}
  def resolve_contract_input(opts, env) do
    cond do
      sol = Keyword.get(opts, :sol) ->
        %{abi: Onchain.Solidity.parse_sol!(sol), is_sol: true, external_files: []}

      file = Keyword.get(opts, :sol_file) ->
        resolve_sol_file_input(file, opts, env)

      json = Keyword.get(opts, :abi_json) ->
        %{abi: Onchain.Solidity.parse_abi_json!(json), is_sol: false, external_files: []}

      file = Keyword.get(opts, :abi_file) ->
        %{abi: Onchain.Solidity.parse_abi_file!(file), is_sol: false, external_files: []}

      true ->
        raise ArgumentError,
              "use Onchain.Contract.Generator requires :sol, :sol_file, :abi_json, or :abi_file option"
    end
  end

  @doc false
  # Resolves a root Solidity file relative to the caller module and parses the selected contract.
  @spec resolve_sol_file_input(String.t(), keyword(), Macro.Env.t() | nil) ::
          %{abi: Onchain.Solidity.parsed_sol(), is_sol: true, external_files: [String.t()]}
  defp resolve_sol_file_input(file, opts, env) do
    sol_path = expand_sol_file_path(file, env)
    sol_opts = Keyword.take(opts, [:remappings, :root_contract])
    resolution = Onchain.Solidity.resolve_sol_file!(sol_path, sol_opts)

    abi =
      case Onchain.Solidity.__parse_sol_root__(resolution.source, resolution.root_contract) do
        {:ok, parsed} -> parsed
        {:error, {:parse_error, reason}} -> raise "Solidity parse failed: #{reason}"
        {:error, reason} -> raise "Solidity parse failed: #{inspect(reason)}"
      end

    %{abi: abi, is_sol: true, external_files: resolution.files}
  end

  @doc false
  # Expands sol_file paths relative to the caller file when available.
  @spec expand_sol_file_path(String.t(), Macro.Env.t() | nil) :: String.t()
  defp expand_sol_file_path(file, nil), do: Path.expand(file)

  @doc false
  defp expand_sol_file_path(file, env) do
    Path.expand(file, Path.dirname(env.file))
  end

  # --- Name Conversion ---

  @doc false
  @spec to_snake_case(String.t()) :: String.t()
  def to_snake_case(name) do
    name
    |> String.replace(~r/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1_\\2")
    |> String.downcase()
  end

  # --- Overload Disambiguation ---

  @doc false
  @spec disambiguate([map()]) :: [map()]
  def disambiguate(functions) do
    functions
    |> Enum.map(fn f -> Map.put(f, :elixir_name, to_snake_case(f.name)) end)
    |> disambiguate_collisions()
  end

  @doc false
  @spec disambiguate_collisions([map()]) :: [map()]
  defp disambiguate_collisions(functions) do
    # Group by {snake_name, input_count + 2} (contract + opts params)
    groups =
      Enum.group_by(functions, fn f ->
        {f.elixir_name, length(f.inputs) + 2}
      end)

    Enum.map(functions, fn f ->
      key = {f.elixir_name, length(f.inputs) + 2}

      case Map.get(groups, key) do
        [_single] ->
          f

        collisions when length(collisions) > 1 ->
          # Find the input types that distinguish this overload
          suffix = disambiguation_suffix(f, collisions)
          %{f | elixir_name: f.elixir_name <> "_" <> suffix}
      end
    end)
  end

  @doc false
  @spec disambiguation_suffix(map(), [map()]) :: String.t()
  defp disambiguation_suffix(func, collisions) do
    # For same-arity overloads, suffix with the type of the input that differs
    # Find inputs that are unique to this overload
    other_input_sets =
      collisions
      |> Enum.reject(&(&1.signature == func.signature))
      |> Enum.map(fn f -> Enum.map(f.inputs, & &1.ty) end)

    my_types = Enum.map(func.inputs, & &1.ty)

    # Find first type position unique to this overload
    my_types
    |> Enum.with_index()
    |> Enum.find_value(&unique_type_suffix(&1, other_input_sets))
    # All types match (shouldn't happen with same arity), use full input count
    |> Kernel.||("#{length(func.inputs)}")
  end

  @doc false
  @spec solidity_type_to_suffix(String.t()) :: String.t()
  defp solidity_type_to_suffix("address"), do: "address"
  defp solidity_type_to_suffix("bool"), do: "bool"
  defp solidity_type_to_suffix("string"), do: "string"
  defp solidity_type_to_suffix("bytes"), do: "bytes"
  defp solidity_type_to_suffix("tuple"), do: "tuple"
  defp solidity_type_to_suffix(type), do: type

  @doc false
  # Returns the type suffix if this type at position i is unique across all other overloads
  @spec unique_type_suffix({String.t(), non_neg_integer()}, [[String.t()]]) :: String.t() | nil
  defp unique_type_suffix({my_type, i}, other_input_sets) do
    if Enum.all?(other_input_sets, fn other -> Enum.at(other, i) != my_type end) do
      solidity_type_to_suffix(my_type)
    end
  end

  # --- Mutability Split ---

  @doc false
  @spec split_by_mutability([map()]) :: {[map()], [map()]}
  defp split_by_mutability(functions) do
    Enum.split_with(functions, fn f ->
      f.state_mutability in ["view", "pure"]
    end)
  end

  # --- Code Generation ---

  @doc false
  @spec generate_moduledoc([map()], [map()], [map()]) :: String.t()
  defp generate_moduledoc(functions, read_fns, write_fns) do
    read_names = MapSet.new(read_fns, & &1.name)
    write_names = MapSet.new(write_fns, & &1.name)

    read_lines =
      functions
      |> Enum.filter(fn f -> f.name in read_names end)
      |> Enum.map(fn f -> "  | `#{f.elixir_name}/#{length(f.inputs) + 2}` | #{f.signature} | read |" end)

    write_lines =
      functions
      |> Enum.filter(fn f -> f.name in write_names end)
      |> Enum.map(fn f -> "  | `#{f.elixir_name}/#{length(f.inputs) + 2}` | #{f.signature} | write |" end)

    lines = read_lines ++ write_lines

    """
    Auto-generated contract module via `Onchain.Contract.Generator`.

    ## Functions

    | Function | Solidity | Type |
    |----------|----------|------|
    #{Enum.join(lines, "\n")}
    """
  end

  @doc false
  @spec generate_abi_fn(Onchain.Solidity.parsed_abi()) :: Macro.t()
  defp generate_abi_fn(abi) do
    quote do
      @doc "Returns the full parsed ABI map for this contract."
      @spec __contract_abi__() :: map()
      def __contract_abi__, do: unquote(Macro.escape(abi))
    end
  end

  @doc false
  @spec generate_dialyzer([map()]) :: [Macro.t()]
  defp generate_dialyzer(functions) do
    # Generate @dialyzer annotations for all functions (same cascade as erc20.ex)
    all_fns =
      Enum.flat_map(functions, fn f ->
        name = String.to_atom(f.elixir_name)
        bang = String.to_atom(f.elixir_name <> "!")
        # arity: contract + inputs + opts
        arity = length(f.inputs) + 2
        # bang arity without default opts (for reads, -1 since opts has default)
        is_read = f.state_mutability in ["view", "pure"]
        bang_arities = if is_read, do: [arity - 1, arity], else: [arity]

        [
          {:no_match, [{name, arity}, {bang, arity}]},
          {:no_return, Enum.map(bang_arities, &{bang, &1})},
          {:no_contracts, Enum.map(bang_arities, &{bang, &1})}
        ]
      end)

    # Group by type
    no_match = all_fns |> Enum.filter(&(elem(&1, 0) == :no_match)) |> Enum.flat_map(&elem(&1, 1))
    no_return = all_fns |> Enum.filter(&(elem(&1, 0) == :no_return)) |> Enum.flat_map(&elem(&1, 1))
    no_contracts = all_fns |> Enum.filter(&(elem(&1, 0) == :no_contracts)) |> Enum.flat_map(&elem(&1, 1))

    annotations = []

    annotations =
      if no_match == [], do: annotations, else: annotations ++ [quote(do: @dialyzer({:no_match, unquote(no_match)}))]

    annotations =
      if no_return == [], do: annotations, else: annotations ++ [quote(do: @dialyzer({:no_return, unquote(no_return)}))]

    annotations =
      if no_contracts == [],
        do: annotations,
        else: annotations ++ [quote(do: @dialyzer({:no_contracts, unquote(no_contracts)}))]

    annotations
  end

  @doc false
  @spec generate_function(map(), boolean()) :: [Macro.t()]
  defp generate_function(func, is_sol) do
    name = String.to_atom(func.elixir_name)
    bang_name = String.to_atom(func.elixir_name <> "!")
    is_read = func.state_mutability in ["view", "pure"]
    doc = build_doc(func, is_sol)

    input_vars = build_input_vars(func.inputs)
    address_validations = build_address_validations(func.inputs)

    if is_read do
      generate_read_function(name, bang_name, func, input_vars, address_validations, doc)
    else
      generate_write_function(name, bang_name, func, input_vars, address_validations, doc)
    end
  end

  @doc false
  @spec build_doc(map(), boolean()) :: String.t()
  defp build_doc(func, is_sol) do
    base =
      if is_sol && func[:natspec] && func.natspec[:notice] do
        func.natspec.notice
      else
        "Calls `#{func.signature}`."
      end

    param_docs =
      if is_sol && func[:natspec] && func.natspec[:params] && map_size(func.natspec.params) > 0 do
        param_lines =
          Enum.map(func.natspec.params, fn {k, v} -> "  - `#{k}`: #{v}" end)

        "\n\n## Parameters\n\n" <> Enum.join(param_lines, "\n")
      else
        ""
      end

    base <> param_docs
  end

  @doc false
  @spec build_input_vars([map()]) :: [{atom(), String.t()}]
  defp build_input_vars(inputs) do
    inputs
    |> Enum.with_index()
    |> Enum.map(fn {input, idx} -> {param_var_name(input, idx), input.ty} end)
  end

  @doc false
  @spec build_address_validations([map()]) :: [{atom(), atom()}]
  defp build_address_validations(inputs) do
    inputs
    |> Enum.with_index()
    |> Enum.filter(fn {input, _idx} -> input.ty == "address" end)
    |> Enum.map(fn {input, idx} ->
      var_name = param_var_name(input, idx)
      validated_name = String.to_atom("#{var_name}_bin")
      {var_name, validated_name}
    end)
  end

  @doc false
  # Derives an Elixir variable name from a Solidity input param, falling back to positional naming
  @spec param_var_name(map(), non_neg_integer()) :: atom()
  defp param_var_name(input, idx) do
    if input.name == "" do
      String.to_atom("param_#{idx}")
    else
      input.name |> to_snake_case() |> String.to_atom()
    end
  end

  @doc false
  @spec generate_read_function(atom(), atom(), map(), [{atom(), String.t()}], [{atom(), atom()}], String.t()) ::
          [Macro.t()]
  defp generate_read_function(name, bang_name, func, input_vars, address_validations, doc) do
    var_asts = Enum.map(input_vars, fn {vname, _ty} -> Macro.var(vname, nil) end)
    signature = func.signature
    return_type = func.return_type

    # Build the params list for Contract.call — replace address vars with validated ones
    validated_map = Map.new(address_validations)

    call_params =
      Enum.map(input_vars, fn {vname, _ty} ->
        case Map.get(validated_map, vname) do
          nil -> Macro.var(vname, nil)
          validated -> Macro.var(validated, nil)
        end
      end)

    with_chain = build_with_chain(address_validations, signature, return_type, call_params)

    [
      quote do
        @doc unquote(doc)
        @spec unquote(name)(String.t() | binary(), unquote_splicing(input_spec_types(input_vars)), keyword()) ::
                {:ok, list()} | {:error, term()}
        def unquote(name)(contract, unquote_splicing(var_asts), opts \\ []) do
          unquote(with_chain)
        end
      end,
      quote do
        @doc unquote(doc <> " Raises on error.")
        @spec unquote(bang_name)(String.t() | binary(), unquote_splicing(input_spec_types(input_vars)), keyword()) ::
                list()
        def unquote(bang_name)(contract, unquote_splicing(var_asts), opts \\ []) do
          unquote(build_bang_body(name, var_asts))
        end
      end
    ]
  end

  @doc false
  @spec build_with_chain([{atom(), atom()}], String.t(), String.t(), [Macro.t()]) :: Macro.t()
  defp build_with_chain([], signature, return_type, call_params) do
    quote do
      Onchain.Contract.call(
        contract,
        unquote(signature),
        unquote(call_params),
        unquote(return_type),
        opts
      )
    end
  end

  defp build_with_chain(validations, signature, return_type, call_params) do
    validation_clauses =
      Enum.map(validations, fn {var_name, validated_name} ->
        {:<-, [],
         [
           {:ok, Macro.var(validated_name, nil)},
           quote(do: Onchain.Address.validate(unquote(Macro.var(var_name, nil))))
         ]}
      end)

    body =
      quote do
        Onchain.Contract.call(
          contract,
          unquote(signature),
          unquote(call_params),
          unquote(return_type),
          opts
        )
      end

    {:with, [], validation_clauses ++ [[do: body]]}
  end

  # Builds the bang-wrapper body shared by generated read/write functions:
  # delegate to the non-bang function, return the value on :ok, raise on :error.
  @doc false
  @spec build_bang_body(atom(), [Macro.t()]) :: Macro.t()
  defp build_bang_body(name, var_asts) do
    quote do
      case unquote(name)(contract, unquote_splicing(var_asts), opts) do
        {:ok, result} -> result
        {:error, reason} -> raise "#{unquote(Atom.to_string(name))} failed: #{inspect(reason)}"
      end
    end
  end

  @doc false
  @spec generate_write_function(atom(), atom(), map(), [{atom(), String.t()}], [{atom(), atom()}], String.t()) ::
          [Macro.t()]
  defp generate_write_function(name, bang_name, func, input_vars, address_validations, doc) do
    var_asts = Enum.map(input_vars, fn {vname, _ty} -> Macro.var(vname, nil) end)
    signature = func.signature

    validated_map = Map.new(address_validations)

    call_params =
      Enum.map(input_vars, fn {vname, _ty} ->
        case Map.get(validated_map, vname) do
          nil -> Macro.var(vname, nil)
          validated -> Macro.var(validated, nil)
        end
      end)

    with_chain = build_write_with_chain(address_validations, signature, call_params)

    [
      quote do
        @doc unquote(doc)
        @spec unquote(name)(String.t() | binary(), unquote_splicing(input_spec_types(input_vars)), keyword()) ::
                {:ok, String.t()} | {:error, term()}
        def unquote(name)(contract, unquote_splicing(var_asts), opts) do
          unquote(with_chain)
        end
      end,
      quote do
        @doc unquote(doc <> " Raises on error.")
        @spec unquote(bang_name)(String.t() | binary(), unquote_splicing(input_spec_types(input_vars)), keyword()) ::
                String.t()
        def unquote(bang_name)(contract, unquote_splicing(var_asts), opts) do
          unquote(build_bang_body(name, var_asts))
        end
      end
    ]
  end

  @doc false
  @spec build_write_with_chain([{atom(), atom()}], String.t(), [Macro.t()]) :: Macro.t()
  defp build_write_with_chain(validations, signature, call_params) do
    validation_clauses =
      Enum.map(validations, fn {var_name, validated_name} ->
        {:<-, [],
         [
           {:ok, Macro.var(validated_name, nil)},
           quote(do: Onchain.Address.validate(unquote(Macro.var(var_name, nil))))
         ]}
      end)

    encode_clause =
      {:<-, [],
       [
         {:ok, Macro.var(:calldata_hex, nil)},
         quote(do: Onchain.ABI.encode_call(unquote(signature), unquote(call_params)))
       ]}

    calldata_var = Macro.var(:calldata_hex, nil)

    body =
      quote do
        Onchain.Signer.send_transaction(
          contract,
          Onchain.Hex.decode!(unquote(calldata_var)),
          opts
        )
      end

    {:with, [], validation_clauses ++ [encode_clause] ++ [[do: body]]}
  end

  # --- Type Mapping ---

  @doc false
  @spec input_spec_types([{atom(), String.t()}]) :: [Macro.t()]
  defp input_spec_types(input_vars) do
    Enum.map(input_vars, fn {_name, ty} -> solidity_to_elixir_spec(ty) end)
  end

  @doc false
  @spec solidity_to_elixir_spec(String.t()) :: Macro.t()
  defp solidity_to_elixir_spec("address"), do: quote(do: String.t() | binary())
  defp solidity_to_elixir_spec("bool"), do: quote(do: boolean())
  defp solidity_to_elixir_spec("string"), do: quote(do: String.t())
  defp solidity_to_elixir_spec("bytes"), do: quote(do: binary())
  defp solidity_to_elixir_spec("int" <> _), do: quote(do: integer())
  defp solidity_to_elixir_spec("uint" <> _), do: quote(do: non_neg_integer())
  defp solidity_to_elixir_spec("bytes" <> _), do: quote(do: binary())
  defp solidity_to_elixir_spec("tuple"), do: quote(do: tuple())
  defp solidity_to_elixir_spec(_), do: quote(do: term())

  # --- Struct Generation (.sol only) ---

  @doc false
  @spec generate_struct_modules(Onchain.Solidity.parsed_abi(), module()) :: [Macro.t()]
  defp generate_struct_modules(abi, parent_module) do
    structs = Map.get(abi, :structs, [])
    struct_names = MapSet.new(structs, & &1.name)

    Enum.map(structs, fn struct_info ->
      mod_name = Module.concat(parent_module, struct_info.name)
      field_atoms = Enum.map(struct_info.fields, fn f -> String.to_atom(to_snake_case(f.name)) end)

      field_types =
        Enum.map(struct_info.fields, fn f ->
          {String.to_atom(to_snake_case(f.name)), solidity_to_struct_type(f.ty)}
        end)

      from_raw_body = build_from_raw(struct_info.fields, parent_module, struct_names)

      quote do
        defmodule unquote(mod_name) do
          @moduledoc "Struct for Solidity `#{unquote(struct_info.name)}`."
          @enforce_keys unquote(field_atoms)
          defstruct unquote(field_atoms)

          @type t :: %__MODULE__{unquote_splicing(field_types)}

          @doc "Convert a raw tuple from ABI decoding into a `%#{unquote(struct_info.name)}{}` struct."
          @spec from_raw(tuple()) :: t()
          def from_raw(raw) when is_tuple(raw) do
            values = Tuple.to_list(raw)
            unquote(from_raw_body)
          end
        end
      end
    end)
  end

  @doc false
  # Builds a struct literal from decoded ABI tuple values.
  @spec build_from_raw([map()], module(), MapSet.t(String.t())) :: Macro.t()
  defp build_from_raw(fields, parent_module, struct_names) do
    assignments =
      fields
      |> Enum.with_index()
      |> Enum.map(fn {field, idx} ->
        key = String.to_atom(to_snake_case(field.name))
        value = build_struct_field_value(field.ty, idx, parent_module, struct_names)

        {key, value}
      end)

    quote do
      %__MODULE__{unquote_splicing(assignments)}
    end
  end

  @doc false
  # Recursively converts nested struct fields while preserving address normalization.
  # Handles plain types, arrays of structs, and arrays of addresses.
  @spec build_struct_field_value(String.t(), non_neg_integer(), module(), MapSet.t(String.t())) :: Macro.t()
  defp build_struct_field_value(type, idx, parent_module, struct_names) do
    {base_type, is_array} = strip_array_suffix(type)

    cond do
      base_type == "address" and is_array ->
        quote do
          Enum.map(Enum.at(values, unquote(idx)), &Onchain.Address.checksum!/1)
        end

      base_type == "address" ->
        quote do
          Onchain.Address.checksum!(Enum.at(values, unquote(idx)))
        end

      MapSet.member?(struct_names, base_type) and is_array ->
        nested_module = Module.concat(parent_module, base_type)

        quote do
          Enum.map(Enum.at(values, unquote(idx)), &unquote(nested_module).from_raw/1)
        end

      MapSet.member?(struct_names, base_type) ->
        nested_module = Module.concat(parent_module, base_type)

        quote do
          unquote(nested_module).from_raw(Enum.at(values, unquote(idx)))
        end

      true ->
        quote do
          Enum.at(values, unquote(idx))
        end
    end
  end

  # Strips array suffixes: "Item[]" → {"Item", true}, "Item[2]" → {"Item", true}, "Item" → {"Item", false}
  @spec strip_array_suffix(String.t()) :: {String.t(), boolean()}
  defp strip_array_suffix(type) do
    case Regex.run(~r/^(.+?)(\[.*\])$/, type) do
      [_, base, _suffix] -> {base, true}
      nil -> {type, false}
    end
  end

  @doc false
  @spec solidity_to_struct_type(String.t()) :: Macro.t()
  defp solidity_to_struct_type("address"), do: quote(do: String.t())
  defp solidity_to_struct_type("bool"), do: quote(do: boolean())
  defp solidity_to_struct_type("string"), do: quote(do: String.t())
  defp solidity_to_struct_type("int" <> _), do: quote(do: integer())
  defp solidity_to_struct_type("uint" <> _), do: quote(do: non_neg_integer())
  defp solidity_to_struct_type(_), do: quote(do: term())

  # --- Enum Generation (.sol only) ---

  @doc false
  @spec generate_enum_fns(Onchain.Solidity.parsed_abi()) :: [Macro.t()]
  defp generate_enum_fns(abi) do
    enums = Map.get(abi, :enums, [])

    Enum.flat_map(enums, fn enum_info ->
      # Use only the short name for function prefix (e.g., "IFoo.Status" → "status")
      short_name =
        case String.split(enum_info.name, ".") do
          [_owner, short] -> short
          _ -> enum_info.name
        end

      enum_info.variants
      |> Enum.with_index()
      |> Enum.map(fn {variant, idx} ->
        fn_name =
          String.to_atom(to_snake_case(short_name) <> "_" <> to_snake_case(variant))

        quote do
          @doc "Enum constant `#{unquote(short_name)}.#{unquote(variant)}` (index #{unquote(idx)})."
          @spec unquote(fn_name)() :: non_neg_integer()
          def unquote(fn_name)(), do: unquote(idx)
        end
      end)
    end)
  end
end
