defmodule ABI.BeforeAlloyFixtureTest do
  use ExUnit.Case, async: true

  @fixture Path.expand("../support/fixtures/abi_before_alloy.etf", __DIR__)

  # spec-tags: NIF-4
  test "the pre-migration ABI corpus retains exact return values and exception reasons" do
    records = @fixture |> File.read!() |> :erlang.binary_to_term()
    assert Enum.count_until(records, 17_353) == 17_352

    Enum.each(records, fn {mod, fun, args, kind, expected} ->
      actual =
        try do
          {:return_from, apply(mod, fun, args)}
        catch
          class, reason -> {:exception_from, {class, reason}}
        end

      assert actual == {kind, expected}, "captured call differs: #{inspect({mod, fun, args}, limit: 20)}"
    end)
  end
end
