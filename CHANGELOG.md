# Changelog — onchain-stack

This is the monorepo root. Each package keeps its own changelog — release
history lives there, not here:

| Package | Changelog |
|---|---|
| hieroglyph | [packages/hieroglyph/CHANGELOG.md](packages/hieroglyph/CHANGELOG.md) |
| cartouche | [packages/cartouche/CHANGELOG.md](packages/cartouche/CHANGELOG.md) |
| onchain | [packages/onchain/CHANGELOG.md](packages/onchain/CHANGELOG.md) |
| onchain_aave | [packages/onchain_aave/CHANGELOG.md](packages/onchain_aave/CHANGELOG.md) |
| onchain_aerodrome | [packages/onchain_aerodrome/CHANGELOG.md](packages/onchain_aerodrome/CHANGELOG.md) |
| onchain_evm | [packages/onchain_evm/CHANGELOG.md](packages/onchain_evm/CHANGELOG.md) |
| onchain_js | [packages/onchain_js/CHANGELOG.md](packages/onchain_js/CHANGELOG.md) |
| onchain_tempo | [packages/onchain_tempo/CHANGELOG.md](packages/onchain_tempo/CHANGELOG.md) |

Root-level (non-package) changes — tooling under `bin/`, the shared gate
helpers, the merged roadmap — are tracked through git history only.

## 2026-08-27 — the monorepo migration

The eight standalone repos were absorbed into this monorepo with full git
history under `packages/<name>/`. Hex packages, versions, and public APIs are
unchanged; the standalone GitHub repos are archived. See `CLAUDE.md` for the
mechanism (sibling/3 dual-mode deps, `ONCHAIN_PUBLISH=1`, the root gate).
