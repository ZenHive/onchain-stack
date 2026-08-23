# Changelog

Completed roadmap tasks. For upcoming work, see [ROADMAP.md](ROADMAP.md).

---

## [Unreleased]

### Added

- Independent evidence for the deployed Ethereum Aave V4 wrappers, pinned to
  mainnet block 25_800_000. Hub/Spoke/Oracle/TokenizationSpoke reads agree on
  WETH accounting; signed PositionManager supply/borrow/repay calls mutate
  that accounting on a local `onchain_evm` fork and decode the Taker's
  `InsufficientBorrowAllowance` revert before approval.

### Changed

- Raised the dev/test-only `onchain_evm` requirement from `~> 0.5` to
  `~> 0.6`. 0.6 forks `BlockEnv` from the selected block and applies state
  overrides on top of the fetched account, so V4 write simulation keeps
  WETH code and the forked block time. The same lock refresh resolved
  hieroglyph 1.6.2 → 1.7.0 (transitive via cartouche) and swapped `rustler`
  for `rustler_precompiled`. This dependency is not part of the published
  runtime requirements.

---

## v0.4.0 — Aave V4 support (2026-08-22)

### Added — Aave V4 support (Hub-and-Spoke)

Aave V4 went live on Ethereum mainnet on 2026-03-30 with an architecture that is
not a drop-in extension of V3: the monolithic `Pool` is replaced by Hubs
(routing + rate environment + credit lines), Spokes (risk-isolated borrow venues,
each with its own oracle), ERC-4626 Tokenization Spokes (supply positions), and
Position Managers (the user-facing write entrypoints). The V3 tree is untouched;
V4 lands as a sibling under `Onchain.Aave.V4.*`. Addresses are registered in
`Onchain.Aave.Contracts` under flat `:v4_`-prefixed keys, with Tokenization
Spokes resolved by `{hub, asset}`.

- `Onchain.Aave.V4.Hub` — Hub reads: member Spokes, credit lines (drawn and
  premium shares, deficits), and the rate environment.
- `Onchain.Aave.V4.Spoke` — per-Spoke reads. V4 has no global
  `getUserAccountData`; user health is Spoke-scoped and shaped by that Spoke's
  collateral and borrowable sets. Reserves are addressed by `uint256 reserveId`
  scoped to a Spoke, not by asset address as in V3.
- `Onchain.Aave.V4.Oracle` — Spoke-scoped `IAaveOracle` and Chainlink reads. The
  oracle is a property of each Spoke rather than a single protocol-wide feed.
- `Onchain.Aave.V4.TokenizationSpoke` — ERC-4626 share accounting for supply
  positions, which replace V3's aTokens.
- `Onchain.Aave.V4.PositionManager` — the V4 write surface. Supply and repay go
  through the Giver Position Manager, borrow and withdraw through the Taker.
  Every position action takes the owner as an explicit required argument; none
  infers it from `msg.sender`, so the wrappers compose under DELEGATECALL from a
  Safe. Borrow and withdraw send the assets to the *caller* and require an
  allowance from the owner, so the allowance surface (`approve_borrow`,
  `approve_withdraw`, the `renounce_*` counterparts, and the two allowance
  views) ships with them. `InsufficientBorrowAllowance` and
  `InsufficientWithdrawAllowance` reverts decode to tagged tuples carrying the
  allowance and the required amount.
- `Onchain.Aave.Math.V4` — V4 math conversions alongside the V3 helpers.

There is no stable-rate borrowing in V4, and no `UiPoolDataProvider` analog.
V4 is Ethereum-mainnet only, so the write paths are pinned by encoded-calldata
unit tests rather than testnet sends.

### Added — mutation-grade math verification

- Pinned Aave V3/V4 Solidity wrapper bytecode, compiler/source provenance, and
  REVM-generated oracle vectors now independently check the Elixir math ports.
- Property domains cover every public V3/V4 math operation across zero, unit,
  boundary, overflow-adjacent, and rounding-sensitive inputs.
- Generated and domain-specific mutations must be killed or explicitly
  allowlisted with evidence; a deliberate rounding canary validates the
  campaign itself.

### Changed

- `OnchainAave.describe/0` registers every public module. The manifest test now
  derives its expectation from the compiled application instead of asserting a
  hardcoded module count, so a module that is added without being registered
  fails the suite rather than reaching consumers undiscoverable.
