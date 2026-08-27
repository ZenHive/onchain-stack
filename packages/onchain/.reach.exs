# Reach architecture/smell policy for `mix reach.check --arch --smells`.
#
# `reach` was already a dev/test dependency here, but this file was missing, so
# `mix reach.check --arch` aborted with "No .reach.exs architecture policy
# found" — the dep was half-installed. This is the missing half.
#
# `:arch` starts permissive (no layer/boundary policy yet) so reach gates on
# cross-function smells only, matching the sibling policy in cartouche. onchain's
# module surface is currently flat under `Onchain.*` (rpc, abi, erc*, signer,
# ens, aa, dex, erc7730, subscription) with no enforced layering to encode;
# populate `layers` / `deps[:forbidden]` here once that architecture solidifies.
# See the `elixir:reach` skill for the policy DSL.
[
  # `--smells` is advisory unless strict is set (reach 2.8.2 config.ex ~L351);
  # this makes every `mix reach.check --arch --smells` invocation gate.
  smells: [strict: true]
]
