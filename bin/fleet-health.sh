#!/usr/bin/env bash
# Onchain stack — cross-repo health sweep.
#
# One table for all ten repos: git state, outdated Hex deps, retired deps,
# known vulnerabilities, open GitHub issues/PRs, and open GitHub security
# alerts (Dependabot + code scanning).
#
# READ-ONLY by design. It never runs `mix deps.get`, never publishes, never
# writes to a repo. `git fetch` is the only remote write-ish thing it does and
# `--no-fetch` turns that off. That matters: the "dirty tree" column is only
# meaningful if the sweep itself cannot dirty a tree.
#
# The advisory database freshness gate runs ONCE, not per repo. mix_audit reads
# a single shared clone (see bin/advisory-freshness.sh); ten repos audit against
# the same copy, so ten fetches would be nine wasted ones. If that gate fails,
# every VULN cell reads `?` — a stale database prints "No vulnerabilities found"
# and exits 0 (mirego/mix_audit#61), so an unverified green is not a green.
#
# Usage:
#   ./bin/fleet-health.sh                    # sweep every repo
#   ./bin/fleet-health.sh onchain cartouche  # sweep named repos only
#   ./bin/fleet-health.sh --json             # machine-readable, one object per repo
#
# Options:
#   --no-fetch     skip `git fetch` (fast; ahead/behind may be stale)
#   --no-gh        skip all GitHub queries (offline / no gh auth)
#   --no-hex       skip hex.outdated + hex.audit (the slow, network-bound part)
#   --no-audit     skip the advisory gate + deps.audit
#   -j N           parallel repos (default 4)
#   --json         emit JSON instead of the table
#   -h, --help     this header
#
# Exit status:
#   0  nothing actionable found
#   1  a HARD finding: vulnerability, retired dep, open security alert, or an
#      unverifiable advisory database. Outdated deps, open issues/PRs and a
#      dirty tree are reported but do NOT fail — they are normal working state.
#   2  usage error

set -uo pipefail

CODE_DIR="${ONCHAIN_CODE_DIR:-$HOME/_DATA/code}"
GH_ORG="${ONCHAIN_GH_ORG:-ZenHive}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cascade order (upstream → downstream), same order publish-prep.sh uses.
ALL_REPOS=(descripex zen_websocket hieroglyph cartouche onchain onchain_aave onchain_evm onchain_js onchain_tempo mpp)

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
    -h|--help)  sed -n '2,44p' "$0"; exit 0 ;;
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

# ---------------------------------------------------------------- advisory gate

