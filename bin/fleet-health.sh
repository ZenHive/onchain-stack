#!/usr/bin/env bash
# Onchain stack — cross-repo health sweep (monorepo layout, 2026-08-27).
#
# One table for the whole family: git state, toolchain pin, outdated Hex deps,
# retired deps, known vulnerabilities, open GitHub issues/PRs, and open
# Dependabot security alerts.
#
# THE LAYOUT, and why rows no longer all mean the same thing. Eight of the
# packages now live inside ONE git repo:
#
#   ~/_DATA/code/onchain-stack            the monorepo root  (row: onchain-stack)
#     packages/hieroglyph  cartouche  onchain  onchain_aave
#     packages/onchain_aerodrome  onchain_evm  onchain_js  onchain_tempo
#   ~/_DATA/code/descripex | zen_websocket | mpp   standalone repos, unchanged
#
# So the columns are split by what actually varies per row:
#
#   onchain-stack row  — git (fetch, ahead/behind, repo-wide dirty), TOOLCH
#                        (the root `.tool-versions`, the only one there is), and
#                        the GitHub columns (issues/PRs/Dependabot of the
#                        monorepo remote). Carries no dep columns: the root
#                        project is analyzer-only and is not a Hex package.
#   package rows       — the dep columns (hex.outdated, hex.audit, deps.audit,
#                        each run in packages/<name> where that package's own
#                        mix.lock lives) plus a package-scoped dirty count.
#                        Their GIT ahead/behind, TOOLCH and GitHub cells read
#                        `-`: those facts belong to the onchain-stack row and
#                        repeating one number eight times would imply eight
#                        independent measurements. It also means eight fewer
#                        `git fetch`es and 24 fewer gh API calls per sweep.
#   external rows      — everything, exactly as before.
#
# Only the onchain-stack row and the three external rows fetch, so no two probes
# ever `git fetch` the same repository concurrently.
#
# There is no CI column and no code-scanning column: the family removed its
# GitHub Actions workflows on 2026-08-22 and `mix ci` is the whole gate, run
# locally before a push. A `gh run list` against a repo with no workflows
# returns an empty list, which would render as a reassuring `ok` — an absent
# gate must not look like a passing one, so the column is gone rather than
# always-green. Dependabot ALERTS stay: they come from the dependency graph,
# not from a workflow, and survive the removal.
#
# READ-ONLY by design. It never runs `mix deps.get`, never publishes, never
# writes to a repo, and never sets ONCHAIN_PUBLISH — every dep column is read
# through the monorepo's own path-dep resolution, which is what a developer
# actually builds against. (Whether the published Hex requirements still hold is
# a different question, answered by `mix onchain.bounds` at the root and by
# publish-prep.sh.) `git fetch` is the only remote write-ish thing it does and
# `--no-fetch` turns that off. That matters: the "dirty tree" column is only
# meaningful if the sweep itself cannot dirty a tree.
#
# The advisory database freshness gate runs ONCE, not per repo. mix_audit reads
# a single shared clone (see bin/advisory-freshness.sh); every package audits
# against the same copy, so N fetches would be N-1 wasted ones. If that gate
# fails, every VULN cell reads `?` — a stale database prints "No vulnerabilities
# found" and exits 0 (mirego/mix_audit#61), so an unverified green is not a green.
#
# Usage:
#   ./bin/fleet-health.sh                    # sweep everything
#   ./bin/fleet-health.sh onchain cartouche  # sweep named repos/packages only
#   ./bin/fleet-health.sh --json             # machine-readable, one object per row
#
# Options:
#   --no-fetch     skip `git fetch` (fast; ahead/behind may be stale)
#   --no-gh        skip all GitHub queries (offline / no gh auth)
#   --no-hex       skip hex.outdated + hex.audit (the slow, network-bound part)
#   --no-audit     skip the advisory gate + deps.audit
#   -j N           parallel probes (default 4)
#   --json         emit JSON instead of the table
#   -h, --help     this header
#
# Environment:
#   ONCHAIN_STACK_DIR   monorepo root  (default ~/_DATA/code/onchain-stack)
#   ONCHAIN_CODE_DIR    standalone repos' parent (default ~/_DATA/code)
#
# Exit status:
#   0  nothing actionable found
#   1  a HARD finding: vulnerability, retired dep, open Dependabot alert, an
#      unverifiable advisory database, or a toolchain divergence. Outdated deps,
#      open issues/PRs and a dirty tree are reported but do NOT fail — they are
#      normal working state.
#   2  usage error

