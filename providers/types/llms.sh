#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/llms.sh"

usage() {
  cat <<'USAGE'
Usage: providers/types/llms.sh --provider NAME --output DIR --index-url URL [options]

Options:
  --full-index-url URL       Optional llms-full.txt URL
  --pattern REGEX            ripgrep regex used to extract doc links
  --strip-prefix PREFIX      Prefix stripped from URL to form output path
  --strip-suffix SUFFIX      Suffix stripped from URL-derived path (e.g. '.txt')
  --throttle-seconds SECONDS Sleep between downloads (default: 0.1)
  --download-jobs N          Parallel downloads for llms docs (default: 4)
  --force                    Re-download even if the file exists
  --token TOKEN              Adds 'Authorization: Bearer TOKEN' header
  --header 'K: V'            Adds an arbitrary header (repeatable)
  --include-full-index       Union in llms-full.txt results too
  --fail-on-missing          Exit non-zero if any downloads fail
  --max-docs N               Limit number of docs (debug)
USAGE
}

PROVIDER=""
OUT_DIR=""
INDEX_URL=""
FULL_INDEX_URL=""
PATTERN=""
STRIP_PREFIX=""
STRIP_SUFFIX=""
THROTTLE_SECONDS="0.1"
DOWNLOAD_JOBS="${LLMS_DOWNLOAD_JOBS:-4}"
FORCE="0"
TOKEN=""
HEADERS=()
INCLUDE_FULL_INDEX="0"
FAIL_ON_MISSING="0"
MAX_DOCS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      PROVIDER="${2:-}"; shift 2 ;;
    --output)
      OUT_DIR="${2:-}"; shift 2 ;;
    --index-url)
      INDEX_URL="${2:-}"; shift 2 ;;
    --full-index-url)
      FULL_INDEX_URL="${2:-}"; shift 2 ;;
    --pattern)
      PATTERN="${2:-}"; shift 2 ;;
    --strip-prefix)
      STRIP_PREFIX="${2:-}"; shift 2 ;;
    --strip-suffix)
      STRIP_SUFFIX="${2:-}"; shift 2 ;;
    --throttle-seconds)
      THROTTLE_SECONDS="${2:-0}"; shift 2 ;;
    --download-jobs)
      DOWNLOAD_JOBS="${2:-}"; shift 2 ;;
    --force)
      FORCE="1"; shift ;;
    --token)
      TOKEN="${2:-}"; shift 2 ;;
    --header)
      HEADERS+=("${2:-}"); shift 2 ;;
    --include-full-index)
      INCLUDE_FULL_INDEX="1"; shift ;;
    --fail-on-missing)
      FAIL_ON_MISSING="1"; shift ;;
    --max-docs)
      MAX_DOCS="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      usage; exit 1 ;;
  esac
done

if [[ -z "$PROVIDER" || -z "$OUT_DIR" || -z "$INDEX_URL" ]]; then
  usage
  exit 1
fi

if ! [[ "$DOWNLOAD_JOBS" =~ ^[0-9]+$ ]] || [[ "$DOWNLOAD_JOBS" -lt 1 ]]; then
  echo "--download-jobs must be a positive integer" >&2
  exit 1
fi

# Reasonable default: match absolute and relative links to markdown sources.
if [[ -z "$PATTERN" ]]; then
  PATTERN='(?:https?://|/|\./)[^ \t\r\n\)\]]+\.(?:md|mdx)(?:\.txt)?'
fi

LLMS_CURL_BASE=(
  curl -fsSL
  --retry 5
  --retry-delay 2
  --retry-connrefused
  --retry-all-errors
  --retry-max-time 120
  --http1.1
)

if [[ -n "$TOKEN" ]]; then
  LLMS_CURL_BASE+=( -H "Authorization: Bearer $TOKEN" )
fi

if [[ ${#HEADERS[@]} -gt 0 ]]; then
  for header in "${HEADERS[@]}"; do
    [[ -n "$header" ]] || continue
    LLMS_CURL_BASE+=( -H "$header" )
  done
fi

export LLMS_INCLUDE_FULL_INDEX="$INCLUDE_FULL_INDEX"
export LLMS_FAIL_ON_MISSING="$FAIL_ON_MISSING"
if [[ -n "$MAX_DOCS" ]]; then
  export LLMS_MAX_DOCS="$MAX_DOCS"
fi

llms_mirror "$PROVIDER" "$INDEX_URL" "$FULL_INDEX_URL" "$PATTERN" "$STRIP_PREFIX" "$STRIP_SUFFIX" "$OUT_DIR" "$THROTTLE_SECONDS" "$DOWNLOAD_JOBS" "$FORCE"