- Widened the `descripex` requirement from `~> 0.12.0` to `~> 0.12`. The
  three-segment cap turned every additive descripex minor into a forced
  nine-repo release cascade while protecting nothing in-family — `mix.lock` is
  committed, so a new descripex only ever lands through a deliberate
  `mix deps.update` behind `mix ci`.
- Resolved the refreshed family upstreams: onchain 0.13.0, descripex 0.13.0,
  cartouche 0.7.1, hieroglyph 1.6.2, zen_websocket 0.7.1 and the dev/test-only
  onchain_evm 0.5.1.

---

## v0.3.2 — dependency refresh (2026-08-17)

No public API or runtime dependency requirement changed.

### Changed

- Resolved `onchain 0.12.1`, `cartouche 0.7.0`, `descripex 0.12.1`,
  `hieroglyph 1.6.1`, and `zen_websocket 0.6.1` within the existing runtime
  requirements.
- Raised the dev/test-only `onchain_evm` requirement from `~> 0.4` to
  `~> 0.5`. Its REVM 42 engine can change simulation results; the Aave math
  cross-validation suites remain green against the new engine. This dependency
  is not part of the published runtime requirements.
- Updated development tooling: `sobelow` 0.14.1 → 0.15.0, `tidewave`
  0.8.1 → 0.8.4, and `ex_ast` 0.12.10 → 0.13.1. Reach 2.8.2 still declares
  `ex_ast ~> 0.12.0`; the direct dev/test override preserves the same clean
  smell result under 0.13.1.

---

## v0.3.1 — publishable tarball, no sibling checkout required (2026-08-02)

No public API change and no runtime requirement change: `onchain ~> 0.12`,
`decimal ~> 3.1` and `descripex ~> 0.12.0` are what 0.3.0 declared. Every
change here is to what gets packaged and how the repo builds.

### Fixed — the published tarball carried 5.4 MB of dialyzer PLT

`package/0` declared no `files`, so hex's default list shipped all of `priv/`.
`dialyzer/0` pins `plt_local_path`/`plt_core_path` to `priv/plts`, and
`mix hex.build` does not honour `.gitignore`, so the four PLT files landed in
the release: onchain_aave 0.3.0 is a 5.5 MB tarball of which ~16 KB is the
package. `files` is now explicit — `lib priv/abis .formatter.exs mix.exs
README.md LICENSE CHANGELOG.md` — matching the sibling packages, which all
carry an explicit list for the same reason.

### Added — `LICENSE`

The package declared `licenses: ["MIT"]` with no license text in the repo or
the tarball. The MIT text is now present and shipped, as in `onchain`,
`onchain_evm` and `cartouche`.

### Fixed — README install block declared bounds that cannot resolve

It read `{:onchain, "~> 0.8"}, {:onchain_aave, "~> 0.2"}`. Since 0.3.0 this
package requires `onchain ~> 0.12`, so a consumer copying that block got a
resolution failure. The block now names `{:onchain_aave, "~> 0.3"}` only and
notes that `onchain` arrives transitively.

### Changed — `onchain_evm` resolves from Hex, not a sibling path

`{:onchain_evm, path: "../onchain_evm", only: [:dev, :test]}` became
`{:onchain_evm, "~> 0.4", only: [:dev, :test]}` (0.4.0 in the lock). This dep
is dev/test-only — it backs the revm math cross-validation suites
(`math_revm_test.exs`, `v4_revm_test.exs`) — so it never appeared in the
published requirements either before or after. What changes is that a clone of
this repo alone now builds: no `../onchain_evm` checkout has to exist beside
it.

Both GitHub workflows drop the second `actions/checkout` of
`ZenHive/onchain_evm@development` and the `path:`-nested working directory it
forced, and gain an explicit `dtolnay/rust-toolchain@stable` plus a Cargo
registry cache — onchain_evm ships no precompiled artifacts, so its NIF crates
build from source on the runner.

---

## v0.3.0 — onchain 0.12 line, clone dedup, real gates, bounds narrowed (2026-08-01)

No public API change: every function keeps its name, arity and return shape.

