#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: providers/types/openapi.sh --provider NAME --output DIR (--spec-url URL | --index-url URL) [options]

Options:
  --spec-url URL        Direct OpenAPI spec URL (yaml/yml/json)
  --index-url URL       Index to scan for a spec URL (commonly llms.txt)
  --spec-regex REGEX    ripgrep regex used to locate the spec URL inside the index
  --fallback-spec-url URL
                        If scanning the index fails, fall back to this spec URL
  --title TITLE         Title for generated index.md (defaults to spec info.title)
USAGE
}

PROVIDER=""
OUT_DIR=""
SPEC_URL=""
FALLBACK_SPEC_URL=""
INDEX_URL=""
SPEC_REGEX=""
TITLE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      PROVIDER="${2:-}"; shift 2 ;;
    --output)
      OUT_DIR="${2:-}"; shift 2 ;;
    --spec-url)
      SPEC_URL="${2:-}"; shift 2 ;;
    --fallback-spec-url)
      FALLBACK_SPEC_URL="${2:-}"; shift 2 ;;
    --index-url)
      INDEX_URL="${2:-}"; shift 2 ;;
    --spec-regex)
      SPEC_REGEX="${2:-}"; shift 2 ;;
    --title)
      TITLE="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      usage; exit 1 ;;
  esac
done

if [[ -z "$PROVIDER" || -z "$OUT_DIR" ]]; then
  usage
  exit 1
fi

if [[ -z "$SPEC_URL" && -z "$INDEX_URL" ]]; then
  usage
  exit 1
fi

common_require_cmds curl mktemp rg ruby

CURL_BASE=(curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused --retry-all-errors --retry-max-time 120 --http1.1)

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

if [[ -z "$SPEC_URL" ]]; then
  echo "[$PROVIDER] Downloading index from $INDEX_URL"
  "${CURL_BASE[@]}" "$INDEX_URL" -o "$WORKDIR/index.txt"

  # Default: first likely yaml/yml/json URL in the file.
  if [[ -z "$SPEC_REGEX" ]]; then
    SPEC_REGEX='https?://[^[:space:]]+[.](?:yaml|yml|json)'
  fi

  SPEC_URL="$(rg -o "$SPEC_REGEX" "$WORKDIR/index.txt" | head -n 1 || true)"

  if [[ -z "$SPEC_URL" && -n "$FALLBACK_SPEC_URL" ]]; then
    SPEC_URL="$FALLBACK_SPEC_URL"
  fi

  if [[ -z "$SPEC_URL" ]]; then
    common_die "[$PROVIDER] Could not locate a spec URL in $INDEX_URL (regex: $SPEC_REGEX)"
  fi
fi

mkdir -p "$OUT_DIR"

SPEC_PATH="$WORKDIR/openapi-spec"
echo "[$PROVIDER] Downloading OpenAPI spec from $SPEC_URL"
"${CURL_BASE[@]}" "$SPEC_URL" -o "$SPEC_PATH"

# Keep a local copy for tooling/debugging.
cp "$SPEC_PATH" "$OUT_DIR/openapi.raw"

timestamp="$(common_timestamp_utc)"

args=("$SPEC_PATH" "$OUT_DIR" "$SPEC_URL" "$timestamp")
if [[ -n "$TITLE" ]]; then
  args+=("$TITLE")
fi

ruby "$SCRIPT_DIR/lib/openapi_to_markdown.rb" "${args[@]}"

echo "[$PROVIDER] Wrote OpenAPI reference into $OUT_DIR"
