# Tempo 0x76 native encoding

Rules for onchain_tempo's transaction encoding after task 9033 moves it onto
tempo-primitives. Status is `draft` until 9033 lands. Each rule's source
follows it.

TEMPO-1: onchain_tempo's 0x76 transaction and 0x78 fee-payer encoding comes from tempo-primitives in a separate precompiled crate in packages/onchain_tempo; no hand-written 0x76/0x78 RLP encoding remains in Elixir.
  Source: task 9033 (acceptance criteria 4-5).

TEMPO-2: The 0x78 fee-payer signing preimage includes key_authorization when the transaction carries one.
  Source: task 9033 body (split_base_fields/1; tempo-primitives fee_payer_signature_hash).

TEMPO-3: For every fixture, with and without key_authorization, tx bytes, signing hash, tx hash, cosigned bytes and fee-payer preimage match tempo-primitives byte for byte; where the pre-migration encoder diverges, tempo-primitives and the Tempo spec win.
  Source: task 9033 (acceptance criteria 1-2).

TEMPO-4: Signing stays Secp256k1-only, and the public functions build, cosign_fee_payer/3, has_fee_payer_placeholder?/1 and decode keep their return contracts.
  Source: task 9033 (acceptance criterion 5, body).
