# Security Policy

`hieroglyph` implements Ethereum ABI encoding and decoding (`ABI.*`). It
routinely decodes untrusted on-chain data and encodes calldata that moves funds,
so malformed input that corrupts a decoded value or mis-encodes a call is a
security concern.

## Supported Versions

Only the current release line receives security fixes.

| Version | Supported          |
| ------- | ------------------ |
| 1.6.x   | :white_check_mark: |
| < 1.6   | :x:                |

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

Report privately through GitHub's **Security** tab on this repository:
**Security → Advisories → "Report a vulnerability"**
(<https://github.com/ZenHive/onchain-stack/security/advisories/new>).

This opens a private advisory visible only to you and the maintainers.

### In scope

- ABI decoding of untrusted / on-chain data
- ABI and calldata encoding, type handling, and selector computation
- The yecc/leex function-signature parser

### Out of scope

- Correctness of ABIs supplied by the caller
- Vulnerabilities in upstream dependencies — a heads-up is welcome.

### What to expect

- **Acknowledgement** within a few business days.
- A fix or mitigation plan communicated through the private advisory.
- Coordinated disclosure: we'll agree on a disclosure timeline with you before any public release.

Thank you for helping keep the stack safe.
