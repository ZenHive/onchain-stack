defmodule Onchain.BangHelper do
  @moduledoc false

  @doc """
  Generates a bang (!) function that wraps a non-bang function returning
  `{:ok, result} | {:error, reason}`.

  The bang function unwraps `{:ok, result}` and raises on `{:error, reason}`.

  ## Simple usage (Pattern A)

  When no options are given, the error message uses the function name:

      @spec simulate_call!(String.t(), String.t(), keyword()) :: String.t()
      defbang simulate_call!(address, data, opts \\\\ [])

  Expands to:

      def simulate_call!(address, data, opts \\\\ []) do
        case simulate_call(address, data, opts) do
          {:ok, result} -> result
          {:error, reason} -> raise "simulate_call failed: \#{inspect(reason)}"
        end
      end

  ## Tagged errors (Pattern B/C)

  Use `errors:` to match specific tagged error tuples, and `fallback:` for a
  catch-all message:

      defbang parse_abi_file!(path),
        errors: [parse_error: "ABI parse failed", file_error: "ABI file error"],
        fallback: "ABI error"
  """
  defmacro defbang(call, opts \\ []) do
    {bang_name, args_with_defaults} = Macro.decompose_call(call)

    # The wrapped function is always defined in the same module, so its name
    # already exists as an atom by macro-expansion time. to_existing_atom both
    # avoids atom-table growth and turns a typo'd base name into a compile error.
    base_name =
      bang_name
      |> Atom.to_string()
      |> String.trim_trailing("!")
      |> String.to_existing_atom()

    call_args = strip_defaults(args_with_defaults)

    ok_clause = quote(do: ({:ok, result} -> result))
    error_clauses = build_error_clauses(bang_name, opts)
    all_clauses = List.flatten([ok_clause | error_clauses])

    inner_call = quote(do: unquote(base_name)(unquote_splicing(call_args)))
    case_expr = {:case, [], [inner_call, [do: all_clauses]]}

    quote do
      def unquote(bang_name)(unquote_splicing(args_with_defaults)) do
        unquote(case_expr)
      end
    end
  end

  # Strips default values from args for the inner function call.
  # {:\\, _, [arg, _default]} -> arg
  @spec strip_defaults([Macro.t()]) :: [Macro.t()]
  defp strip_defaults(args) do
    Enum.map(args, fn
      {:\\, _, [arg, _default]} -> arg
      arg -> arg
    end)
  end

  # Pattern A: no options — simple "func_name failed: reason" message
  @spec build_error_clauses(atom(), keyword()) :: [Macro.t()]
  defp build_error_clauses(bang_name, []) do
    label = bang_name |> Atom.to_string() |> String.trim_trailing("!")

    [
      quote do
        {:error, reason} -> raise unquote(label) <> " failed: " <> inspect(reason)
      end
    ]
  end

  # Pattern B/C: tagged error clauses + optional fallback
  defp build_error_clauses(_bang_name, opts) do
    tagged = Keyword.get(opts, :errors, [])
    fallback_msg = Keyword.get(opts, :fallback)

    tagged_clauses =
      Enum.map(tagged, fn {tag, msg_prefix} ->
        quote do
          {:error, {unquote(tag), reason}} -> raise unquote(msg_prefix) <> ": " <> reason
        end
      end)

    fallback_clause =
      if fallback_msg do
        [
          quote do
            {:error, reason} -> raise unquote(fallback_msg) <> ": " <> inspect(reason)
          end
        ]
      else
        []
      end

    tagged_clauses ++ fallback_clause
  end
end
