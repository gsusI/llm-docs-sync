#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: providers/generic-llms.sh --provider NAME --index-url URL [--full-index-url URL] [--strip-prefix PREFIX] [--strip-suffix SUFFIX] [--pattern REGEX] [--output DIR] [--throttle-seconds SECONDS] [--token TOKEN]

Mirror docs referenced by a llms.txt index. Intended for simple mirror-only providers.
USAGE
}

PROVIDER=""
OUTPUT_DIR=""
INDEX_URL=""
FULL_INDEX_URL=""
STRIP_PREFIX=""
STRIP_SUFFIX=""
PATTERN=""
THROTTLE_SECONDS="0.1"
TOKEN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      PROVIDER="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --index-url)
      INDEX_URL="${2:-}"
      shift 2
      ;;
    --full-index-url)
      FULL_INDEX_URL="${2:-}"
      shift 2
      ;;
    --strip-prefix)
      STRIP_PREFIX="${2:-}"
      shift 2
      ;;
    --strip-suffix)
      STRIP_SUFFIX="${2:-}"
      shift 2
      ;;
    --pattern)
      PATTERN="${2:-}"
      shift 2
      ;;
    --throttle-seconds)
      THROTTLE_SECONDS="${2:-0}"
      shift 2
      ;;
    --token)
      TOKEN="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$PROVIDER" || -z "$INDEX_URL" ]]; then
  usage
  exit 1
fi

if [[ -z "$PATTERN" ]]; then
  PATTERN="https?://[^ ]+\\.(md|mdx)"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/llms.sh"

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="${PROVIDER}-docs"
fi

if [[ "$OUTPUT_DIR" = /* ]]; then
  OUT_DIR="$OUTPUT_DIR"
else
  OUT_DIR="$ROOT_DIR/$OUTPUT_DIR"
fi

LLMS_CURL_BASE=(curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused --retry-all-errors --retry-max-time 120 --http1.1)
if [[ -n "$TOKEN" ]]; then
  LLMS_CURL_BASE+=(-H "Authorization: Bearer $TOKEN")
fi

llms_mirror "$PROVIDER" "$INDEX_URL" "$FULL_INDEX_URL" "$PATTERN" "$STRIP_PREFIX" "$STRIP_SUFFIX" "$OUT_DIR" "$THROTTLE_SECONDS"
