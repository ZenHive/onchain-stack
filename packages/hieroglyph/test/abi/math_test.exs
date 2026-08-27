defmodule ABI.MathTest do
  use ExUnit.Case, async: true

  alias ABI.Math

  doctest Math

  describe "mod/2" do
    # The negative branch is `rem(rem(x, n) + n, n)`; the doctests only
    # exercise dividends of magnitude >= 5, so the -1 boundary (the first
    # value below the `x < 0` guard) is pinned here explicitly.
    test "wraps small negative dividends into 0..n-1" do
      assert Math.mod(-1, 5) == 4
      assert Math.mod(-2, 5) == 3
      assert Math.mod(-1, 1) == 0
      assert Math.mod(-1, 1337) == 1336
    end
  end
end
