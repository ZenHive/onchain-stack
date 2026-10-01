defmodule Cartouche.RPCPortabilityTest do
  use ExUnit.Case, async: true

  import Cartouche.Test.Live

  @moduletag :integration

  # Observed on Alchemy mainnet, 2026-10-01. Keep the refusal
  # verbatim: accepting an arbitrary error would also accept broken credentials.
  @alchemy_refusal "eth_baseFee is not available on the ETH_MAINNET. For more information see our docs: https://docs.alchemy.com/alchemy/documentation/apis/ethereum"

  @infura_refusal "The method eth_baseFee does not exist/is not available"

  test "eth_baseFee returns on archive and pins both hosted refusals" do
    assert_portability!(&Cartouche.RPC.send_rpc("eth_baseFee", [], &1),
      archive: &match?({:ok, "0x" <> _fee}, &1),
      alchemy: &alchemy_refusal?/1,
      infura: &infura_refusal?/1
    )
  end

  test "portable base_fee returns on archive, Alchemy, and Infura" do
    fee? = &match?({:ok, fee} when is_integer(fee) and fee >= 0, &1)
    assert_portability!(&Cartouche.RPC.base_fee/1, archive: fee?, alchemy: fee?, infura: fee?)
  end

  defp infura_refusal?({:error, {:method_not_found, %{code: -32_601, message: @infura_refusal}}}), do: true
  defp infura_refusal?(_answer), do: false

  # Since the shared transport (task 2137) the HTTP 400 JSON-RPC body is decoded
  # and tagged; the code and message stay verbatim.
  defp alchemy_refusal?({:error, {:method_not_found, %{code: -32_600, message: @alchemy_refusal}}}), do: true

  defp alchemy_refusal?(_answer), do: false
end
