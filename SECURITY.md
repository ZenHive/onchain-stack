# Security Policy

`onchain_aave` wraps Aave V3 protocol interactions — calldata construction for
supply/borrow/repay/withdraw and position reads. Mis-encoded calldata or a
misread position can move or risk funds, so we take security reports seriously.

## Supported Versions

This library is pre-1.0; only the current release line receives security fixes.

| Version | Supported          |
| ------- | ------------------ |
| 0.2.x   | :white_check_mark: |
| < 0.2   | :x:                |

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

Report privately through GitHub's **Security** tab on this repository:
**Security → Advisories → "Report a vulnerability"**
(<https://github.com/ZenHive/onchain_aave/security/advisories/new>).

This opens a private advisory visible only to you and the maintainers.

### In scope

- Aave V3 calldata construction and parameter/selector encoding
- Reserve-data and position decoding

### Out of scope

- The Aave V3 protocol contracts themselves
- Vulnerabilities in upstream dependencies (`onchain`, `onchain_evm`) — a heads-up is welcome.

### What to expect

- **Acknowledgement** within a few business days.
- A fix or mitigation plan communicated through the private advisory.
- Coordinated disclosure: we'll agree on a disclosure timeline with you before any public release.

Thank you for helping keep the stack safe.
