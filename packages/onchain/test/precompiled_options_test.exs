defmodule Onchain.PrecompiledOptionsTest do
  use ExUnit.Case, async: true

  test "Tempo uses its own application, crate and release namespace" do
    opts = Onchain.Precompiled.opts("onchain_tempo")
    assert opts[:otp_app] == :onchain_tempo
    assert opts[:crate] == "onchain_tempo"
    assert opts[:base_url] =~ "/onchain_tempo-v"
    assert opts[:targets] == Onchain.Precompiled.targets()
    assert opts[:nif_versions] == Onchain.Precompiled.nif_versions()
  end

  test "existing ABI and EVM release namespaces are preserved" do
    for {crate, app} <- [{"onchain_abi", :onchain}, {"onchain_evm", :onchain_evm}, {"onchain_solidity", :onchain_evm}] do
      opts = Onchain.Precompiled.opts(crate)
      assert opts[:otp_app] == app
      assert opts[:crate] == crate
      assert opts[:base_url] =~ "/#{app}-v"
    end
  end
end