set -uo pipefail

# Deliberately env-configurable rather than derived from ${BASH_SOURCE[0]}: the
# script is also run from a scratch copy during review, where SCRIPT_DIR/.. is
# not the monorepo.
STACK_DIR="${ONCHAIN_STACK_DIR:-$HOME/_DATA/code/onchain-stack}"
CODE_DIR="${ONCHAIN_CODE_DIR:-$HOME/_DATA/code}"
GH_ORG="${ONCHAIN_GH_ORG:-ZenHive}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The monorepo root's own row. Not a Hex package; it is where git, the toolchain
# pin and the GitHub state for all eight packages actually live.
ROOT_ROW="onchain-stack"

# The eight packages that live under $STACK_DIR/packages/.
PACKAGES=(hieroglyph cartouche onchain onchain_aave onchain_aerodrome onchain_evm onchain_js onchain_tempo)

# Cascade order (upstream → downstream), same order publish-prep.sh uses, with
# the monorepo root inserted ahead of the packages it contains.
ALL_REPOS=(descripex zen_websocket "$ROOT_ROW" hieroglyph cartouche onchain onchain_aave onchain_aerodrome onchain_evm onchain_js onchain_tempo mpp)

# The one toolchain the whole family builds on. In the monorepo there is now
# exactly ONE `.tool-versions` for the eight packages — the root's — which is
# the layout this column always wanted: a per-package pin could not diverge
# without someone adding a file that has no reason to exist. The three external
# repos each still carry their own, and those are what the column watches for
# drift now.
#
# Bumping the family toolchain means editing these two lines AND four
# `.tool-versions` files (the monorepo root plus descripex, zen_websocket, mpp);
# the TOOLCHAIN column is what makes forgetting one visible instead of silent.
CANON_ERLANG="${ONCHAIN_CANON_ERLANG:-29.0.3}"
CANON_ELIXIR="${ONCHAIN_CANON_ELIXIR:-1.20.2-otp-29}"

DO_FETCH=1
DO_GH=1
DO_HEX=1
DO_AUDIT=1
AS_JSON=0
JOBS=4
REPOS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --no-fetch) DO_FETCH=0; shift ;;
    --no-gh)    DO_GH=0; shift ;;
    --no-hex)   DO_HEX=0; shift ;;
    --no-audit) DO_AUDIT=0; shift ;;
    --json)     AS_JSON=1; shift ;;
    -j)         JOBS="${2:-4}"; shift 2 ;;
    # Print the whole leading comment block rather than a hardcoded line range:
    # a range silently truncates the help the moment the header grows.
    -h|--help)  awk 'NR>1 { if (/^#/) { sub(/^#[[:space:]]?/, ""); print } else exit }' "$0"; exit 0 ;;
    -*)         echo "fleet-health: unknown option '$1'" >&2; exit 2 ;;
    *)          REPOS+=("$1"); shift ;;
  esac
done

[ "${#REPOS[@]}" -eq 0 ] && REPOS=("${ALL_REPOS[@]}")

