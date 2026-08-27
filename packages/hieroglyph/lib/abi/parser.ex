defmodule ABI.Parser do
  @moduledoc false

  alias ABI.FunctionSelector

  @doc false
  @spec parse!(String.t(), keyword()) :: FunctionSelector.type() | FunctionSelector.t()
  def parse!(str, opts \\ []) do
    {:ok, tokens, _} = str |> String.to_charlist() |> :ethereum_abi_lexer.string()

    tokens =
      case opts[:as] do
        nil -> tokens
        :type -> [{:"expecting type", 1} | tokens]
        :selector -> [{:"expecting selector", 1} | tokens]
      end

    {:ok, ast} = :ethereum_abi_parser.parse(tokens)

    case ast do
      {:type, type} ->
        reject_unsupported!(type)
        type

      {:selector, selector_parts} ->
        selector_parts |> Map.get(:types, []) |> Enum.each(&reject_unsupported!(&1.type))

        case Map.get(selector_parts, :returns) do
          nil -> :ok
          returns -> reject_unsupported!(returns)
        end

        struct!(FunctionSelector, selector_parts)
    end
  end

  # The grammar accepts `fixed<M>x<N>` and `ufixed<M>x<N>` for ABI-spec
  # compatibility, but this library does not implement encode/decode for them
  # (Solidity itself does not fully support fixed-point types — see
  # https://docs.soliditylang.org/en/latest/types.html). Reject at parse time
  # with a link to the tracking issue so the error lands on the user's input
  # instead of deep inside the type-encoder catch-all.
  # See https://github.com/exthereum/abi/issues/54.
  @spec reject_unsupported!(
          FunctionSelector.type()
          | {:fixed, non_neg_integer(), non_neg_integer()}
          | {:ufixed, non_neg_integer(), non_neg_integer()}
        ) :: :ok
  defp reject_unsupported!({:fixed, m, n}), do: raise_unsupported!("fixed#{m}x#{n}")

  defp reject_unsupported!({:ufixed, m, n}), do: raise_unsupported!("ufixed#{m}x#{n}")

  defp reject_unsupported!({:array, inner}), do: reject_unsupported!(inner)
  defp reject_unsupported!({:array, inner, _len}), do: reject_unsupported!(inner)

  defp reject_unsupported!({:tuple, args}) when is_list(args), do: Enum.each(args, &reject_unsupported!(&1.type))

  defp reject_unsupported!(_other), do: :ok

  @spec raise_unsupported!(String.t()) :: no_return()
  defp raise_unsupported!(name) do
    raise ArgumentError,
          "ABI type `#{name}` is accepted by the grammar but not implemented by this library. " <>
            "Tracking: https://github.com/exthereum/abi/issues/54"
  end
end
