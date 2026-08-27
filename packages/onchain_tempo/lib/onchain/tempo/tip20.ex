defmodule Onchain.Tempo.TIP20 do
  @moduledoc """
  TIP-20 token function selectors, ABI calldata encoders, and Tempo constants.

  TIP-20 is Tempo's token standard (compatible with ERC-20, with extensions
  like `transferWithMemo`). This module provides the function selectors and
  calldata builders needed for constructing and matching Tempo transaction calls.

  ## Selectors

  All selectors are 4-byte binaries (keccak256 of the function signature):

      Onchain.Tempo.TIP20.transfer_selector()
      #=> <<0xA9, 0x05, 0x9C, 0xBB>>

  ## Calldata

  Calldata functions accept raw 20-byte binaries (not hex strings):

      recipient = <<0x74, 0x2D, ...::binary-size(18)>>
      Onchain.Tempo.TIP20.transfer_calldata(recipient, 1_000_000)

  ## Constants

      Onchain.Tempo.TIP20.stablecoin_dex_address()
      #=> <<0xDE, 0xC0, ...>>  # 20-byte binary
  """

  # TIP-20 function selectors (keccak256 of function signature, first 4 bytes).

  # transfer(address,uint256)
  @transfer_selector <<0xA9, 0x05, 0x9C, 0xBB>>

  # transferWithMemo(address,uint256,bytes32)
  @transfer_with_memo_selector <<0x95, 0x77, 0x7D, 0x59>>

  # approve(address,uint256)
  @approve_selector <<0x09, 0x5E, 0xA7, 0xB3>>

  # swapExactAmountOut(address,address,uint128,uint128)
  @swap_exact_amount_out_selector <<0xF0, 0x12, 0x2B, 0x75>>

  # balanceOf(address)
  @balance_of_selector <<0x70, 0xA0, 0x82, 0x31>>

  # Tempo stablecoin DEX contract address (canonical, from viem/tempo).
  @stablecoin_dex_address <<0xDE, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                            0x00, 0x00, 0x00, 0x00, 0x00>>

  @doc "Returns the `transfer(address,uint256)` function selector."
  @spec transfer_selector() :: <<_::32>>
  def transfer_selector, do: @transfer_selector

  @doc "Returns the `transferWithMemo(address,uint256,bytes32)` function selector."
  @spec transfer_with_memo_selector() :: <<_::32>>
  def transfer_with_memo_selector, do: @transfer_with_memo_selector

  @doc "Returns the `approve(address,uint256)` function selector."
  @spec approve_selector() :: <<_::32>>
  def approve_selector, do: @approve_selector

  @doc "Returns the `swapExactAmountOut(address,address,uint128,uint128)` function selector."
  @spec swap_exact_amount_out_selector() :: <<_::32>>
  def swap_exact_amount_out_selector, do: @swap_exact_amount_out_selector

  @doc "Returns the `balanceOf(address)` function selector."
  @spec balance_of_selector() :: <<_::32>>
  def balance_of_selector, do: @balance_of_selector

  @doc "Returns the canonical Tempo stablecoin DEX contract address (20-byte binary)."
  @spec stablecoin_dex_address() :: <<_::160>>
  def stablecoin_dex_address, do: @stablecoin_dex_address

  @doc """
  ABI-encode `transfer(address,uint256)` calldata.

  ## Parameters

    * `recipient` — 20-byte binary address
    * `amount` — transfer amount as non-negative integer
  """
  @spec transfer_calldata(<<_::160>>, non_neg_integer()) :: binary()
  def transfer_calldata(recipient, amount)
      when is_binary(recipient) and byte_size(recipient) == 20 and is_integer(amount) and amount >= 0 do
    @transfer_selector <> <<0::96, recipient::binary-size(20), amount::unsigned-big-size(256)>>
  end

  @doc """
  ABI-encode `transferWithMemo(address,uint256,bytes32)` calldata.

  ## Parameters

    * `recipient` — 20-byte binary address
    * `amount` — transfer amount as non-negative integer
    * `memo` — 32-byte binary memo
  """
  @spec transfer_with_memo_calldata(<<_::160>>, non_neg_integer(), <<_::256>>) :: binary()
  # credo:disable-for-lines:3 Credo.Check.Readability.MaxLineLength
  def transfer_with_memo_calldata(recipient, amount, memo)
      when is_binary(recipient) and byte_size(recipient) == 20 and is_integer(amount) and amount >= 0 and is_binary(memo) and
             byte_size(memo) == 32 do
    @transfer_with_memo_selector <>
      <<0::96, recipient::binary-size(20), amount::unsigned-big-size(256), memo::binary-size(32)>>
  end

  @doc """
  ABI-encode `approve(address,uint256)` calldata.

  ## Parameters

    * `spender` — 20-byte binary address
    * `amount` — approval amount as non-negative integer
  """
  @spec approve_calldata(<<_::160>>, non_neg_integer()) :: binary()
  def approve_calldata(spender, amount)
      when is_binary(spender) and byte_size(spender) == 20 and is_integer(amount) and amount >= 0 do
    @approve_selector <> <<0::96, spender::binary-size(20), amount::unsigned-big-size(256)>>
  end

  @doc """
  ABI-encode `balanceOf(address)` calldata.

  ## Parameters

    * `owner` — 20-byte binary address whose balance to query
  """
  @spec balance_of_calldata(<<_::160>>) :: binary()
  def balance_of_calldata(owner) when is_binary(owner) and byte_size(owner) == 20 do
    @balance_of_selector <> <<0::96, owner::binary-size(20)>>
  end

  @doc """
  Decode a hex address string (with or without `0x` prefix) to a 20-byte binary.

  ## Examples

      Onchain.Tempo.TIP20.decode_address("0xdec0000000000000000000000000000000000000")
      #=> <<0xDE, 0xC0, 0x00, ...>>
  """
  @spec decode_address(String.t()) :: binary()
  def decode_address("0x" <> hex), do: decode_address(hex)

  def decode_address(hex) when is_binary(hex) do
    {:ok, bytes} = Base.decode16(hex, case: :mixed)
    bytes
  end
end
