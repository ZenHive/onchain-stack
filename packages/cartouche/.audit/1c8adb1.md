# Audit — `1c8adb1` (range `4ccb2fc..1c8adb1`)

Post-merge hygiene pass over the work that landed since `audit(8872019...e8beee0)`. Fix-forward only; nothing reverted or blocked. No rmap tasks filed.

## Range reviewed

| Theme | Commits |
|---|---|
| Task 118 — Low-s as a library-wide invariant; close `sign_direct/4` bypass | `51b971c` |
| Task 112 — V4 `get_signature` onto `Signature.get/1`; V_2930 write surface | `82a990d` |
| Task 116 — enforce `Signer.Backend` at the boundary (payload length, curve, DER) | `7964cc8` |
| Task 70 — CLZ (EIP-7939) on the struct-log opcode whitelist | `403f09e` |
| RPC — label `Error(string)` reverts from their own selector | `4f7cfb1` |
| `mix check.dispatch` defined; GitHub Actions workflows removed | `81415fc`, `53b1686` |
| Releases 0.6.0 / 0.6.1 / 0.7.0 / 0.7.1, descripex/hieroglyph/req/bandit bumps | `64b7065` … `19adb46` |
| Generator: skip ABI items whose inputs/outputs are JSON null | `aec7a5a` |
| Signer specs: `GenServer.server()` matching doctests | `be2796a` |
| Reach smell cleanup; debug_traceCall behind `:debug_namespace` | `50cead4`, `5054cc3` |
| Roadmap / dep-audit watch / AGENTS.md regen | remaining commits in range |

## Findings

**1. (fixed) Task 118 shipped with no Unreleased CHANGELOG entry.**
`51b971c` closed the `sign_direct/4` low-s bypass — a consumer-facing change to the public signing API and to `CloudKMS.sign/7` — but `[Unreleased]` recorded tasks 112/116, the `Error(string)` label fix, CLZ, and `mix check.dispatch` and omitted 118. The Unreleased section also carried a second `### Added` that left the CLZ entry orphaned below Fixed. Added the 118 entry under Fixed (MFA carrier kept, funnel-enforced low-s) and folded CLZ into the first Added block.

**2. (fixed) Typed-tx `sign/2` specs still said `GenServer.name()` after this range settled `GenServer.server()`.**
`be2796a` widened `Cartouche.Signer.sign/3` (and Solana) to `GenServer.server()` because the doctests and tests pass a pid. Task 112 then added `V_2930.sign/2` by copying V3's stale spec, and V4 (touched in the same task for `get_signature`) kept the same lie on `sign/2` and `sign_authorization/2`. Tests in this range pass a signer pid into `V_2930.sign/2`. Widened V3/V4/V_2930 to `GenServer.server()` — `name()` is a subset, so this is a spec correction, not a behaviour change.

## Reviewed clean (no action)

- **Task 118 implementation** — `emit_signature/4` is the sole 65-byte funnel; both the `{backend, config}` path and `sign_direct/4` pass through `normalize_low_s/1` before recid search. MFA kept with the reason recorded in the `Cartouche.Signer` moduledoc. Tests stub a high-s MFA and a high-s Backend and assert packed `s <= n/2` plus recoverability.
- **Task 116** — 32-byte payload guards, `algorithm/1` consumed via `Backend.expect_algorithm/3`, CloudKMS DER parse returns `{:error, :invalid_signature}` instead of wrapping a non-struct. Matches the prior audit's recorded follow-ups (findings 2–4 of `7c82cd8`).
- **V_2930 write surface** — `encode/1` field order matches EIP-2930; unsigned payloads omit yParity/r/s; `Transaction.encode/1` dispatches `%V_2930{}`; signature helpers delegate to `Signature`. Mainnet type-1 vector round-trip is tested. Encode/decode conformance gaps (bare-address access lists, empty lists the EIP forbids) are already task 117 (`in_progress`); not re-filed.
- **`Error(string)` classification** — labelled from selector `0x08c379a0`; candidates must match their own 4-byte selector before attribution. Tests cover labelled Error(string) with and without `:errors`, custom-error hit, and unlisted selector staying unattributed.
- **CLZ whitelist** — closed list, compile-time atoms, test for `"CLZ"` plus the unknown-opcode raise.
- **`mix check.dispatch`** — defined, `MIX_ENV=test` via `def cli`, omits dialyzer / coverage / `agents.check` as documented. Workflows removed; CLAUDE.md / AGENTS.md / mix.exs comments agree that `mix ci` is the only remaining gate.
- **No leftover debug** — the only `IO.puts` in `lib/` is `Cartouche.VM.FFIs.log_ffi/1`, the console.sol FFI, not a stray debug print.
- **README Status still says `0.2.0` / `~> 0.2` while `mix.exs` is `0.7.1`.** Pre-existing across many releases in this range; CHANGELOG is the release record. Not introduced here; a rewrite is product copy, not a one-line hygiene fix. Not filed.

## Reviewer rejections

None recorded for this project.

## Cold check

`mix deps.get && MIX_ENV=test mix check.dispatch` in this un-warmed worktree (no copied `deps` / `_build` / PLTs): **passed** (exit 0; 1192 passed, 32 excluded, 0 failed).
