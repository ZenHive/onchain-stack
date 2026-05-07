# Test fixtures — Aave V3 math wrapper bytecode

`wad_ray_wrapper.{sol,bin,json}` are consumed by `test/onchain/aave/math_revm_test.exs` to cross-validate `Onchain.Aave.Math` against the canonical Solidity bodies via revm.

- `wad_ray_wrapper.sol` — wrapper source. Bodies are inlined verbatim from `aave-v3-origin@1e3d70c`.
- `wad_ray_wrapper.bin` — deployed (runtime) bytecode. Hex string, no `0x` prefix, no trailing newline processing required by the test.
- `wad_ray_wrapper.json` — provenance: solc version, optimizer flags, EVM version, upstream pin + file SHA1s, bytecode SHA256. The test asserts the bytecode matches this checksum at setup time — drift fails loudly.

## Regenerating

Only needed when bumping the Aave pin, modifying the wrapper source, or updating the solc toolchain. Keep solc pinned at 0.8.10 to match Aave V3.

```bash
# One-time: install svm-rs + solc 0.8.10
cargo install svm-rs
svm install 0.8.10
svm use 0.8.10

# Compile (run from this directory)
cd test/fixtures
solc --bin-runtime --optimize --optimize-runs 100000 --metadata-hash none wad_ray_wrapper.sol \
  | awk '/^Binary of the runtime part:/{flag=1;next} flag{printf "%s", $0; exit}' > wad_ray_wrapper.bin

# Update checksum in provenance JSON
shasum -a 256 wad_ray_wrapper.bin
```

Then edit `wad_ray_wrapper.json` — update `bin_sha256`, `compiled_at`, and any source SHA1s (recompute with `shasum <file>` on the upstream sources) if the Aave pin changed.

The `awk 'printf "%s"'` form deliberately writes the bytecode without a trailing newline. Keep it that way: the test reads the file and trims whitespace before hashing, so any trailing whitespace (e.g. a stray newline added by hand-editing) will produce a hash that no longer matches the `bin_sha256` recorded by `shasum`.

## Design notes

- **Runtime bytecode, not deploy:** `state_overrides["code"]` in revm injects the runtime portion (what lives at an address after deployment), so we strip the constructor.
- **`--metadata-hash none`:** keeps builds reproducible across hosts. With the default ipfs hash, the bytecode would change whenever the file path or timestamp changed.
- **`--optimize --optimize-runs 100000`:** matches Aave V3's deployment settings.
- **EVM version `london`:** solc 0.8.10's default. Paris (the plan's original suggestion) is not available in this compiler. The pure arithmetic under test has no fork-dependent opcodes, so this is immaterial.
