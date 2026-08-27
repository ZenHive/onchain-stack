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
#   * 24x "unsafe atom creation" in lib/mix/cartouche.gen.ex — `String.to_atom/1`
#     CREATES the identifiers of the code the generator emits;
#     `String.to_existing_atom/1` is impossible for a not-yet-defined function.
#   * 1x "Repeated map shapes" (383 sites) in lib/cartouche/contract/i_console.ex
#     — generated contract bindings (the generator's output).
#
# Every other smell in hand-written `lib/cartouche/**` and in the generator
# itself is fixed for real, not excluded.
[
  smells: [
    # `--smells` is advisory unless strict is set (reach 2.8.2 config.ex
    # ~L351); this makes every `mix reach.check --arch --smells` invocation gate.
    strict: true,
    ignore: [
      paths: [
        "lib/mix/cartouche.gen.ex",
        "lib/cartouche/contract/**",
        "test/support/cartouche/contract/**"
      ]
    ],
    # `Cartouche.Filter` contains one provider-owned ABI argument map. It only
    # crosses the repetition threshold when grouped with generated IERC20 maps;
    # this exception applies solely to that check, not other Filter smells.
    fixed_shape_map: [
      ignore: [paths: ["lib/cartouche/filter.ex"]]
    ]
  ]
]
