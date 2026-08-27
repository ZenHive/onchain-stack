defmodule OnchainTempoTest do
  use ExUnit.Case, async: true

  test "describe/0 returns module overview" do
    result = OnchainTempo.describe()
    assert is_map(result) or is_list(result)
  end
end
