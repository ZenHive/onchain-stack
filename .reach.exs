# Reach architecture/smell policy for `mix reach.check --arch --smells`.
#
# `:arch` starts permissive, matching the sibling policies in cartouche /
# onchain / onchain_evm: onchain_tempo is a focused surface (Onchain.Tempo.*
# — transaction building/signing, RPC, TIP-20, event parsing) with no layering
# worth enforcing yet. Populate `layers` / `deps[:forbidden]` if the module
# surface grows a real boundary. See the `elixir:reach` skill for the DSL.
[]
