defmodule ABI.FunctionSelectorRealWorldTest do
  @moduledoc """
  Golden vectors for `ABI.method_id/1` against known mainnet 4-byte selectors,
  plus `FunctionSelector.encode/1 ∘ FunctionSelector.decode/1` round-trips for the
  tuple/`tuple[]`/fixed-array signatures that exercise the canonical-signature
  serialization corners of the spec.

  Selectors sourced from the `defi-skills` v0.3.0 playbooks (Aave V3, Compound V3,
  Lido, ERC-20, Uniswap V3, Balancer V2, EigenLayer, Curve 3pool, WETH).
  """

  use ExUnit.Case, async: true
  use ABI.Hex

  alias ABI.FunctionSelector

  describe "ABI.method_id/1 against known-mainnet selectors" do
    test "transfer(address,uint256) — ERC-20 baseline" do
      assert ABI.method_id("transfer(address,uint256)") == ~h[0xa9059cbb]
    end

    test "transferFrom(address,address,uint256) — ERC-20/ERC-721 shared selector" do
      assert ABI.method_id("transferFrom(address,address,uint256)") ==
               ~h[0x23b872dd]
    end

    test "supply(address,uint256,address,uint16) — Aave V3" do
      assert ABI.method_id("supply(address,uint256,address,uint16)") ==
               ~h[0x617ba037]
    end

    test "borrow(address,uint256,uint256,uint16,address) — Aave V3" do
      assert ABI.method_id("borrow(address,uint256,uint256,uint16,address)") ==
               ~h[0xa415bcad]
    end

    test "withdraw(uint256) — WETH unwrap / Curve gauge withdraw (duplicate by design)" do
      assert ABI.method_id("withdraw(uint256)") == ~h[0x2e1a7d4d]
    end

    test "deposit() — WETH wrap / Rocket Pool stake (duplicate by design)" do
      assert ABI.method_id("deposit()") == ~h[0xd0e30db0]
    end

    test "requestWithdrawals(uint256[],address) — Lido (dynamic uint256[])" do
      assert ABI.method_id("requestWithdrawals(uint256[],address)") ==
               ~h[0xd6681042]
    end

    test "claim(address,address,bool) — Compound V3" do
      assert ABI.method_id("claim(address,address,bool)") == ~h[0xb7034f7e]
    end

    test "add_liquidity(uint256[3],uint256) — Curve 3pool (fixed-size uint256[3])" do
      assert ABI.method_id("add_liquidity(uint256[3],uint256)") ==
               ~h[0x4515cef3]
    end

    test "exactInputSingle(tuple) — Uniswap V3 (single tuple arg)" do
      sig =
        "exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))"

      assert ABI.method_id(sig) == ~h[0x414bf389]
    end

    test "swap(tuple,tuple,uint256,uint256) — Balancer V2 (multiple top-level tuples)" do
      sig =
        "swap((bytes32,uint8,address,address,uint256,bytes)," <>
          "(address,bool,address,bool),uint256,uint256)"

      assert ABI.method_id(sig) == ~h[0x52bbbe29]
    end

    test "queueWithdrawals(tuple[]) — EigenLayer (dynamic tuple[])" do
      assert ABI.method_id("queueWithdrawals((address[],uint256[],address)[])") ==
               ~h[0x0dd8dd02]
    end
  end

  describe "FunctionSelector.encode/1 round-trips through decode/1" do
    # Confirms canonical-signature serialization matches the spec for the
    # tuple / tuple[] / fixed-array edge cases — parse the signature, then
    # re-encode it, and verify the round-tripped string matches and still
    # hashes to the original selector.
    @round_trip_cases [
      {"exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))", ~h[0x414bf389]},
      {"swap((bytes32,uint8,address,address,uint256,bytes)," <>
         "(address,bool,address,bool),uint256,uint256)", ~h[0x52bbbe29]},
      {"queueWithdrawals((address[],uint256[],address)[])", ~h[0x0dd8dd02]},
      {"add_liquidity(uint256[3],uint256)", ~h[0x4515cef3]}
    ]

    for {sig, selector} <- @round_trip_cases do
      test "decode → encode preserves canonical form: #{sig}" do
        selector_struct = FunctionSelector.decode(unquote(sig))

        assert FunctionSelector.encode(selector_struct) == unquote(sig)

        assert ABI.method_id(selector_struct) == unquote(selector)
      end
    end
  end
end
