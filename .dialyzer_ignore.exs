# Every pattern here matches a live warning. Verified by running `mix dialyzer`
# with ignores disabled (7 warnings: 6 pattern_match_cov, 1 call_without_opaque)
# and then bisecting the list. The former transitive-dep skips
# (`Function Jason./Req./Signet./Onchain./Descripex.`) are gone: the PLT now
# resolves those apps, so they matched nothing while still being broad enough
# to mask a real call error.
[
  # Bang function error clauses — Dialyzer thinks the ok-path spec is exhaustive,
  # but the NIF can return errors at runtime that Dialyzer can't see.
  ~r/pattern.*can never match.*covered by previous clauses/,
  # MapSet opaque term in Onchain.Solidity.Resolver — Dialyzer doesn't track
  # MapSet internals.
  ~r/opaque term.*member\?/
]
