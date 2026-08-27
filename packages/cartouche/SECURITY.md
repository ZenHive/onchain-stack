# Security Policy

`cartouche` is a low-level substrate for signing, transaction encoding, raw
JSON-RPC, and cryptographic primitives. Bugs here can leak key material, produce
malformed signed transactions, or move funds, so we take security reports
seriously.

## Supported Versions

This library is pre-1.0; only the current release line receives security fixes.

| Version | Supported          |
| ------- | ------------------ |
| 0.8.x   | :white_check_mark: |
| < 0.8   | :x:                |

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

Report privately through GitHub's **Security** tab on this repository:
**Security → Advisories → "Report a vulnerability"**
(<https://github.com/ZenHive/cartouche/security/advisories/new>).

This opens a private advisory visible only to you and the maintainers.

### In scope

- Signing and private-key handling (including recid/recovery paths)
- Transaction construction and serialization
- Cryptographic primitives
- Raw JSON-RPC request construction and response parsing

### Out of scope

- A compromised local environment or developer machine / key material
- Vulnerabilities in upstream dependencies — a heads-up is welcome.

### What to expect

- **Acknowledgement** within a few business days.
- A fix or mitigation plan communicated through the private advisory.
- Coordinated disclosure: we'll agree on a disclosure timeline with you before any public release.

Thank you for helping keep the stack safe.
