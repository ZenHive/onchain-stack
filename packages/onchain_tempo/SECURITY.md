# Security Policy

`onchain_tempo` provides low-level Tempo blockchain primitives — 0x76 transaction
handling, signing, TIP-20 calldata encoding, and RPC. Bugs in this surface can
move funds or corrupt signed payloads, so we take security reports seriously.

## Supported Versions

This library is pre-1.0; only the current release line receives security fixes.

| Version | Supported          |
| ------- | ------------------ |
| 0.5.x   | :white_check_mark: |
| < 0.5   | :x:                |

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

Report privately through GitHub's **Security** tab on this repository:
**Security → Advisories → "Report a vulnerability"**
(<https://github.com/ZenHive/onchain_tempo/security/advisories/new>).

This opens a private advisory visible only to you and the maintainers.

### In scope

- Transaction construction, deserialization, and payment matching (`Onchain.Tempo.Transaction`)
- Signing and fee-payer co-signing (Curvy / recid recovery paths)
- TIP-20 selector and calldata encoding (`Onchain.Tempo.TIP20`)
- RPC broadcast / receipt parsing and event-log decoding

### Out of scope

- Vulnerabilities in upstream dependencies (`onchain`, `cartouche`, `req`) — report those to their respective projects, though we welcome a heads-up.
- Issues requiring a malicious local environment or compromised developer machine.

### What to expect

- **Acknowledgement** within a few business days.
- A fix or mitigation plan communicated through the private advisory.
- Coordinated disclosure: we'll agree on a disclosure timeline with you before any public release.

Thank you for helping keep the Tempo ecosystem safe.
