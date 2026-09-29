# Onchain Solana

See the root CLAUDE.md for the shared toolchain, sibling dependencies, and verification policy.

Solana modules live under Onchain.Solana; Base58 lives at Onchain.Solana.Base58.
Cartouche supplies shared HTTP, CloudKMS, Hex, and Signer.Backend helpers; do not duplicate them.
The application supervises configured Ed25519 signers. Existing :cartouche configuration
keys (:solana_node, :solana_timeout, :solana_signer, :req_options and per-module transport
options) are preserved; module keys use the Onchain.Solana namespace.

Run mix check.dispatch for formatting and compilation, then mix test for the migrated
Solana tests (including mocked KMS requests). No live credentials are needed.
Full post-merge QA uses mix ci, with 95% coverage and the shared gate helpers.
Publish builds must set ONCHAIN_PUBLISH=1 (DIST-10, docs/specs/onchain-distribution.md). Publishing remains human-gated.
