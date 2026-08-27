# Security Policy

`onchain_js` runs JavaScript / npm packages on the BEAM via QuickBEAM, backed by
Zig NIFs. Executing JS — potentially from untrusted bundles — together with the
native boundary makes this a security-sensitive surface.

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
(<https://github.com/ZenHive/onchain_js/security/advisories/new>).

This opens a private advisory visible only to you and the maintainers.

### In scope

- The Zig NIF boundary — memory safety and sandbox escape
- Evaluation of untrusted JavaScript / npm bundles
- The Elixir↔JS bridge and handler exposure
- Runtime pool / context isolation

### Out of scope

- Vulnerabilities within the npm packages you choose to load
- Vulnerabilities in upstream dependencies — a heads-up is welcome.

### What to expect

- **Acknowledgement** within a few business days.
- A fix or mitigation plan communicated through the private advisory.
- Coordinated disclosure: we'll agree on a disclosure timeline with you before any public release.

Thank you for helping keep the stack safe.
