defmodule Cartouche.Test.SleuthHandler do
  @moduledoc false
  use Cartouche.Hex

  alias Cartouche.Contract.BlockNumber

  @block_number_query BlockNumber.bytecode()

  @spec handle_call(binary(), binary()) :: binary() | no_return()
  defp handle_call(@block_number_query, calldata) do
    case BlockNumber.decode_call(calldata) do
      {:ok, "query", _} ->
        encode_sleuth(BlockNumber.query_selector(), {2})

      {:ok, "queryTwo", _} ->
        encode_sleuth(BlockNumber.query_two_selector(), {2, 3})

      {:ok, "queryThree", _} ->
        encode_sleuth(BlockNumber.query_three_selector(), {2})

      {:ok, "queryFour", _} ->
        encode_sleuth(
          BlockNumber.query_four_selector(),
          {~h[0x010203], ~h[0x0000000000000000000000000000000000000001]}
        )

      {:ok, "queryCool", _} ->
        encode_sleuth(
          BlockNumber.query_cool_selector(),
          {{"hi", [1, 2, 3], {"meow"}}}
        )

      _ ->
        raise "Unknown Sleuth query call"
    end
  end

  defp handle_call(query, _calldata) do
    raise "Unknown sleuth query: #{to_hex(query)}"
  end

  @doc false
  @spec eth_call(map(), term()) :: binary() | {:error, map()}
  def eth_call(%{"data" => data_hex}, _block) do
    data = from_hex!(data_hex)

    cond do
      String.contains?(data, ~h[0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF00000000]) ->
        "0x"

      String.contains?(data, ~h[0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF00000001]) ->
        {:error,
         %{
           "code" => 3,
           "message" => "execution reverted"
         }}

      true ->
        [query, calldata] = Cartouche.Contract.Sleuth.decode_query_call(data)

        Base.encode16(handle_call(query, calldata))
    end
  end

  @spec encode_sleuth(ABI.FunctionSelector.t(), tuple()) :: binary()
  defp encode_sleuth(query_selector, values) do
    return_selector = %ABI.FunctionSelector{
      types: [%{type: {:tuple, query_selector.returns}}]
    }

    query_resp = ABI.TypeEncoder.encode([values], return_selector)
    ABI.encode("(bytes)", [{query_resp}])
  end
end
