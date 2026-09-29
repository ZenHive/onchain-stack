defmodule ABI.DefiCalldataTest do
  @moduledoc """
  Real-world golden calldata fixtures captured from `defi-skills build --action <name> --json`
  (defi-skills v0.3.0). Each fixture locks a `{signature, args, calldata}` triple from a
  mainnet-style call. Round-tripping through `ABI.encode/2` + `ABI.decode_call/3` must
  reproduce the calldata byte-for-byte and recover the original args.

  Fixtures cover Aave V3, Compound V3, Lido, EigenLayer, ERC-20 transfer, and WETH unwrap.
  """

  use ExUnit.Case, async: true
  use ABI.Hex

  # Mainnet addresses referenced below:
  #   USDC                       0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48
  #   Compound USDC market       0xc3d688b66703497daa19211eedff47f25384cdc3
  #   EigenLayer stETH strategy  0x93c4b944d05dfe6df7645a86cd2206016c51564d
  #   Lido stETH                 0xae7ab96520de3a18e5e111b5eaab095312d7fe84
  # Test wallets:
  #   Sender / onBehalfOf        0x1111111111111111111111111111111111111111
  #   Transfer recipient         0x2222222222222222222222222222222222222222
  # Numeric conventions:
  #   1.0 token (18 decimals)    1_000_000_000_000_000_000
  #   500 USDC (6 decimals)      500_000_000
  @fixtures [
    %{
      action: :aave_supply,
      signature: "supply(address,uint256,address,uint16)",
      args: [
        ~h[0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48],
        500_000_000,
        ~h[0x1111111111111111111111111111111111111111],
        0
      ],
      calldata:
        ~h[0x617ba037000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000001dcd650000000000000000000000000011111111111111111111111111111111111111110000000000000000000000000000000000000000000000000000000000000000]
    },
    %{
      action: :aave_borrow,
      signature: "borrow(address,uint256,uint256,uint16,address)",
      args: [
        ~h[0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48],
        250_000_000,
        2,
        0,
        ~h[0x1111111111111111111111111111111111111111]
      ],
      calldata:
        ~h[0xa415bcad000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000000ee6b280000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000001111111111111111111111111111111111111111]
    },
    %{
      action: :aave_set_collateral,
      signature: "setUserUseReserveAsCollateral(address,bool)",
      args: [
        ~h[0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48],
        true
      ],
      calldata:
        ~h[0x5a3b74b9000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000000000000000000000000000000000000000001]
    },
    %{
      action: :compound_supply,
      signature: "supply(address,uint256)",
      args: [
        ~h[0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48],
        500_000_000
      ],
      calldata:
        ~h[0xf2b9fdb8000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000001dcd6500]
    },
    %{
      action: :compound_claim_rewards,
      signature: "claim(address,address,bool)",
      args: [
        ~h[0xc3d688b66703497daa19211eedff47f25384cdc3],
        ~h[0x1111111111111111111111111111111111111111],
        true
      ],
      calldata:
        ~h[0xb7034f7e000000000000000000000000c3d688b66703497daa19211eedff47f25384cdc300000000000000000000000011111111111111111111111111111111111111110000000000000000000000000000000000000000000000000000000000000001]
    },
    %{
      action: :lido_stake,
      signature: "submit(address)",
      args: [~h[0x0000000000000000000000000000000000000000]],
      calldata: ~h[0xa1903eab0000000000000000000000000000000000000000000000000000000000000000]
    },
    %{
      action: :lido_unstake,
      signature: "requestWithdrawals(uint256[],address)",
      args: [
        [1_000_000_000_000_000_000],
        ~h[0x1111111111111111111111111111111111111111]
      ],
      calldata:
        ~h[0xd66810420000000000000000000000000000000000000000000000000000000000000040000000000000000000000000111111111111111111111111111111111111111100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000de0b6b3a7640000]
    },
    %{
      action: :eigenlayer_deposit,
      signature: "depositIntoStrategy(address,address,uint256)",
      args: [
        ~h[0x93c4b944d05dfe6df7645a86cd2206016c51564d],
        ~h[0xae7ab96520de3a18e5e111b5eaab095312d7fe84],
        1_000_000_000_000_000_000
      ],
      calldata:
        ~h[0xe7a050aa00000000000000000000000093c4b944d05dfe6df7645a86cd2206016c51564d000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe840000000000000000000000000000000000000000000000000de0b6b3a7640000]
    },
    %{
      action: :transfer_erc20,
      signature: "transfer(address,uint256)",
      args: [
        ~h[0x2222222222222222222222222222222222222222],
        100_000_000
      ],
      calldata:
        ~h[0xa9059cbb00000000000000000000000022222222222222222222222222222222222222220000000000000000000000000000000000000000000000000000000005f5e100]
    },
    %{
      action: :weth_unwrap,
      signature: "withdraw(uint256)",
      args: [1_000_000_000_000_000_000],
      calldata: ~h[0x2e1a7d4d0000000000000000000000000000000000000000000000000de0b6b3a7640000]
    }
  ]

  describe "real-world DeFi calldata round-trips" do
    for f <- @fixtures do
      %{action: action, signature: sig, args: args, calldata: calldata} = f

      test "#{action}: ABI.encode/2 produces the locked calldata" do
        assert ABI.encode(unquote(sig), unquote(args)) == unquote(calldata)
      end

      test "#{action}: decode_call/3 round-trips through the locked calldata" do
        assert {:ok, unquote(args)} =
                 ABI.decode_call(unquote(sig), unquote(calldata))
      end
    end
  end
end
