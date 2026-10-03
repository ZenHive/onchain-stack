# Reach architecture/smell policy for `mix reach.check --arch --smells`.
#
# `:arch` starts permissive (no layer/boundary policy yet) so reach gates on
# cross-function smells only. Populate layer/boundary rules here as cartouche's
# module architecture solidifies (substrate vs signer backends vs RPC vs codecs).
# See the `elixir:reach` skill / hexdocs for the policy DSL.
#
# `smells.ignore.paths` scopes the smell detector to hand-written runtime code.
# Reach's global and per-check ignores accept `paths:`/`modules:`. Global
# exclusions below hide only shapes inherent to metaprogramming:
#
#   * "unsafe atom creation" in lib/onchain/contract/generator.ex —
#     `String.to_atom/1` creates the identifiers the generator emits.
#     `String.to_existing_atom/1` is impossible for a not-yet-defined function.
#   * Generated bindings under lib/onchain/contract/** and the hand-written
#     test contracts that mimic that old surface.
#
[
  # Keep all hand-written runtime, development and test-support sources.
  checks: [source_paths: ["lib", "dev", "sol/src", "test/support"]],
  smells: [
    # `--smells` is advisory unless strict is set (reach 2.8.2 config.ex
    # ~L351); this makes every `mix reach.check --arch --smells` invocation gate.
    strict: true,
    ignore: [
      paths: [
        "lib/onchain/contract/generator.ex",
        "lib/onchain/contract/sleuth.ex",
        "test/support/cartouche/contract/**"
      ]
    ],
    # The `{indexed, name, type}` map is the public ABI argument shape
    # (`Onchain.ABI.FunctionSelector` types and event filters), not an anonymous
    # literal. Generated `IConsole` used to be the grouped site and was
    # excluded with the other contract bindings. These two hand-written
    # producers are the same contract. This exception applies solely to
    # that check.
    fixed_shape_map: [
      ignore: [
        paths: [
          "lib/onchain/abi/function_selector.ex",
          "lib/onchain/filter.ex"
        ]
      ]
    ]
  ]
]