c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_dim=$'\033[2m'; c_bld=$'\033[1m'; c_rst=$'\033[0m'
[ -t 1 ] || { c_red=""; c_grn=""; c_yel=""; c_dim=""; c_bld=""; c_rst=""; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/fleet-health.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# `timeout` is coreutils, not macOS base. Degrade to running unbounded rather
# than failing every probe on a host that lacks it.
if command -v timeout >/dev/null 2>&1; then
  tmo() { timeout "$@"; }
elif command -v gtimeout >/dev/null 2>&1; then
  tmo() { gtimeout "$@"; }
else
  tmo() { shift; "$@"; }
fi

# ------------------------------------------------------------------- layout

# One of the eight in-monorepo packages?
is_package() {
  local p
  for p in "${PACKAGES[@]}"; do [ "$p" = "$1" ] && return 0; done
  return 1
}

# "package" | "root" | "external" — the row's kind decides which columns it owns.
row_kind() {
  if [ "$1" = "$ROOT_ROW" ]; then printf 'root'
  elif is_package "$1"; then printf 'package'
  else printf 'external'; fi
}

# The single place the monorepo split is encoded.
repo_dir() {
  if [ "$1" = "$ROOT_ROW" ]; then printf '%s' "$STACK_DIR"
  elif is_package "$1"; then printf '%s/packages/%s' "$STACK_DIR" "$1"
  else printf '%s/%s' "$CODE_DIR" "$1"; fi
}

# ---------------------------------------------------------------- advisory gate

# ADVISORY_OK: 1 = database provably current, 0 = unverified (VULN reads `?`).
ADVISORY_OK=0
ADVISORY_NOTE=""
if [ "$DO_AUDIT" = 1 ]; then
  # Next to this script when it runs from bin/; in the monorepo's bin/ when it
  # runs from a scratch copy.
  ADVISORY_SH=""
  for cand in "$SCRIPT_DIR/advisory-freshness.sh" "$STACK_DIR/bin/advisory-freshness.sh"; do
    [ -x "$cand" ] && { ADVISORY_SH="$cand"; break; }
  done
  if [ -n "$ADVISORY_SH" ]; then
    if ADVISORY_NOTE="$(tmo 120 "$ADVISORY_SH" 2>&1)"; then
      ADVISORY_OK=1
    fi
  else
    ADVISORY_NOTE="advisory-freshness.sh not found next to this script or in $STACK_DIR/bin"
  fi
fi

# ------------------------------------------------------------------- per repo

# owner/name from the origin remote, so a rename on GitHub does not silently
# make every gh query hit a 404 under the assumed org.
gh_slug() {
  local dir="$1" url
  url="$(git -C "$dir" remote get-url origin 2>/dev/null)"
  case "$url" in
    *github.com[:/]*)
      url="${url##*github.com}"; url="${url#:}"; url="${url#/}"; url="${url%.git}"
      printf '%s' "$url" ;;
    *) printf '%s/%s' "$GH_ORG" "$(basename "$dir")" ;;
  esac
}

# Fetch a paginated gh endpoint as ONE flat JSON array. --paginate emits several
# concatenated arrays, so slurp-and-add is what joins them. Non-zero exit means
# the caller must render `?`: a failed call (auth, 404, rate limit) must never
# read as zero — zero is what "all clear" looks like, and a silent 404 forges it.
gh_json() {
  local out
  out="$(tmo 60 gh api --paginate "$1" 2>/dev/null)" || return 1
  printf '%s' "$out" | jq -e -s 'add // [] | if type == "array" then . else [] end' 2>/dev/null
}

gh_count() {
  local out
  out="$(gh_json "$1")" || { printf '?'; return; }
  printf '%s' "$out" | jq 'length'
}

