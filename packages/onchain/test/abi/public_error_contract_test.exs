defmodule Onchain.ABI.PublicErrorContractTest do
  @moduledoc """
  Wrong-argument-type contracts of four public ABI heads.

  Each expected outcome was observed by running the same call at e669099f,
  task 9031's benchmark baseline, where these functions were still `ABI.*`.
  Its packages/onchain/lib is identical to 358658e, the parent of the commit
  that swapped the handwritten codec for the alloy NIF (c9c7256). A failure here after a
  codec or facade change is a behaviour regression, not a test to relax.

  The describe names cite the muex campaign survivor each test kills
  (`.mutation/hieroglyph/`, file:line as the campaign reported it). Every one
  is `Guard: replace guard with true`, and at e669099f the same guard sits at
  that file:line.
  """
  use ExUnit.Case, async: true

  alias Onchain.ABI
  alias Onchain.ABI.Event
  alias Onchain.ABI.FunctionSelector
  alias Onchain.ABI.TypeEncoder

  @transfer_event %FunctionSelector{
    function: "Transfer",
    types: [
      %{type: :address, name: "from", indexed: true},
      %{type: :address, name: "to", indexed: true},
      %{type: {:uint, 256}, name: "amount"}
    ]
  }

  @address <<0xB2B7C1795F19FBC28FDA77A95E59EDBB8B3709C8::160>>

  # Hides a wrong-typed literal from Elixir's type checker, which otherwise
  # warns that the call can never succeed. The runtime value is unchanged.
  defp opaque(value), do: value |> :erlang.term_to_binary() |> :erlang.binary_to_term()

  defp transfer_abi do
    ABI.parse_specification([
      %{
        "type" => "function",
        "name" => "transfer",
        "inputs" => [%{"type" => "address"}, %{"type" => "uint256"}]
      }
    ])
  end

  describe "decode_error/3 is_list guard (muex survivor lib/abi.ex:687)" do
    test "a single definition string instead of a list raises FunctionClauseError" do
      revert_data = ABI.encode("NotFound()", [])

      assert_raise FunctionClauseError, fn -> ABI.decode_error(revert_data, opaque("NotFound()"), []) end
    end

    test "nil definitions raise FunctionClauseError" do
      revert_data = ABI.encode("NotFound()", [])

      assert_raise FunctionClauseError, fn -> ABI.decode_error(revert_data, opaque(nil), []) end
    end
  end

  describe "get_abi_item/3 is_list/is_binary guard (muex survivor lib/abi.ex:1136)" do
    test "an atom name raises FunctionClauseError instead of answering :not_found" do
      abi = transfer_abi()

      assert_raise FunctionClauseError, fn -> ABI.get_abi_item(abi, opaque(:transfer), nil) end
    end

    test "a bare selector instead of a list raises FunctionClauseError" do
      [selector] = transfer_abi()

      assert_raise FunctionClauseError, fn -> ABI.get_abi_item(opaque(selector), "transfer", nil) end
    end
  end

  describe "Event.encode_event_topics/2 is_list guard (muex survivor lib/abi/event.ex:139)" do
    test "a bare indexed value instead of a list raises FunctionClauseError" do
      assert_raise FunctionClauseError, fn -> Event.encode_event_topics(@transfer_event, opaque(@address)) end
    end

    test "nil indexed values raise FunctionClauseError" do
      assert_raise FunctionClauseError, fn -> Event.encode_event_topics(@transfer_event, opaque(nil)) end
    end
  end

  describe "TypeEncoder.encode_packed/2 is_list guard (muex survivor lib/abi/type_encoder.ex:349)" do
    test "a scalar value instead of a value list raises FunctionClauseError" do
      assert_raise FunctionClauseError, fn ->
        TypeEncoder.encode_packed(opaque(42), [%{type: {:uint, 256}}])
      end
    end

    test "a bare type map instead of a type list raises FunctionClauseError" do
      assert_raise FunctionClauseError, fn ->
        TypeEncoder.encode_packed([42], opaque(%{type: {:uint, 256}}))
      end
    end
  end
end
