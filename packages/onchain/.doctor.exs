%Doctor.Config{
  # Onchain.RPC.Codegen is a compile-time macro module: its only "functions" are
  # the `def`s emitted inside `quote` blocks. Doctor's AST walker counts those
  # quoted defs as undocumented public functions (their names are `unquote(...)`
  # expressions that can never carry @doc/@spec), so the module reports 0% doc
  # and spec coverage regardless of how it is documented. Ignore it here; the
  # module itself is documented via its moduledoc comment and @doc false macros.
  ignore_modules: [Onchain.RPC.Codegen],
  ignore_paths: [],
  min_module_doc_coverage: 40,
  min_module_spec_coverage: 0,
  min_overall_doc_coverage: 50,
  min_overall_moduledoc_coverage: 100,
  min_overall_spec_coverage: 0,
  exception_moduledoc_required: true,
  raise: false,
  reporter: Doctor.Reporters.Full,
  struct_type_spec_required: true,
  umbrella: false
}
