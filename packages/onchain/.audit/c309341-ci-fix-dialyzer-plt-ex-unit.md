---
sha: c309341d2ac6610589c73121f175d28dafdbcfc8
short_sha: c309341
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: clean — fast-path
codex_status: not-dispatched
audited_by: audit-review v1
---

# Audit: ci: fix dialyzer on Elixir 1.20/OTP29 — add :ex_unit to PLT, spec flunk helper

**Reason for fast-path:** 4 LOC, no production-code paths (mix.exs PLT config + test/support helper).
**Author:** E.FU
**Files touched:** mix.exs, test/support/rpc_case.ex
