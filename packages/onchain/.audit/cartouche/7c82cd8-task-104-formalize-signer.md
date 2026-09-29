---
sha: 7c82cd82b18d8120b1dbbbd2465c66b6d7633363
short_sha: 7c82cd8
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: Task 104: formalize signer backends as Cartouche.Signer.Backend behaviour

**Original commit:** 7c82cd8 — `Task 104: formalize signer backends as Cartouche.Signer.Backend behaviour`
**Author:** E.FU
**Files touched:** 19
**LOC:** ±902

**PR resolution:** no `(#NNN)` in subject; no PR resolvable via `gh` — direct push to
`development` (Cat 6 priority-4: no PR review trail recorded; the family convention per
`onchain-workspace.md` is no-PR ff-merge to `development`, so this is expected, not a defect).
No Linear link. No open Dependabot alerts / advisories cross-matched the diff.

## Summary

High-quality, faithful refactor that splits the **custody axis** (where the key lives) from
the **message axis** (what gets hashed) behind a new `Cartouche.Signer.Backend` behaviour with
a pure-payload contract. Eth-tx and Solana signing behaviour is preserved; the only net-new
runtime behaviour is `Cartouche.Recover.normalize_low_s/1` (EIP-2 low-s canonicalization), a
genuine correctness improvement that lets DER-decoded KMS/HSM backends inherit the malleability
fix. No correctness regression found in the live signing paths.

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 6   | doc-gap (verified) | lib/cartouche/signer/backend.ex:71 | `@callback public_key` doc said "64 bytes without 0x04 prefix"; `Address.from_public_key/1` matches `<<4, ...>>` and requires the 65-byte 0x04-prefixed SEC1 form | **applied** — corrected to "65 bytes including the leading 0x04 prefix" |
| 2 | 3   | bug (verified, latent) | lib/cartouche/signer/curvy.ex, signer/cloud_kms.ex (secp256k1 `sign_payload/2`) | Guard is only `is_binary/1`; a non-32-byte payload is signed as garbage rather than rejected. Footgun against the freshly-documented 32-byte-digest contract | recorded — no live trigger (every caller passes `keccak(message)` = 32 B); pre-existing (old `sign_digest` had no length guard); hardening to critical signing code is the active implementer's call |
| 3 | 4   | bug (verified, latent) | lib/cartouche/signer/cloud_kms.ex:88 | `{:ok, Curvy.Signature.parse(decoded_sig)}` can wrap a non-`%Curvy.Signature{}`; `normalize_low_s/1` would then raise FunctionClauseError | recorded — unchanged by this commit (parse-wrap is pre-existing); KMS-path only (optional dep, not locally testable); KMS does not emit malformed DER in practice |
| 4 | discuss-design | design | lib/cartouche/signer.ex, solana/signer.ex | `algorithm/1` callback is defined + implemented by every backend but never consumed — no curve-mismatch guard (Eth signer + ed25519 backend, or Solana + Curvy, would mis-dispatch) | recorded (Claude + Codex agree) — reversible; wiring curve-validation into both signers is scope-add to critical code, deferred to the active Task-104 implementer |
| 5 | 4   | doc-gap | roadmap/tasks.toml:1328 | Acceptance criterion names callbacks `get_address/...` + `sign/...`; shipped behaviour is `public_key/1` + `sign_payload/2` (better names) | recorded only — roadmap files are foreign-dirty WIP in the working tree; path-scoped staging forbids touching them |
| 6 | 5   | doc-gap | ROADMAP.md:177, roadmap/tasks.toml:1328 | Task 104 still `in_progress` with no `implemented` field though CHANGELOG presents the behaviour as landed | recorded only — roadmap files are foreign-dirty WIP; not flipped (avoid entangling another session's uncommitted roadmap edit + avoid inventing a status change) |

## Auto-applied fixes

- lib/cartouche/signer/backend.ex:71 — corrected the `@callback public_key` byte-layout doc
  (was "64 bytes without the 0x04 prefix"; the SEC1 uncompressed point is 65 bytes WITH the
  `0x04` prefix, which `Cartouche.Address.from_public_key/1` strips via `<<4, _::binary>>`).

## Discuss-tier resolutions

- Finding 4 (`algorithm/1` unused): no divergence — Claude and Codex agree it is a real but
  latent defensive gap. Reversible (additive guard or removal of the callback). Not applied:
  wiring curve-validation into `Cartouche.Signer.backend_sign/4` and
  `Cartouche.Solana.Signer.backend_sign/2` is a behavioural change to critical signing code on
  a task that is still `in_progress`; the warm implementer owns the strictness decision. The
  user can re-open via this report.

## Codex second-opinion

Status: dual-reviewer (background job task-mqrqyh91-u0tvkc, completed)
Independently verified by Codex: the Eth path keccaks in the caller, signs that digest, and
feeds the SAME digest to `find_recid_from_digest/3`; Curvy 0.3.1 `hash: :keccak` does NOT
re-hash (`hash_message/2` identity clause for non-`:sha*` algos) — confirming no double-hash and
that the "signs exactly the bytes" moduledoc claim is accurate (also independently checked from
`deps/curvy/lib/curvy.ex:309-312` in-session).
Corroborated findings: 4 (`algorithm/1` unused — Claude + Codex)
Codex-only findings (verified real): 1, 3 (latent), 5, 6 (doc drift)
Codex-only findings (discarded as over-flag): none
