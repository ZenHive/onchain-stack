# Reach architecture/smell policy for `mix reach.check --arch --smells`.
#
# `:arch` starts permissive (no layer/boundary policy yet) so reach gates on
# cross-function smells only. Populate layer/boundary rules here as onchain_evm's
# module architecture solidifies (EVM execution vs Solidity parsing vs trace). See the `elixir:reach` skill / hexdocs for the policy DSL.
#
# `strict: true` makes this gate enforce (`--smells` is otherwise advisory —
# reach 2.8.2 config.ex ~L351). Contract codegen lives in onchain; this package
# keeps the Solidity frontend only. Every smell in the hand-written runtime
# (evm.ex, solidity.ex, trace.ex, bang_helper.ex) is fixed for real.
[
  smells: [
    strict: true
  ]
]