probe_repo() {
  local repo="$1"
  local dir kind
  dir="$(repo_dir "$repo")"
  kind="$(row_kind "$repo")"
  local detail="$TMP/$repo.detail"
  : >"$detail"

  # Every field carries "-" rather than "" when unknown or not-applicable-to-
  # this-row-kind. That is not cosmetic: tab is IFS *whitespace*, so
  # `IFS=$'\t' read` collapses runs of it and an empty field silently shifts
  # every later column one to the left.
  local status=ok
  local git_cell="-" dirty="-" ahead="-" behind="-"
  local outd="-" blocked="-" retired="-" vuln="-"
  local issues="-" prs="-" dependabot="-"
  local toolchain="-"

  # A package is a directory inside a repo, not a repo — it has no `.git`.
  # Testing for one would report all eight as missing.
  local present=0
  if [ "$kind" = package ]; then
    [ -d "$dir" ] && [ -f "$dir/mix.exs" ] && present=1
  else
    [ -d "$dir/.git" ] && present=1
  fi
  if [ "$present" != 1 ]; then
    printf '%s\tmissing\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t%s\n' "$repo" "$kind" >"$TMP/$repo.tsv"
    printf 'nothing at %s\n' "$dir" >"$detail"
    return
  fi

  # --- git ------------------------------------------------------------------
  # Packages: dirty only, scoped to the package directory. ahead/behind and the
  # fetch belong to the onchain-stack row — one repo, one measurement, and no
  # two probes racing a fetch on the same .git.
  if [ "$kind" = package ]; then
    dirty="$(git -C "$dir" status --porcelain -- . 2>/dev/null | grep -c '')"
    if [ "$dirty" = 0 ]; then git_cell="clean"; else git_cell="${dirty}dirty"; fi
  else
    [ "$DO_FETCH" = 1 ] && tmo 60 git -C "$dir" fetch --quiet --prune origin >/dev/null 2>&1
    dirty="$(git -C "$dir" status --porcelain 2>/dev/null | grep -c '')"
    local counts
    if counts="$(git -C "$dir" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null)"; then
      behind="${counts%%[[:space:]]*}"
      ahead="${counts##*[[:space:]]}"
    else
      behind="-"; ahead="-"   # no upstream tracking branch
    fi
    # ASCII on purpose: printf pads by BYTES, so a multi-byte arrow would shrink
    # the visible column and skew every row that has one.
    git_cell=""
    [ "$ahead" != "-" ] && [ "$ahead" != 0 ] && git_cell="+$ahead"
    [ "$behind" != "-" ] && [ "$behind" != 0 ] && git_cell="$git_cell-$behind"
    [ "$ahead" = "-" ] && git_cell="no-upstream"
    [ "$dirty" != 0 ] && git_cell="$git_cell ${dirty}dirty"
    [ -z "$git_cell" ] && git_cell="clean"
    git_cell="${git_cell# }"
  fi
  if [ "$dirty" != 0 ] && [ "$dirty" != "-" ]; then
    { printf '  git: %s uncommitted path(s)\n' "$dirty"
      if [ "$kind" = package ]; then
        git -C "$dir" status --short -- . | sed 's/^/    /'
      else
        git -C "$dir" status --short | sed 's/^/    /'
      fi; } >>"$detail"
  fi

  # --- toolchain ------------------------------------------------------------
  # Only rows that own a `.tool-versions`: the monorepo root and the three
  # external repos. A package carrying its own pin would be the drift, not the
  # measurement — the root file is the runtime `mix ci` uses for all eight.
  if [ "$kind" != package ]; then
    local tv="$dir/.tool-versions"
    local tv_erl="" tv_ex="" pin_bad=0
    if [ -f "$tv" ]; then
      tv_erl="$(awk '$1 == "erlang" {print $2; exit}' "$tv")"
      tv_ex="$(awk '$1 == "elixir" {print $2; exit}' "$tv")"
      [ "$tv_erl" = "$CANON_ERLANG" ] && [ "$tv_ex" = "$CANON_ELIXIR" ] || pin_bad=1
    else
      pin_bad=2
    fi

    if [ "$pin_bad" = 2 ]; then
      toolchain="none"
      status=fail
      printf '  toolchain: no .tool-versions — the runtime is whatever the shell resolves\n' >>"$detail"
    elif [ "$pin_bad" = 1 ]; then
      toolchain="drift"
      status=fail
      { printf '  toolchain: .tool-versions differs from the family canonical pair\n'
        printf '    canonical: erlang %s / elixir %s\n' "$CANON_ERLANG" "$CANON_ELIXIR"
        printf '    this repo: erlang %s / elixir %s\n' "${tv_erl:-none}" "${tv_ex:-none}"
      } >>"$detail"
    else
      toolchain="ok"
    fi
  else
    # A stray per-package pin is worth naming: it would silently override the
    # root for that package only. Reported, not failed — see the footnote.
    if [ -f "$dir/.tool-versions" ]; then
      toolchain="own"
      printf '  toolchain: packages/%s carries its OWN .tool-versions, shadowing the root pin\n' "$repo" >>"$detail"
      [ "$status" = ok ] && status=warn
    fi
  fi

  # --- hex.outdated / hex.audit --------------------------------------------
  # Skipped on the monorepo root row: the root project is analyzer-only
  # (credo/ex_slop/styler) and ships no runtime code, so its dep state says
  # nothing about the family. The eight package rows each run in their own
  # directory, where that package's mix.lock is.
  #
  # In-family siblings resolve as PATH deps here (no ONCHAIN_PUBLISH), and
  # `mix hex.outdated` only reports Hex deps — so siblings simply do not appear
  # in these columns. That is correct rather than a gap: a path dep has no
  # version to be behind. Whether the *declared* Hex requirement still admits
  # the in-repo version is `mix onchain.bounds` at the root, which `mix ci`
  # runs first.
  if [ "$DO_HEX" = 1 ] && [ "$kind" != root ]; then
    local o
    if o="$(cd "$dir" && tmo 240 mix hex.outdated 2>&1)"; then :; else :; fi
    if printf '%s' "$o" | grep -q 'Dependency'; then
      outd="$(printf '%s\n' "$o" | grep -c 'Update possible')"
      blocked="$(printf '%s\n' "$o" | grep -c 'Update not possible')"
      if [ "$outd" != 0 ] || [ "$blocked" != 0 ]; then
        { printf '  outdated deps:\n'
          printf '%s\n' "$o" | grep -E 'Update (not )?possible' | sed 's/^/    /'; } >>"$detail"
      fi
    else
      outd="?"; blocked="?"
      { printf '  hex.outdated failed:\n'; printf '%s\n' "$o" | tail -5 | sed 's/^/    /'; } >>"$detail"
      [ "$status" = ok ] && status=warn
    fi

    local a
    a="$(cd "$dir" && tmo 120 mix hex.audit 2>&1)"
    # Match on 'No retired' alone, not the full 'No retired packages'. Hex now
    # prints "No retired or security advisory packages found"; the stricter
    # pattern missed it, fell through to the `grep -qi retired` branch (which
    # the all-clear line also matches), counted zero table rows, and rendered a
    # red `?` plus status=fail for EVERY repo. publish-prep.sh always used the
    # loose form — this aligns the two.
    if printf '%s' "$a" | grep -qi 'No retired'; then
      retired=0
    elif printf '%s' "$a" | grep -qi 'retired'; then
      retired="$(printf '%s\n' "$a" | grep -cE '^\s+\S+\s+[0-9]')"
      [ "$retired" = 0 ] && retired="?"
      { printf '  retired packages:\n'; printf '%s\n' "$a" | sed 's/^/    /'; } >>"$detail"
      status=fail
    else
      retired="?"
      { printf '  hex.audit failed:\n'; printf '%s\n' "$a" | tail -5 | sed 's/^/    /'; } >>"$detail"
      [ "$status" = ok ] && status=warn
    fi
  fi

  # --- deps.audit -----------------------------------------------------------
  # Same row split as hex above. `.mix_audit_ignore` is a SYMLINK to the root
  # file in six of the eight packages — `[ -f ]` follows symlinks, so the same
  # test keeps working; a broken link correctly reads as absent and falls back
  # to a bare audit rather than passing mix_audit a path it cannot open.
  if [ "$DO_AUDIT" = 1 ] && [ "$kind" != root ]; then
    if [ "$ADVISORY_OK" != 1 ]; then
      # Auditing against an unverified database is worse than not auditing:
      # it prints green. Report unknown and let the summary carry the reason.
      vuln="?"
      status=fail
    else
      local args=() v
      [ -f "$dir/.mix_audit_ignore" ] && args=(--ignore-file .mix_audit_ignore)
      v="$(cd "$dir" && tmo 120 mix deps.audit "${args[@]}" 2>&1)"
      if printf '%s' "$v" | grep -q 'No vulnerabilities found'; then
        vuln=0
      elif printf '%s' "$v" | grep -qE '[0-9]+ vulnerabilit'; then
        vuln="$(printf '%s\n' "$v" | grep -oE '[0-9]+ vulnerabilit' | grep -oE '[0-9]+' | head -1)"
        { printf '  vulnerabilities:\n'; printf '%s\n' "$v" | sed 's/^/    /'; } >>"$detail"
        status=fail
      else
        vuln="?"
        { printf '  deps.audit failed:\n'; printf '%s\n' "$v" | tail -8 | sed 's/^/    /'; } >>"$detail"
        status=fail
      fi
    fi
  fi

  # --- GitHub ---------------------------------------------------------------
  # Package rows make no gh calls at all: their issues, PRs and Dependabot
  # alerts are the monorepo's, already counted once on the onchain-stack row.
  # Eight repeats of the same three API calls would cost eight times the rate
  # limit to print the same number eight times.
  if [ "$DO_GH" = 1 ] && [ "$kind" != package ]; then
    local slug; slug="$(gh_slug "$dir")"

    # `issues` returns PRs too — filter them out rather than double-counting.
    local raw_issues="" raw_dep=""
    if raw_issues="$(gh_json "repos/$slug/issues?state=open&per_page=100")"; then
      issues="$(printf '%s' "$raw_issues" | jq 'map(select(.pull_request | not)) | length')"
    else
      issues="?"
    fi
    prs="$(gh_count "repos/$slug/pulls?state=open&per_page=100")"

    if raw_dep="$(gh_json "repos/$slug/dependabot/alerts?state=open&per_page=100")"; then
      dependabot="$(printf '%s' "$raw_dep" | jq 'length')"
    else
      dependabot="?"
    fi
    # A Dependabot alert is always hard — it names a known-vulnerable version.
    # It is also the one GitHub-side security signal that outlived the
    # workflows: it reads the dependency graph, not a run. Sobelow findings
    # used to arrive here too, via a code-scanning upload; they now surface
    # only where they always mattered, in `mix ci`'s own sobelow step.
    #
    # On the monorepo row an alert may name any of the eight packages' locks —
    # the detail lines below carry the package name, so read them, don't guess.
    case "$dependabot" in ''|0|'?') ;; *) status=fail ;; esac

    if [ -n "${raw_dep:-}" ] && [ "$dependabot" != 0 ]; then
      { printf '  dependabot alerts (%s):\n' "$dependabot"
        printf '%s' "$raw_dep" \
          | jq -r '.[] | "    \(.security_advisory.severity)\t\(.dependency.package.name)\t\(.security_advisory.summary)"'; } >>"$detail"
    fi
    if [ -n "${raw_issues:-}" ] && [ "$issues" != 0 ]; then
      { printf '  open issues (%s):\n' "$issues"
        printf '%s' "$raw_issues" \
          | jq -r 'map(select(.pull_request | not)) | .[] | "    #\(.number)\t\(.title)"'; } >>"$detail"
    fi
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$repo" "$status" "$git_cell" "$dirty" "$ahead" "$behind" \
    "$outd" "$blocked" "$retired" "$vuln" "$issues" "$prs" "$dependabot" "$toolchain" "$kind" \
    >"$TMP/$repo.tsv"
}

