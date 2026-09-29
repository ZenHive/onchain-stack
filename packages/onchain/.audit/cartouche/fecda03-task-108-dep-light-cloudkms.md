---
sha: fecda03e520b507c8c7778435110cef2747471d3
short_sha: fecda03
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: findings-deferred
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: harness: agent delivery — task 108 Req/Goth dep-light CloudKMS backend

**Original commit:** fecda03 — `harness: agent delivery — task 108 Req/Goth dep-light CloudKMS backend — drop google_api_cloud_kms + google_gax + tesla`
**Author:** harness (auto-land; no PR review trail — expected for harness delivery)
**Files touched:** 9
**LOC:** ±485

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | —   | discuss-design | lib/cartouche/signer/cloud_kms.ex + solana/signer/cloud_kms.ex | ~40 lines of identical KMS-REST transport helpers duplicated across both signer modules (commit grew dup from ~4 → ~40 LOC) | **Deferred at user request** — not applied |
| 2 | —   | correctness (verified clean) | lib/cartouche/signer/cloud_kms.ex:112 | `Req.request(base_opts, [json: body])` two-arg keyword pattern | Verified correct against installed Req 0.6.2 (`new(opts1, opts2)` concatenates) — no fix |

## Auto-applied fixes

- (none) — correctness verdict is clean; the one structural finding was deferred by the user.

## Discuss-tier resolutions

- **Finding 1 (transport duplication), deferred:** `request/4`, `normalize_response/1`,
  `credential_token/1`, `req_options/0`, `get_public_key/2`, `asymmetric_sign/3`, and
  `@kms_base_url` are byte-identical across `Cartouche.Signer.CloudKMS` (secp256k1) and
  `Cartouche.Solana.Signer.CloudKMS` (Ed25519). Extraction to a shared private
  `Cartouche.Signer.CloudKMS.Transport` module is reversible (all `defp`, no public
  surface) but threads the per-signer config key (`req_options/0` reads
  `Application.get_env(:cartouche, __MODULE__)`, which differs per module). The user
  elected to defer; recorded here, not filed as an rmap task.

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: Req-pattern correctness (Codex independently verified `Req.request/2`
keyword+keyword, KMS REST shapes for getPublicKey/asymmetricSign, Goth `fetch!/2` return shape,
20 focused KMS tests passing).
Codex-only findings (verified): —
Codex-only findings (discarded as over-flag): —
Codex Category 1-6 verdict: **none — clean**.

## Notes

- ROADMAP Task 108 → done and Task 107 superseded are carried by sibling commit 212b940 (in-batch); Cat 6 ROADMAP-flip satisfied.
- CHANGELOG `[Unreleased]` rewritten to describe the dep-light rewrite — accurate, no gap.
- `.dialyzer_ignore.exs` + `mix.exs` `plt_ignore_apps` comments updated to match (Goth-only); `config/test.exs` Tesla.Mock adapter removed; the stale `# TODO: Tesla.Env.client()` comment removed. All consistent.
- New HTTP error-handling tests added (non-2xx `%Req.Response{}` + transport-error message) — coverage increase.
