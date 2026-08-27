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
[
  # `--smells` is advisory unless strict is set (reach 2.8.2 config.ex ~L351);
  # this makes every `mix reach.check --arch --smells` invocation gate.
  #
  # Dormant for now: `mix ci` passes only `--arch` here, because reach 2.8.2
  # crashes on this repo's JavaScript nodes (elixir-vibe/reach#36 — see the
  # comment on the alias in mix.exs). Kept set so the gate is live again the
  # moment `--smells` goes back into the alias.
  smells: [strict: true]
]
