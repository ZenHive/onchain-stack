defmodule Onchain.RPC.Codegen do
  @moduledoc false

  # Declarative codegen for the uniform `Onchain.RPC.*` wrappers.
  #
  # The named JSON-RPC wrappers in `Onchain.RPC` share a near-identical shape:
  # optional per-arg validation, param construction, a `do_rpc/3` dispatch, and a
  # mechanical bang variant. This module captures the two genuinely-uniform parts
  # as macros so the shape is declared once rather than hand-copied per wrapper:
  #
  #   * `defrpc/2` — the read function for wrappers whose body reduces to
  #     "validate positional args → do_rpc → maybe decode".
  #   * `defrpc_bang/2` — the `name!` variant that unwraps `{:ok, v}` / raises on error.
  #
  # Wrappers outside the declared validator/decoder shapes (nested-map params,
  # multi-clause dispatch, filter whitelists, bespoke deserialization) stay
  # hand-written in `Onchain.RPC`; they still use `defrpc_bang/2` for their
  # mechanical bang.
  # This mirrors Ecto/Phoenix codegen: a narrow macro for the common case, plain
  # functions for the outliers — rather than growing one macro past its contract.
  #
  # The `@doc`/`@spec`/`api/3` declarations stay hand-authored in `Onchain.RPC`
  # so the Descripex hints and dialyzer specs remain byte-identical; these macros
  # only emit the function bodies. Method names are checked against the vendored
  # OpenRPC spec at compile time so declarations fail fast on typos.

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
           :block,
           :block_hash,
           :block_and_index,
           :block_hash_and_index
         ]},
      default: :none,
      doc:
        "Leading positional argument shape. :none → no args (params []); " <>
          ":address → validated address + normalized :block option (params [hex_addr, block]); " <>
          ":data → 0x-hex gate on the raw value (params [data]); block shapes normalize " <>
          "block references and optional transaction indexes."
    ],
    decode: [
      type:
        {:in,
         [
           nil,
           :hex_unsigned,
           :nullable_hex_unsigned,
           :receipt_list,
           :transaction,
           :block_access_list
         ]},
      default: nil,
      doc:
        "Result decoder. nil leaves the raw result untouched; :hex_unsigned uses cartouche; " <>
          "nullable quantities, receipt lists, and transactions use Onchain's existing parsers; " <>
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

  @doc false
  # Generates a uniform read wrapper. See @defrpc_schema for the option contract.
  defmacro defrpc(name, opts) do
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

  @doc false
  # Generates the mechanical `name!` variant. See @defrpc_bang_schema.
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

  defp build_block_rpc(name, method, :block_hash, decode) do
    result = block_rpc_result(method, quote(do: [block_hash]), decode)

    quote do
      def unquote(name)(block_hash, opts \\ []) do
        with {:ok, block_hash} <- ensure_block_hash(block_hash) do
          unquote(result)
        end
      end
    end
  end

  defp build_block_rpc(name, method, :block_and_index, decode) do
    result = block_rpc_result(method, quote(do: [block, transaction_index]), decode)

    quote do
      def unquote(name)(block, transaction_index, opts \\ []) do
        with {:ok, block} <- normalize_block(block),
             {:ok, transaction_index} <- normalize_transaction_index(transaction_index) do
          unquote(result)
        end
      end
    end
  end

  defp build_block_rpc(name, method, :block_hash_and_index, decode) do
    result = block_rpc_result(method, quote(do: [block_hash, transaction_index]), decode)

    quote do
      def unquote(name)(block_hash, transaction_index, opts \\ []) do
        with {:ok, block_hash} <- ensure_block_hash(block_hash),
             {:ok, transaction_index} <- normalize_transaction_index(transaction_index) do
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

      :nullable_hex_unsigned ->
        quote(do: decode_nullable_quantity_result(unquote(rpc_call)))

      :receipt_list ->
        quote(do: decode_receipt_list_result(unquote(rpc_call)))

      :transaction ->
        quote(do: decode_transaction_result(unquote(rpc_call)))

      :block_access_list ->
        quote(do: decode_block_access_list_result(unquote(rpc_call)))
    end
  end
end
