defmodule Onchain.RPCSimulateLiveTest do
  use ExUnit.Case, async: false

  import Onchain.Test.Live

  alias Onchain.Filter.Log
  alias Onchain.Hex
  alias Onchain.RPC
  alias Onchain.RPC.Simulate.AccountOverride
  alias Onchain.RPC.Simulate.BlockResult
  alias Onchain.RPC.Simulate.BlockStateCall
  alias Onchain.RPC.Simulate.Call
  alias Onchain.RPC.Simulate.CallError
  alias Onchain.RPC.Simulate.CallFailure
  alias Onchain.RPC.Simulate.CallSuccess
  alias Onchain.RPC.Simulate.Payload

  @moduletag :integration

  @from Hex.decode_address!("0x1111111111111111111111111111111111111111")
  @bob Hex.decode_address!("0x2222222222222222222222222222222222222222")
  @carol Hex.decode_address!("0x3333333333333333333333333333333333333333")
  @dai Hex.decode_address!("0x6b175474e89094c44da98b954eedeac495271d0f")
  @vitalik Hex.decode_address!("0xd8da6bf26964af9d7eed9e03e53415d37aa96045")
  @trace_emitter Hex.decode_address!("0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee")
  @transfer_topic Hex.decode_word!("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef")
  @dai_message "execution reverted: Dai/insufficient-balance"
  @infura_message "The method eth_simulateV1 does not exist/is not available"
  @dai_data Hex.decode_hex!(
              "0x08c379a0" <>
                "0000000000000000000000000000000000000000000000000000000000000020" <>
                "0000000000000000000000000000000000000000000000000000000000000018" <>
                "4461692f696e73756666696369656e742d62616c616e6365" <>
                "0000000000000000"
            )

  test "a funded multi-call succeeds on archive and Alchemy; Infura refuses the method" do
    assert_portability!(&RPC.eth_simulate_v1(funded_payload(), &1),
      archive: &funded?/1,
      alchemy: &funded?/1,
      infura: &infura_unsupported?/1
    )
  end

  test "a reverting call stays inside a successful response on archive and Alchemy" do
    assert_portability!(&RPC.eth_simulate_v1(reverting_payload(), &1),
      archive: &reverting_call?/1,
      alchemy: &reverting_call?/1,
      infura: &infura_unsupported?/1
    )
  end

  test "nonce 0 under validation is a request rejection, distinct from unsupported" do
    assert_portability!(&rejection_answer/1,
      archive: &nonce_rejection?/1,
      alchemy: &nonce_rejection?/1,
      infura: &infura_nonce_refusal?/1
    )
  end

  defp funded?({:ok, [%BlockResult{calls: [first, second]}]}) do
    transfer?(first, @bob, 1, 0) and transfer?(second, @carol, 2, 1)
  end

  defp funded?(_answer), do: false

  defp transfer?(%CallSuccess{} = call, to, value, index) do
    case call do
      %CallSuccess{status: 1, return_data: <<>>, gas_used: 21_000, max_used_gas: 21_000, logs: [log]} ->
        transfer_log?(log, to, value, index)

      _ ->
        false
    end
  end

  defp transfer?(_call, _to, _value, _index), do: false

  defp transfer_log?(%Log{} = log, to, value, index) do
    case log do
      %Log{
        address: @trace_emitter,
        data: <<^value::256>>,
        log_index: ^index,
        transaction_index: ^index,
        removed: false,
        topics: [@transfer_topic, from_topic, to_topic]
      } ->
        from_topic == padded(@from) and to_topic == padded(to)

      _ ->
        false
    end
  end

  defp transfer_log?(_log, _to, _value, _index), do: false

  defp reverting_call?(
         {:ok,
          [
            %BlockResult{
              calls: [
                %CallSuccess{status: 1, return_data: <<>>, gas_used: 21_000, max_used_gas: 21_000, logs: []},
                %CallFailure{
                  status: 0,
                  return_data: <<>>,
                  gas_used: 24_211,
                  max_used_gas: 24_211,
                  logs: [],
                  error: %CallError{code: 3, message: @dai_message, data: @dai_data}
                }
              ]
            }
          ]}
       ), do: true

  defp reverting_call?(_answer), do: false

  defp rejection_answer(opts) do
    case RPC.get_nonce(@vitalik, opts) do
      {:ok, nonce} -> {nonce, RPC.eth_simulate_v1(rejection_payload(), opts)}
      other -> other
    end
  end

  defp nonce_rejection?({nonce, {:error, %{code: -38_010, message: message}}}) when is_integer(nonce) do
    message == "nonce too low: next nonce #{nonce}, tx nonce 0"
  end

  defp nonce_rejection?(_answer), do: false

  defp infura_unsupported?({:error, {:method_not_found, %{code: -32_601, message: @infura_message}}}), do: true
  defp infura_unsupported?(_answer), do: false

  defp infura_nonce_refusal?({_nonce, {:error, {:method_not_found, %{code: -32_601, message: @infura_message}}}}) do
    true
  end

  defp infura_nonce_refusal?(_answer), do: false

  defp funded_payload do
    %Payload{
      block_state_calls: [
        %BlockStateCall{
          calls: [
            %Call{from: @from, to: @bob, value: 1, gas: 21_000},
            %Call{from: @from, to: @carol, value: 2, gas: 21_000}
          ],
          state_overrides: %{@from => %AccountOverride{balance: 1_000_000_000_000_000_000}}
        }
      ],
      trace_transfers: true,
      validation: false
    }
  end

  defp reverting_payload do
    %Payload{
      block_state_calls: [
        %BlockStateCall{
          calls: [
            %Call{from: @from, to: @bob, value: 0, gas: 21_000},
            %Call{from: @from, to: @dai, input: dai_transfer(), gas: 100_000}
          ]
        }
      ],
      validation: false
    }
  end

  defp rejection_payload do
    %Payload{
      block_state_calls: [
        %BlockStateCall{
          calls: [
            %Call{
              from: @vitalik,
              to: @bob,
              value: 0,
              nonce: 0,
              gas: 21_000,
              max_fee_per_gas: 100_000_000,
              max_priority_fee_per_gas: 1
            }
          ]
        }
      ],
      validation: true
    }
  end

  defp dai_transfer do
    <<0xA9, 0x05, 0x9C, 0xBB>> <> padded(@bob) <> <<1::256>>
  end

  defp padded(<<_::160>> = address), do: <<0::96, address::binary>>
end
