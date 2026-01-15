#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: providers/huggingface.sh [--output DIR] [--index-url URL] [--full-index-url URL] [--throttle-seconds SECONDS] [--token TOKEN]

Mirror the Hugging Face Hub docs referenced by llms.txt.
USAGE
}

OUTPUT_DIR="huggingface-hub-docs"
INDEX_URL="https://huggingface.co/docs/hub/llms.txt"
FULL_INDEX_URL="https://huggingface.co/docs/hub/llms-full.txt"
THROTTLE_SECONDS="0.1"
TOKEN="${HF_TOKEN:-}"

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/llms.sh"

if [[ "$OUTPUT_DIR" = /* ]]; then
  OUT_DIR="$OUTPUT_DIR"
else
  OUT_DIR="$ROOT_DIR/$OUTPUT_DIR"
fi

LLMS_CURL_BASE=(curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused --retry-all-errors --retry-max-time 120 --http1.1)
if [[ -n "$TOKEN" ]]; then
  LLMS_CURL_BASE+=(-H "Authorization: Bearer $TOKEN")
fi

PATTERN="https://huggingface\\.co/docs/hub/[A-Za-z0-9._\\-/]+\\.md"
llms_mirror "huggingface" "$INDEX_URL" "$FULL_INDEX_URL" "$PATTERN" "https://huggingface.co/docs/hub/" "" "$OUT_DIR" "$THROTTLE_SECONDS"
