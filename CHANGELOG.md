# Changelog

Completed roadmap tasks. For upcoming work, see [ROADMAP.md](ROADMAP.md).

---

## [Unreleased]

### Dependency updates

Updated all dependencies to latest (`@version` → `0.1.1`). Every dep now reports up-to-date via `mix hex.outdated`:

- **onchain** `0.5.3` → `0.7.0` (core in-stack dep) — cascades **cartouche** → `0.2.2`, and requires `decimal ~> 3.1.1` + `descripex ~> 0.7.0`, which unblocked both:
  - **decimal** `~> 2.0` → `~> 3.1` (now `3.1.1`) — previously held back by the old onchain/doctor `~> 2.0` floor; the onchain 0.7 bump + doctor 0.23 (`decimal ~> 3.1`) cleared it.
  - **descripex** `~> 0.6` → `~> 0.7` (now `0.7.0`).
- Dev/test tooling: **doctor** `~> 0.22` → `~> 0.23` (`0.23.0`), **ex_unit_json** `~> 0.4.3` → `~> 0.5.0` (`0.5.0` — the last remaining `hex.outdated` block; 0.5.0 renames the summary key `failures` → `failed`), plus **credo** `1.7.19`, **bandit** `1.12.0`, **sobelow** `0.14.1`, **styler** `1.11.0`, **dialyzer_json** `0.2.1`, **ex_doc** `0.40.3`.

Verified: `mix compile --warnings-as-errors` clean; `mix test.json --exclude integration` → 185 passed, 0 failed.

### Task 41: revm cross-validation of `Aave.Math`

**Completed** | [D:4/B:7/U:6 → Eff:1.63] 🚀

Added an integration test harness (`test/onchain/aave/math_revm_test.exs`) that runs the canonical Aave V3 Solidity bodies inside revm and asserts bit-exact equality with `Onchain.Aave.Math` across all 8 Layer-2 functions. No divergence found — all tests (8 deterministic + 8 StreamData property, 200 runs each) green on first full pass.

**Bytecode provenance, not runtime compilation.** Vendored a pre-compiled Solidity wrapper rather than invoking solc at test time:

- `test/fixtures/wad_ray_wrapper.sol` — inlines `rayMul`, `rayDiv`, `wadMul`, `wadDiv`, `rayToWad`, `wadToRay` from `WadRayMath.sol` and `calculateLinearInterest` / `calculateCompoundedInterest` from `MathUtils.sol`, copied verbatim from `aave-v3-origin@1e3d70c`. The file's header records the upstream commit + per-file SHA1 so drift is visible.
- `test/fixtures/wad_ray_wrapper.bin` — runtime bytecode, metadata hash stripped for reproducibility.
- `test/fixtures/wad_ray_wrapper.json` — solc version, optimizer flags, EVM version, upstream pin, bin SHA256. `setup_all` rehashes the `.bin` and flunks on mismatch.

Compile recipe documented in `test/fixtures/README.md`: `svm use 0.8.10 && solc --bin-runtime --optimize --optimize-runs 100000 --metadata-hash none`. Regeneration is a rare one-off when the Aave pin moves.

**Deviations from the plan.** The plan specified `--evm-version paris`, but solc 0.8.10 predates the Paris fork and rejects that flag; used `london` (the compiler default and what shipped on mainnet for Aave V3). No impact on the pure arithmetic under test — none of the functions touch fork-specific opcodes. Also dropped the planned copy of `Onchain.RPCCase` into `test/support/`: the sibling module from the `onchain` path dep is already compiled into this project's test env, so a second copy would duplicate without benefit.

**Test shape.** `@moduletag :integration, :math_revm`, `async: false`, `timeout: :infinity`. `setup_all` validates the bytecode SHA256 then builds one `state_overrides` map injecting the wrapper at `0x...BEEF`; every test reuses that fork config. Property bounds stay well below the Solidity overflow reverts (10_000 × RAY for ray ops, 10_000 × WAD for wad ops, 10 × RAY for rates, 10-year elapsed window). On divergence, `flunk` surfaces the exact inputs plus both outputs.

