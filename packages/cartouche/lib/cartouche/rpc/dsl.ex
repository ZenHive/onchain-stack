defmodule Cartouche.RPC.DSL do
  @moduledoc """
  Compile-time DSL for the uniform thin JSON-RPC wrappers in `Cartouche.RPC`.

  `defrpc/3` generates, from one declaration, the four artifacts these
  wrappers otherwise hand-maintain in lockstep:

    1. the public function,
    2. its `@spec` (return type derived from `:decode`),
    3. its `@doc` (carrying the doctest), and
    4. the Descripex `api/3` metadata block read by `Cartouche.describe/2`.

  Two uniform shapes are covered, selected by whether `:address_desc` is given:

    * **address-at-block** — `name(<<_::160>> = address, opts) ->
      send_rpc(method, [encode(address), block_number], decode: ...)`
      (e.g. `get_balance`, `get_code`).
    * **no-arg** — `name(opts) -> send_rpc(method, [], decode: ...)`
      (e.g. `eth_chain_id`, `gas_price`).

  Only the genuinely uniform shapes are covered. Wrappers with extra guards,
  struct dispatch, multi-clause normalization, or per-method prose deviations
  (e.g. `get_nonce`, whose param name, encoder, and opts description all differ)
  stay hand-written — folding them in would grow more knobs than the
  duplication it removes.

  Prototype for ROADMAP Task 110 (defrpc), proving the `api()` introspection
  stays byte-identical across the conversion.
  """

  # The block-selector wrappers and the plain wrappers document `opts`
  # differently in the original source; preserve both verbatim so the
  # `Cartouche.describe/2` introspection stays byte-identical.
  @block_opts_description ~s{Keyword options including `:block_number` (`"latest"`, `"pending"`, integer, or hex quantity) and transport options.}
  @plain_opts_description "Common `send_rpc/3` transport options."

  @doc """
  Define a uniform thin JSON-RPC wrapper.

  `name` is the generated function (and `api/3`) name; `method` is the JSON-RPC
  method string. Required `opts`:

    * `:decode` — `send_rpc/3` decode mode; also fixes the `@spec` return type
      (`:hex` → `binary()`, `:hex_unsigned` → `non_neg_integer()`).
    * `:summary` — one-line Descripex description.
    * `:returns_desc` — Descripex description of the `:ok` return.
    * `:doc` — the `@doc` body (with doctest).

  Shape selection / optional:

    * `:address_desc` — present ⇒ the address-at-block shape; its value is the
      Descripex description of the leading `address` param. Absent ⇒ no-arg shape.
    * `:encode` — address encoder for the address shape, `:to_hex` (default) or
      `:big_hex`. Ignored by the no-arg shape.
  """
  @spec defrpc(atom(), String.t(), Keyword.t()) :: Macro.t()
  defmacro defrpc(name, method, opts) do
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
      {:ok, address_desc} -> address_at_block(ctx, address_desc, Keyword.get(opts, :encode, :to_hex))
      :error -> no_arg(ctx)
    end
  end

  @spec return_type(:hex | :hex_unsigned) :: Macro.t()
  defp return_type(:hex), do: quote(do: binary())
  defp return_type(:hex_unsigned), do: quote(do: non_neg_integer())

  @spec address_at_block(map(), String.t(), :to_hex | :big_hex) :: Macro.t()
  defp address_at_block(ctx, address_desc, encode) do
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

    encoded_address =
      case encode do
        :to_hex -> quote(do: Cartouche.Hex.to_hex(address))
        :big_hex -> quote(do: Cartouche.Hex.encode_big_hex(address))
      end

    quote do
      api(unquote(name), unquote(summary),
        params: [
          address: [kind: :value, description: unquote(address_desc)],
          opts: [kind: :value, default: [], description: unquote(@block_opts_description)]
        ],
        returns: %{type: :ok_error_tuple, description: unquote(returns_desc)}
      )

      @doc unquote(doc)
      @spec unquote(name)(<<_::160>>, Keyword.t()) :: {:ok, unquote(return_type)} | {:error, term()}
      def unquote(name)(<<_::160>> = address, opts \\ []) do
        block_number = opts |> Keyword.get(:block_number, "latest") |> normalize_block_param()

        send_rpc(
          unquote(method),
          [unquote(encoded_address), block_number],
          Keyword.put(opts, :decode, unquote(decode))
        )
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