**Minor, not patch.** This was drafted as 0.2.2 while every dependency edit was
dev/test-scoped. It now narrows a *runtime* requirement (`descripex`), and
narrowing a runtime bound can fail resolution for a consumer pinned below the
new floor. That failure is loud rather than silent, but it is still a
compatibility break and semver should say so.

### Changed — `{:onchain, "~> 0.11"}` → `{:onchain, "~> 0.12"}`

onchain 0.12.0 is the release that raises `zen_websocket` to `~> 0.6.0`, which
*requires* the gun version carrying the GHSA-w4f7-4cxr-rv3c fix rather than
merely permitting it. `~> 0.11` admits 0.12.0 but does not require it, so this
package's lock would have kept resolving onchain 0.11.0 → zen_websocket 0.4.2,
whose looser gun bound only happens to have landed on a fixed 2.5.0 — a lock
entry that still satisfies its bound is never re-resolved.

The lock now carries onchain 0.12.0 and zen_websocket 0.6.0. onchain 0.12.0 also
narrows `descripex` to `~> 0.12.0`, matching what this package now declares
directly (below). No code change was needed: onchain 0.12.0 makes no public API
change, and the suite is green against it.

### Changed — hieroglyph 1.6.0 in the lock, `elixir: "~> 1.17"` → `"~> 1.18"`

`mix.exs` gains no `hieroglyph` line — it arrives transitively through
onchain/cartouche, whose published bounds already admit it — but the lock now
carries 1.6.0, which restores `ABI.Event.decode_event/4`'s documented total
contract (unnamed event inputs no longer raise; an array length prefix that
cannot fit the remaining payload is rejected before the element list is
allocated) and makes `decode_structs: true` work on the event path.

The Elixir floor moves with it: hieroglyph 1.6.0's encode path uses
`Enum.sum_by/2` (1.18+), so declaring `~> 1.17` here would let this package
resolve on 1.17 and then fail compiling a dependency. Same reasoning as the
`descripex` narrowing below — a loud resolution failure, but still a
compatibility break.

### Changed — `{:descripex, "~> 0.11"}` → `{:descripex, "~> 0.12.0"}`

descripex 0.12.0 changed `short_name` in `describe/1` output from an atom to a
string — a consumer-visible contract change shipped at a *minor* bump, which the
old two-segment `~> 0.11` (`>= 0.11.0 and < 1.0.0`) would have absorbed on any
fresh resolution without a version bump here. The requirement is now
three-segment (`< 0.13.0`): a 0.x package that breaks on minor earns the tighter
form, and the cap gets raised deliberately after reading its release notes.

onchain_aave does not read `short_name` — nothing in `lib/` or `test/`
references it, and the suite (232 tests) is green against descripex 0.12.0 with
no code change. The break is in the *bound*, not the behaviour.

### Changed — two real duplicated blocks removed

`ex_dna` was not a dependency here at all, so clone detection had never run.
Adding it with `--max-clones 0` surfaced two genuine clones (no false
positives):

- `validate_addresses/1` — byte-identical `defp` in `oracle.ex` and `pool.ex`.
  Moved into the existing internal helper module `Onchain.Aave.Opts`
  (`@moduledoc false`), which already held `split_network/1`.
- `calculate_linear_interest/3` — identical in `Onchain.Aave.Math` and
  `Onchain.Aave.Math.V4`, same guard and same `@ray` / `@seconds_per_year`
  values. Aave's linear-interest formula is unchanged between V3 and V4, so
  `Math.V4` now delegates to `Math`. Both public functions keep their exact
  name, arity and return shape; the dead `@seconds_per_year` attribute in
  `v4.ex` is gone.

Coverage was measured before touching code. `math.ex` and `math/v4.ex` were
already fully covered. `oracle.ex`'s `validate_addresses` success branch was
not — only the failure path was tested — so that test was written and confirmed
passing against the *unchanged* code before the extraction.

### Changed — the quality gates now actually gate

- **`reach` added** with `.reach.exs` carrying `smells: [strict: true]`. The
  strict flag is the point: `reach.check --smells` raises only when
  `opts[:strict] || config.smells.strict`, so without it the check reports
  findings and still exits 0.
