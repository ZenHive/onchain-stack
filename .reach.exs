# Reach architecture/smell policy for `mix reach.check --arch --smells`.
#
# `:arch` starts permissive (no layer/boundary policy yet) so reach gates on
# cross-function smells only. Populate layer/boundary rules here as onchain_evm's
# module architecture solidifies (EVM execution vs Solidity parsing vs trace vs
# codegen). See the `elixir:reach` skill / hexdocs for the policy DSL.
#
# `smells.ignore.paths` scopes the smell detector to hand-written runtime code.
# Reach's `smells.ignore` accepts only `paths:`/`modules:` — no per-check
# granularity (deps/reach/lib/reach/config.ex `valid_ignore?/1`) — so this is a
# path-level exclusion. What it hides, exclusively, is INHERENT to
# metaprogramming, never a fixable defect:
#
#   * 1x "unsafe atom creation" in lib/onchain/contract/generator.ex —
#     `String.to_atom/1` CREATES the identifiers (function/variable/
#     struct-field names) of the code the generator emits at compile time;
#     `String.to_existing_atom/1` is impossible for a not-yet-defined function.
#
# `strict: true` makes this gate enforce (`--smells` is otherwise advisory —
# reach 2.8.2 config.ex ~L351). onchain_evm commits no generated output (the
# generator emits modules via macro, not files), so only the generator source
# itself is scoped — every smell in hand-written runtime code (evm.ex,
# solidity.ex, trace.ex, bang_helper.ex) and every non-inherent smell in the
# generator itself is fixed for real, not excluded.
[
  smells: [
    strict: true,
    ignore: [
      paths: [
        "lib/onchain/contract/generator.ex"
      ]
    ]
  ]
]
