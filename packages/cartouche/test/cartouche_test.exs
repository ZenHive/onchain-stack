defmodule CartoucheTest do
  use ExUnit.Case, async: false

  doctest Cartouche

  # `normalize_descripex_summary/1`'s catch-all is only reachable when
  # `Descripex.Describe.describe/1` yields an entry that is not a `%{module: _}`
  # map. Production never does that; the clause is still the public contract of
  # `describe/0` (pass-through, do not crash).
  test "describe/0 passes through summaries that are not module maps" do
    :meck.new(Descripex.Describe, [:passthrough, :unstick, :no_link])

    :meck.expect(Descripex.Describe, :describe, fn _modules ->
      ["not a summary map", %{short_name: :orphan}]
    end)

    try do
      assert Cartouche.describe() == ["not a summary map", %{short_name: :orphan}]
    after
      :meck.unload(Descripex.Describe)
    end
  end
end
