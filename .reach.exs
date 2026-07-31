# Reach architecture/smell policy for `mix reach.check --arch --smells`.
#
# `reach` was already a dev/test dependency here with no policy file, so
# `mix reach.check --arch` aborted with "No .reach.exs architecture policy
# found" — the dep was half-installed. This is the missing half, mirroring the
# sibling policies in cartouche / onchain / onchain_evm.
#
# `:arch` starts permissive: onchain_js is a thin bridge (OnchainJs.* over
# QuickBEAM/npm) with no layering to encode yet. Populate `layers` /
# `deps[:forbidden]` once the module surface justifies it. See the
# `elixir:reach` skill for the policy DSL.
[]
