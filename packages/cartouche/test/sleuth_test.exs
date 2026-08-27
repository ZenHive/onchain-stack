defmodule SleuthTest do
  use ExUnit.Case
  use Cartouche.Hex

  alias Cartouche.Contract.BlockNumber
  alias Cartouche.Sleuth

  # Req function plug (`fun(conn) -> conn`), running in the test process that
  # issues the `eth_call`. Returns whatever the current test stashed under
  # `:sleuth_eth_call_result` as the JSON-RPC result.
  defmodule StaticEthCallClient do
    @moduledoc false

    @spec call(Plug.Conn.t()) :: Plug.Conn.t()
    def call(conn) do
      %{"id" => id} = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()
      result = Process.get(:sleuth_eth_call_result)
      Req.Test.json(conn, %{"jsonrpc" => "2.0", "result" => result, "id" => id})
    end
  end

  defmodule MissingFunsContract do
    @moduledoc false
    # Intentionally does not define bytecode/0, encode_query/0, or query_selector/0.
    # Used to exercise the try_apply rescue clause.
  end

  doctest Sleuth

  describe "try_apply rescue" do
    test "raises descriptive error when contract module is missing :bytecode/0" do
      assert_raise RuntimeError,
                   ~r/Sleuth module .*MissingFunsContract does not define required "bytecode\/0"/,
                   fn -> Sleuth.query_by(MissingFunsContract) end
    end
  end

  # Phase A coverage push for INE-43 / ROADMAP Task 48:
  # Lock in pre-Phase-B (hot-atom) behavior of `query_by/3` and `name_keyword/1`
  # before the `String.to_atom/1` -> `String.to_existing_atom/1` swap. Phase B
  # must keep these green; only the cold-atom paths change in Phase B.
  describe "Phase A — query_by/3 hot-atom invariants" do
    test "query_by/3 with explicit known :fun resolves derived encoder/selector atoms" do
      assert {:ok, %{"x" => 2, "y" => 3}} ==
               Sleuth.query_by(BlockNumber, :query_two, [])
    end

    test "query_by/3 keyword form preserves :query default and forwards opts" do
      # `query_by/3` always routes through `query_internal` (be_obvious: false),
      # so `named_returns:` is forwarded as RPC-opt and ignored by postprocess.
      assert {:ok, %{"blockNumber" => 2}} ==
               Sleuth.query_by(BlockNumber, named_returns: true)
    end

    test "query_by/3 derived encoder/selector atoms are already in the atom table" do
      # Sanity check: every `fun` we exercise via `query_by/3` must already
      # have its derived `encode_<fun>` / `<fun>_selector` atoms in the table
      # (compile-time function defs interned them). Phase B's
      # `String.to_existing_atom/1` swap relies on this contract.
      assert :encode_query == String.to_existing_atom("encode_query")
      assert :query_selector == String.to_existing_atom("query_selector")
      assert :encode_query_two == String.to_existing_atom("encode_query_two")
      assert :query_two_selector == String.to_existing_atom("query_two_selector")
    end
  end

  describe "Phase A — name_keyword/1 hot-atom invariants" do
    test "named_returns: true atomizes existing snake_cased field names" do
      # Hot path: "blockNumber" -> :block_number (compiled at module-eval).
      assert :block_number == String.to_existing_atom("block_number")

      assert {:ok, [block_number: 2]} ==
               Sleuth.query_v2(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query(),
                 BlockNumber.query_selector(),
                 named_returns: true
               )
    end

    test "name_keyword collapses nil/empty names to :__unnamed__ via to_named_pair" do
      # Exercises the `name_keyword(nil)` and `name_keyword("")` clauses
      # without minting any atom.
      selector = %ABI.FunctionSelector{
        types: [%{type: {:uint, 256}}, %{type: {:uint, 256}}],
        returns: [%{name: nil, type: {:uint, 256}}, %{name: "", type: {:uint, 256}}]
      }

      set_sleuth_result(ABI.TypeEncoder.encode([7, 8], selector))

      assert {:ok, [__unnamed__: 7, __unnamed__: 8]} =
               Sleuth.query_v2(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query(),
                 %ABI.FunctionSelector{returns: selector.returns},
                 req_options: [plug: &StaticEthCallClient.call/1],
                 named_returns: true
               )
    end
  end

  describe "Phase A — postprocess fallback branches (coverage)" do
    test "query/4 returns [] when selector returns are empty" do
      selector = %ABI.FunctionSelector{returns: []}
      set_sleuth_result(<<>>)

      assert {:ok, []} ==
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query(),
                 selector,
                 req_options: [plug: &StaticEthCallClient.call/1]
               )
    end

    test "query/4 collapses a single nil-named return to the scalar value" do
      # Exercises the `[{nil, result}] -> result` branch in be_obvious: false.
      selector = %ABI.FunctionSelector{
        types: [%{type: {:uint, 256}}],
        returns: [%{name: nil, type: {:uint, 256}}]
      }

      set_sleuth_result(ABI.TypeEncoder.encode([7], selector))

      assert {:ok, 7} ==
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query(),
                 %ABI.FunctionSelector{returns: selector.returns},
                 req_options: [plug: &StaticEthCallClient.call/1]
               )
    end

    test "query_v2/3 (no opts) is a valid arity exposed by the default" do
      # Pins the `def query_v2(_, _, _, opts \\ [])` 3-arg variant.
      assert {:ok, [2]} ==
               Sleuth.query_v2(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query(),
                 BlockNumber.query_selector()
               )
    end

    test "preintern_decode_struct_atoms tolerates non-list selector.returns" do
      # selector.returns = nil -> preintern_decode_struct_atoms fall-through.
      # Decode then fails (not a list), surfaces structured error.
      selector = %ABI.FunctionSelector{returns: nil}
      set_sleuth_result(<<>>)

      assert {:error, "error decoding: " <> _} =
               Sleuth.query_v2(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query(),
                 selector,
                 req_options: [plug: &StaticEthCallClient.call/1],
                 decode_structs: true
               )
    end
  end

  describe "Phase B — query_by/3 cold-atom rejection" do
    test "rejects a :fun whose derived encode_<fun> atom does not exist" do
      # The atom `:encode_phase_b_cold_fun_unique_<n>` must not exist in the
      # BEAM. After the swap, `String.to_existing_atom/1` raises
      # `ArgumentError`, which `query_by/3` catches and reraises as the same
      # RuntimeError shape `try_apply/3` produces for "function does not
      # exist on module" — keeping the public-facing error uniform.
      suffix = System.unique_integer([:positive])
      cold_fun_name = "phase_b_cold_fun_unique_#{suffix}"
      cold_fun = String.to_atom(cold_fun_name)
      derived_encoder = "encode_" <> cold_fun_name

      refute existing_atom?(derived_encoder)

      assert_raise RuntimeError,
                   ~r/Sleuth module does not define required "#{derived_encoder}\/0" function/,
                   fn -> Sleuth.query_by(BlockNumber, cold_fun, []) end

      # Critical: the swap must NOT have minted the cold derived atom.
      refute existing_atom?(derived_encoder)
    end

    test "rejects a :fun whose derived <fun>_selector atom does not exist" do
      # Force the encode_ atom to exist (so the first lookup succeeds), then
      # leave the _selector atom cold so we hit the second derivation.
      suffix = System.unique_integer([:positive])
      cold_fun_name = "phase_b_selector_cold_#{suffix}"
      cold_fun = String.to_atom(cold_fun_name)
      _ = String.to_atom("encode_" <> cold_fun_name)
      derived_selector = cold_fun_name <> "_selector"

      refute existing_atom?(derived_selector)

      # The encoder lookup hits `try_apply` first (function not defined on
      # BlockNumber even though atom exists), so it raises with the
      # try_apply message. The point of this test is the same: no atom
      # gets minted by the lookup itself.
      assert_raise RuntimeError, fn -> Sleuth.query_by(BlockNumber, cold_fun, []) end
      refute existing_atom?(derived_selector)
    end

    test "hot-atom path remains unchanged: known :fun resolves and decodes" do
      assert {:ok, 2} ==
               Sleuth.query_by(BlockNumber, :query_three, [])
    end
  end

  describe "Phase B — name_keyword/1 cold-atom rejection via query_v2" do
    test "query_v2/4 with named_returns: true rejects cold runtime return-field name" do
      # The selector field name -> snake_cased atom that has never been
      # minted anywhere must trigger the INE-17-style structured error
      # (not raise ArgumentError to the caller, not silently mint).
      suffix = System.unique_integer([:positive])
      cold_field_name = "coldNamedReturnField#{suffix}"
      cold_field_atom_name = Macro.underscore(cold_field_name)

      refute existing_atom?(cold_field_atom_name)

      selector = %ABI.FunctionSelector{
        types: [%{type: {:uint, 256}}],
        returns: [%{name: cold_field_name, type: {:uint, 256}}]
      }

      set_sleuth_result(ABI.TypeEncoder.encode([7], selector))

      assert {:error, error} =
               Sleuth.query_v2(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query(),
                 selector,
                 req_options: [plug: &StaticEthCallClient.call/1],
                 named_returns: true,
                 # decode_structs: false isolates the named_returns path
                 # from the existing INE-17 decode_structs preintern.
                 decode_structs: false
               )

      assert error =~ "pre-existing return-field atom"
      assert error =~ cold_field_atom_name
      refute existing_atom?(cold_field_atom_name)
    end

    test "query_v2/4 with named_returns: true accepts hot return-field name" do
      # Pre-intern the field atom so the symmetric happy-path works.
      _ = String.to_atom("hot_named_return_field")

      selector = %ABI.FunctionSelector{
        types: [%{type: {:uint, 256}}],
        returns: [%{name: "hotNamedReturnField", type: {:uint, 256}}]
      }

      set_sleuth_result(ABI.TypeEncoder.encode([42], selector))

      assert {:ok, [hot_named_return_field: 42]} =
               Sleuth.query_v2(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query(),
                 selector,
                 req_options: [plug: &StaticEthCallClient.call/1],
                 named_returns: true,
                 decode_structs: false
               )
    end
  end

  describe "generated Sleuth call shape" do
    test "build_trx_query/3 returns an eth_call struct instead of a partial V2 transaction" do
      call = Cartouche.Contract.Sleuth.build_trx_query(<<1::160>>, <<2, 3>>, <<4, 5>>)

      assert %Cartouche.Transaction.Call{destination: <<1::160>>, data: data} = call
      assert data == Cartouche.Contract.Sleuth.encode_query(<<2, 3>>, <<4, 5>>)
    end
  end

  describe "BlockNumber" do
    test "query_by/2 keyword form defaults to :query" do
      assert {:ok, %{"blockNumber" => 2}} == Sleuth.query_by(BlockNumber, named_returns: true)
    end

    test "query()" do
      assert {:ok, %{"blockNumber" => 2}} ==
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query(),
                 BlockNumber.query_selector()
               )

      v2_case = fn opts ->
        Sleuth.query_v2(
          BlockNumber.bytecode(),
          BlockNumber.encode_query(),
          BlockNumber.query_selector(),
          opts
        )
      end

      assert {:ok, [2]} == v2_case.([])
      assert {:ok, [block_number: 2]} == v2_case.(named_returns: true)
    end

    test "query() failure with trace" do
      assert {:error,
              %{
                code: 3,
                message: "execution reverted",
                trace: _
              }} =
               Sleuth.query(
                 ~h[],
                 ~h[0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF00000001],
                 BlockNumber.query_selector(),
                 trace_reverts: true
               )
    end

    test "query() failure with debug trace" do
      assert {:error,
              %{
                code: 3,
                message: "execution reverted",
                trace: _
              }} =
               Sleuth.query(
                 ~h[],
                 ~h[0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF00000001],
                 BlockNumber.query_selector(),
                 trace_reverts: true,
                 debug_trace: true
               )
    end

    test "query_by() via mod/fun" do
      assert {:ok, %{"blockNumber" => 2}} ==
               Sleuth.query_by(
                 BlockNumber,
                 :query
               )
    end

    test "query_by() via mod" do
      assert {:ok, %{"blockNumber" => 2}} ==
               Sleuth.query_by(BlockNumber)
    end

    test "queryTwo()" do
      assert {:ok, %{"x" => 2, "y" => 3}} ==
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query_two(),
                 BlockNumber.query_two_selector()
               )

      v2_case = fn opts ->
        Sleuth.query_v2(
          BlockNumber.bytecode(),
          BlockNumber.encode_query_two(),
          BlockNumber.query_two_selector(),
          opts
        )
      end

      assert {:ok, [2, 3]} == v2_case.([])
      assert {:ok, [x: 2, y: 3]} == v2_case.(named_returns: true)
    end

    test "queryTwo() - annotated" do
      assert {:ok, %{"x" => {{:uint, 256}, 2}, "y" => {{:uint, 256}, 3}}} ==
               Sleuth.query_annotated(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query_two(),
                 BlockNumber.query_two_selector()
               )

      v2_case = fn opts ->
        Sleuth.query_v2(
          BlockNumber.bytecode(),
          BlockNumber.encode_query_two(),
          BlockNumber.query_two_selector(),
          opts
        )
      end

      assert {:ok, [{{:uint, 256}, 2}, {{:uint, 256}, 3}]} == v2_case.(annotated: true)

      assert {:ok, [x: {{:uint, 256}, 2}, y: {{:uint, 256}, 3}]} ==
               v2_case.(annotated: true, named_returns: true)
    end

    test "queryThree()" do
      assert {:ok, 2} ==
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query_three(),
                 BlockNumber.query_three_selector()
               )

      v2_case = fn opts ->
        Sleuth.query_v2(
          BlockNumber.bytecode(),
          BlockNumber.encode_query_three(),
          BlockNumber.query_three_selector(),
          opts
        )
      end

      assert {:ok, [2]} == v2_case.([])
      assert {:ok, [__unnamed__: 2]} == v2_case.(named_returns: true)
    end

    test "queryThree() - annotated" do
      assert {:ok, {{:uint, 256}, 2}} ==
               Sleuth.query_annotated(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query_three(),
                 BlockNumber.query_three_selector()
               )

      assert {:ok, [{{:uint, 256}, 2}]} ==
               Sleuth.query_v2(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query_three(),
                 BlockNumber.query_three_selector(),
                 annotated: true
               )
    end

    test "queryFour()" do
      assert {:ok, %{"var0" => ~h[0x010203], "var1" => <<1::160>>}} ==
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query_four(),
                 BlockNumber.query_four_selector()
               )

      v2_case = fn opts ->
        Sleuth.query_v2(
          BlockNumber.bytecode(),
          BlockNumber.encode_query_four(),
          BlockNumber.query_four_selector(),
          opts
        )
      end

      assert {:ok, [~h[0x010203], <<1::160>>]} == v2_case.([])

      assert {:ok, [__unnamed__: ~h[0x010203], __unnamed__: <<1::160>>]} ==
               v2_case.(named_returns: true)
    end

    test "queryFour() - no decode binaries" do
      assert {:ok, %{"var0" => "0x010203", "var1" => "0x0000000000000000000000000000000000000001"}} ==
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query_four(),
                 BlockNumber.query_four_selector(),
                 decode_binaries: false
               )

      v2_case = fn opts ->
        Sleuth.query_v2(
          BlockNumber.bytecode(),
          BlockNumber.encode_query_four(),
          BlockNumber.query_four_selector(),
          opts
        )
      end

      assert {:ok, ["0x010203", "0x0000000000000000000000000000000000000001"]} ==
               v2_case.(decode_binaries: false)

      assert {:ok, [__unnamed__: "0x010203", __unnamed__: "0x0000000000000000000000000000000000000001"]} ==
               v2_case.(decode_binaries: false, named_returns: true)
    end

    test "queryCool()" do
      assert {:ok,
              %{
                "cool" => %{
                  "fun" => %{"cat" => "meow"},
                  "x" => "hi",
                  "ys" => [1, 2, 3]
                }
              }} ==
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query_cool(),
                 BlockNumber.query_cool_selector()
               )

      v2_case = fn opts ->
        Sleuth.query_v2(
          BlockNumber.bytecode(),
          BlockNumber.encode_query_cool(),
          BlockNumber.query_cool_selector(),
          opts
        )
      end

      assert {:ok,
              [
                %{
                  fun: %{cat: "meow"},
                  x: "hi",
                  ys: [1, 2, 3]
                }
              ]} == v2_case.([])

      assert {:ok,
              [
                %{
                  "fun" => %{"cat" => "meow"},
                  "x" => "hi",
                  "ys" => [1, 2, 3]
                }
              ]} == v2_case.(decode_structs: false)

      assert {:ok,
              [
                cool: %{
                  fun: %{cat: "meow"},
                  x: "hi",
                  ys: [1, 2, 3]
                }
              ]} == v2_case.(named_returns: true)

      assert {:ok,
              [
                cool: %{
                  "fun" => %{"cat" => "meow"},
                  "x" => "hi",
                  "ys" => [1, 2, 3]
                }
              ]} == v2_case.(named_returns: true, decode_structs: false)
    end

    test "queryCool() - annotated" do
      assert {:ok,
              %{
                "cool" => %{
                  "fun" => %{"cat" => {:string, "meow"}},
                  "x" => {:string, "hi"},
                  "ys" => [{{:uint, 256}, 1}, {{:uint, 256}, 2}, {{:uint, 256}, 3}]
                }
              }} ==
               Sleuth.query_annotated(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query_cool(),
                 BlockNumber.query_cool_selector()
               )

      v2_case = fn opts ->
        Sleuth.query_v2(
          BlockNumber.bytecode(),
          BlockNumber.encode_query_cool(),
          BlockNumber.query_cool_selector(),
          opts
        )
      end

      assert {:ok,
              [
                %{
                  fun: %{cat: {:string, "meow"}},
                  x: {:string, "hi"},
                  ys: [{{:uint, 256}, 1}, {{:uint, 256}, 2}, {{:uint, 256}, 3}]
                }
              ]} == v2_case.(annotated: true)

      assert {:ok,
              [
                %{
                  "fun" => %{"cat" => {:string, "meow"}},
                  "x" => {:string, "hi"},
                  "ys" => [{{:uint, 256}, 1}, {{:uint, 256}, 2}, {{:uint, 256}, 3}]
                }
              ]} == v2_case.(annotated: true, decode_structs: false)

      assert {:ok,
              [
                cool: %{
                  "fun" => %{"cat" => {:string, "meow"}},
                  "x" => {:string, "hi"},
                  "ys" => [{{:uint, 256}, 1}, {{:uint, 256}, 2}, {{:uint, 256}, 3}]
                }
              ]} == v2_case.(annotated: true, decode_structs: false, named_returns: true)
    end
  end

  describe "decode failures and return postprocessing" do
    test "query_v2/4 rejects cold runtime return-field atoms before struct decode" do
      suffix = System.unique_integer([:positive])
      module_name = Module.concat(Cartouche.Contract, "ColdLoadProbe#{suffix}")
      field_name = "coldLoadReturnField#{suffix}"
      field_atom_name = Macro.underscore(field_name)

      refute Code.loaded?(module_name)
      refute existing_atom?(field_atom_name)

      Code.compile_string("""
      defmodule #{inspect(module_name)} do
        def bytecode, do: <<>>
        def encode_query, do: <<>>

        def query_selector do
          %ABI.FunctionSelector{
            returns: [%{name: #{inspect(field_name)}, type: {:uint, 256}}]
          }
        end
      end
      """)

      assert Code.loaded?(module_name)
      refute existing_atom?(field_atom_name)

      selector = module_name.query_selector()
      set_sleuth_result(ABI.TypeEncoder.encode([7], %ABI.FunctionSelector{types: selector.returns}))

      assert_raise ArgumentError, ~r/requires the snake_case field atom/, fn ->
        ABI.decode(
          %ABI.FunctionSelector{types: selector.returns},
          ABI.TypeEncoder.encode([7], %ABI.FunctionSelector{types: selector.returns}),
          decode_structs: true
        )
      end

      refute existing_atom?(field_atom_name)

      assert {:error, error} =
               Sleuth.query_v2(
                 module_name.bytecode(),
                 module_name.encode_query(),
                 selector,
                 req_options: [plug: &StaticEthCallClient.call/1],
                 named_returns: true
               )

      assert error =~ "pre-existing return-field atom"
      assert error =~ field_atom_name
      refute existing_atom?(field_atom_name)
    end

    test "query_v2/4 decodes runtime selectors when field atoms already exist" do
      selector = %ABI.FunctionSelector{
        returns: [%{name: "items", type: {:uint, 256}}]
      }

      set_sleuth_result(ABI.TypeEncoder.encode([7], %ABI.FunctionSelector{types: selector.returns}))

      assert {:ok, [items: 7]} =
               Sleuth.query_v2(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query(),
                 selector,
                 req_options: [plug: &StaticEthCallClient.call/1],
                 named_returns: true
               )
    end

    test "query_v2/4 validates cold nested tuple and array return-field atoms" do
      suffix = System.unique_integer([:positive])
      nested_field_name = "coldNestedReturnField#{suffix}"
      nested_atom_name = Macro.underscore(nested_field_name)

      selector = %ABI.FunctionSelector{
        returns: [
          %{
            name: "items",
            type: {:array, {:tuple, [%{name: nested_field_name, type: {:uint, 256}}]}}
          }
        ]
      }

      refute existing_atom?(nested_atom_name)

      assert {:error, error} =
               query_static(<<>>, selector.returns, named_returns: true)

      assert error =~ "pre-existing return-field atom"
      assert error =~ nested_atom_name
      refute existing_atom?(nested_atom_name)
    end

    test "returns a decode-bytes error when the eth_call result is not ABI bytes" do
      Process.put(:sleuth_eth_call_result, "0x1234")

      assert {:error, "error decoding bytes: " <> _} =
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query(),
                 BlockNumber.query_selector(),
                 req_options: [plug: &StaticEthCallClient.call/1]
               )
    end

    test "returns a selector decode error when the inner bytes do not match returns" do
      set_sleuth_result(<<1, 2, 3>>)

      assert {:error, "error decoding: " <> _} =
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query(),
                 BlockNumber.query_selector(),
                 req_options: [plug: &StaticEthCallClient.call/1]
               )
    end

    test "postprocesses empty and unnamed returns" do
      assert {:ok, []} = query_static(<<>>, [])

      selector = %ABI.FunctionSelector{types: [%{type: {:uint, 256}}], returns: [%{name: nil, type: {:uint, 256}}]}
      assert {:ok, [7]} = query_static(ABI.TypeEncoder.encode([7], selector), selector.returns)
    end

    test "postprocesses fixed bytes and scalar values when binary decoding is disabled" do
      selector = %ABI.FunctionSelector{
        returns: [%{name: "fixed", type: {:bytes, 3}}, %{name: "n", type: {:uint, 256}}]
      }

      query_result =
        ABI.TypeEncoder.encode([{<<1, 2, 3>>, 7}], %ABI.FunctionSelector{types: [%{type: {:tuple, selector.returns}}]})

      assert {:ok, [fixed: "0x010203", n: 7]} =
               query_static(query_result, selector.returns, decode_binaries: false, named_returns: true)
    end

    test "query/4 falls back to indexed names for multiple unnamed returns" do
      selector = %ABI.FunctionSelector{
        types: [%{type: {:uint, 256}}, %{type: {:uint, 256}}],
        returns: [%{name: nil, type: {:uint, 256}}, %{name: nil, type: {:uint, 256}}]
      }

      set_sleuth_result(ABI.TypeEncoder.encode([7, 8], selector))

      assert {:ok, %{"var0" => 7, "var1" => 8}} =
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query(),
                 %ABI.FunctionSelector{returns: selector.returns},
                 req_options: [plug: &StaticEthCallClient.call/1]
               )
    end

    test "postprocesses fixed-size arrays" do
      selector = %ABI.FunctionSelector{
        types: [%{type: {:array, {:uint, 256}, 2}}],
        returns: [%{name: "items", type: {:array, {:uint, 256}, 2}}]
      }

      assert {:ok, [items: [7, 8]]} =
               query_static(ABI.TypeEncoder.encode([[7, 8]], selector), selector.returns, named_returns: true)
    end

    test "query_v2/4 preserves empty string return names when named returns are disabled" do
      selector = %ABI.FunctionSelector{
        types: [%{type: {:uint, 256}}],
        returns: [%{name: "", type: {:uint, 256}}]
      }

      assert {:ok, [7]} = query_static(ABI.TypeEncoder.encode([7], selector), selector.returns)
    end

    test "query/4 collapses an empty string single return to the scalar value" do
      selector = %ABI.FunctionSelector{
        types: [%{type: {:uint, 256}}],
        returns: [%{name: "", type: {:uint, 256}}]
      }

      set_sleuth_result(ABI.TypeEncoder.encode([7], selector))

      assert {:ok, 7} =
               Sleuth.query(
                 BlockNumber.bytecode(),
                 BlockNumber.encode_query(),
                 %ABI.FunctionSelector{returns: selector.returns},
                 req_options: [plug: &StaticEthCallClient.call/1]
               )
    end
  end

  # ---------------------------------------------------------------------------
  # Phase B+C — preintern edge cases (INE-43 / Task 48)
  # ---------------------------------------------------------------------------
  #
  # These tests cover atom-hardening paths introduced in Phase B+C that are not
  # exercised by the Phase A/B blocks above: fixed-size arrays, non-list returns
  # fall-throughs, empty/nil name pass-throughs, and error-message formatting.

  describe "Phase C — preintern_type_atoms fixed-size array cold-atom rejection" do
    test "query_v2/4 rejects cold atom inside a fixed-size array element type" do
      # {:array, type, size} -- the _size variant -- wraps a named tuple type.
      # preintern_type_atoms/1 must recurse into fixed-size arrays the same way
      # it recurses into dynamic arrays.
      suffix = System.unique_integer([:positive])
      cold_field = "coldFixedArrayField#{suffix}"
      cold_atom = Macro.underscore(cold_field)

      refute existing_atom?(cold_atom)

      # Nested: outer return is a fixed-size array of a named tuple
      selector = %ABI.FunctionSelector{
        returns: [
          %{
            name: "items",
            type: {:array, {:tuple, [%{name: cold_field, type: {:uint, 256}}]}, 2}
          }
        ]
      }

      # decode_structs: true triggers preintern_decode_struct_atoms -> preintern_type_atoms
      assert {:error, error} =
               query_static(<<>>, selector.returns, decode_structs: true)

      assert error =~ "pre-existing return-field atom"
      assert error =~ cold_atom
      # Critical: the cold atom must NOT have been minted by the lookup
      refute existing_atom?(cold_atom)
    end
  end

  describe "Phase C — preintern_named_return_atoms non-list fall-through" do
    test "query_v2/4 with non-list returns and named_returns: true surfaces a decode error, not crash" do
      # preintern_named_return_atoms/1 has a fall-through clause for non-list
      # returns (e.g. nil). When `named_returns: true`, the preintern step
      # silently passes, then `try_decode/4` fails when ABI.decode gets a
      # nil types list — the overall call must return {:error, ...}, not raise.
      selector = %ABI.FunctionSelector{returns: nil}
      set_sleuth_result(<<>>)

      result =
        Sleuth.query_v2(
          BlockNumber.bytecode(),
          BlockNumber.encode_query(),
          selector,
          req_options: [plug: &StaticEthCallClient.call/1],
          named_returns: true,
          decode_structs: false
        )

      assert {:error, _} = result
    end
  end

  describe "Phase C — preintern_name_atom empty/nil pass-through" do
    test "query_v2/4 decode_structs: true tolerates a return field with empty string name" do
      # preintern_name_atom/1 has a guard `when name != ""` —
      # empty string passes through without atom lookup.
      selector = %ABI.FunctionSelector{
        types: [%{type: {:uint, 256}}],
        returns: [%{name: "", type: {:uint, 256}}]
      }

      assert {:ok, [7]} =
               query_static(
                 ABI.TypeEncoder.encode([7], %ABI.FunctionSelector{types: selector.returns}),
                 selector.returns,
                 decode_structs: true
               )
    end

    test "query_v2/4 decode_structs: true tolerates a return field with nil name" do
      # preintern_name_atom/1 has a catch-all clause for non-binary names.
      selector = %ABI.FunctionSelector{
        types: [%{type: {:uint, 256}}],
        returns: [%{name: nil, type: {:uint, 256}}]
      }

      assert {:ok, [7]} =
               query_static(
                 ABI.TypeEncoder.encode([7], %ABI.FunctionSelector{types: selector.returns}),
                 selector.returns,
                 decode_structs: true
               )
    end
  end

  describe "Phase C — existing_function_atom/2 error message formatting" do
    test "error message for cold encoder atom includes the /0 arity suffix" do
      # existing_function_atom/2 formats `"#{name}/#{arity}"` in its reraise
      # message. The arity for all derived encoder/selector atoms is 0.
      suffix = System.unique_integer([:positive])
      cold_fun_name = "phase_c_arity_cold_#{suffix}"
      cold_fun = String.to_atom(cold_fun_name)
      derived_encoder = "encode_" <> cold_fun_name

      refute existing_atom?(derived_encoder)

      assert_raise RuntimeError,
                   ~r/does not define required "#{derived_encoder}\/0"/,
                   fn -> Sleuth.query_by(BlockNumber, cold_fun, []) end
    end
  end

  describe "Phase C — query_by/3 arity-0 default via query_by/1" do
    test "query_by/1 single-arg form resolves :query and returns correct value" do
      # Exercises the `def query_by(mod)` head that defaults fun to :query.
      # After Phase B's existing_function_atom swap, this must still work
      # because :encode_query and :query_selector were interned at compile time.
      assert {:ok, %{"blockNumber" => 2}} == Sleuth.query_by(BlockNumber)
    end
  end

  describe "Phase C — existing_atom/1 helper behaviour" do
    test "query_by/3 does not create new atoms when rejecting cold function names" do
      # Regression: verify no atom-table growth across two cold lookups
      # with different suffixes (each generates a unique cold name).
      suffix_a = System.unique_integer([:positive])
      suffix_b = System.unique_integer([:positive])
      cold_a = "phase_c_regression_a_#{suffix_a}"
      cold_b = "phase_c_regression_b_#{suffix_b}"

      refute existing_atom?("encode_" <> cold_a)
      refute existing_atom?("encode_" <> cold_b)

      assert_raise RuntimeError, fn -> Sleuth.query_by(BlockNumber, String.to_atom(cold_a), []) end
      assert_raise RuntimeError, fn -> Sleuth.query_by(BlockNumber, String.to_atom(cold_b), []) end

      refute existing_atom?("encode_" <> cold_a)
      refute existing_atom?("encode_" <> cold_b)
    end
  end

  defp query_static(query_result, returns, opts \\ []) do
    set_sleuth_result(query_result)
    selector = %ABI.FunctionSelector{returns: returns}

    Sleuth.query_v2(
      BlockNumber.bytecode(),
      BlockNumber.encode_query(),
      selector,
      Keyword.put(opts, :req_options, plug: &StaticEthCallClient.call/1)
    )
  end

  defp set_sleuth_result(query_result) do
    Process.put(:sleuth_eth_call_result, Base.encode16(ABI.encode("(bytes)", [{query_result}])))
  end

  defp existing_atom?(name) do
    _atom = String.to_existing_atom(name)
    true
  rescue
    ArgumentError -> false
  end
end