# ADVISORY_OK: 1 = database provably current, 0 = unverified (VULN reads `?`).
ADVISORY_OK=0
ADVISORY_NOTE=""
if [ "$DO_AUDIT" = 1 ]; then
  if [ -x "$SCRIPT_DIR/advisory-freshness.sh" ]; then
    if ADVISORY_NOTE="$(tmo 120 "$SCRIPT_DIR/advisory-freshness.sh" 2>&1)"; then
      ADVISORY_OK=1
    fi
  else
    ADVISORY_NOTE="advisory-freshness.sh not found next to this script"
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
  local dir="$CODE_DIR/$repo"
  local detail="$TMP/$repo.detail"
  : >"$detail"

  # Every field carries "-" rather than "" when unknown. That is not cosmetic:
  # tab is IFS *whitespace*, so `IFS=$'\t' read` collapses runs of it and an
  # empty field silently shifts every later column one to the left.
  local status=ok
  local git_cell="-" dirty="-" ahead="-" behind="-"
  local outd="-" blocked="-" retired="-" vuln="-"
  local issues="-" prs="-" dependabot="-" codescan="-"
  local ci_red="-" ci_total="-"

  if [ ! -d "$dir/.git" ]; then
    printf '%s\tmissing\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\n' "$repo" >"$TMP/$repo.tsv"
    printf 'no repo at %s\n' "$dir" >"$detail"
    return
  fi

  # --- git ------------------------------------------------------------------
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
  if [ "$dirty" != 0 ]; then
    { printf '  git: %s uncommitted path(s)\n' "$dirty"
      git -C "$dir" status --short | sed 's/^/    /'; } >>"$detail"
  fi

  # --- hex.outdated / hex.audit --------------------------------------------
  if [ "$DO_HEX" = 1 ]; then
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
    if printf '%s' "$a" | grep -q 'No retired packages'; then
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
  if [ "$DO_AUDIT" = 1 ]; then
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
  if [ "$DO_GH" = 1 ]; then
    local slug; slug="$(gh_slug "$dir")"

    # `issues` returns PRs too — filter them out rather than double-counting.
    local raw_issues="" raw_dep="" raw_cs=""
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
    # Code scanning 404s with "no analysis found" on a repo that never ran it.
    # That is "not configured", not "unknown" — collapsing the two would hide a
    # repo with NO scanning behind the same `?` as a transient API failure.
    local cs_out
    if cs_out="$(tmo 60 gh api --paginate "repos/$slug/code-scanning/alerts?state=open&per_page=100" 2>"$TMP/$repo.cserr")"; then
      raw_cs="$(printf '%s' "$cs_out" | jq -s 'add // []' 2>/dev/null)" || raw_cs=""
      if [ -n "$raw_cs" ]; then codescan="$(printf '%s' "$raw_cs" | jq 'length')"; else codescan="?"; fi
    elif grep -qiE 'no analysis found|Advanced Security|not enabled' "$TMP/$repo.cserr" 2>/dev/null; then
      codescan="n/a"
      printf '  code scanning: not enabled on %s\n' "$slug" >>"$detail"
    else
      codescan="?"
    fi

    # A Dependabot alert is always hard — it names a known-vulnerable version.
    # Code scanning is not: this org uploads Sobelow output there, and a
    # `warning` finding is a lint result, not a breach. Only high/critical (or
    # an `error`-level rule) escalates; the rest is reported and left to you.
    case "$dependabot" in ''|0|'?') ;; *) status=fail ;; esac
    if [ -n "$raw_cs" ]; then
      local severe
      severe="$(printf '%s' "$raw_cs" \
        | jq '[.[] | select((.rule.security_severity_level // "") as $s
                            | $s == "critical" or $s == "high"
                              or (.rule.severity // "") == "error")] | length')"
      if [ "${severe:-0}" != 0 ]; then
        status=fail
      elif [ "$codescan" != 0 ] && [ "$status" = ok ]; then
        status=warn
      fi
    fi

    if [ -n "${raw_dep:-}" ] && [ "$dependabot" != 0 ]; then
      { printf '  dependabot alerts (%s):\n' "$dependabot"
        printf '%s' "$raw_dep" \
          | jq -r '.[] | "    \(.security_advisory.severity)\t\(.dependency.package.name)\t\(.security_advisory.summary)"'; } >>"$detail"
    fi
    if [ -n "${raw_cs:-}" ] && [ "$codescan" != 0 ]; then
      { printf '  code-scanning alerts (%s):\n' "$codescan"
        printf '%s' "$raw_cs" \
          | jq -r '.[] | "    \(.rule.security_severity_level // .rule.severity)\t\(.rule.id)\t\(.most_recent_instance.location.path // "?")"'; } >>"$detail"
    fi
    if [ -n "${raw_issues:-}" ] && [ "$issues" != 0 ]; then
      { printf '  open issues (%s):\n' "$issues"
        printf '%s' "$raw_issues" \
          | jq -r 'map(select(.pull_request | not)) | .[] | "    #\(.number)\t\(.title)"'; } >>"$detail"
    fi

    # A repo's own gate being red is a hard finding. The sweep once reported
    # onchain_aave clean while every CI run since its 0.3.0 release had failed:
    # auditing deps while the gate that runs those audits is broken is theatre.
    # `gh run list` is newest-first, so the head of each workflow's group is its
    # latest run — judge per workflow, not on the last N runs overall.
    local runs_raw
    if runs_raw="$(tmo 60 gh run list --repo "$slug" --limit 30 --json workflowName,conclusion 2>/dev/null)"; then
      ci_total="$(printf '%s' "$runs_raw" | jq '[group_by(.workflowName)[] | .[0]] | length' 2>/dev/null || printf '?')"
      ci_red="$(printf '%s' "$runs_raw" \
        | jq '[group_by(.workflowName)[] | .[0]]
              | map(select(.conclusion == "failure" or .conclusion == "timed_out"))
              | length' 2>/dev/null || printf '?')"
      if [ "$ci_red" != 0 ] && [ "$ci_red" != "?" ]; then
        status=fail
        { printf '  red CI (%s of %s workflows):\n' "$ci_red" "$ci_total"
          printf '%s' "$runs_raw" \
            | jq -r '[group_by(.workflowName)[] | .[0]]
                     | .[] | select(.conclusion == "failure" or .conclusion == "timed_out")
                     | "    \(.workflowName)\t\(.conclusion)"'; } >>"$detail"
      fi
    else
      ci_red="?"; ci_total="?"
    fi
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$repo" "$status" "$git_cell" "$dirty" "$ahead" "$behind" \
    "$outd" "$blocked" "$retired" "$vuln" "$issues" "$prs" "$dependabot" "$codescan" \
    "$ci_red" "$ci_total" \
    >"$TMP/$repo.tsv"
}

# ------------------------------------------------------------------ run probes

[ "$AS_JSON" = 1 ] || printf '%ssweeping %d repo(s)%s\n\n' "$c_dim" "${#REPOS[@]}" "$c_rst" >&2

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
  num() { printf '%s' "$1"; }
  for repo in "${REPOS[@]}"; do
    [ -f "$TMP/$repo.tsv" ] && cat "$TMP/$repo.tsv"
  done | jq -Rs --argjson advisory "$ADVISORY_OK" '
    split("\n") | map(select(length > 0)) | map(split("\t")) |
    map({
      repo: .[0], status: .[1], git: .[2],
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
      code_scanning_enabled: (.[13] != "n/a"),
      code_scanning_alerts: (.[13] | if . == "?" or . == "-" or . == "" or . == "n/a" then null else tonumber end),
      ci_workflows_red: (.[14] | if . == "?" or . == "-" or . == "" then null else tonumber end),
      ci_workflows_total: (.[15] | if . == "?" or . == "-" or . == "" then null else tonumber end)
    }) | {advisory_db_verified: ($advisory == 1), repos: .}'
  exit "$exit_code"
fi

printf '%-16s %-14s %-9s %-8s %-6s %-7s %-5s %-7s %s\n' \
  "REPO" "GIT" "OUTDATED" "RETIRED" "VULN" "ISSUES" "PRS" "ALERTS" "CI"
printf '%s\n' "-----------------------------------------------------------------------------------------"

saw_no_codescan=0

for repo in "${REPOS[@]}"; do
  [ -f "$TMP/$repo.tsv" ] || continue
  IFS=$'\t' read -r r st git_cell dirty ahead behind outd blocked retired vuln issues prs dependabot codescan ci_red ci_total <"$TMP/$repo.tsv"

  if [ "$st" = missing ]; then
    printf '%-16s %s%s%s\n' "$r" "$c_yel" "no repo at $CODE_DIR/$r" "$c_rst"
    continue
  fi

  # "possible/blocked" — blocked means another dep's requirement caps it (the
  # ex_ast ~> 0.12.0 case), which is a different decision than "just bump it".
  out_cell="$outd"
  [ "$blocked" != "-" ] && [ "$blocked" != 0 ] && out_cell="$outd/$blocked"

  # Dependabot and code scanning are one concern to the reader; sum them, but
  # a `?` in either must not be summed away into a reassuring number. `n/a`
  # (code scanning never configured) prints the Dependabot count with a `*`.
  if [ "$dependabot" = "?" ] || [ "$codescan" = "?" ]; then
    alerts_cell="?"
  elif [ "$dependabot" = "-" ]; then
    alerts_cell="-"
  elif [ "$codescan" = "n/a" ]; then
    alerts_cell="$dependabot*"
    saw_no_codescan=1
  else
    alerts_cell="$((dependabot + codescan))"
  fi

  # Pad FIRST, colour after: escape sequences are bytes printf would count as
  # column width, which is what pulls every coloured row out of alignment.
  printf -v git_pad '%-14s' "$git_cell"
  [ "$git_cell" = clean ] || git_pad="$c_yel$git_pad$c_rst"
  printf -v vuln_pad '%-6s' "$vuln"
  printf -v alerts_pad '%-7s' "$alerts_cell"
  printf -v retired_pad '%-8s' "$retired"
  case "$vuln" in 0) ;; *) vuln_pad="$c_red$vuln_pad$c_rst" ;; esac
  # Yellow, not red, when the only alerts are the sub-high ones that did not
  # fail the sweep — a red cell above a "no hard findings" footer is a lie.
  case "$alerts_cell" in
    0|'0*'|-) ;;
    *) if [ "$st" = fail ]; then alerts_pad="$c_red$alerts_pad$c_rst"
       else alerts_pad="$c_yel$alerts_pad$c_rst"; fi ;;
  esac
  case "$retired" in 0|-) ;; *) retired_pad="$c_red$retired_pad$c_rst" ;; esac

  # Quote the '?' — unquoted it is a glob matching ANY single character, which
  # would swallow every single-digit failure count into the "unknown" branch.
  case "$ci_red" in
    0)      ci_cell="ok" ;;
    -|'?')  ci_cell="$ci_red" ;;
    *)      ci_cell="$ci_red/$ci_total red" ;;
  esac
  printf -v ci_pad '%-7s' "$ci_cell"
  case "$ci_cell" in ok|-|'?') ;; *) ci_pad="$c_red$ci_pad$c_rst" ;; esac

  printf '%-16s %s %-9s %s %s %-7s %-5s %s %s\n' \
    "$r" "$git_pad" "$out_cell" "$retired_pad" "$vuln_pad" "$issues" "$prs" "$alerts_pad" "$ci_pad"
done

# details
first=1
for repo in "${REPOS[@]}"; do
  [ -s "$TMP/$repo.detail" ] || continue
  [ "$first" = 1 ] && { printf '\n%s— details —%s\n' "$c_bld" "$c_rst"; first=0; }
  printf '\n%s%s%s\n' "$c_bld" "$repo" "$c_rst"
  cat "$TMP/$repo.detail"
done

printf '\n%sOUTDATED is possible/blocked — blocked means another dep caps the version%s\n' "$c_dim" "$c_rst"
printf '%s(e.g. reach pins ex_ast ~> 0.12.0), so it is a decision, not a bump.%s\n' "$c_dim" "$c_rst"
[ "$saw_no_codescan" = 1 ] && \
  printf '%s* code scanning not enabled there — ALERTS counts Dependabot only.%s\n' "$c_dim" "$c_rst"

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
  printf '%shard findings present%s (vulnerability, retired dep, security alert, or unverified DB).\n' "$c_red" "$c_rst"
fi
printf '%sRelease readiness is a separate question: ./bin/publish-prep.sh status%s\n' "$c_dim" "$c_rst"

exit "$exit_code"
