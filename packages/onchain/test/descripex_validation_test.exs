defmodule Onchain.DescripexValidationTest do
  use ExUnit.Case, async: false

  describe "Onchain.Configuration.__descripex_modules__/0" do
    test "registers transaction modules for Phase 12 discovery" do
      assert Onchain.Transaction in Onchain.Configuration.__descripex_modules__()
      assert Onchain.Transaction.V1 in Onchain.Configuration.__descripex_modules__()
      assert Onchain.Transaction.V2 in Onchain.Configuration.__descripex_modules__()
    end

    test "every public function in a registered module carries descripex :hints metadata" do
      for module <- Onchain.Configuration.__descripex_modules__() do
        case Code.fetch_docs(module) do
          {:docs_v1, _, _, _, _, _, docs} ->
            for {{:function, name, arity}, _line, _sigs, doc, meta} <- docs, doc != :hidden do
              case meta[:hints] do
                %{description: description} when is_binary(description) and description != "" ->
                  :ok

                _ ->
                  flunk("""
                  #{inspect(module)}.#{name}/#{arity} is missing descripex :hints metadata.

                  Annotate the function with an `api(...)` block (see `agent-economy.md`),
                  or hide it from the public surface with `@doc false`.
                  """)
              end
            end

          {:error, reason} ->
            flunk("""
            Code.fetch_docs(#{inspect(module)}) returned {:error, #{inspect(reason)}}.

            The module is registered in Onchain.Configuration.__descripex_modules__/0 but appears
            uncompiled or stripped of doc chunks. Confirm it compiles cleanly and
            is not built with strip_beams: true / docs disabled.
            """)
        end
      end
    end

    test "every @doc hints: block is attached to the correctly-named function (no api() misattachment)" do
      # Descripex 0.6's `api()` macro physically binds `@doc hints:` to the next def
      # (deps/descripex/lib/descripex.ex:64, 89-93, 433-441). A stray `api()` block above
      # an unrelated function silently leaks hints meant for a different function — the
      # description-presence pass above still passes because the leaked hints are non-empty.
      #
      # This pass cross-checks `Code.fetch_docs/1` hints against `Module.__api__/0` (descripex's
      # canonical declaration introspection). Every function carrying `meta[:hints]` MUST have at
      # least one matching `__api__()` entry for its name, and the function's hints must equal one
      # of those entries' hints. Same-name multi-decls (e.g. two `api(:new, ...)` blocks for
      # different arities) are tracked as a list, NOT collapsed — so a misplaced block above a
      # function whose name has no api(...) declaration is detected even when other declarations
      # exist for the leaked-from name.
      for module <- Onchain.Configuration.__descripex_modules__(),
          Code.ensure_loaded?(module),
          function_exported?(module, :__api__, 0) do
        case Code.fetch_docs(module) do
          {:docs_v1, _, _, _, _, _, docs} ->
            api_hints_by_name = Enum.group_by(module.__api__(), & &1.name, & &1.hints)

            for {{:function, name, arity}, _line, _sigs, doc, meta} <- docs,
                doc != :hidden,
                is_map(meta[:hints]) do
              api_hints_list = Map.get(api_hints_by_name, name, [])

              assert api_hints_list != [], """
              #{inspect(module)}.#{name}/#{arity} has @doc hints metadata but no api(:#{name}, ...) declaration exists in __api__/0.

              This indicates an api(...) block was placed above the wrong def. Descripex physically attaches
              `@doc hints:` to the next def regardless of name, so a misplaced api() block leaks hints onto
              an unrelated function. Move the api() block immediately above its matching def, or hide the
              unrelated function with `@doc false`.
              """

              # Compare modulo descripex's runtime spec-enrichment: since descripex
              # 0.8/0.9, `__api__/0` fills `params/opts.<name>.schema` (and returns.schema)
              # from `@spec` at runtime, but the compile-time BEAM doc chunk
              # (`meta[:hints]`) is NOT enriched — a module can't read its own specs at
              # `__before_compile__`. So a param with a spec-derived schema legitimately
              # diverges between the two surfaces; that is enrichment, not misattachment.
              # Strip the injected `:schema` from both sides so this test keeps detecting
              # genuine api()-misattachment (its purpose) without false-positiving on the
              # asymmetry. Tracked in descripex roadmap Task 24 (reconcile or document).
              meta_hints = drop_runtime_schema(meta.hints)
              api_hints_list_normalized = Enum.map(api_hints_list, &drop_runtime_schema/1)

              assert meta_hints in api_hints_list_normalized, """
              #{inspect(module)}.#{name}/#{arity} hints don't match any api(:#{name}, ...) declaration.

              Function meta[:hints] (schema-normalized): #{inspect(meta_hints)}
              __api__/0 hints for :#{name} (#{length(api_hints_list)} declaration(s), schema-normalized): #{inspect(api_hints_list_normalized)}

              Function-level hints must equal one of the declared api(:#{name}, ...) hints (ignoring descripex's
              runtime-injected spec `schema` keys) — descripex's propagate_hints_to_all_arities injects the
              last-declared hints onto every arity. Drift here means the @doc hints: attribute was consumed by
              a different def before propagation could inject the canonical hints, the fingerprint of a
              misattached api() block.
              """
            end

          {:error, reason} ->
            flunk("""
            Code.fetch_docs(#{inspect(module)}) returned {:error, #{inspect(reason)}}.

            The module is registered in Onchain.Configuration.__descripex_modules__/0 but appears
            uncompiled or stripped of doc chunks. Confirm it compiles cleanly and
            is not built with strip_beams: true / docs disabled.
            """)
        end
      end
    end

    test "returns a list (initially empty until Phase 12 annotation tasks register modules)" do
      assert is_list(Onchain.Configuration.__descripex_modules__())
    end

    test "Cartouche discovery functions carry descripex hints" do
      {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(Onchain.Configuration)

      for arity <- 0..2 do
        assert {{:function, :describe, ^arity}, _, _, _, %{hints: %{description: description}}} =
                 Enum.find(docs, fn
                   {{:function, :describe, doc_arity}, _, _, _, _} -> doc_arity == arity
                   _ -> false
                 end)

        assert description =~ "registered API surface"
      end
    end

    test "Cartouche contract address helper handles binary and configured atom inputs" do
      address = "0x0000000000000000000000000000000000000001"
      previous_contracts = Application.get_env(:cartouche, :contracts)
      Application.put_env(:cartouche, :contracts, Keyword.put(previous_contracts || [], :test_descripex, address))

      on_exit(fn ->
        case previous_contracts do
          nil -> Application.delete_env(:cartouche, :contracts)
          contracts -> Application.put_env(:cartouche, :contracts, contracts)
        end
      end)

      assert <<1::160>> = Onchain.Configuration.get_contract_address(address)
      assert <<1::160>> = Onchain.Configuration.get_contract_address(:test_descripex)
    end
  end

  describe "Onchain.Configuration.describe/1 transaction aliases" do
    test "exposes top-level transaction constructor helpers" do
      functions = Onchain.Configuration.describe(:transaction)

      assert Enum.any?(functions, &match?(%{name: :build_trx}, &1))
      assert Enum.any?(functions, &match?(%{name: :build_trx_v2}, &1))
    end

    test "exposes versioned transaction modules through stable nested aliases" do
      assert Enum.any?(Onchain.Configuration.describe(:transaction_v1), &match?(%{name: :encode}, &1))
      assert Enum.any?(Onchain.Configuration.describe(:transaction_v2), &match?(%{name: :encode}, &1))
    end

    test "exposes top-level transaction encode dispatcher metadata" do
      detail = Onchain.Configuration.describe(:transaction, :encode)

      assert %{
               params: %{transaction: %{kind: :value}},
               returns: %{type: :transaction_binary},
               description: description
             } = detail

      assert description =~ "dispatching on struct"
    end

    test "exposes top-level transaction encode dispatcher metadata for module input" do
      detail = Onchain.Configuration.describe(Onchain.Transaction, :encode)

      assert %{
               params: %{transaction: %{kind: :value}},
               returns: %{type: :transaction_binary},
               description: description
             } = detail

      assert description =~ "dispatching on struct"
    end

    test "keeps top-level transaction decode and build metadata aligned" do
      assert %{description: decode_description} = fetch_hints(Onchain.Transaction, :decode, 1)
      assert decode_description =~ "Decode raw Ethereum transaction bytes"

      assert %{description: build_description} = fetch_hints(Onchain.Transaction, :build_trx, 7)
      assert build_description =~ "Build a legacy transaction"
    end
  end

  # Strip descripex's runtime-injected `:schema` keys (params/opts/returns) so a
  # hints map from the compile-time doc chunk compares equal to the runtime-enriched
  # `__api__/0` form. See descripex roadmap Task 24.
  defp drop_runtime_schema(hints) when is_map(hints) do
    hints
    |> drop_section_schema(:params)
    |> drop_section_schema(:opts)
    |> update_in_existing(:returns, &Map.delete(&1, :schema))
  end

  defp drop_section_schema(hints, section) do
    update_in_existing(hints, section, fn entries ->
      Map.new(entries, fn {name, detail} -> {name, Map.delete(detail, :schema)} end)
    end)
  end

  defp update_in_existing(map, key, fun) do
    case map do
      %{^key => value} -> Map.put(map, key, fun.(value))
      _ -> map
    end
  end

  defp fetch_hints(module, function, arity) do
    {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)

    docs
    |> Enum.find_value(fn
      {{:function, ^function, ^arity}, _line, _sigs, _doc, meta} -> meta[:hints]
      _ -> nil
    end)
    |> tap(fn
      nil -> flunk("#{inspect(module)}.#{function}/#{arity} is missing docs metadata")
      _ -> :ok
    end)
  end
end
