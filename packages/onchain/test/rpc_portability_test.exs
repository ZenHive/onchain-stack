defmodule Cartouche.RPCPortabilityTest do
  use ExUnit.Case, async: true

  import Cartouche.Test.Live

  @moduletag :integration

  # Observed on Alchemy mainnet, 2026-09-15, HTTP 400. Keep the refusal
  # verbatim: accepting an arbitrary error would also accept broken credentials.
  @alchemy_refusal "eth_baseFee is not available on the ETH_MAINNET. For more information see our docs: https://docs.alchemy.com/alchemy/documentation/apis/ethereum"

  test "base_fee returns on archive and records Alchemy's real refusal" do
    assert_portability!(&Cartouche.RPC.base_fee/1,
      archive: &match?({:ok, fee} when is_integer(fee) and fee >= 0, &1),
      alchemy: &alchemy_refusal?/1
    )
  end

  defp alchemy_refusal?({:error, %Req.Response{status: 400, body: body}}) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"code" => -32_600, "message" => @alchemy_refusal}}} -> true
      _ -> false
    end
  end

  defp alchemy_refusal?(_answer), do: false
end