# ------------------------------------------------------------------ run probes

[ "$AS_JSON" = 1 ] || printf '%ssweeping %d row(s)%s\n\n' "$c_dim" "${#REPOS[@]}" "$c_rst" >&2

i=0
for repo in "${REPOS[@]}"; do
  probe_repo "$repo" &
  i=$((i + 1))
  [ $((i % JOBS)) -eq 0 ] && wait
done
wait

# --------------------------------------------------------------------- render

exit_code=0
for repo in "${REPOS[@]}"; do
  [ -f "$TMP/$repo.tsv" ] || continue
  st="$(cut -f2 "$TMP/$repo.tsv")"
  [ "$st" = fail ] && exit_code=1
done

if [ "$AS_JSON" = 1 ]; then
  for repo in "${REPOS[@]}"; do
    [ -f "$TMP/$repo.tsv" ] && cat "$TMP/$repo.tsv"
  done | jq -Rs --argjson advisory "$ADVISORY_OK" \
                --arg erl "$CANON_ERLANG" --arg ex "$CANON_ELIXIR" \
                --arg stack "$STACK_DIR" '
    split("\n") | map(select(length > 0)) | map(split("\t")) |
    map({
      repo: .[0], status: .[1],
      # kind: "root" = the monorepo checkout, "package" = packages/<name>
      # inside it, "external" = its own repo. A null column on a package row
      # means "owned by the root row", not "unknown".
      kind: .[14],
      git: .[2],
      dirty: (.[3] | if . == "-" or . == "" then null else tonumber end),
      ahead: (.[4] | if . == "-" or . == "" then null else tonumber end),
      behind: (.[5] | if . == "-" or . == "" then null else tonumber end),
      outdated: (.[6] | if . == "?" or . == "-" or . == "" then null else tonumber end),
      outdated_blocked: (.[7] | if . == "?" or . == "-" or . == "" then null else tonumber end),
      retired: (.[8] | if . == "?" or . == "-" or . == "" then null else tonumber end),
      vulnerabilities: (.[9] | if . == "?" or . == "-" or . == "" then null else tonumber end),
      issues: (.[10] | if . == "?" or . == "-" or . == "" then null else tonumber end),
      pull_requests: (.[11] | if . == "?" or . == "-" or . == "" then null else tonumber end),
      dependabot_alerts: (.[12] | if . == "?" or . == "-" or . == "" then null else tonumber end),
      toolchain: (.[13] | if . == "-" or . == "" then null else . end)
    }) | {advisory_db_verified: ($advisory == 1),
          monorepo_root: $stack,
          canonical_toolchain: {erlang: $erl, elixir: $ex},
          repos: .}'
  exit "$exit_code"
