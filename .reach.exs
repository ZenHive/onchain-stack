# Reach architecture/smell policy for `mix reach.check --arch --smells`.
#
# `:arch` starts permissive (no layer/boundary policy yet) so reach gates on
# cross-function smells only. Populate layer/boundary rules here as onchain_evm's
# module architecture solidifies (EVM execution vs Solidity parsing vs trace vs
# codegen). See the `elixir:reach` skill / hexdocs for the policy DSL.
#
# `smells.ignore.paths` scopes the smell detector to hand-written runtime code.
# Excluded is the build-time code generator, where the flagged patterns are
# INHERENT to metaprogramming, not fixable defects:
#
#   * lib/onchain/contract/generator.ex — the .sol → Elixir module generator.
#     Its `String.to_atom/1` calls CREATE the identifiers (function/variable/
#     struct-field names) of the code it emits at compile time;
#     `String.to_existing_atom/1` is impossible for a not-yet-defined function,
#     so the "unsafe atom creation" smell has no valid fix here. Its repeated
#     `quote` shapes are codegen templates. These `String.to_atom` lines also
#     carry `# sobelow_skip ["DOS.StringToAtom"]` — the project already ruled
#     them intentional-and-unavoidable for the sibling linter.
#
# Unlike cartouche, onchain_evm commits NO generated output: the generator emits
# modules at compile time via macro, so there is no generated-bindings dir to
# exclude. Only the generator source itself is scoped.
#
# This is linter SCOPING (the codegen isn't hand-written runtime code), not a
# finding baseline: no per-finding fingerprints, no churn on line shifts. Every
# smell in hand-written runtime code (evm.ex, solidity.ex, trace.ex,
# bang_helper.ex) is fixed for real.
[
  smells: [
    ignore: [
      paths: [
        "lib/onchain/contract/generator.ex"
      ]
    ]
  ]
]
