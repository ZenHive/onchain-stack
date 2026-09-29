defmodule Cartouche.VmTestHelpers do
  @moduledoc false

  @doc false
  @spec word(integer() | binary(), pos_integer() | nil) :: binary()
  def word(x, sz \\ nil)

  def word(x, nil) when is_integer(x) and x >= 0 do
    {:ok, res} = Cartouche.VM.uint_to_word(x)
    res
  end

  def word(x, sz) when is_integer(x) and x >= 0 do
    <<_::binary-size(32 - ^sz), res::binary-size(^sz)>> = word(x)
    res
  end

  def word(x, nil) when is_integer(x) and x < 0 do
    {:ok, res} = Cartouche.VM.sint_to_word(x)
    res
  end

  def word("0x" <> x, nil) do
    {:ok, res} = Cartouche.VM.pad_to_word(Cartouche.Hex.from_hex!(x))
    res
  end

  def word(x, nil) when is_binary(x) do
    {:ok, res} = Cartouche.VM.pad_to_word(x)
    res
  end
end