fi

printf '%-20s %-14s %-7s %-9s %-8s %-6s %-7s %-5s %s\n' \
  "REPO" "GIT" "TOOLCH" "OUTDATED" "RETIRED" "VULN" "ISSUES" "PRS" "ALERTS"
printf '%s\n' "-----------------------------------------------------------------------------------------"

for repo in "${REPOS[@]}"; do
  [ -f "$TMP/$repo.tsv" ] || continue
  IFS=$'\t' read -r r st git_cell dirty ahead behind outd blocked retired vuln issues prs dependabot toolchain kind <"$TMP/$repo.tsv"

  # Indent the in-repo packages so the table shows the layout at a glance, and
  # so the `-` cells next to them read as "the row above owns this".
  if [ "$kind" = package ]; then label="  $r"; else label="$r"; fi

  if [ "$st" = missing ]; then
    printf '%-20s %s%s%s\n' "$label" "$c_yel" "nothing at $(repo_dir "$r")" "$c_rst"
    continue
  fi

  # "possible/blocked" — blocked means another dep's requirement caps it (the
  # ex_ast ~> 0.12.0 case), which is a different decision than "just bump it".
  out_cell="$outd"
  [ "$blocked" != "-" ] && [ "$blocked" != 0 ] && out_cell="$outd/$blocked"

  # `?` (query failed) must never render as a number: zero is what all-clear
  # looks like, and a rate-limited call must not forge it.
  alerts_cell="$dependabot"

  # Pad FIRST, colour after: escape sequences are bytes printf would count as
  # column width, which is what pulls every coloured row out of alignment.
  printf -v git_pad '%-14s' "$git_cell"
  case "$git_cell" in clean|-) ;; *) git_pad="$c_yel$git_pad$c_rst" ;; esac
  printf -v vuln_pad '%-6s' "$vuln"
  printf -v alerts_pad '%-7s' "$alerts_cell"
  printf -v retired_pad '%-8s' "$retired"
  case "$vuln" in 0|-) ;; *) vuln_pad="$c_red$vuln_pad$c_rst" ;; esac
  # Quote the '?' — unquoted it is a glob matching ANY single character, which
  # would swallow every single-digit alert count into the "unknown" branch.
  case "$alerts_cell" in
    0|-) ;;
    '?') alerts_pad="$c_yel$alerts_pad$c_rst" ;;
    *)   alerts_pad="$c_red$alerts_pad$c_rst" ;;
  esac
  case "$retired" in 0|-) ;; *) retired_pad="$c_red$retired_pad$c_rst" ;; esac

  printf -v tc_pad '%-7s' "$toolchain"
  case "$toolchain" in ok|-) ;; own) tc_pad="$c_yel$tc_pad$c_rst" ;; *) tc_pad="$c_red$tc_pad$c_rst" ;; esac

  printf '%-20s %s %s %-9s %s %s %-7s %-5s %s\n' \
    "$label" "$git_pad" "$tc_pad" "$out_cell" "$retired_pad" "$vuln_pad" "$issues" "$prs" "$alerts_pad"
