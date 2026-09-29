#!/usr/bin/env bash
set -euo pipefail
export ONCHAIN_PACKAGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ONCHAIN_CRATES="onchain_evm onchain_solidity"
exec "$ONCHAIN_PACKAGE_ROOT/../onchain/scripts/build-precompiled.sh" "$@"
