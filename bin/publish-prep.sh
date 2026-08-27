#!/usr/bin/env bash
# Onchain stack — publish pre-flight & handoff (monorepo layout, 2026-08-27).
#
# Does NOT publish. `mix hex.publish` is interactive (2FA) and stays a human
# step. This script runs the deterministic gauntlet and prints the exact
# command for you to run.
#
# Layout since the monorepo migration:
#   ~/_DATA/code/onchain-stack/packages/<pkg>   the eight in-repo packages
#     hieroglyph cartouche onchain onchain_aave onchain_aerodrome
#     onchain_evm onchain_js onchain_tempo
#   ~/_DATA/code/<repo>                          the three standalone repos
#     descripex zen_websocket mpp
# Each package is still its own Hex package with its own mix.exs, mix.lock and
# CHANGELOG; only the checkout moved. The Hex package name equals the directory
# name for all eleven.
#
# THE MONOREPO'S ONE NEW FAILURE CLASS. In-family deps are declared as
# `sibling(:name, "~> x.y")`. Inside the checkout (marker file
# `.onchain-monorepo-root` found by walking up) that becomes a path dep, so the
# `"~> x.y"` half is never exercised locally. With ONCHAIN_PUBLISH=1 — or from
# anywhere without the marker — it becomes the Hex requirement instead.
#
# Hex >= 2.5 does NOT abort on a path dep at build time: it silently DROPS it
# and prints "Dependencies excluded from the package (only Hex packages can be
# dependencies)". A tarball missing its sibling requirement installs fine and
# then fails at the consumer. So `check` runs the ENTIRE gauntlet with
# ONCHAIN_PUBLISH=1 exported, and treats that phrase as a hard failure.
#
# Side effect of that, and why the check restores state on the way out: a
# publish-mode `mix deps.get` re-resolves the siblings through Hex and rewrites
# the package's `mix.lock`. The check puts the lock back byte-for-byte when it
# finishes (success or failure). `deps/` and `_build/` are gitignored and are
# NOT restored — your next ordinary `mix deps.get` in that package puts the path
# deps back.
#
# Usage:
#   ./bin/publish-prep.sh status            # local-vs-Hex version table, all 11
#   ./bin/publish-prep.sh check <repo>      # pre-flight one repo (offline tests)
#   ./bin/publish-prep.sh check <repo> --integration   # also run integration tests
#
# Environment:
#   ONCHAIN_STACK_DIR   monorepo root  (default ~/_DATA/code/onchain-stack)
#   ONCHAIN_CODE_DIR    standalone repos' parent (default ~/_DATA/code)

set -uo pipefail

# Deliberately env-configurable rather than derived from ${BASH_SOURCE[0]}: the
# script is also run from a scratch copy during review, where SCRIPT_DIR/.. is
# not the monorepo.
STACK_DIR="${ONCHAIN_STACK_DIR:-$HOME/_DATA/code/onchain-stack}"
CODE_DIR="${ONCHAIN_CODE_DIR:-$HOME/_DATA/code}"

# The eight packages that live inside the monorepo. Order matters only within
# REPOS below; this list is membership, not sequence.
PACKAGES=(hieroglyph cartouche onchain onchain_aave onchain_aerodrome onchain_evm onchain_js onchain_tempo)

# Cascade order (upstream → downstream). status prints in this order.
# descripex + zen_websocket are shared upstreams (used beyond this family) — they
# head the cascade but a release there has a wider blast radius. zen_websocket
# feeds onchain directly, not hieroglyph. mpp is always last.
REPOS=(descripex zen_websocket hieroglyph cartouche onchain onchain_aave onchain_aerodrome onchain_evm onchain_js onchain_tempo mpp)

c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_dim=$'\033[2m'; c_rst=$'\033[0m'
# Colour only on a tty: the status table is routinely piped into a file or a
# grep, and raw escapes there defeat exact-match comparisons of a version cell.
[ -t 1 ] || { c_red=""; c_grn=""; c_yel=""; c_dim=""; c_rst=""; }

