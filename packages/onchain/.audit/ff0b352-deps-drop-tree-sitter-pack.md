---
sha: ff0b352c18554c55bfe4804a5d5e42851e1a396a
short_sha: ff0b352
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: clean — fast-path
codex_status: not-dispatched
audited_by: audit-review v1
---

# Audit: deps: drop tree_sitter_language_pack — Erigon scraper now pure-Elixir regex

**Reason for fast-path:** 85 LOC, no production-code paths (dev mix task + mix.exs + CHANGELOG; scraper lives under dev/, not lib/).
**Author:** E.FU
**Files touched:** CHANGELOG.md, dev/mix/tasks/onchain.scrape_erigon_methods.ex, mix.exs
