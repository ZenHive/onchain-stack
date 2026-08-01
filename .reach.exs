# Reach architecture/smell policy for `mix reach.check --arch --smells`.
#
# `:arch` starts permissive, matching the sibling policies in cartouche /
# onchain / onchain_evm: onchain_tempo is a focused surface (Onchain.Tempo.*
# — transaction building/signing, RPC, TIP-20, event parsing) with no layering
# worth enforcing yet. Populate `layers` / `deps[:forbidden]` if the module
# surface grows a real boundary. See the `elixir:reach` skill for the DSL.
[
  # `--smells` is advisory unless strict is set (reach 2.8.2 config.ex ~L351);
  # this makes every `mix reach.check --arch --smells` invocation gate.
  smells: [strict: true]
]
