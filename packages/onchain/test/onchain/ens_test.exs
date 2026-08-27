defmodule Onchain.ENSTest do
  use ExUnit.Case, async: true

  alias Onchain.ENS

  describe "namehash/1" do
    test "empty string returns 32 zero bytes" do
      assert {:ok, <<0::256>>} = ENS.namehash("")
    end

    test "hashes 'eth' correctly (EIP-137 vector)" do
      expected =
        Base.decode16!("93CDEB708B7545DC668EB9280176169D1C33CFD8ED6F04690A0BCC88A93FC4AE")

      assert {:ok, ^expected} = ENS.namehash("eth")
    end

    test "hashes 'foo.eth' correctly (EIP-137 vector)" do
      expected =
        Base.decode16!("DE9B09FD7C5F901E23A3F19FECC54828E9C848539801E86591BD9801B019F84F")

      assert {:ok, ^expected} = ENS.namehash("foo.eth")
    end

    test "normalizes uppercase to lowercase before hashing" do
      assert {:ok, lower} = ENS.namehash("foo.eth")
      assert {:ok, ^lower} = ENS.namehash("FOO.ETH")
      assert {:ok, ^lower} = ENS.namehash("Foo.Eth")
    end

    test "strips trailing dot before hashing" do
      assert {:ok, without_dot} = ENS.namehash("foo.eth")
      assert {:ok, ^without_dot} = ENS.namehash("foo.eth.")
    end

    test "rejects empty labels" do
      assert {:error, {:invalid_name, "a..b"}} = ENS.namehash("a..b")
    end

    test "rejects leading dot" do
      assert {:error, {:invalid_name, ".eth"}} = ENS.namehash(".eth")
    end

    test "normalizes (case-folds) Unicode labels rather than rejecting them" do
      # Under ENSIP-15 a well-formed Unicode label is normalized, not rejected
      # (the old ASCII-only rule is gone). Case folding makes upper/lower agree.
      assert {:ok, lower} = ENS.namehash("виталик.eth")
      assert {:ok, ^lower} = ENS.namehash("ВИТАЛИК.eth")
      assert byte_size(lower) == 32
    end

    test "rejects names containing disallowed code points" do
      # A C0 control character (U+0007 BELL) is disallowed by ENSIP-15.
      control_name = "foo" <> <<0x07::utf8>> <> "bar.eth"
      assert {:error, {:invalid_name, _}} = ENS.namehash(control_name)

      # A zero-width joiner (U+200D) outside an emoji sequence is disallowed.
      zwj_name = "foo" <> <<0x200D::utf8>> <> "bar.eth"
      assert {:error, {:invalid_name, _}} = ENS.namehash(zwj_name)
    end

    test "rejects bare dot (normalizes to empty but is not a valid name)" do
      assert {:error, {:invalid_name, "."}} = ENS.namehash(".")
    end
  end

  describe "namehash/1 — hyphen handling (ENSIP-15 CheckHyphens=false)" do
    test "accepts label starting with hyphen" do
      assert {:ok, hash} = ENS.namehash("-foo.eth")
      assert byte_size(hash) == 32
    end

    test "accepts label ending with hyphen" do
      assert {:ok, hash} = ENS.namehash("foo-.eth")
      assert byte_size(hash) == 32
    end

    test "accepts hyphen in middle of label" do
      assert {:ok, _} = ENS.namehash("my-name.eth")
    end

    test "accepts label that is only a hyphen" do
      assert {:ok, hash} = ENS.namehash("-.eth")
      assert byte_size(hash) == 32
    end
  end

  describe "namehash/1 — reverse name construction" do
    test "reverse name produces correct namehash for known address" do
      # The reverse name for 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045 is
      # "d8da6bf26964af9d7eed9e03e53415d37aa96045.addr.reverse"
      # We verify that namehash of the reverse name produces a deterministic 32-byte hash
      reverse_name = "d8da6bf26964af9d7eed9e03e53415d37aa96045.addr.reverse"
      assert {:ok, hash} = ENS.namehash(reverse_name)
      assert byte_size(hash) == 32
      assert hash != <<0::256>>
    end
  end

  describe "normalize/1" do
    test "passes through canonical ASCII names" do
      assert {:ok, "vitalik.eth"} = ENS.normalize("vitalik.eth")
    end

    test "case-folds to lowercase" do
      assert {:ok, "vitalik.eth"} = ENS.normalize("VITALIK.ETH")
    end

    test "strips a trailing dot" do
      assert {:ok, "foo.eth"} = ENS.normalize("foo.eth.")
    end

    test "applies NFC so composed and decomposed forms agree" do
      composed = "café.eth"
      decomposed = "cafe" <> <<0x0301::utf8>> <> ".eth"
      assert {:ok, normalized} = ENS.normalize(decomposed)
      assert {:ok, ^normalized} = ENS.normalize(composed)
    end

    test "strips ignored code points (soft hyphen, variation selector)" do
      with_soft_hyphen = "ab" <> <<0x00AD::utf8>> <> "c.eth"
      assert {:ok, "abc.eth"} = ENS.normalize(with_soft_hyphen)
    end

    test "rejects empty labels" do
      assert {:error, {:invalid_name, "a..b"}} = ENS.normalize("a..b")
    end

    test "the empty string is the root name" do
      assert {:ok, ""} = ENS.normalize("")
    end
  end

  describe "normalize!/1" do
    test "returns the normalized name directly" do
      assert "vitalik.eth" = ENS.normalize!("Vitalik.ETH")
    end

    test "raises on an invalid name" do
      assert_raise RuntimeError, ~r/normalize failed/, fn -> ENS.normalize!("a..b") end
    end
  end

  describe "dns_encode/1" do
    test "encodes labels as length-prefixed with a null terminator (ENSIP-10)" do
      assert {:ok, <<3, "foo", 3, "eth", 0>>} = ENS.dns_encode("foo.eth")
    end

    test "normalizes before encoding" do
      assert {:ok, <<3, "foo", 3, "eth", 0>>} = ENS.dns_encode("FOO.eth")
    end

    test "encodes the root name as a single null byte" do
      assert {:ok, <<0>>} = ENS.dns_encode("")
    end

    test "rejects an invalid name" do
      assert {:error, {:invalid_name, "a..b"}} = ENS.dns_encode("a..b")
    end
  end

  describe "dns_encode!/1" do
    test "returns the encoding directly" do
      assert <<3, "foo", 3, "eth", 0>> = ENS.dns_encode!("foo.eth")
    end

    test "raises on an invalid name" do
      assert_raise RuntimeError, ~r/dns_encode failed/, fn -> ENS.dns_encode!("a..b") end
    end
  end

  describe "wildcard_suffix_names/1 (ENSIP-10 parent walk)" do
    test "lists suffixes from the full name down to the TLD" do
      assert ENS.wildcard_suffix_names("sub.parent.eth") == [
               "sub.parent.eth",
               "parent.eth",
               "eth"
             ]
    end

    test "single-label name is only itself" do
      assert ENS.wildcard_suffix_names("eth") == ["eth"]
    end

    test "root name is a single empty-label candidate (EIP-137 root node)" do
      assert ENS.wildcard_suffix_names("") == [""]
    end
  end

  describe "evm_coin_type/1" do
    test "derives the ENSIP-11 coin type from a chain id" do
      # 0x80000000 | 1 = 2147483649 (Ethereum mainnet, ENSIP-11 form)
      assert ENS.evm_coin_type(1) == 2_147_483_649
      # 0x80000000 | 10 = 2147483658 (Optimism)
      assert ENS.evm_coin_type(10) == 2_147_483_658
      # 0x80000000 | 8453 = 2147492101 (Base)
      assert ENS.evm_coin_type(8453) == 2_147_492_101
    end
  end

  describe "address/3 input validation" do
    test "rejects an invalid name" do
      assert {:error, {:invalid_name, "a..b"}} = ENS.address("a..b")
    end

    test "rejects an invalid name for a non-default coin type" do
      assert {:error, {:invalid_name, "a..b"}} = ENS.address("a..b", 0)
    end
  end

  describe "address!/3" do
    test "raises on an invalid name" do
      assert_raise RuntimeError, ~r/address resolution failed/, fn -> ENS.address!("a..b") end
    end
  end

  describe "resolve/2 input validation" do
    test "rejects invalid name" do
      assert {:error, {:invalid_name, "a..b"}} = ENS.resolve("a..b")
    end
  end

  describe "reverse/2 input validation" do
    test "rejects invalid address" do
      assert {:error, {:invalid_address, "not_an_address"}} = ENS.reverse("not_an_address")
    end
  end

  describe "namehash!/1" do
    test "returns hash directly on success" do
      expected =
        Base.decode16!("93CDEB708B7545DC668EB9280176169D1C33CFD8ED6F04690A0BCC88A93FC4AE")

      assert ^expected = ENS.namehash!("eth")
    end

    test "raises on invalid name" do
      assert_raise RuntimeError, ~r/namehash failed/, fn ->
        ENS.namehash!("a..b")
      end
    end
  end

  describe "resolver!/2" do
    test "raises on invalid name" do
      assert_raise RuntimeError, ~r/resolver lookup failed/, fn ->
        ENS.resolver!("a..b")
      end
    end
  end

  describe "resolve!/2" do
    test "raises on invalid name" do
      assert_raise RuntimeError, ~r/resolve failed/, fn ->
        ENS.resolve!("a..b")
      end
    end
  end

  describe "reverse!/2" do
    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/reverse failed/, fn ->
        ENS.reverse!("not_an_address")
      end
    end
  end

  describe "text!/3" do
    test "raises on invalid name" do
      assert_raise RuntimeError, ~r/text lookup failed/, fn ->
        ENS.text!("a..b", "avatar")
      end
    end
  end

  describe "contenthash!/2" do
    test "raises on invalid name" do
      assert_raise RuntimeError, ~r/contenthash lookup failed/, fn ->
        ENS.contenthash!("a..b")
      end
    end
  end

  describe "pubkey!/2" do
    test "raises on invalid name" do
      assert_raise RuntimeError, ~r/pubkey lookup failed/, fn ->
        ENS.pubkey!("a..b")
      end
    end
  end

  describe "abi!/3" do
    test "raises on invalid name" do
      assert_raise RuntimeError, ~r/abi lookup failed/, fn ->
        ENS.abi!("a..b", 1)
      end
    end
  end
end
