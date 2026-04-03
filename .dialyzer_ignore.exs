# Transitive deps via onchain are not resolved in the PLT.
# These are false positives — all functions exist at runtime.
[
  # Jason (via onchain)
  ~r/Function Jason\./,
  # Req (via onchain)
  ~r/Function Req\./,
  # Signet (via onchain → signet)
  ~r/Function Signet\./,
  # Onchain modules
  ~r/Function Onchain\./,
  # Descripex (Discoverable macro)
  ~r/Function Descripex\./,
  # Bang function error clauses — Dialyzer thinks the ok-path spec is exhaustive,
  # but the NIF can return errors at runtime that Dialyzer can't see.
  ~r/pattern.*can never match.*covered by previous clauses/,
  # MapSet opaque term warnings — Dialyzer doesn't track MapSet internals
  ~r/opaque term.*member\?/,
  ~r/opaque term.*union/
]