**Why wrapper injection and not Path B (live Pool reads).** The deployed Aave Pool exercises only 3 of 8 ported functions through production code paths, and Path B would have taken a blocking dependency on the archive node's historical storage re-index. The wrapper path validates every function individually and runs entirely off `state_overrides` at `"latest"`. Left as a follow-on to add only if the wrapper surfaces gaps.

**Scope exclusions.** Task 40b (floor/ceil WadRayMath variants) stays 🔶 gated — no caller needs them today, so Task 41's harness has nothing to validate against. Path B deferred as above.

Added `{:stream_data, "~> 1.0", only: [:dev, :test]}` and `{:onchain_evm, path: "../onchain_evm", only: [:dev, :test]}` (the latter was already pre-wired earlier this session). Tidewave alias port registered at `4012`.

### Task 40: Port Aave V3 WadRayMath + MathUtils to Elixir

**Completed** | [D:5/B:8/U:9 → Eff:1.70] 🚀

Ported Aave's two protocol-level math libraries from Solidity into `Onchain.Aave.Math`: `WadRayMath` (`ray_mul/2`, `ray_div/2`, `wad_mul/2`, `wad_div/2`, `ray_to_wad/1`, `wad_to_ray/1`) and `MathUtils` (`calculate_linear_interest/3`, `calculate_compounded_interest/3`). Source pinned to [aave-dao/aave-v3-origin](https://github.com/aave-dao/aave-v3-origin) commit `1e3d70c4151a94166ebc59e2eaa4aff6e6ba6978` — `src/contracts/protocol/libraries/math/{WadRayMath,MathUtils}.sol` — and referenced from the `@moduledoc`.

**Integer-native, not Decimal-wrapping.** Inputs and outputs are non-negative integers at ray (10^27) or wad (10^18) scale, matching Solidity's uint256 representation exactly. Rationale: Task 41's revm cross-validation asserts bit-exact equality against live Solidity, which would be obscured by Decimal round-trips. Existing `to_usd`, `to_ltv`, `to_health_factor`, `to_ray`, `to_wad` Decimal display helpers unchanged — the new integer primitives are a second layer. BEAM arbitrary-precision integers make `div(a * b + @half_ray, @ray)` a one-liner equivalent to Solidity's assembly `div(add(mul(a, b), HALF_RAY), RAY)`.

**Rounding preserved.** `ray_mul` / `wad_mul` / `ray_div` / `wad_div` / `ray_to_wad` use Solidity's round-half-up idiom (add half the divisor before floor-dividing). Non-negative guards ensure BEAM's `div/2` truncate-toward-zero equals floor. `wad_to_ray` is exact.

**`calculate_compounded_interest` matches the current v3.1 polynomial approximation**: `RAY + x + rayMul(x, x/2 + rayMul(x, x/6))` where `x = rate * exp / SECONDS_PER_YEAR`. This is the simpler form the v3-origin repo ships today — not the older `aave-v3-core` `(exp)(exp-1)(exp-2)` binomial I initially sketched in the plan. Bit-exact port is what Task 41 will validate.

Fifty-four new unit tests cover identity, zero-absorption, rounding at / below / above midpoints, division by zero (guard), negative inputs (guard), and linear-vs-compounded compounding-premium parity. Property-based cross-validation via StreamData stays in Task 41's scope.

Descripex `api(...)` annotations on all eight new functions; dialyzer 0; credo 0.

### Task 39: Centralize dialyzer cascade suppressions

**Completed** | [D:2/B:3/U:4 → Eff:1.75] 🚀

Moved per-module `@dialyzer` blocks out of `pool.ex`, `oracle.ex`, `ui_pool_data_provider.ex`, and `faucet.ex` into `.dialyzer_ignore.exs` as file + warning-type tuples (`:pattern_match`, `:no_return`, `:invalid_contract`). One upstream-tracking `TODO(upstream:signet)` comment in `.dialyzer_ignore.exs` documents the `Signet.Hex` spec mismatch that produces the cascade — when upstream ships a fix, one block deletes instead of four. Trade-off: file-level granularity instead of per-function. Acceptable because the affected modules are thin wrappers around `Onchain.ABI` with no other realistic source for those warning types. `mix dialyzer.json --summary-only` stays at 0.