ok()   { printf '  %s✓%s %s\n' "$c_grn" "$c_rst" "$1"; }
warn() { printf '  %s!%s %s\n' "$c_yel" "$c_rst" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$c_red" "$c_rst" "$1"; }

# Is this repo one of the eight that live under packages/?
is_package() {
  local p
  for p in "${PACKAGES[@]}"; do [ "$p" = "$1" ] && return 0; done
  return 1
}

# Where a repo's checkout is. The single place the monorepo split is encoded —
# everything else in this script goes through it.
repo_dir() {
  if is_package "$1"; then
    printf '%s/packages/%s' "$STACK_DIR" "$1"
  else
    printf '%s/%s' "$CODE_DIR" "$1"
  fi
}

# Latest version published on Hex for a package (empty if unpublished).
hex_version() {
  local pkg="$1" dir
  dir="$(repo_dir "$pkg")"
  # Parse the first full semver under "Recent releases:" — the Config: {:pkg, "~> X.Y"}
  # line strips trailing .0 (1.5.0 → "1.5"), which broke equality vs local versions.
  (cd "$dir" 2>/dev/null && mix hex.info "$pkg" 2>/dev/null) \
    | sed -n '/Recent releases:/,$p' \
    | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# Local version from a repo's mix.exs (@version "x" or version: "x").
local_version() {
  local f; f="$(repo_dir "$1")/mix.exs"
  [ -f "$f" ] || { echo ""; return; }
  grep -Eo '(@version[[:space:]]+"|version:[[:space:]]*")[0-9][0-9.]*"' "$f" \
    | grep -Eo '[0-9][0-9.]+' | head -1
}

# Sibling package names this package declares, read from the source.
# Comment lines are stripped first: every package `mix.exs` documents the
# convention with a literal `sibling(:name, "<requirement>")` in a comment, and
# a naive grep would report a phantom dep called `name`. `defp sibling(name,
# req, ...)` is excluded for free — the definition has no leading colon.
sibling_names() {
  local f="$1"
  [ -f "$f" ] || return 0
  grep -vE '^[[:space:]]*#' "$f" \
    | grep -Eo 'sibling\(:[a-z0-9_]+' \
    | sed 's/^sibling(://' \
    | sort -u
}

cmd_status() {
  printf '%-20s %-12s %-12s %s\n' "REPO" "LOCAL" "HEX" "STATE"
  printf '%s\n' "----------------------------------------------------------------"
  for repo in "${REPOS[@]}"; do
    local loc hex state name
    loc="$(local_version "$repo")"
    hex="$(hex_version "$repo")"
    if [ -z "$hex" ]; then
      state="${c_yel}unpublished${c_rst}"
    elif [ "$loc" = "$hex" ]; then
      state="${c_dim}published${c_rst}"
    else
      state="${c_grn}local ahead → publish${c_rst}"
    fi
    # Indent the in-repo packages so the table shows the layout at a glance.
    if is_package "$repo"; then name="  $repo"; else name="$repo"; fi
    # ASCII "-" for unpublished, never an em-dash: printf pads by BYTES, so a
    # multi-byte glyph shrinks the visible column and skews that row.
    printf '%-20s %-12s %-12s %b\n' "$name" "${loc:-?}" "${hex:--}" "$state"
  done
  printf '\n%sIndented = packages/<name> inside %s; flush = standalone repo under %s.%s\n' \
    "$c_dim" "$STACK_DIR" "$CODE_DIR" "$c_rst"
  printf '%sVersions drift — this is a snapshot. semver bump is your judgment.%s\n' "$c_dim" "$c_rst"
}

# --------------------------------------------------------------- lock restore

# Set by cmd_check before it perturbs anything; read by the EXIT trap.
LOCK_FILE=""
LOCK_BACKUP=""

# Restore the package's mix.lock to exactly what it was before the publish-mode
# deps.get rewrote it. A byte copy rather than `git checkout -- mix.lock` on
# purpose: another session may already have had uncommitted lock edits in this
# package, and `git checkout` would silently discard their work. When the lock
# was clean going in, the two are equivalent.
restore_lock() {
  [ -n "$LOCK_BACKUP" ] || return 0
  if [ -f "$LOCK_BACKUP" ] && [ -f "$LOCK_FILE" ]; then
    if ! cmp -s "$LOCK_BACKUP" "$LOCK_FILE"; then
      cp "$LOCK_BACKUP" "$LOCK_FILE"
      printf '\n%srestored%s %s (the ONCHAIN_PUBLISH=1 deps.get had re-resolved the\n' \
        "$c_dim" "$c_rst" "$LOCK_FILE"
      printf 'siblings through Hex and rewritten it).\n'
      printf '%sdeps/ and _build/ still hold the Hex-resolved siblings — run a plain\n' "$c_dim"
      printf '`mix deps.get` in that package to put the path deps back.%s\n' "$c_rst"
    fi
  fi
  rm -f "$LOCK_BACKUP"
  LOCK_BACKUP=""
}

cmd_check() {
  local repo="$1"; shift || true
  local integration=0
  [ "${1:-}" = "--integration" ] && integration=1

  local dir; dir="$(repo_dir "$repo")"
  [ -d "$dir" ] || { bad "no such repo: $dir"; exit 2; }
  cd "$dir" || exit 2

  local pkg=0
  is_package "$repo" && pkg=1

  printf '%s== pre-flight: %s ==%s\n' "$c_dim" "$repo" "$c_rst"
  [ "$pkg" = 1 ] && printf '%s   packages/%s — running the whole gauntlet with ONCHAIN_PUBLISH=1%s\n' \
    "$c_dim" "$repo" "$c_rst"
  local fail=0

  # The publish-mode switch, exported once and inherited by every mix call
  # below. It must cover deps.get / compile / test as well as hex.build: a
  # tarball built from a tree whose deps were resolved as path deps is exactly
  # the failure this whole script exists to catch.
  if [ "$pkg" = 1 ]; then
    export ONCHAIN_PUBLISH=1
    LOCK_FILE="$dir/mix.lock"
    if [ -f "$LOCK_FILE" ]; then
      LOCK_BACKUP="$(mktemp "${TMPDIR:-/tmp}/publish-prep-lock.XXXXXX")"
      cp "$LOCK_FILE" "$LOCK_BACKUP"
    fi
    trap restore_lock EXIT
  fi

  # 1. clean working tree
  #
  # Path-scoped for a package: the monorepo holds eight of them plus the root,
  # and a parallel session's WIP three directories over is not this package's
  # problem. `git status --porcelain -- .` from inside the package is the
  # narrowest true statement.
  if [ "$pkg" = 1 ]; then
    if [ -z "$(git status --porcelain -- . 2>/dev/null)" ]; then ok "packages/$repo tree clean"
    else warn "packages/$repo has uncommitted changes — commit before publishing"; fi

    # Root files the package build reads. `shared/mix_helpers.exs` is loaded by
    # every package mix.exs (behind a File.exists? guard) and the root `mix.exs`
    # owns `mix onchain.bounds`, which is what proves the sibling requirements
    # still admit the in-repo versions. Neither is shipped in the tarball, so
    # dirt here cannot corrupt the artifact — it only means the gate you just
    # ran is not the gate anyone else will run. Warn, never fail.
    if [ -n "$(git status --porcelain -- "$STACK_DIR/shared" "$STACK_DIR/mix.exs" 2>/dev/null)" ]; then
      warn "monorepo root has uncommitted shared/ or mix.exs changes — commit them too,"
      warn "  or the gate you just ran is not the one the next checkout reproduces"
    fi
  else
    if [ -z "$(git status --porcelain)" ]; then ok "working tree clean"
    else warn "working tree dirty — commit/stage before publishing"; fi
  fi

  # 2. version delta vs Hex
  local loc hex; loc="$(local_version "$repo")"; hex="$(hex_version "$repo")"
  if [ -z "$hex" ]; then ok "version $loc (unpublished — first release)"
  elif [ "$loc" = "$hex" ]; then bad "version $loc already on Hex — bump @version first"; fail=1
  else ok "version $loc (Hex: $hex) — local ahead"; fi

  # 3. deps resolve
  #
  # Under ONCHAIN_PUBLISH=1 this is the real test of the sibling requirements:
  # it asks Hex to satisfy `~> x.y` from published releases. A failure here
  # usually means an upstream sibling has not been published yet — publish
  # upstream-first, one version at a time.
  local dg
  dg="$(mix deps.get 2>&1)"
  if [ $? -eq 0 ]; then ok "deps.get$([ "$pkg" = 1 ] && printf ' (siblings resolved from Hex)')"
  else
    bad "deps.get failed"; fail=1
    printf '%s\n' "$dg" | tail -15 | sed 's/^/      /'
    [ "$pkg" = 1 ] && printf '      %shint: an upstream sibling may not be on Hex at the required version yet.%s\n' "$c_dim" "$c_rst"
  fi

  # 3b. the siblings must now be HEX entries in mix.lock, not absent
  #
  # A path dep leaves no mix.lock entry at all, so "declared as a sibling but
  # missing from the lock" is precisely "the ONCHAIN_PUBLISH branch did not
  # fire". This is the positive counterpart to the hex.build phrase check in
  # step 8 — that one catches the drop, this one catches the cause.
  if [ "$pkg" = 1 ]; then
    local sibs missing=""
    sibs="$(sibling_names "$dir/mix.exs")"
    if [ -n "$sibs" ]; then
      local s
      while IFS= read -r s; do
        [ -n "$s" ] || continue
        grep -q "\"$s\": {:hex," mix.lock 2>/dev/null || missing="$missing $s"
      done <<<"$sibs"
      if [ -z "$missing" ]; then
        ok "sibling deps resolved as Hex deps ($(printf '%s' "$sibs" | tr '\n' ' '))"
      else
        bad "sibling(s) NOT resolved through Hex:$missing"
        bad "  ONCHAIN_PUBLISH=1 did not take effect — the tarball would ship without"
        bad "  those requirements. Check sibling/3 in packages/$repo/mix.exs."
        fail=1
      fi
    fi
  fi

  # 4. retired deps
  #
  # Capture first, grep second. `mix hex.audit | grep -q` under `set -o
  # pipefail` is a race: grep -q exits on the first match, mix dies on
  # SIGPIPE, and the pipeline reports failure even though the output said
  # "No retired ..." — hex.audit's trailing ignore_advisories warnings made
  # that race a near-certain loss.
  local ha
  ha="$(mix hex.audit 2>&1)"
  if printf '%s' "$ha" | grep -qi "No retired"; then ok "hex.audit clean"
  else warn "hex.audit flagged retired deps (review)"; fi

  # 5. compile warnings-as-errors
  if mix compile --warnings-as-errors >/dev/null 2>&1; then ok "compile --warnings-as-errors"
  else bad "compile failed (warnings-as-errors)"; fail=1; fi

  # 6. tests
  if [ "$integration" = 1 ]; then
    if mix test.json --include integration >/dev/null 2>&1; then ok "tests (incl. integration)"
    else bad "tests failed (integration)"; fail=1; fi
  else
    if mix test.json >/dev/null 2>&1; then ok "tests (offline)"
    else bad "tests failed (offline)"; fail=1; fi
  fi

  # 7. CHANGELOG mentions the version
  if [ -f CHANGELOG.md ] && grep -q "$loc" CHANGELOG.md; then ok "CHANGELOG mentions $loc"
  else warn "CHANGELOG.md has no entry for $loc"; fi

  # 8. packaging dry-run — output is EVIDENCE, not noise
  #
  # `mix hex.build` exits 0 while dropping a path dep from the package. The only
  # signal is the line it prints. Capture it, and treat the phrase as hard.
  local hb
  hb="$(mix hex.build 2>&1)"
  local hb_status=$?
  if [ "$hb_status" != 0 ]; then
    bad "hex.build failed (packaging/metadata)"; fail=1
    printf '%s\n' "$hb" | tail -15 | sed 's/^/      /'
  elif printf '%s' "$hb" | grep -qi 'excluded from the package'; then
    bad "hex.build SILENTLY EXCLUDED a dependency — the tarball is broken:"
    printf '%s\n' "$hb" | grep -i -A3 'excluded from the package' | sed 's/^/      /'
    bad "  A path dep reached the build. Hex >= 2.5 drops it instead of aborting,"
    bad "  so the published tarball would carry no requirement for it and the"
    bad "  consumer would fail at compile time. The ONCHAIN_PUBLISH=1 branch of"
    bad "  sibling/3 in packages/$repo/mix.exs did not fire."
    fail=1
  else
    ok "hex.build (packaging ok, no excluded deps)"
  fi

  echo
  if [ "$fail" = 0 ]; then
    printf '%sREADY.%s Publish (2FA required):\n' "$c_grn" "$c_rst"
    if [ "$pkg" = 1 ]; then
      # No `git push` in the handoff: the package is not its own repo any more.
      # Pushing is a monorepo-root action and covers all eight at once, so
      # gluing it onto a per-package publish line would push seven other
      # packages' commits as a side effect of releasing this one.
      # deps.get first: this script restores the DEV mix.lock on exit, and the
      # dev lock has no Hex entries for the siblings — hex.publish then fails
      # with "the dependency is not locked". Re-resolve in publish mode, publish,
      # and put the dev lock back afterwards.
      printf '    cd %s \\\n      && ONCHAIN_PUBLISH=1 mix deps.get \\\n      && ONCHAIN_PUBLISH=1 mix hex.publish \\\n      && git checkout -- mix.lock && mix deps.get\n' "$dir"
      printf '\n%sONCHAIN_PUBLISH=1 is not optional — without it hex.publish packages the\n' "$c_dim"
      printf 'path deps away and the tarball ships without its sibling requirements.\n'
      printf 'Push from the monorepo root (%s) separately; it covers every package.%s\n' "$STACK_DIR" "$c_rst"
    else
      printf '    cd %s && git push && mix hex.publish\n' "$dir"
    fi
  else
    printf '%sNOT READY%s — fix the ✗ items above, re-run.\n' "$c_red" "$c_rst"
    exit 1
  fi
}

case "${1:-}" in
  status) cmd_status ;;
  check)  shift; [ $# -ge 1 ] || { echo "usage: $0 check <repo> [--integration]" >&2; exit 2; }; cmd_check "$@" ;;
  -h|--help) awk 'NR>1 { if (/^#/) { sub(/^#[[:space:]]?/, ""); print } else exit }' "$0"; exit 0 ;;
  *) echo "usage: $0 {status | check <repo> [--integration]}" >&2; exit 2 ;;
esac
