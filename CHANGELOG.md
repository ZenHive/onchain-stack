# Changelog

Completed roadmap tasks. For upcoming work, see [ROADMAP.md](ROADMAP.md).

---

## v0.1.0 — Initial Release (Split from onchain)

Extracted from [onchain](../onchain) v0.3.0 monolith as a standalone package.

**What's included:**

- **Onchain.Aave.Contracts** — address registry for mainnet + 6 chains (Arbitrum, Optimism, Base, Polygon, Avalanche, Sepolia)
- **Onchain.Aave.Math** — to_usd, to_ltv, to_health_factor, to_ray conversions
- **Onchain.Aave.Pool** — read (getUserAccountData) + write (supply, borrow, repay, withdraw)
- **Onchain.Aave.Oracle** — getAssetPrice + Chainlink fallback
- **Onchain.Aave.UiPoolDataProvider** — bulk reserve/user data
- **Onchain.Aave.Faucet** — testnet faucet interactions
- **Types** — UserAccountData, AggregatedReserveData, BaseCurrencyInfo, UserReserveData

**Why:** Consumers who only need core Ethereum primitives no longer pull in Aave protocol dependencies. Zero code changes for existing consumers — only `mix.exs` deps change.

**Initial-commit review pass:**
- Corrected `CLAUDE.md` env var name for Sepolia write tests (`ETH_SEPOLIA_PRIVATE_KEY`, was `SIGNER_PRIVATE_KEY`)
- Converted stale verification-date comment on Sepolia addresses into `TODO(Task 6): …` so Credo tracks re-verification on Aave upgrades
- Bumped patches: `credo` 1.7.17→1.7.18, `ex_unit_json` 0.4.2→0.4.3, `onchain` 0.5.0→0.5.1
- Captured cleanup backlog as Tasks 36–39 in `ROADMAP.md`