done

# details
first=1
for repo in "${REPOS[@]}"; do
  [ -s "$TMP/$repo.detail" ] || continue
  [ "$first" = 1 ] && { printf '\n%s— details —%s\n' "$c_bld" "$c_rst"; first=0; }
  printf '\n%s%s%s\n' "$c_bld" "$repo" "$c_rst"
  cat "$TMP/$repo.detail"
done

printf '\n%sIndented rows are packages/<name> inside the onchain-stack checkout. Their%s\n' "$c_dim" "$c_rst"
printf '%s`-` cells are not unknown — git ahead/behind, TOOLCH and the GitHub columns%s\n' "$c_dim" "$c_rst"
printf '%sare one repo-wide fact, measured once on the onchain-stack row. GIT on a%s\n' "$c_dim" "$c_rst"
printf '%spackage row is that package directory'"'"'s uncommitted paths only.%s\n' "$c_dim" "$c_rst"
printf '%sOUTDATED is possible/blocked — blocked means another dep caps the version%s\n' "$c_dim" "$c_rst"
printf '%s(e.g. reach pins ex_ast ~> 0.12.0), so it is a decision, not a bump. In-family%s\n' "$c_dim" "$c_rst"
printf '%ssiblings are path deps here and never appear; `mix onchain.bounds` checks those.%s\n' "$c_dim" "$c_rst"
printf '%sTOOLCH ok = .tool-versions pins erlang %s / elixir %s.%s\n' \
  "$c_dim" "$CANON_ERLANG" "$CANON_ELIXIR" "$c_rst"
