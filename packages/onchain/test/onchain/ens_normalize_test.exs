defmodule Onchain.ENS.NormalizeTest do
  use ExUnit.Case, async: true

  alias Onchain.ENS.Normalize

  describe "normalize/1 — reference vectors" do
    # Each {input, expected} is a deterministic UTS-46 / ENSIP-15 transformation
    # (case fold + NFC + ignored-code-point removal). Confusable / script-mixing
    # filters are intentionally out of scope — see the module docs.
    @vectors [
      {"vitalik.eth", "vitalik.eth"},
      {"VITALIK.ETH", "vitalik.eth"},
      {"Nick.ETH", "nick.eth"},
      {"foo.eth.", "foo.eth"},
      {"", ""}
    ]

    for {input, expected} <- @vectors do
      test "normalize(#{inspect(input)}) == #{inspect(expected)}" do
        assert {:ok, unquote(expected)} = Normalize.normalize(unquote(input))
      end
    end

    test "NFC composes a decomposed label (café)" do
      composed = <<0x63, 0x61, 0x66, 0xC3, 0xA9>> <> ".eth"
      decomposed = <<0x63, 0x61, 0x66, 0x65, 0xCC, 0x81>> <> ".eth"

      assert {:ok, ^composed} = Normalize.normalize(decomposed)
    end

    test "strips a soft hyphen (U+00AD) ignored code point" do
      input = "ab" <> <<0x00AD::utf8>> <> "c.eth"
      assert {:ok, "abc.eth"} = Normalize.normalize(input)
    end

    test "strips an emoji variation selector (U+FE0F)" do
      heart_qualified = <<0x2764::utf8, 0xFE0F::utf8>>
      heart_bare = <<0x2764::utf8>>

      assert {:ok, normalized} = Normalize.normalize(heart_qualified <> ".eth")
      assert normalized == heart_bare <> ".eth"
    end
  end

  describe "normalize/1 — idempotency" do
    for {_input, expected} <- [{"x", "vitalik.eth"}, {"y", "café.eth"}, {"z", "nick.eth"}] do
      test "normalize is a fixed point for #{inspect(expected)}" do
        assert {:ok, once} = Normalize.normalize(unquote(expected))
        assert {:ok, ^once} = Normalize.normalize(once)
      end
    end
  end

  describe "normalize/1 — rejections" do
    test "empty labels" do
      assert {:error, {:invalid_name, "a..b"}} = Normalize.normalize("a..b")
      assert {:error, {:invalid_name, ".eth"}} = Normalize.normalize(".eth")
      assert {:error, {:invalid_name, "."}} = Normalize.normalize(".")
    end

    test "C0/C1 control characters" do
      assert {:error, {:invalid_name, _}} =
               Normalize.normalize("a" <> <<0x00::utf8>> <> "b.eth")

      assert {:error, {:invalid_name, _}} =
               Normalize.normalize("a" <> <<0x85::utf8>> <> "b.eth")
    end

    test "zero-width and format code points" do
      for cp <- [0x200B, 0x200C, 0x200D, 0xFEFF, 0x2060] do
        input = "a" <> <<cp::utf8>> <> "b.eth"
        assert {:error, {:invalid_name, _}} = Normalize.normalize(input)
      end
    end

    test "a label consisting only of ignored code points" do
      assert {:error, {:invalid_name, _}} = Normalize.normalize(<<0xFE0F::utf8>> <> ".eth")
    end

    test "non-binary input" do
      assert {:error, {:invalid_name, :not_a_string}} = Normalize.normalize(:not_a_string)
    end
  end
end
