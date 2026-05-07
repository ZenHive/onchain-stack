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
  # QuickBEAM (via quickbeam)
  ~r/Function QuickBEAM\./
]
