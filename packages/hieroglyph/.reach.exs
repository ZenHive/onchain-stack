# Reach architecture/smell policy for `mix reach.check --arch --smells`.
#
# Flat single-namespace library (`ABI.*`): the facade (abi.ex) and its encode/
# decode/parse/math submodules are mutually consulted with no enforceable
# facade-vs-internal or generator-vs-output split. The one Mix task
# (lib/mix/tasks/hieroglyph.manifest.ex) depends on the runtime lib one-way,
# as any packaging task does. No `layers`/`deps`.
[
  # Pin the source set to the hand-written Elixir. By default reach analyzes
  # `:elixirc_paths` *and* `:erlc_paths`, so `src/` — the yecc/leex output of
  # ethereum_abi_{lexer,parser}.{xrl,yrl} — was in scope. Wrong on two counts:
  # a smell in generated Erlang is unfixable by definition, and reach 2.8.2
  # aborts the entire `--smells` pass on those nodes (`KeyError key :module`,
  # elixir-vibe/reach#36) because non-Elixir function meta carries no
  # `:module`. Dropping `src/` scopes the gate to code we can act on and
  # clears the crash — the CI red since 2026-08-01.
  checks: [source_paths: ["lib", "test/support"]],
  smells: [strict: true]
]
