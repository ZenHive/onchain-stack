# Lightweight helpers for building dummy 0x76 Tempo Transactions in unit tests.
# Uses ExRLP directly for encoding (no real signing).
defmodule Onchain.Tempo.TestHelpers do
  @moduledoc false

  alias Onchain.Tempo.TIP20

  @doc "Builds a hex-encoded 0x76 Tempo Transaction with the given calls and chain_id."
  @spec build_tempo_tx(keyword()) :: String.t()
  def build_tempo_tx(opts \\ []) do
    chain_id = Keyword.get(opts, :chain_id, 42_431)
    calls = Keyword.get(opts, :calls, [])
    fee_payer? = Keyword.get(opts, :fee_payer, false)

    # fee_payer_signature: <<0x00>> (placeholder) when fee_payer, <<>> (absent) otherwise.
    fee_payer_sig = if fee_payer?, do: <<0x00>>, else: <<>>

    body = [
      :binary.encode_unsigned(chain_id),
      <<>>,
      <<>>,
      :binary.encode_unsigned(21_000),
      calls,
      [],
      <<>>,
      <<>>,
      <<>>,
      <<>>,
      <<>>,
      fee_payer_sig,
      [],
      <<1::512>>
    ]

    raw = <<0x76>> <> ExRLP.encode(body)
    "0x" <> Base.encode16(raw, case: :lower)
  end

  @doc "Builds a single call tuple [to, value, input] for RLP encoding."
  @spec build_call(String.t(), binary()) :: [binary()]
  def build_call(to_hex, input) do
    [TIP20.decode_address(to_hex), <<>>, input]
  end

  @doc "Builds ABI-encoded calldata for transfer(address,uint256)."
  @spec transfer_calldata(String.t(), non_neg_integer()) :: binary()
  def transfer_calldata(recipient_hex, amount) do
    TIP20.transfer_calldata(TIP20.decode_address(recipient_hex), amount)
  end

  @doc "Builds ABI-encoded calldata for transferWithMemo(address,uint256,bytes32)."
  @spec transfer_with_memo_calldata(String.t(), non_neg_integer(), String.t()) :: binary()
  def transfer_with_memo_calldata(recipient_hex, amount, memo_hex) do
    recipient = TIP20.decode_address(recipient_hex)
    {:ok, memo_bytes} = Base.decode16(strip_0x(memo_hex), case: :mixed)
    TIP20.transfer_with_memo_calldata(recipient, amount, memo_bytes)
  end

  @doc "Builds ABI-encoded calldata for approve(address,uint256)."
  @spec approve_calldata(String.t(), non_neg_integer()) :: binary()
  def approve_calldata(spender_hex, amount) do
    TIP20.approve_calldata(TIP20.decode_address(spender_hex), amount)
  end

  @doc "Builds ABI-encoded calldata for swapExactAmountOut with zero-padded args."
  @spec swap_calldata() :: binary()
  def swap_calldata do
    TIP20.swap_exact_amount_out_selector() <> :binary.copy(<<0>>, 96)
  end

  @doc "Returns the canonical stablecoin DEX address (hex string)."
  @spec dex_address() :: String.t()
  def dex_address, do: "0xdec0000000000000000000000000000000000000"

  @doc "Decodes a hex address to a 20-byte binary."
  @spec decode_address(String.t()) :: binary()
  def decode_address(hex), do: TIP20.decode_address(hex)

  @doc "Strips the optional 0x prefix from a hex string."
  @spec strip_0x(String.t()) :: String.t()
  def strip_0x("0x" <> rest), do: rest
  def strip_0x(hex), do: hex
end