- **`mix_audit` added and wired.** `deps.audit.gated` proves the advisory
  database is current *before* auditing — `mix_audit` discards its own sync exit
  status (mirego/mix_audit#61), so a database that can no longer sync still
  prints "No vulnerabilities found" and exits 0.
- **`ex_dna --max-clones 0`** added as a gate step (see above).
- **`agents.check`** fails when `AGENTS.md` has drifted from `CLAUDE.md`.
- **CI invokes `mix ci`** instead of a hand-maintained check list. The check
  stack documented in `AGENTS.md` is now backed by an alias that runs it.
- **MCP config mirrored to all four agent families** (`.cursor/`, `.codex/`,
  `.grok/`) — a server declared only in `.mcp.json` is invisible to cross-family
  agents.

---

## v0.2.1 — dependency floors + revive the Sepolia write tests (2026-07-31)

No library code changes.

### Changed — dependency floors raised to what actually resolves

- `{:onchain, "~> 0.8"}` → `{:onchain, "~> 0.11"}`. onchain 0.11.0 is the
  release carrying `cartouche ~> 0.6`, which lifts cartouche's transitive
  `req < 0.7` cap. The old bound *permitted* 0.11.0 without *requiring* it, so a
  consumer holding a lock on an older onchain would keep resolving cartouche
  0.5.x — and therefore req 0.6.x — indefinitely, since a lock entry that still
  satisfies its bound is never re-resolved.
- `{:descripex, "~> 0.9"}` → `{:descripex, "~> 0.11"}`, matching what cartouche
  0.6 already forces.

Resolves to onchain 0.11.0, cartouche 0.6.0, descripex 0.11.0, req 0.7.1.

### Fixed — Sepolia write tests were dead at `setup`

`Onchain.SignerCase.signer_address!/0` aliased `Signet.Signer.Curvy`, a leftover
from before the cartouche migration. `signet` appears in neither `mix.exs` nor
`mix.lock`, so the alias had never been resolvable — every integration test that
derives the signer address from its private key died in `setup` with
`UndefinedFunctionError`, taking out `faucet_integration_test`,
`pool_write_integration_test` (2 tests), and `debt_token_write_integration_test`.

Replaced with `Onchain.Signer.address_from_key!/1` from the direct `onchain`
dependency, which folds hex decoding, key derivation, and EIP-55 checksumming
into one call — the helper drops from three lines to one. All four tests now run
against real Sepolia and pass.

---

## v0.2.0 — onchain-0.8 / descripex-0.9 line, Multicall batch reads, V4 groundwork (2026-06-12)

### Changed — v0.2.0 dependency line

- Moved to the descripex-0.9 / onchain-0.8 line: `onchain ~> 0.7.0` → `~> 0.8`, `descripex ~> 0.7` → `~> 0.9`. Additive upstreams (descripex 0.9.1's `safe_convert` fix keeps manifest/`describe` from crashing on unconvertible spec types; onchain 0.8.0 relaxes its descripex/cartouche floors). No onchain_aave code changes; compile clean under `--warnings-as-errors`, 231 offline tests green against the new chain.

### Task 55: Adopt `Onchain.Multicall` in Aave batch read paths

**Completed** | [D:3/B:6/U:6 → Eff:2.0] 🎯

Audited the `Onchain.Aave.*` read modules for places that issue N independent RPC round-trips where the protocol does **not** already pre-batch, and adopted Multicall3 there.

- **`Onchain.Aave.Pool.get_user_account_data_many/2`** (+ `!` variant) — fetches full positions for a list of users in **one** Multicall3 round-trip instead of N `getUserAccountData` calls. Results are aligned positionally with the input; empty input short-circuits to `{:ok, []}` with no RPC. The obvious consumer is liquidation monitoring / dashboards tracking many accounts.

**Audit — left as-is (already batched, no win):**
- `UiPoolDataProvider.get_reserves_data/1` and `get_user_reserves_data/2` — Aave's own contract aggregates all reserves/user balances server-side in a single call.
- `Oracle.get_asset_prices/2` — uses Aave's native `getAssetsPrices(address[])` batch.

Single-asset/single-user reads (`get_asset_price`, `get_source_of_asset`, oracle config getters) are one RPC each; batching them is a future helper only if a multi-asset caller materializes.

Tests: unit (validation, unsupported network, empty-list short-circuit, `!` raises) + integration (positional alignment, zero-position vs active borrower, binary addresses, parity with the single-user call).

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
