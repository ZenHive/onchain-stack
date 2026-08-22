# Test fixtures — Aave V3/V4 math oracle

Pinned official Solidity math, compiled to exact runtime bytecode, is the
independent oracle for `Onchain.Aave.Math` and `Onchain.Aave.Math.V4`. Elixir
never generates expected values for bytecode ops.

| File | Role |
|------|------|
| `wad_ray_wrapper.{sol,bin,json}` | V3 WadRayMath + MathUtils wrapper (aave-v3-origin@1e3d70c, solc 0.8.10) |
| `v4_math_wrapper.{sol,bin,json}` | V4 WadRayMath + MathUtils + liquidation bonus wrapper (aave/aave-v4@2524fe40, solc 0.8.28) |
| `math_oracle_vectors.json` | Domain-vector outputs from revm against those binaries |
| `math_verification_ledger.json` | Authority, compiler settings, bytecode hashes, mutator versions, survivor review |

`.json` provenance files pin solc version, optimizer flags, EVM version, upstream
commit, source SHA1s, and bytecode SHA256. Tests hash the `.bin` at setup —
drift fails loudly.

## Regenerating V3

Keep solc pinned at 0.8.10 to match Aave V3.

```bash
cargo install svm-rs
svm install 0.8.10

SOLC="$HOME/Library/Application Support/svm/0.8.10/solc-0.8.10"
cd test/fixtures
"$SOLC" --bin-runtime --optimize --optimize-runs 100000 --metadata-hash none wad_ray_wrapper.sol \
  | awk '/^Binary of the runtime part:/{flag=1;next} flag{printf "%s", $0; exit}' > wad_ray_wrapper.bin
shasum -a 256 wad_ray_wrapper.bin
```

## Regenerating V4

Compiler settings match `aave/aave-v4` `foundry.toml` profile.default.

```bash
svm install 0.8.28
SOLC="$HOME/Library/Application Support/svm/0.8.28/solc-0.8.28"
cd test/fixtures
"$SOLC" --bin-runtime --optimize --optimize-runs 44444444 --evm-version cancun --metadata-hash none v4_math_wrapper.sol \
  | awk '/^Binary of the runtime part:/{flag=1;next} flag{printf "%s", $0; exit}' > v4_math_wrapper.bin
shasum -a 256 v4_math_wrapper.bin
```

Then refresh goldens (requires RPC; writes `math_oracle_vectors.json`):

```bash
ETHEREUM_API_URL=http://localhost:8545 MIX_ENV=test mix run -e 'Onchain.Aave.MathOracle.generate_goldens!(Onchain.RPCCase.rpc_url!())'
```

The `awk 'printf "%s"'` form writes bytecode without a trailing newline. The
test hashes trimmed contents; a stray newline will fail the checksum.

## Design notes

- **Runtime bytecode, not deploy:** `state_overrides["code"]` injects the runtime portion.
- **`--metadata-hash none`:** reproducible across hosts.
- **V3 optimizer_runs 100000 / london:** Aave V3 deployment settings; solc 0.8.10 has no Paris.
- **V4 optimizer_runs 44444444 / cancun:** Aave V4 `foundry.toml` default profile.
