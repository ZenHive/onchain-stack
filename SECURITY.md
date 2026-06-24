# Security Policy

`onchain_evm` provides EVM simulation, Solidity parsing, tracing, and codegen,
backed by a Rust (Rustler) NIF. Bugs in the native layer or in simulation/parsing
of untrusted bytecode or Solidity are security-relevant.

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
(<https://github.com/ZenHive/onchain_evm/security/advisories/new>).

This opens a private advisory visible only to you and the maintainers.

### In scope

- The Rust NIF boundary — memory safety and panics crossing the NIF
- EVM simulation of untrusted bytecode
- Solidity / source parsing of untrusted input
- Trace and codegen output

### Out of scope

- Vulnerabilities in the contracts being simulated
- Vulnerabilities in upstream dependencies — a heads-up is welcome.

### What to expect

- **Acknowledgement** within a few business days.
- A fix or mitigation plan communicated through the private advisory.
- Coordinated disclosure: we'll agree on a disclosure timeline with you before any public release.

Thank you for helping keep the stack safe.
