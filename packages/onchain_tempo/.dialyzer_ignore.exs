# Transitive deps via onchain (hex dep) are not resolved in the PLT under :apps_direct.
# These are false positives — all functions exist at runtime.
[
  # Jason (via onchain)
  ~r/Function Jason\./,
  # Req (via onchain)
  ~r/Function Req\./,
  # Cartouche (via onchain → cartouche; transitive, not in :apps_direct PLT)
  ~r/Function Cartouche\./,
  # Onchain modules
  ~r/Function Onchain\./,
  # Descripex (Discoverable macro)
  ~r/Function Descripex\./,
  # ExRLP (via onchain → cartouche; transitive, only surfaces in test env via test/support)
  ~r/Function ExRLP\./
]
