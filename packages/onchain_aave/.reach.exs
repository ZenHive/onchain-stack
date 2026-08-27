# Reach architecture/smell policy for `mix reach.check --arch --smells`.
#
# Real boundary confirmed by grep (no code references, only prose in
# @moduledoc strings, in either direction):
#   - `Onchain.Aave.Types.*` are data structs built from raw pool/oracle
#     results. They legitimately call `Onchain.Aave.Math` for unit conversion
#     (wad/ray -> human values) while parsing, but never call the protocol
#     modules (Pool, Oracle, DebtToken, Faucet, UiPoolDataProvider).
#   - `Onchain.Aave.Contracts` (address registry — "all other Aave modules
#     depend on this for addresses", contracts.ex moduledoc) and
#     `Onchain.Aave.Math`/`Math.V4` (pure numeric conversions) are leaf
#     utilities: neither depends on Types or the protocol modules.
# First attempt classified Math as `core`, which produced 20 false-positive
# violations + a layer cycle — Types legitimately depends on Math. Math
# belongs with Contracts as `base`, not `core`.
#
# Layer order matters: reach's glob `*` crosses module-name segments, so a
# catch-all like "Onchain.Aave.*" matches everything below it too. More
# specific layers must be declared before the broad `core` catch-all so they
# win the first-match tiebreak.
[
  layers: [
    types: "Onchain.Aave.Types.*",
    base: ["Onchain.Aave.Contracts", "Onchain.Aave.Math", "Onchain.Aave.Math.*"],
    core: "Onchain.Aave.*"
  ],
  deps: [
    forbidden: [
      {:types, :core},
      {:base, :types},
      {:base, :core}
    ]
  ],
  smells: [strict: true]
]
