#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: providers/openrouter.sh [--output DIR] [--index-url URL] [--full-index-url URL] [--throttle-seconds SECONDS]

Mirror the OpenRouter docs referenced by llms.txt.
USAGE
}

OUTPUT_DIR="openrouter-docs"
INDEX_URL="https://openrouter.ai/docs/llms.txt"
FULL_INDEX_URL="https://openrouter.ai/docs/llms-full.txt"
THROTTLE_SECONDS="0.1"

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --throttle-seconds)
      THROTTLE_SECONDS="${2:-0}"
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/llms.sh"

if [[ "$OUTPUT_DIR" = /* ]]; then
  OUT_DIR="$OUTPUT_DIR"
else
  OUT_DIR="$ROOT_DIR/$OUTPUT_DIR"
fi

LLMS_CURL_BASE=(curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused --retry-all-errors --retry-max-time 120 --http1.1)

PATTERN="https://openrouter\\.ai/docs/[A-Za-z0-9._\\-/]+\\.mdx?"
llms_mirror "openrouter" "$INDEX_URL" "$FULL_INDEX_URL" "$PATTERN" "https://openrouter.ai/docs/" "" "$OUT_DIR" "$THROTTLE_SECONDS"
