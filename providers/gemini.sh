#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: providers/gemini.sh [--output DIR] [--index-url URL]

Download the Gemini API docs referenced by the Gemini llms.txt index and save
their Markdown counterparts into the output directory.
USAGE
}

OUTPUT_DIR="gemini-api-docs"
INDEX_URL="https://ai.google.dev/gemini-api/docs/llms.txt"

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

PATTERN="https://ai\\.google\\.dev/gemini-api/[A-Za-z0-9._\\-/]+\\.md\\.txt"
llms_mirror "gemini" "$INDEX_URL" "" "$PATTERN" "https://ai.google.dev/gemini-api/" ".txt" "$OUT_DIR" "0"
