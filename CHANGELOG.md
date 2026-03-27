# Changelog

Completed roadmap tasks. For upcoming work, see [ROADMAP.md](ROADMAP.md).

---

## v0.1.0 — Project Setup

Initial project creation. Extracted JS bridge tasks from [onchain](https://github.com/ZenHive/onchain) Phase 9 into a dedicated library.

**Why:** QuickBEAM (Zig NIF) violates onchain's "pure Elixir, no native deps" principle. Following the portfolio pattern where each native runtime gets its own package (onchain_evm for Rust, onchain_js for Zig).

**What's included:**
- Project scaffold with supervision tree
- Dependencies: onchain (path), quickbeam, npm, descripex
- Dev tooling: ex_unit_json, dialyzer_json, styler, credo, dialyxir, doctor, sobelow, ex_doc
- Project documentation: CLAUDE.md, README.md, ROADMAP.md, CHANGELOG.md
- Roadmap with 7 tasks across 3 phases (migrated from onchain Phase 9)