printf '%sdrift = pin disagrees · none = no .tool-versions at all · own = a package%s\n' "$c_dim" "$c_rst"
printf '%scarries its own pin, shadowing the root for that package alone.%s\n' "$c_dim" "$c_rst"
printf '%sALERTS is Dependabot only, and no column here says whether `mix ci` passes —%s\n' "$c_dim" "$c_rst"
printf '%snothing runs it for you. Run `mix ci` at the monorepo root; it iterates the%s\n' "$c_dim" "$c_rst"
printf '%seight packages serially (one shared advisory clone — never parallelise it),%s\n' "$c_dim" "$c_rst"
printf '%sand run it in descripex / zen_websocket / mpp separately.%s\n' "$c_dim" "$c_rst"

printf '\n'
if [ "$DO_AUDIT" = 1 ] && [ "$ADVISORY_OK" != 1 ]; then
  printf '%sVULN unverified%s — the advisory database could not be proven current, so\n' "$c_red" "$c_rst"
  printf 'a green audit would be meaningless. Reason:\n%s\n' "$(printf '%s' "$ADVISORY_NOTE" | sed 's/^/  /')"
elif [ "$DO_AUDIT" = 1 ]; then
  printf '%s%s%s\n' "$c_dim" "$ADVISORY_NOTE" "$c_rst"
fi

if [ "$exit_code" = 0 ]; then
  printf '%sno hard findings.%s Outdated/issues/dirty columns are informational.\n' "$c_grn" "$c_rst"
else
  printf '%shard findings present%s (vulnerability, retired dep, Dependabot alert, toolchain divergence, or unverified DB).\n' "$c_red" "$c_rst"
fi
printf '%sRelease readiness is a separate question: ./bin/publish-prep.sh status%s\n' "$c_dim" "$c_rst"

exit "$exit_code"
