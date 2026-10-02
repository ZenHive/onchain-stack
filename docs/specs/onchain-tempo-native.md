# Tempo 0x76 native encoding

Rules for onchain_tempo's transaction encoding after task 9033 moves it onto
tempo-primitives (landed 21ed60e). Each rule's source follows it.

TEMPO-1: onchain_tempo's 0x76 transaction and 0x78 fee-payer encoding comes from tempo-primitives in a separate precompiled crate in packages/onchain_tempo; no hand-written 0x76/0x78 RLP encoding remains in Elixir.
  Source: task 9033 (acceptance criteria 4-5).

TEMPO-2: The 0x78 fee-payer signing preimage includes key_authorization when the transaction carries one.
  Source: task 9033 body (split_base_fields/1; tempo-primitives fee_payer_signature_hash).

TEMPO-3: For every fixture, with and without key_authorization, tx bytes, signing hash, tx hash, cosigned bytes and fee-payer preimage match tempo-primitives byte for byte; where the pre-migration encoder diverges, tempo-primitives and the Tempo spec win.
  Source: task 9033 (acceptance criteria 1-2).

TEMPO-4: Our signing stays Secp256k1; decode, serialize, hash, cosign and sender recovery accept every signature type tempo-primitives supports. Keychain recovery verifies the inner signature but does not establish on-chain access-key authorization.
  Source: task 9052 (operator-approved architecture, 2026-10-02).

TEMPO-5: Every supported sender signature type, including keychain V1/V2, P-256 and WebAuthn, round-trips byte-identically and recovers the sender against versioned independent ox vectors. Signing hashes, transaction hashes, key-authorization hashes and fee-payer cosigned bytes match the independent oracle. Malformed envelopes return errors without raising or crashing the VM.
  Source: task 9052 (acceptance criteria 1-4, 6).

TEMPO-6: The public Transaction struct represents every tempo-primitives TempoTransaction field by name, with typed signature and key-authorization unions. Serde maps and positional RLP field lists are not public API; JSON conversion occurs only at the internal NIF boundary.
  Source: task 9052 (operator-approved architecture, acceptance criterion 5).
