defmodule Onchain.ABI.Parser do
  @moduledoc false

  alias Onchain.ABI.FunctionSelector

  @doc false
  @spec parse!(String.t(), keyword()) :: FunctionSelector.type() | FunctionSelector.t()
  def parse!(str, opts \\ []) do
    case opts[:as] do
      :type -> parse_type(str)
      mode -> parse_selector(str, mode)
    end
  end

  defp parse_type(str), do: str |> native(:type) |> reject_type()

  defp reject_type(type) do
    reject_unsupported!(type)
    type
  end

  defp parse_selector(str, mode) do
    [input | returns] = String.split(str, "->", parts: 2)

    {name, params} =
      case String.split(input, "(", parts: 2) do
        [name, rest] -> {String.trim(name), "(" <> rest}
        _ -> {"", input}
      end

    types = native(params, :params)
    types = if mode == nil and name == "" and returns == [], do: [%{type: {:tuple, types}}], else: types

    %FunctionSelector{
      function: if(name == "", do: nil, else: name),
      types: types,
      returns:
        case returns do
          [] -> nil
          [type] -> parse_type(String.trim(type))
        end
    }
  end

  defp native(str, kind) do
    case Onchain.ABI.Native.abi(:parse, str, kind) do
      {:ok, result} ->
        result

      {:error, "unsupported:" <> name} ->
        name = if name in ["fixed", "ufixed"], do: name <> "128x18", else: name
        raise_unsupported!(name)

      {:error, reason} ->
        message =
          if String.trim(str) == "",
            do: [~c"syntax error before: ", []],
            else: [~c"syntax error before: ", String.to_charlist(reason)]

        :erlang.error({:badmatch, {:error, {1, :ethereum_abi_parser, message}}})
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
