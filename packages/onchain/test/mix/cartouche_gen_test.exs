defmodule Mix.Tasks.Cartouche.GenTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Mix.Tasks.Cartouche.Gen

  # Drives the generator end-to-end through its public Mix-task entrypoint
  # so the assertions cover the full code path users actually hit.

  setup do
    tmp = Path.join(System.tmp_dir!(), "cartouche_gen_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  defp pure_function_abi do
    [
      %{
        "type" => "function",
        "name" => "ping",
        "inputs" => [%{"name" => "x", "type" => "uint256", "internalType" => "uint256"}],
        "outputs" => [%{"name" => "", "type" => "uint256", "internalType" => "uint256"}],
        "stateMutability" => "pure"
      }
    ]
  end

  defp synthetic_abi do
    __DIR__
    |> Path.join("../support/synthetic_abi.json")
    |> File.read!()
    |> Jason.decode!()
  end

  defp write_artifact(tmp, name, bytecode_object, abi, opts) do
    artifact = %{
      "abi" => abi,
      "metadata" => metadata_for(name, opts)
    }

    write_artifact_map(tmp, name, put_bytecode(artifact, bytecode_object))
  end

  defp write_artifact_map(tmp, name, artifact) do
    path = Path.join(tmp, "#{name}.json")
    File.write!(path, Jason.encode!(artifact))
    path
  end

  defp metadata_for(name, opts) do
    if Keyword.get(opts, :metadata, true) do
      %{"settings" => %{"compilationTarget" => %{"src/#{name}.sol" => name}}}
    end
  end

  defp put_bytecode(artifact, bytecode_object) do
    case bytecode_object do
      :absent ->
        artifact

      v ->
        bytecode = %{"object" => v}

        artifact
        |> Map.put("bytecode", bytecode)
        |> Map.put("deployedBytecode", bytecode)
    end
  end

  defp put_bytecodes(artifact, init_bytecode, deployed_bytecode) do
    artifact
    |> maybe_put_bytecode("bytecode", init_bytecode)
    |> maybe_put_bytecode("deployedBytecode", deployed_bytecode)
  end

  defp maybe_put_bytecode(artifact, _key, :absent), do: artifact
  defp maybe_put_bytecode(artifact, key, bytecode), do: Map.put(artifact, key, %{"object" => bytecode})

  defp generate(tmp, name, bytecode_object, abi \\ pure_function_abi(), opts \\ []) do
    artifact_path = write_artifact(tmp, name, bytecode_object, abi, opts)
    generate_file(tmp, name, artifact_path)
  end

  defp generate_artifact(tmp, name, artifact) do
    artifact_path = write_artifact_map(tmp, name, artifact)
    generate_file(tmp, name, artifact_path)
  end

  defp generate_file(tmp, name, artifact_path) do
    out_dir = Path.join(tmp, "out")
    File.mkdir_p!(out_dir)

    Gen.run([
      "--prefix",
      "gen_test",
      "--out",
      out_dir,
      artifact_path
    ])

    out_dir
    |> Path.join("gen_test")
    |> Path.join("#{Macro.underscore(name)}.ex")
    |> File.read!()
  end

  defp solidity_artifact(name, abi, opts \\ []) do
    metadata =
      %{
        "settings" => %{
          "compilationTarget" => %{"src/#{name}.sol" => name}
        }
      }

    metadata =
      if Keyword.get(opts, :metadata_json?, false) do
        Jason.encode!(metadata)
      else
        metadata
      end

    %{"abi" => abi, "metadata" => metadata}
  end

  defp ast_artifact(name, abi) do
    %{
      "abi" => abi,
      "ast" => %{
        "sourceUnit" => 1,
        "absolutePath" => "/synthetic/contracts/#{name}.sol"
      }
    }
  end

  defp abi_only_file(tmp, name, abi) do
    path = Path.join(tmp, "#{name}.json")
    File.write!(path, Jason.encode!(abi))
    path
  end

  defp generate_abi_file(tmp, name, abi) do
    generate_file(tmp, name, abi_only_file(tmp, name, abi))
  end

  defp generated_module(contents) do
    [{module, _bytecode}] = Code.compile_string(contents)
    module
  end

  defp refute_bytecode_emission(contents) do
    refute contents =~ "def exec_vm_"
    refute contents =~ "def bytecode"
    refute contents =~ "def deployed_bytecode"
  end

  defp assert_bytecode_emission(contents) do
    assert contents =~ "def exec_vm_"
    assert contents =~ "def bytecode"
    assert contents =~ "def deployed_bytecode"
  end

  defp public_defs(contents) do
    ~r/^\s{2}def\s+([a-z_][a-zA-Z0-9_!?]*)(?:\(|\b)/m
    |> Regex.scan(contents, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp annotation_stanza(contents, name) do
    pattern = ~r/@doc (?:\"[^\"]+\"|false)\n\s+@spec #{name}\([\s\S]*?\n\s+def #{name}(?:\(|\b)/

    Regex.run(pattern, contents)
  end

  describe "blank_bytecode?/1 predicate" do
    test "literal \"0x\" bytecode emits no exec_vm_* and no bytecode/0", %{tmp: tmp} do
      refute_bytecode_emission(generate(tmp, "BlankZeroX", "0x"))
    end

    test "absent bytecode key emits no exec_vm_* and no bytecode/0", %{tmp: tmp} do
      refute_bytecode_emission(generate(tmp, "BlankAbsent", :absent))
    end

    test "real bytecode emits exec_vm_* for :pure selectors", %{tmp: tmp} do
      assert_bytecode_emission(generate(tmp, "RealBytecode", "0x6080604052348015"))
    end

    test "generated preintern helper is a compile-time atom literal, not a runtime walk",
         %{tmp: tmp} do
      contents = generate(tmp, "SpecPreintern", "0x6080604052348015")

      # The decode-field atom set is collected at generation time and emitted as a
      # module-attribute literal the BEAM interns at load; the helper just returns it.
      assert contents =~ "@decode_field_atoms"
      assert contents =~ "defp preintern_return_atoms!(_returns)"

      # No runtime String.to_atom/1 — the previous walk shipped that unsafe idiom
      # into every generated contract.
      refute contents =~ "String.to_atom"
      refute contents =~ "preintern_name_atom!"
    end

    test "whitespace-only bytecode is treated as blank", %{tmp: tmp} do
      refute_bytecode_emission(generate(tmp, "BlankWhitespace", "   "))
    end

    test "unlinked library placeholder bytecode is treated as blank", %{tmp: tmp} do
      link_marker = "__$0123456789abcdef0123456789abcdef01$__"

      bytecode = %{
        "object" => "0x60806040#{link_marker}6000",
        "linkReferences" => %{
          "src/MathLib.sol" => %{
            "MathLib" => [%{"length" => 20, "start" => 4}]
          }
        }
      }

      artifact =
        "UnlinkedLibrary"
        |> solidity_artifact(pure_function_abi())
        |> Map.put("bytecode", bytecode)
        |> Map.put("deployedBytecode", bytecode)

      contents = generate_artifact(tmp, "UnlinkedLibrary", artifact)

      refute_bytecode_emission(contents)
      assert contents =~ "def encode_ping"
      assert contents =~ "def call_ping"
      assert contents =~ "def execute_ping"

      module = generated_module(contents)

      assert function_exported?(module, :encode_ping, 1)
      refute function_exported?(module, :bytecode, 0)
      refute function_exported?(module, :deployed_bytecode, 0)
    end
  end

  describe "RPC-side API survives bytecode dropout" do
    test "encode_/call_/execute_ helpers are emitted even without bytecode", %{tmp: tmp} do
      contents = generate(tmp, "RpcOnly", "0x")

      assert contents =~ "def encode_ping"
      assert contents =~ "def call_ping"
      assert contents =~ "def execute_ping"
    end

    test "generated public functions include ABI-derived docs and specs", %{tmp: tmp} do
      contents = generate(tmp, "DocumentedRpc", "0x6080604052348015")

      for name <- public_defs(contents) do
        assert annotation_stanza(contents, name)
      end

      assert contents =~ ~S|@doc "Encodes ABI calldata for `encode_ping/ping(uint256)`."|
      assert contents =~ "@spec encode_ping(non_neg_integer()) :: binary()"
      assert contents =~ "@spec ping_selector() :: ABI.FunctionSelector.t()"
      assert contents =~ "@spec decode_ping_call(binary()) :: [non_neg_integer()]"
      assert contents =~ "@spec call_ping(<<_::160>>, non_neg_integer(), Keyword.t()) ::"
      assert contents =~ "@spec exec_vm_ping(non_neg_integer(), Keyword.t()) ::"
      assert contents =~ "@spec bytecode() :: binary()"
      assert contents =~ "@spec deployed_bytecode() :: binary()"
      assert contents =~ "@spec abi() :: [map()]"
    end

    test "generated specs track calldata inputs and exec_vm return unwrapping", %{tmp: tmp} do
      abi = [
        %{
          "type" => "function",
          "name" => "differentShapes",
          "inputs" => [
            %{"name" => "who", "type" => "address"},
            %{"name" => "label", "type" => "string"}
          ],
          "outputs" => [%{"name" => "", "type" => "bool"}],
          "stateMutability" => "pure"
        },
        %{
          "type" => "function",
          "name" => "triple",
          "inputs" => [],
          "outputs" => [
            %{
              "name" => "",
              "type" => "tuple",
              "components" => [
                %{"name" => "", "type" => "uint256"},
                %{"name" => "", "type" => "bool"},
                %{"name" => "", "type" => "address"}
              ]
            }
          ],
          "stateMutability" => "pure"
        }
      ]

      contents = generate(tmp, "SpecShapes", "0x6080604052348015", abi)

      assert contents =~ "@spec decode_different_shapes_call(binary()) :: [<<_::160>> | String.t()]"
      assert contents =~ "@spec exec_vm_different_shapes(<<_::160>>, String.t(), Keyword.t()) ::"
      assert contents =~ "{:ok, boolean()} | {:revert, String.t(), term()}"
      assert contents =~ "@spec exec_vm_triple(Keyword.t()) ::"
      assert contents =~ "{:ok, {non_neg_integer(), boolean(), <<_::160>>}} | {:revert, String.t(), term()}"
    end

    test "fallback and receive docs describe synthesized calldata argument", %{tmp: tmp} do
      contents = generate(tmp, "FallbackDocs", "0x6080604052348015", synthetic_abi())

      assert contents =~ ~S|@doc "Encodes ABI calldata for `encode_fallback/fallback(bytes)`."|
      assert contents =~ ~S|@doc "Encodes ABI calldata for `encode_receive/receive(bytes)`."|
    end
  end

  describe "selector shapes" do
    test "constructor helpers use bytecode and tuple field atoms", %{tmp: tmp} do
      abi = [
        %{
          "type" => "constructor",
          "inputs" => [
            %{
              "name" => "config",
              "type" => "tuple",
              "components" => [
                %{"name" => "firstValue", "type" => "uint256"},
                %{"name" => "secondValue", "type" => "address"}
              ]
            }
          ]
        }
      ]

      contents = generate(tmp, "ConstructorOnly", "0x6080", abi)

      assert contents =~ "def encode_constructor(_config = %{first_value: first_value, second_value: second_value})"
      assert contents =~ "bytecode() <> ABI.encode(\"((uint256,address))\""
      assert contents =~ "config = %{first_value: _first_value, second_value: _second_value}"
      assert contents =~ "def prepare_constructor("
      assert contents =~ "def execute_constructor("
    end

    test "event and error selectors emit dedicated decoders and generic dispatchers", %{tmp: tmp} do
      abi = [
        %{
          "type" => "event",
          "name" => "LogThing",
          "inputs" => [%{"name" => "value", "type" => "uint256", "indexed" => false}]
        },
        %{
          "type" => "error",
          "name" => "BadThing",
          "inputs" => [%{"name" => "reason", "type" => "uint256"}]
        }
      ]

      contents = generate(tmp, "EventsAndErrors", :absent, abi)

      assert contents =~ "def log_thing_event_selector"
      assert contents =~ "def encode_log_thing_event(value)"
      assert contents =~ "def decode_log_thing_event(topics, data) when is_list(topics)"
      assert contents =~ "def decode_event(\n        [\n          <<"
      assert contents =~ "def bad_thing_selector"
      assert contents =~ "def encode_bad_thing(reason)"
      assert contents =~ "def decode_bad_thing_error(<<"
      assert contents =~ "def decode_error(<<"

      # The error decoder decodes the error's *input* params, so its return spec
      # must reflect them (`Stumble`-style errors carry inputs, never returns).
      # Regression guard: keying the spec off `selector.returns` emitted `:: []`.
      assert contents =~ "@spec decode_bad_thing_error(binary()) :: [non_neg_integer()]"
    end

    test "duplicate function names receive signature suffixes", %{tmp: tmp} do
      abi = [
        %{
          "type" => "function",
          "name" => "dupe",
          "inputs" => [%{"name" => "value", "type" => "uint256"}],
          "outputs" => [],
          "stateMutability" => "view"
        },
        %{
          "type" => "function",
          "name" => "dupe",
          "inputs" => [%{"name" => "who", "type" => "address"}],
          "outputs" => [],
          "stateMutability" => "view"
        }
      ]

      contents = generate(tmp, "DuplicateNames", :absent, abi)

      assert contents =~ "def dupe_selector"
      assert contents =~ "def dupe_22222abd_selector"
    end

    test "contract name falls back to AST absolute path", %{tmp: tmp} do
      abi = pure_function_abi()
      artifact_path = write_artifact(tmp, "IgnoredName", "0x6080", abi, metadata: false)

      artifact_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.put("ast", %{"sourceUnit" => 1, "absolutePath" => "/tmp/AstNamed.sol"})
      |> Jason.encode!()
      |> then(&File.write!(artifact_path, &1))

      out_dir = Path.join(tmp, "ast-out")
      File.mkdir_p!(out_dir)

      Gen.run(["--prefix", "gen_test", "--out", out_dir, artifact_path])

      assert File.exists?(Path.join([out_dir, "gen_test", "ast_named.ex"]))
    end
  end

  describe "synthetic ABI generation" do
    test "emits selectors, fallback helpers, and catch-all decoders", %{tmp: tmp} do
      artifact =
        "Synthetic"
        |> solidity_artifact(synthetic_abi(), metadata_json?: true)
        |> put_bytecodes("0x60806040", "0x60806041")

      module =
        tmp
        |> generate_artifact("Synthetic", artifact)
        |> generated_module()

      assert module.contract_name() == "Synthetic"
      assert module.encode_fallback(<<1, 2, 3>>) == <<1, 2, 3>>
      assert module.encode_receive(<<4, 5>>) == <<4, 5>>
      assert is_binary(module.bytecode())
      assert is_binary(module.deployed_bytecode())

      assert %ABI.FunctionSelector{function: "noArgs"} = module.no_args_selector()
      assert %ABI.FunctionSelector{function: "blankName"} = module.blank_name_selector()
      assert %ABI.FunctionSelector{function: "setPair"} = module.set_pair_selector()
      assert %ABI.FunctionSelector{function: "CustomError"} = module.custom_error_selector()
      assert %ABI.FunctionSelector{function: "Pinged"} = module.pinged_event_selector()

      assert module.decode_call(<<0, 0, 0, 0>>) == :not_found
      assert module.decode_error(<<0, 0, 0, 0>>) == :not_found
      assert module.decode_event([<<0::256>>], <<>>) == :not_found
    end

    test "uses AST contract-name fallback when metadata has no compilation target", %{tmp: tmp} do
      contents = generate_artifact(tmp, "AstNamed", ast_artifact("AstNamed", pure_function_abi()))

      assert contents =~ "defmodule GenTest.AstNamed do"
      assert contents =~ ~s("AstNamed")
    end

    test "converts ABI-only JSON into a solidity artifact wrapper", %{tmp: tmp} do
      contents = generate_abi_file(tmp, "AbiOnly", pure_function_abi())

      assert contents =~ "defmodule GenTest.AbiOnly do"
      assert contents =~ ~s("AbiOnly")
      assert contents =~ "def encode_ping"
    end
  end

  describe "bytecode shape coverage" do
    test "init bytecode without deployed bytecode emits no exec_vm helpers", %{tmp: tmp} do
      artifact =
        "InitOnly"
        |> solidity_artifact(pure_function_abi())
        |> put_bytecodes("0x60806040", :absent)

      contents = generate_artifact(tmp, "InitOnly", artifact)

      assert contents =~ "def bytecode"
      refute contents =~ "def exec_vm_ping"
      refute contents =~ "deployed_bytecode()"
      refute contents =~ "def deployed_bytecode"

      module = generated_module(contents)

      assert function_exported?(module, :encode_ping, 1)
      refute function_exported?(module, :exec_vm_ping, 1)
    end

    test "deployed bytecode without init bytecode emits exec_vm helpers", %{tmp: tmp} do
      artifact =
        "DeployedOnly"
        |> solidity_artifact(pure_function_abi())
        |> put_bytecodes(:absent, "0x60806041")

      contents = generate_artifact(tmp, "DeployedOnly", artifact)

      refute contents =~ "def bytecode"
      assert contents =~ "def exec_vm_ping"
      assert contents =~ "def deployed_bytecode"

      module = generated_module(contents)

      assert function_exported?(module, :exec_vm_ping, 1)
      assert function_exported?(module, :deployed_bytecode, 0)
      refute function_exported?(module, :bytecode, 0)
    end

    # ABI return-field names a function can return — top-level and nested tuple
    # components, in camelCase to exercise Macro.underscore/1.
    defp named_return_abi do
      [
        %{
          "type" => "function",
          "name" => "snapshot",
          "inputs" => [],
          "outputs" => [
            %{"name" => "blockNumber", "type" => "uint256", "internalType" => "uint256"},
            %{
              "name" => "feeData",
              "type" => "tuple",
              "internalType" => "struct Fee",
              "components" => [
                %{"name" => "baseFee", "type" => "uint256", "internalType" => "uint256"},
                %{"name" => "maxTip", "type" => "uint256", "internalType" => "uint256"}
              ]
            }
          ],
          "stateMutability" => "pure"
        }
      ]
    end

    test "exec_vm contracts intern the bounded ABI field-atom set at compile time, not via String.to_atom",
         %{tmp: tmp} do
      artifact =
        "NamedReturns"
        |> solidity_artifact(named_return_abi())
        |> put_bytecodes(:absent, "0x60806041")

      contents = generate_artifact(tmp, "NamedReturns", artifact)

      # Field names (incl. nested tuple components) are collected at generation
      # time, underscored, deduped/sorted, and emitted as a compile-time literal
      # the BEAM interns at module load — so ABI.decode(decode_structs: true) can
      # resolve them via String.to_existing_atom/1.
      assert contents =~ "@decode_field_atoms [:base_fee, :block_number, :fee_data, :max_tip]"
      assert contents =~ "defp preintern_return_atoms!"

      # The previous runtime walk shipped an unsafe String.to_atom/1 into every
      # generated contract; the compile-time form must not.
      refute contents =~ "String.to_atom"

      # And it still compiles — the literal interning is valid module source.
      module = generated_module(contents)
      assert function_exported?(module, :exec_vm_snapshot, 1)
    end
  end

  describe "underscore-collision dedup" do
    # getValue + get_value have different selectors and downcase differently
    # ("getvalue" vs "get_value"), but both Macro.underscore to "get_value".
    # The dedup must key on Macro.underscore/1 (what the generated identifiers
    # use), or the second function emits a shadowed encode_get_value/1 clause
    # that is silently unreachable.
    defp colliding_abi do
      for name <- ["getValue", "get_value"] do
        %{
          "type" => "function",
          "name" => name,
          "inputs" => [%{"name" => "x", "type" => "uint256", "internalType" => "uint256"}],
          "outputs" => [%{"name" => "", "type" => "uint256", "internalType" => "uint256"}],
          "stateMutability" => "pure"
        }
      end
    end

    test "names colliding only under Macro.underscore are renamed, not shadowed", %{tmp: tmp} do
      contents = generate_abi_file(tmp, "Collision", colliding_abi())

      # First keeps the clean identifier; the second is suffixed with its
      # 4-byte signature rather than colliding on encode_get_value/1.
      assert contents =~ "def encode_get_value("
      assert contents =~ "def encode_get_value_"

      module = generated_module(contents)

      encoders =
        for {name, 1} <- module.__info__(:functions),
            String.starts_with?(Atom.to_string(name), "encode_get_value"),
            do: name

      # Two distinct encoders survive — pre-fix the shadowed clause collapses
      # these into a single encode_get_value/1.
      assert [_, _] = encoders

      # Behavioral proof: each encoder emits its own selector, so neither is
      # an unreachable duplicate of the other.
      calldatas = Enum.map(encoders, &apply(module, &1, [1]))
      assert calldatas == Enum.uniq(calldatas)
    end
  end

  describe "malformed ABI items are warned-and-skipped, not crashed, by the narrowed rescues" do
    # accumulate_named_abi/2, get_encode_call/4, and selector_return_field_atoms/1
    # each wrap a call to ABI.FunctionSelector.parse_specification_item/1 in a
    # try/rescue over @parse_specification_errors. Direct probing of that
    # dependency call (hieroglyph) found these exception types reachable from
    # malformed-but-plausible solc ABI-JSON input: ArgumentError (an
    # accepted-by-grammar-but-unimplemented type, e.g. fixed128x18),
    # FunctionClauseError (an unrecognized/missing/non-string "type", at the item
    # or input level), MatchError (an inner type string the lexer can't tokenize
    # at all), and Protocol.UndefinedError ("inputs"/"outputs" present but JSON
    # null — parse_specification_item/1's `Map.get(item, "inputs", [])` default
    # only applies when the key is ABSENT, so nil reaches Enum.map/2). The list is
    # evidence-based, not proven exhaustive: a newly-reachable exception type must
    # be added to @parse_specification_errors with a case here. Each case combines
    # a well-formed struct-returning function (to force the
    # collect_return_field_atoms/selector_return_field_atoms path, which only
    # runs when the generated module uses preintern_return_atoms!) with one
    # malformed sibling function, so a single generation run exercises all three
    # rescue sites at once.

    defp abi_with_malformed_sibling(malformed_item) do
      named_return_abi() ++ [malformed_item]
    end

    defp generate_with_malformed_sibling(tmp, name, malformed_item) do
      artifact =
        name
        |> solidity_artifact(abi_with_malformed_sibling(malformed_item))
        |> put_bytecodes(:absent, "0x60806041")

      with_log(fn -> generate_artifact(tmp, name, artifact) end)
    end

    test "unsupported fixed-point type (ArgumentError) is skipped, not raised", %{tmp: tmp} do
      malformed = %{
        "type" => "function",
        "name" => "brokenFixed",
        "inputs" => [%{"name" => "x", "type" => "fixed128x18", "internalType" => "fixed128x18"}],
        "outputs" => [],
        "stateMutability" => "pure"
      }

      {contents, log} = generate_with_malformed_sibling(tmp, "MalformedArgError", malformed)

      assert log =~ "Ignoring"
      refute contents =~ "broken_fixed"
      assert contents =~ "def exec_vm_snapshot"
      assert contents =~ "defp preintern_return_atoms!"
    end

    test "unrecognized top-level ABI item type (FunctionClauseError) is skipped, not raised", %{tmp: tmp} do
      malformed = %{
        "type" => "weird_type_here",
        "name" => "brokenType",
        "inputs" => [],
        "outputs" => []
      }

      {contents, log} = generate_with_malformed_sibling(tmp, "MalformedFunctionClauseError", malformed)

      assert log =~ "Ignoring"
      refute contents =~ "broken_type"
      assert contents =~ "def exec_vm_snapshot"
      assert contents =~ "defp preintern_return_atoms!"
    end

    test "unlexable inner type string (MatchError) is skipped, not raised", %{tmp: tmp} do
      malformed = %{
        "type" => "function",
        "name" => "brokenMatch",
        "inputs" => [%{"name" => "x", "type" => "not_a_real_type!!", "internalType" => "not_a_real_type!!"}],
        "outputs" => [],
        "stateMutability" => "pure"
      }

      {contents, log} = generate_with_malformed_sibling(tmp, "MalformedMatchError", malformed)

      assert log =~ "Ignoring"
      refute contents =~ "broken_match"
      assert contents =~ "def exec_vm_snapshot"
      assert contents =~ "defp preintern_return_atoms!"
    end

    test "null inputs/outputs (Protocol.UndefinedError) is skipped, not raised", %{tmp: tmp} do
      # `Map.get(item, "inputs", [])` inside parse_specification_item/1 returns the
      # JSON null, not the default — the default only fires on an ABSENT key — so
      # Enum.map/2 is handed nil and raises Protocol.UndefinedError.
      malformed = %{
        "type" => "function",
        "name" => "brokenNull",
        "inputs" => nil,
        "outputs" => nil,
        "stateMutability" => "pure"
      }

      {contents, log} = generate_with_malformed_sibling(tmp, "MalformedProtocolError", malformed)

      assert log =~ "Ignoring due to failed parse"
      refute contents =~ "broken_null"
      assert contents =~ "def exec_vm_snapshot"
      assert contents =~ "defp preintern_return_atoms!"
    end
  end

  describe "error paths" do
    test "invalid JSON shape raises a generator-specific file error", %{tmp: tmp} do
      path = Path.join(tmp, "Invalid.json")
      File.write!(path, Jason.encode!(%{"not_abi" => true}))

      assert_raise Gen.InvalidFileError, ~r/Invalid Solidity output or ABI/, fn ->
        generate_file(tmp, "Invalid", path)
      end
    end

    test "missing CLI arguments raise usage", %{tmp: _tmp} do
      assert_raise RuntimeError, ~r/usage: mix cartouche\.gen/, fn ->
        Gen.run([])
      end
    end
  end
end
