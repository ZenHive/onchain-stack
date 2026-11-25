defmodule OnchainJs.ScriptTest do
  use ExUnit.Case, async: false

  alias OnchainJs.Runtime
  alias OnchainJs.Script

  @js_dir Path.expand("../support/js", __DIR__)
  @node_modules Path.expand("../../node_modules", __DIR__)

  defp entry(name), do: Path.join(@js_dir, name)

  defp require_npm_install! do
    if !File.dir?(Path.join(@node_modules, "@noble/hashes")) do
      flunk("node_modules/@noble/hashes missing: run `mix npm.ci` in packages/onchain_js")
    end
  end

  describe "bundle/2 failures" do
    test "a missing entry file is a bundle_error carrying the posix reason" do
      path = entry("does_not_exist.js")

      assert {:error, {:bundle_error, ^path, {:file_read_error, ^path, :enoent}}} = Script.bundle(path)
    end

    test "an unresolvable npm import names the specifier and installs nothing" do
      path = entry("missing_package.js")

      assert {:error, {:bundle_error, ^path, {:module_not_found, "onchain-js-no-such-package", message}}} =
               Script.bundle(path)

      assert is_binary(message) and message != ""
      refute File.exists?(Path.join(@node_modules, "onchain-js-no-such-package"))
    end

    test "a syntax error is a bundle_error carrying the parser's diagnostics" do
      path = entry("syntax_error.js")

      assert {:error, {:bundle_error, ^path, {:parse_error, ^path, [_ | _] = errors}}} = Script.bundle(path)
      assert Enum.all?(errors, &(is_binary(&1.message) and &1.message != ""))
    end
  end

  describe "npm package from node_modules" do
    @describetag :integration

    setup do
      require_npm_install!()
      {:ok, rt} = Runtime.start_link()
      on_exit(fn -> if Process.alive?(rt), do: Runtime.stop(rt) end)
      {:ok, rt: rt}
    end

    test "@noble/hashes keccak_256 reproduces the Ethereum Keccak-256 vectors", %{rt: rt} do
      assert :ok = Script.load(rt, entry("keccak.js"))

      # Keccak-256 (pre-NIST padding), the Ethereum hash: empty-input digest is the
      # well-known empty code hash; "abc" is the Keccak team's reference vector.
      assert {:ok, "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"} =
               Runtime.call(rt, "keccak256Hex", [""])

      assert {:ok, "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"} =
               Runtime.call(rt, "keccak256Hex", ["abc"])

      # Cross-check against the native implementation the rest of the stack signs with.
      input = "transfer(address,uint256)"
      expected = input |> ExKeccak.hash_256() |> Base.encode16(case: :lower)
      assert {:ok, ^expected} = Runtime.call(rt, "keccak256Hex", [input])
      assert String.starts_with?(expected, "a9059cbb")
    end

    test "a release-style priv/ layout outside the project resolves from its own node_modules", %{rt: rt} do
      # Disjoint from this project: the ancestor walk can only find the copy.
      root = Path.join(System.tmp_dir!(), "onchain_js_release_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(root) end)

      js = Path.join(root, "priv/js/keccak.js")
      File.mkdir_p!(Path.dirname(js))
      File.cp!(entry("keccak.js"), js)

      assert {:error, {:bundle_error, ^js, {:module_not_found, "@noble/hashes/sha3.js", _}}} =
               Script.load(rt, js)

      File.cp_r!(@node_modules, Path.join(root, "priv/node_modules"))

      assert :ok = Script.load(rt, js)

      assert {:ok, "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"} =
               Runtime.call(rt, "keccak256Hex", [""])
    end

    test "a :node_modules override is rejected rather than silently ignored", %{rt: rt} do
      path = entry("keccak.js")

      assert {:error, {:bundle_error, ^path, {:unsupported_option, :node_modules}}} =
               Script.load(rt, path, node_modules: @node_modules)

      assert {:error, {:bundle_error, ^path, {:unsupported_option, :node_modules}}} =
               Script.bundle(path, node_modules: "node_modules")
    end

    test "a missing browser global surfaces the JS ReferenceError", %{rt: rt} do
      path = entry("needs_self.js")

      assert {:error, {:eval_error, ^path, %QuickBEAM.JSError{name: "ReferenceError", message: message}}} =
               Script.load(rt, path, browser_stubs: false)

      assert message =~ "self is not defined"
    end

    test "the default browser stubs satisfy the same script", %{rt: rt} do
      assert :ok = Script.load(rt, entry("needs_self.js"))
      assert {:ok, true} = Runtime.call(rt, "rootIsGlobal", [])
    end

    test "a bundling failure is returned from load/3 unchanged", %{rt: rt} do
      path = entry("missing_package.js")

      assert {:error, {:bundle_error, ^path, {:module_not_found, "onchain-js-no-such-package", _}}} =
               Script.load(rt, path)
    end

    test "Runtime.start_link(script:) loads the same bundle at startup" do
      assert {:ok, rt} = Runtime.start_link(script: entry("keccak.js"))

      try do
        assert {:ok, "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"} =
                 Runtime.call(rt, "keccak256Hex", ["abc"])
      after
        Runtime.stop(rt)
      end
    end
  end
end
