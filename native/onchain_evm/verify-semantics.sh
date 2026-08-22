#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
fixture_dir="$script_dir/testdata/semantics"
oracle_image="runtimeverificationinc/kontrol@sha256:858f004144d61b005997f56bb8b7cd15673850286c96e0e5ec0502d9c9a9e204"
oracle_platform="linux/amd64"

if ! docker image inspect "$oracle_image" >/dev/null 2>&1; then
  echo "Pinned KEVM/Kontrol image is unavailable: $oracle_image" >&2
  echo "Load that exact digest for $oracle_platform before verification." >&2
  exit 1
fi

echo "repository_commit=$(git -C "$script_dir/../.." rev-parse HEAD)"
cargo test --manifest-path "$script_dir/Cargo.toml" semantics_verification -- --nocapture

run_kevm() {
  local fixture_path="$1"
  local mode="$2"
  shift 2

  docker run --rm --platform "$oracle_platform" \
    -v "$fixture_path:/workspace/vector.json:ro" \
    "$oracle_image" \
    kevm-pyk run /workspace/vector.json --target llvm --mode "$mode" --chainid 1 "$@"
}

for fixture_name in call_output_1 create_empty_contract_with_storage \
    create_empty000_create_in_initcode_transaction revert_opcode; do
  run_kevm "$fixture_dir/official/$fixture_name.json" NORMAL >/dev/null
  echo "kevm_pass=$fixture_name"
done

for fixture_name in sstore_load_1 log1_non_empty_mem; do
  run_kevm "$fixture_dir/official/$fixture_name.json" VMTESTS --schedule FRONTIER >/dev/null
  echo "kevm_pass=$fixture_name"
done

negative_log="$(mktemp -t onchain-evm-kevm-negative.XXXXXX.log)"
set +e
run_kevm "$fixture_dir/negative/sstore_load_1_bad_storage.json" VMTESTS \
  --schedule FRONTIER >"$negative_log" 2>&1
negative_result=$?
set -e

if [[ "$negative_result" -eq 0 ]]; then
  echo "Invalid verification: corrupted storage control unexpectedly passed KEVM." >&2
  exit 1
fi

if ! grep -q 'check "account"' "$negative_log"; then
  echo "Invalid verification: KEVM failed without detecting the corrupted account state." >&2
  echo "KEVM output: $negative_log" >&2
  exit 1
fi

echo "kevm_expected_failure=sstore_load_1_bad_storage"
unlink "$negative_log"
