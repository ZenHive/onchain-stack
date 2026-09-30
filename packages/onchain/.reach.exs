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
[
  # Keep all hand-written sources; exclude only generated yecc/leex Erlang.
  checks: [source_paths: ["lib", "dev", "sol/src", "test/support"]],
  smells: [
    # `--smells` is advisory unless strict is set (reach 2.8.2 config.ex
    # ~L351); this makes every `mix reach.check --arch --smells` invocation gate.
    strict: true,
    ignore: [
      paths: [
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
