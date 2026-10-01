defmodule Onchain.RPC.Codegen do
  @moduledoc """
  Spec-checked JSON-RPC wrapper generation for `Cartouche.RPC`.

  `defrpc/2` takes a function name and keyword options including `:method`.
  Every declaration is checked against `Onchain.RPC.Specs` at compile time,
  including its vendored extension specs. Declarations with `:summary`, `:doc`,
  and `:returns_desc` also generate Descripex metadata and specs; `:address_desc`
  selects the validated address-at-block shape. Otherwise the caller supplies
  metadata and selects `:arg` and `:decode` explicitly.

  `defrpc_bang/2` generates `name!`, with the positional names in `:args` and
  trailing optional `opts`. It unwraps `{:ok, value}` (including nil), and
  raises `RuntimeError` with `"name failed: ..."` on `{:error, reason}`.
  """

  alias Onchain.RPC.Specs

  @defrpc_schema [
    method: [
      type: :string,
      required: true,
      doc: "JSON-RPC method name, e.g. \"eth_getBalance\"."
    ],
    arg: [
      type:
        {:in,
         [
           :none,
           :address,
           :data,
           :block
         ]},
      default: :none,
      doc:
        "Leading positional argument shape. :none → no args (params []); " <>
          ":address → validated address + normalized :block option (params [hex_addr, block]); " <>
          ":data → 0x-hex gate on the raw value (params [data]); " <>
          ":block → normalized block number, tag, or hash (params [block])."
    ],
    decode: [
      type:
        {:in,
         [
           nil,
           :hex_unsigned,
           :block_access_list
         ]},
      default: nil,
      doc:
        "Result decoder. nil leaves the raw result untouched; :hex_unsigned uses cartouche; " <>
          ":block_access_list keeps the node's camelCase EIP-7928 maps."
    ]
  ]

  @defrpc_bang_schema [
    args: [
      type: {:list, :atom},
      default: [],
      doc:
        "Positional argument names (excluding the trailing opts) forwarded to the non-bang " <>
          "function. Must match the api/3 param names for the bang variant."
    ]
  ]

  @doc "Defines a wrapper for a method in the vendored RPC specs."
  @spec defrpc(atom(), keyword()) :: Macro.t()
  defmacro defrpc(name, opts) do
    method = Keyword.fetch!(opts, :method)
    ensure_known_method!(method)

    if Keyword.has_key?(opts, :summary) do
      build_documented(name, method, opts)
    else
      build_validated(name, opts)
    end
  end

  defp build_documented(name, method, opts) do
    decode = Keyword.fetch!(opts, :decode)

    ctx = %{
      name: name,
      method: method,
      decode: decode,
      summary: Keyword.fetch!(opts, :summary),
      returns_desc: Keyword.fetch!(opts, :returns_desc),
      doc: Keyword.fetch!(opts, :doc),
      return_type: return_type(decode)
    }

    case Keyword.fetch(opts, :address_desc) do
      {:ok, address_desc} -> address_at_block(ctx, address_desc)
      :error -> no_arg(ctx)
    end
  end

  defp build_validated(name, opts) do
    opts = NimbleOptions.validate!(opts, @defrpc_schema)
    method = Keyword.fetch!(opts, :method)
    arg = Keyword.fetch!(opts, :arg)
    decode = Keyword.fetch!(opts, :decode)
    ensure_known_method!(method)

    if arg in [:none, :address, :data] do
      rpc_opts =
        case decode do
          nil -> quote(do: to_rpc_opts(opts))
          d -> quote(do: Keyword.put(to_rpc_opts(opts), :decode, unquote(d)))
        end

      build_rpc(name, method, arg, rpc_opts)
    else
      build_block_rpc(name, method, arg, decode)
    end
  end

  defp ensure_known_method!(method) do
    Code.ensure_compiled!(Specs)

    if is_nil(Specs.lookup(method)) do
      raise ArgumentError, "unknown OpenRPC method for defrpc: #{inspect(method)}"
    end
  end

  @doc "Defines a bang variant that unwraps success and raises on error."
  @spec defrpc_bang(atom(), keyword()) :: Macro.t()
  defmacro defrpc_bang(name, opts \\ []) do
    opts = NimbleOptions.validate!(opts, @defrpc_bang_schema)
    caller = __CALLER__.module
    arg_vars = Enum.map(Keyword.fetch!(opts, :args), &Macro.var(&1, caller))
    bang = :"#{name}!"
    fail_prefix = "#{name} failed: "

    quote do
      def unquote(bang)(unquote_splicing(arg_vars), opts \\ []) do
        case unquote(name)(unquote_splicing(arg_vars), opts) do
          {:ok, result} -> result
          {:error, reason} -> raise unquote(fail_prefix) <> inspect(reason)
        end
      end
    end
  end

  # --- read-wrapper bodies, one per arg shape ---

  defp build_rpc(name, method, :none, rpc_opts) do
    quote do
      def unquote(name)(opts \\ []) do
        do_rpc(unquote(method), [], unquote(rpc_opts))
      end
    end
  end

  defp build_rpc(name, method, :address, rpc_opts) do
    quote do
      def unquote(name)(address, opts \\ []) do
        with {:ok, hex_addr} <- ensure_hex_address(address),
             {:ok, block} <- normalize_block(Keyword.get(opts, :block, "latest")) do
          do_rpc(unquote(method), [hex_addr, block], unquote(rpc_opts))
        end
      end
    end
  end

  defp build_rpc(name, method, :data, rpc_opts) do
    quote do
      def unquote(name)(data, opts \\ []) do
        with {:ok, _hex_data} <- ensure_hex_data(data) do
          do_rpc(unquote(method), [data], unquote(rpc_opts))
        end
      end
    end
  end

  defp build_block_rpc(name, method, :block, decode) do
    result = block_rpc_result(method, quote(do: [block]), decode)

    quote do
      def unquote(name)(block, opts \\ []) do
        with {:ok, block} <- normalize_block(block) do
          unquote(result)
        end
      end
    end
  end

  defp block_rpc_result(method, params, decode) do
    rpc_call =
      quote do
        do_rpc(unquote(method), unquote(params), to_rpc_opts(opts))
      end

    case decode do
      nil ->
        rpc_call

      :hex_unsigned ->
        quote do
          do_rpc(
            unquote(method),
            unquote(params),
            Keyword.put(to_rpc_opts(opts), :decode, :hex_unsigned)
          )
        end

      :block_access_list ->
        quote(do: decode_block_access_list_result(unquote(rpc_call)))
    end
  end

  @block_opts_description "Block selector (:block or :block_number) and transport options."
  @plain_opts_description "Common send_rpc/3 transport options."
  @spec return_type(:hex | :hex_unsigned) :: Macro.t()
  defp return_type(:hex), do: quote(do: binary())
  defp return_type(:hex_unsigned), do: quote(do: non_neg_integer())

  @spec address_at_block(map(), String.t()) :: Macro.t()
  defp address_at_block(ctx, address_desc) do
    %{
      name: name,
      method: method,
      decode: decode,
      summary: summary,
      returns_desc: returns_desc,
      doc: doc,
      return_type: return_type
    } =
      ctx

    quote do
      api(unquote(name), unquote(summary),
        params: [
          address: [kind: :value, description: unquote(address_desc)],
          opts: [kind: :value, default: [], description: unquote(@block_opts_description)]
        ],
        returns: %{type: :ok_error_tuple, description: unquote(returns_desc)}
      )

      @doc unquote(doc)
      @spec unquote(name)(binary(), Keyword.t()) :: {:ok, unquote(return_type)} | {:error, term()}
      def unquote(name)(address, opts \\ []) do
        with {:ok, address} <- Onchain.RPC.Helpers.ensure_hex_address(address),
             {:ok, block} <-
               Onchain.RPC.Helpers.normalize_block(Keyword.get(opts, :block, Keyword.get(opts, :block_number, "latest"))) do
          send_rpc(unquote(method), [address, block], Keyword.put(opts, :decode, unquote(decode)))
        end
      end
    end
  end

  @spec no_arg(map()) :: Macro.t()
  defp no_arg(ctx) do
    %{
      name: name,
      method: method,
      decode: decode,
      summary: summary,
      returns_desc: returns_desc,
      doc: doc,
      return_type: return_type
    } =
      ctx

    quote do
      api(unquote(name), unquote(summary),
        params: [
          opts: [kind: :value, default: [], description: unquote(@plain_opts_description)]
        ],
        returns: %{type: :ok_error_tuple, description: unquote(returns_desc)}
      )

      @doc unquote(doc)
      @spec unquote(name)(Keyword.t()) :: {:ok, unquote(return_type)} | {:error, term()}
      def unquote(name)(opts \\ []) do
        send_rpc(unquote(method), [], Keyword.put(opts, :decode, unquote(decode)))
      end
    end
  end
end
