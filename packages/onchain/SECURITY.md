# Security Policy

`onchain` provides core EVM primitives — JSON-RPC, ABI, ERC token interfaces,
and signing. This surface constructs and signs transactions and decodes untrusted
chain data, so bugs can move funds or corrupt signed payloads.

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
(<https://github.com/ZenHive/onchain-stack/security/advisories/new>).

This opens a private advisory visible only to you and the maintainers.

### In scope

- Signing and transaction construction
- RPC request construction and receipt/response parsing
- ABI / ERC decoding of untrusted chain data and event-log decoding

### Out of scope

- Vulnerabilities in upstream dependencies (`cartouche`, `hieroglyph`, `req`) — report those to their projects, though a heads-up is welcome.
- A compromised local environment or developer machine.

### What to expect

- **Acknowledgement** within a few business days.
- A fix or mitigation plan communicated through the private advisory.
- Coordinated disclosure: we'll agree on a disclosure timeline with you before any public release.

Thank you for helping keep the stack safe.
