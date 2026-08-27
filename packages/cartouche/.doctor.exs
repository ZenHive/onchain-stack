%Doctor.Config{
  # Both excluded modules build AST literals via `def unquote(name)(args)` inside
  # `quote do ... end` blocks (Cartouche.Gen emits contract modules; Cartouche.RPC.DSL's
  # `defrpc` macro emits the uniform RPC wrappers). Doctor's source-level AST walker
  # counts those literals as if they were real defs of the host module (BEAM introspection
  # confirms otherwise) and does not associate the `@doc`/`@spec` attached to the enclosing
  # `defmacro`/`def unquote` — producing false-positive missing-doc/spec warnings. Excluding
  # silences the false positive; the real @moduledoc/@doc/@spec stay in source for hexdocs.
  # TODO(upstream-doctor): drop once Doctor's AST walker handles `def unquote(name)(args)`
  # inside `quote do ... end` blocks. Intentionally untracked in ROADMAP — this is an
  # upstream Doctor limitation we can't fix locally.
  ignore_modules: [Mix.Tasks.Cartouche.Gen, Cartouche.RPC.DSL],
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 100,
  min_overall_doc_coverage: 100,
  min_overall_moduledoc_coverage: 100,
  min_overall_spec_coverage: 100,
  exception_moduledoc_required: true,
  raise: false,
  reporter: Doctor.Reporters.Full,
  struct_type_spec_required: true,
  umbrella: false,
  failed: false
}