### Task 38: Consolidate Pool write integration test helpers

**Completed** | [D:2/B:4/U:3 → Eff:1.75] 🚀

Extracted `supply_weth_collateral!/4` from `test/onchain/aave/pool_write_integration_test.exs` to remove the duplicated approve-WETH-then-supply-WETH preamble shared by the supply/withdraw and borrow/repay tests. Added `TODO:`-prefixed rationale to gas-limit constants (testnet-calibrated headroom), `@oracle_jitter_tolerance` (empirical 5% Chainlink drift slack), and the WETH/faucet threshold/amount constants (cumulative-run sizing). Test behavior unchanged.

### Task 36: Extract shared Pool write helper

**Completed** | [D:3/B:6/U:5 → Eff:1.83] 🚀

Pulled the pool-address lookup + ABI encode + Signer dispatch shared by `Onchain.Aave.Pool.{supply,withdraw,borrow,repay}/4` into a private `send_pool_tx/4` helper. Each write function shrinks to argument validation followed by one helper call. Public API unchanged. `Faucet.mint/4` follows the same shape but stays separate — sharing across two call sites isn't worth promoting the helper to a shared module.

### Roadmap reprioritization: V3 Math Validation before V4 implementation

Reframed ROADMAP.md to gate V4 work on V3 math verification. Added a "🎯 Current Focus" section naming Tasks 40 → 41 as the active path; Task 43 (JS aggregation cross-validation) stays 🔶 gated until off-chain aggregation helpers exist. Bumped Task 40 (WadRayMath + MathUtils port) from U:7 → U:9 (Eff 1.50 📋 → 1.70 🚀) because it gates both Task 41 (V3 revm validation) and Task 42 (V4 revm validation) — it is now the verification bridge rather than isolated math work. Moved the Cleanup Backlog (Tasks 36, 38, 39) below Math Validation to reflect that it is polish, not a capability gate. No code changes.

### Task 44: V4 Hub-and-Spoke scoping

**Completed** | [D:3/B:7/U:8 → Eff:2.50] 🎯

Enumerated the Aave V4 Ethereum mainnet contract surface (live since 2026-03-30) into [V4_SCOPING.md](V4_SCOPING.md): three Hubs (Core, Prime, Plus), ten Hub Spokes plus a standalone Treasury Spoke, thirty-one Tokenization Spokes as ERC-4626 supply vaults, five Position Managers, a per-Spoke oracle model, and supporting infrastructure (Access Manager, Hub/Spoke Configurators, Config Engine, Liquidation Logic). Every address pulled from `bgd-labs/aave-address-book` (`AaveV4Ethereum` namespace). Interface pointers resolve into `github.com/aave/aave-v4/src/{hub,spoke,position-manager,config-engine,access}/interfaces/`.

Produced V3→V4 module mapping and opened implementation Tasks 45–52 in ROADMAP. Key decisions: extend `Onchain.Aave.Contracts` rather than create a parallel V4 registry (Task 45); build V4 siblings under `Onchain.Aave.V4.*` because V4 has no `Pool` analog (Tasks 47–51); replace V3's single `AggregatedReserveData` with Spoke-scoped V4 types (Task 48). Task 42 (V4 math cross-validation via revm) updated to reference the concrete `EXTERNAL_LIBRARIES LIQUIDATION_LOGIC` address discovered during scoping as the likely WadRayMath call-site.

No Elixir code written under Task 44 per the research-only scope.

### Task 37: Named canonical Aave V3 addresses

**Completed** | [D:1/B:5/U:4 → Eff:4.50] 🎯

Extracted the CREATE2-shared V3 canonical pool (`0x794a61358D6845594F94dc1DB02A252b5b4814aD`) and pool-addresses-provider (`0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb`) into `@aave_v3_canonical_pool` / `@aave_v3_canonical_provider` module attributes in `Onchain.Aave.Contracts`. Arbitrum, Optimism, Polygon, and Avalanche now reference the attributes instead of inlining the literals four times each. Documents the shared-deployment intent and makes copy-paste drift syntactically impossible. Public API and stored values unchanged — `address/2` returns identical checksummed strings.

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
