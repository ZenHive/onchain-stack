#!/usr/bin/env bash
# Cross-build rustler_precompiled artifacts for both NIF crates from one
# Apple Silicon Mac. No CI. Upload the tarballs to a GitHub Release; the
# checksum step downloads what was uploaded, so artifacts must be live first:
#
#   1. tag and push (v$VERSION)
#   2. scripts/build-precompiled.sh
#   3. gh release create / gh release upload the .so.tar.gz artifacts
#   4. mix rustler_precompiled.download Onchain.EVM --all --print
#      mix rustler_precompiled.download Onchain.Solidity --all --print
#   5. commit checksum-Elixir.Onchain.EVM.exs checksum-Elixir.Onchain.Solidity.exs
#   6. mix hex.publish
#
# Adding riscv64gc-unknown-linux-gnu or arm-unknown-linux-gnueabihf is a
# one-line append to TARGETS below. Do not add a Windows target without
# solving cargo-zigbuild's msvc gap and the erl_nif import-lib link.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Shipped rustc triples — must match Onchain.Precompiled.targets/0.
TARGETS=(
  aarch64-apple-darwin
  x86_64-apple-darwin
  x86_64-unknown-linux-gnu
  aarch64-unknown-linux-gnu
  x86_64-unknown-linux-musl
)

CRATES=(onchain_evm onchain_solidity)

# Pin the glibc floor. Unsuffixed, Zig picks a default that drifts with the
# Zig release. An invalid suffix silently falls back, so assert_glibc_floor
# checks the artifact rather than trusting the build to fail loudly.
GLIBC_VERSION="${GLIBC_VERSION:-2.28}"
NIF_VERSION="${NIF_VERSION:-2.15}"

VERSION="$(awk -F'"' '/^  @version / { print $2; exit }' mix.exs)"
if [[ -z "$VERSION" ]]; then
  echo "error: could not read @version from mix.exs" >&2
  exit 1
fi
OUT_DIR="${OUT_DIR:-"$ROOT/artifacts/precompiled/v${VERSION}"}"

usage() {
  cat <<EOF
Usage: $0 [--dry-run]

Cross-build every shipped target for both NIF crates with cargo-zigbuild.
Artifacts land in ${OUT_DIR}/ as rustler_precompiled tarball names.

  --dry-run   print planned artifacts and exit (no toolchain required)
EOF
}

DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

zig_target() {
  local target="$1"
  case "$target" in
    *-linux-gnu) printf '%s.%s' "$target" "$GLIBC_VERSION" ;;
    *) printf '%s' "$target" ;;
  esac
}

lib_suffix() {
  case "$1" in
    *-apple-*) printf 'dylib' ;;
    *) printf 'so' ;;
  esac
}

artifact_name() {
  local crate="$1" target="$2"
  printf 'lib%s-v%s-nif-%s-%s.so.tar.gz' "$crate" "$VERSION" "$NIF_VERSION" "$target"
}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: missing $1" >&2
    exit 1
  }
}

assert_glibc_floor() {
  local so="$1" target="$2"
  local versions needed highest

  versions="$(strings "$so" | grep -E '^GLIBC_[0-9]' || true)"

  case "$target" in
    *-linux-musl)
      if [[ -n "$versions" ]]; then
        echo "error: $so is musl but defines GLIBC symbols:" >&2
        echo "$versions" >&2
        exit 1
      fi
      return 0
      ;;
    *-linux-gnu) ;;
    *) return 0 ;;
  esac

  if [[ -z "$versions" ]]; then
    echo "error: $so is linux-gnu but defines no GLIBC_* versions" >&2
    exit 1
  fi

  needed="$(printf '%s\n' "$versions" | sed 's/^GLIBC_//' | sort -V | tail -1)"
  highest="$(printf '%s\n%s\n' "$needed" "$GLIBC_VERSION" | sort -V | tail -1)"
  if [[ "$highest" != "$GLIBC_VERSION" ]]; then
    echo "error: $so requires GLIBC_${needed}, above the pinned floor ${GLIBC_VERSION}" >&2
    echo "$versions" >&2
    exit 1
  fi
}

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "version=${VERSION} nif=${NIF_VERSION} glibc=${GLIBC_VERSION}"
  for crate in "${CRATES[@]}"; do
    for target in "${TARGETS[@]}"; do
      printf '%s %s -> %s (zig --target %s)\n' \
        "$crate" "$target" "$(artifact_name "$crate" "$target")" "$(zig_target "$target")"
    done
  done
  exit 0
fi

need cargo
need rustup
need zig
need tar
need strings
if ! cargo zigbuild -h >/dev/null 2>&1; then
  echo "error: cargo zigbuild not installed. cargo install cargo-zigbuild" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
if compgen -G "${OUT_DIR}/*.tar.gz" >/dev/null; then
  echo "error: output directory already contains precompiled artifacts: $OUT_DIR" >&2
  echo "use an empty OUT_DIR so a release upload cannot include stale targets" >&2
  exit 1
fi
export RUSTLER_NIF_VERSION="$NIF_VERSION"

for target in "${TARGETS[@]}"; do
  rustup target add "$target" >/dev/null
done

for crate in "${CRATES[@]}"; do
  crate_dir="$ROOT/native/$crate"
  for target in "${TARGETS[@]}"; do
    zt="$(zig_target "$target")"
    echo "==> ${crate} ${zt}"
    (cd "$crate_dir" && cargo zigbuild --release --target "$zt")

    built="${crate_dir}/target/${target}/release/lib${crate}.$(lib_suffix "$target")"
    if [[ ! -f "$built" ]]; then
      echo "error: expected $built" >&2
      exit 1
    fi

    assert_glibc_floor "$built" "$target"

    final="lib${crate}-v${VERSION}-nif-${NIF_VERSION}-${target}.so"
    staging="$(mktemp -d)"
    cp "$built" "${staging}/${final}"
    tar -C "$staging" -czf "${OUT_DIR}/$(artifact_name "$crate" "$target")" "$final"
    unlink "${staging}/${final}"
    rmdir "$staging"
    echo "    wrote ${OUT_DIR}/$(artifact_name "$crate" "$target")"
  done
done

echo "done. upload ${OUT_DIR}/*.tar.gz to the v${VERSION} GitHub Release."
