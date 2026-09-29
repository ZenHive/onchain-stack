# Task 9030 — core package relocation

## Changes and acceptance

- Removed `packages/hieroglyph` and `packages/cartouche`. Their runtime modules,
  grammar sources, fixtures, tests and support modules now live in `packages/onchain`.
  All 157 moved lib/src/priv/test files (excluding the two combined test helpers)
  were compared byte-for-byte to HEAD: 37 from hieroglyph, 120 from cartouche.
  No module names or runtime implementations changed; no deduplication.
- Merged dependencies, application startup, test configuration, package contents,
  Reach policy, coverage and Doctor policies. Cartouche.Application remains the
  application callback and reads the original `:cartouche` configuration keys.
- Removed the old sibling edges; Solana now depends on onchain. Updated root
  package bounds, publish/fleet tooling, layout/release docs and MCP endpoints.
  Regenerated root and onchain AGENTS.md with the repository generator.
- Preserved original licenses, reference documentation, audit and mutation records.
- The original Cartouche global RPC stub intercepted Onchain's connection-failure
  tests after consolidation. A test-only request adapter scopes canned responses
  to fixture endpoints; the existing Onchain.RPCTest gets a process-local bypass
  for real transport. Its assertions and all moved test bodies remain unchanged.

## Test counts

Commands before relocation: `cd packages/<package> && mix deps.get && mix test`.
Dependencies initially had stale caches; fetching the committed resolutions fixed
that prerequisite without changing the three original lockfiles.

| Suite | Passed | Excluded |
| --- | ---: | ---: |
| hieroglyph | 531 | 0 |
| cartouche | 1,030 | 50 |
| onchain | 885 | 193 |
| Sum before | **2,446** | **243** |
| Merged `cd packages/onchain && mix test` | **2,446** | **243** |

Merged breakdown: 476 doctests, 26 properties, 1,944 tests.

## Verification results

- `mix check.dispatch` — passed in onchain, onchain_aave, onchain_aerodrome,
  onchain_evm, onchain_js, onchain_tempo and onchain_solana.
- `MIX_ENV=test mix onchain.bounds` — all 8 remaining sibling requirements pass.
- `ONCHAIN_PUBLISH=1 mix hex.build` in onchain — passed; no
  `excluded from the package` line. Inspected the archive: both grammar sources
  and both moved priv JSON fixtures are included.
- `MIX_ENV=test mix onchain.coverage` — passed. Separate weighted library floors:
  ABI 100% / 95%; Cartouche 93.89% / 85%; Onchain 79.51% / 70%; signer modules
  97.10% / 95%. Original generated IConsole exclusion retained. The original
  packages used aggregate coverage gates, not individual-module gates.
- `MIX_ENV=test mix hieroglyph.manifest --check` — passed.
- `mix doctor --raise --config-file .doctor-hieroglyph.exs` and
  `.doctor-cartouche.exs` under MIX_ENV=test — passed, preserving the 100% policies.
- `MIX_ENV=test mix sobelow --skip --exit low` — passed with original suppressions.
- `elixir test/alias_separation_test.exs` — 15 passed.
- `elixir test/consolidated_coverage_test.exs` — 5 passed; covers independent
  library/signer floors and missing-report rejection.
- `rmap validate` — valid. Shell syntax checks and `git diff --check` passed.
- Root and onchain `sync-agents-md.sh --check` — passed.

## Visible limitations and required follow-up

- Reach 2.8.4 `--dead-code --arch --smells` reproduces the old Cartouche timeout
  (`Task.Supervised.stream(30000)`) at the merged 109-file scope. As explicitly
  permitted by this task, onchain retains `--arch --smells`, with the timeout
  documented in its CLAUDE.md. No hand-written source scope was narrowed.
- `reach.check --arch --smells` reports one newly co-located repeated-map-shape
  finding: `lib/abi/function_selector.ex:383`, `lib/cartouche/filter.ex:124`, and
  generated IERC20 support. No suppression was added and no deduplication was
  attempted, per the move-only scope. Full QA therefore remains visibly red at
  this check until the later dedupe work addresses the integrated surface.
- Keeping `:cartouche` configuration keys produces Mix's warning that the old
  application is absent; the unchanged modules still read those keys correctly.
- Roadmap files were left untouched because harness explicitly resets/prohibits
  edits to them. The path-remapping acceptance criterion remains outstanding.
  Update pending tasks 2127, 2128, 2129, 2130, 2131, 2132, 2135, 2137, 9007,
  9013, 9014, 9015 and 9016, plus current task 9030, replacing old package
  prefixes in `touches` with `packages/onchain`. New work targets onchain's
  active README/CHANGELOG; original package documents are historical archives.
- No live provider tests, publish, retirement or full monorepo QA were run.
  The reviewer remains the acceptance gate; this report does not claim approval.
