#!/usr/bin/env bash
# Onchain stack — publish pre-flight & handoff.
#
# Does NOT publish. `mix hex.publish` is interactive (2FA) and stays a human
# step. This script runs the deterministic gauntlet and prints the exact
# command for you to run.
#
# Usage:
#   ./bin/publish-prep.sh status            # local-vs-Hex version table for all repos
#   ./bin/publish-prep.sh check <repo>      # pre-flight one repo (offline tests)
#   ./bin/publish-prep.sh check <repo> --integration   # also run integration tests
#
# <repo> is the directory name (e.g. onchain_evm). Repos live at
# ~/_DATA/code/<repo>; the Hex package name equals the repo name for all 10.

set -uo pipefail

CODE_DIR="${ONCHAIN_CODE_DIR:-$HOME/_DATA/code}"

# Cascade order (upstream → downstream). status prints in this order.
# descripex + zen_websocket are shared upstreams (used beyond this family) — they
# head the cascade but a release there has a wider blast radius. zen_websocket
# feeds onchain directly, not hieroglyph.
REPOS=(descripex zen_websocket hieroglyph cartouche onchain onchain_aave onchain_evm onchain_js onchain_tempo mpp)

c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_dim=$'\033[2m'; c_rst=$'\033[0m'
ok()   { printf '  %s✓%s %s\n' "$c_grn" "$c_rst" "$1"; }
warn() { printf '  %s!%s %s\n' "$c_yel" "$c_rst" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$c_red" "$c_rst" "$1"; }

# Latest version published on Hex for a package (empty if unpublished).
hex_version() {
  local pkg="$1"
  # Parse the first full semver under "Recent releases:" — the Config: {:pkg, "~> X.Y"}
  # line strips trailing .0 (1.5.0 → "1.5"), which broke equality vs local versions.
  (cd "$CODE_DIR/$pkg" 2>/dev/null && mix hex.info "$pkg" 2>/dev/null) \
    | sed -n '/Recent releases:/,$p' \
    | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# Local version from a repo's mix.exs (@version "x" or version: "x").
local_version() {
  local repo="$1" f="$CODE_DIR/$1/mix.exs"
  [ -f "$f" ] || { echo ""; return; }
  grep -Eo '(@version[[:space:]]+"|version:[[:space:]]*")[0-9][0-9.]*"' "$f" \
    | grep -Eo '[0-9][0-9.]+' | head -1
}

cmd_status() {
  printf '%-16s %-12s %-12s %s\n' "REPO" "LOCAL" "HEX" "STATE"
  printf '%s\n' "------------------------------------------------------------"
  for repo in "${REPOS[@]}"; do
    local loc hex state
    loc="$(local_version "$repo")"
    hex="$(hex_version "$repo")"
    if [ -z "$hex" ]; then
      state="${c_yel}unpublished${c_rst}"
    elif [ "$loc" = "$hex" ]; then
      state="${c_dim}published${c_rst}"
    else
      state="${c_grn}local ahead → publish${c_rst}"
    fi
    printf '%-16s %-12s %-12s %b\n' "$repo" "${loc:-?}" "${hex:-—}" "$state"
  done
  printf '\n%sVersions drift — this is a snapshot. semver bump is your judgment.%s\n' "$c_dim" "$c_rst"
}

cmd_check() {
  local repo="$1"; shift || true
  local integration=0
  [ "${1:-}" = "--integration" ] && integration=1
  local dir="$CODE_DIR/$repo"
  [ -d "$dir" ] || { bad "no such repo: $dir"; exit 2; }
  cd "$dir" || exit 2

  printf '%s== pre-flight: %s ==%s\n' "$c_dim" "$repo" "$c_rst"
  local fail=0

  # 1. clean working tree
  if [ -z "$(git status --porcelain)" ]; then ok "working tree clean"
  else warn "working tree dirty — commit/stage before publishing"; fi

  # 2. version delta vs Hex
  local loc hex; loc="$(local_version "$repo")"; hex="$(hex_version "$repo")"
  if [ -z "$hex" ]; then ok "version $loc (unpublished — first release)"
  elif [ "$loc" = "$hex" ]; then bad "version $loc already on Hex — bump @version first"; fail=1
  else ok "version $loc (Hex: $hex) — local ahead"; fi

  # 3. deps resolve
  if mix deps.get >/dev/null 2>&1; then ok "deps.get"; else bad "deps.get failed"; fail=1; fi

  # 4. retired deps
  if mix hex.audit 2>&1 | grep -qi "No retired"; then ok "hex.audit clean"
  else warn "hex.audit flagged retired deps (review)"; fi

  # 5. compile warnings-as-errors
  if mix compile --warnings-as-errors >/dev/null 2>&1; then ok "compile --warnings-as-errors"
  else bad "compile failed (warnings-as-errors)"; fail=1; fi

  # 6. tests
  if [ "$integration" = 1 ]; then
    if mix test --include integration >/dev/null 2>&1; then ok "tests (incl. integration)"
    else bad "tests failed (integration)"; fail=1; fi
  else
    if mix test >/dev/null 2>&1; then ok "tests (offline)"
    else bad "tests failed (offline)"; fail=1; fi
  fi

  # 7. CHANGELOG mentions the version
  if [ -f CHANGELOG.md ] && grep -q "$loc" CHANGELOG.md; then ok "CHANGELOG mentions $loc"
  else warn "CHANGELOG.md has no entry for $loc"; fi

  # 8. packaging dry-run
  if mix hex.build >/dev/null 2>&1; then ok "hex.build (packaging ok)"
  else bad "hex.build failed (packaging/metadata)"; fail=1; fi

  echo
  if [ "$fail" = 0 ]; then
    printf '%sREADY.%s Push, then publish (2FA required):\n' "$c_grn" "$c_rst"
    printf '    cd %s && git push && mix hex.publish\n' "$dir"
  else
    printf '%sNOT READY%s — fix the ✗ items above, re-run.\n' "$c_red" "$c_rst"
    exit 1
  fi
}

case "${1:-}" in
  status) cmd_status ;;
  check)  shift; [ $# -ge 1 ] || { echo "usage: $0 check <repo> [--integration]" >&2; exit 2; }; cmd_check "$@" ;;
  *) echo "usage: $0 {status | check <repo> [--integration]}" >&2; exit 2 ;;
esac
