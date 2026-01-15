#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: providers/anthropic.sh [--output DIR] [--index-url URL] [--full-index-url URL] [--lang LANG|all]

Download the Anthropic/Claude documentation referenced by the Anthropic llms.txt
index and save Markdown pages into the output directory.
USAGE
}

OUTPUT_DIR="anthropic-api-docs"
INDEX_URL="https://platform.claude.com/llms.txt"
FULL_INDEX_URL="https://platform.claude.com/llms-full.txt"
LANG="en"

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
    --lang)
      LANG="${2:-}"
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

PATTERN="https://platform\\.claude\\.com/docs/[A-Za-z0-9._\\-/]+\\.md"
if [[ "$LANG" != "all" ]]; then
  lang_escaped="${LANG//\//\\/}"
  PATTERN="https://platform\\.claude\\.com/docs/${lang_escaped}/[A-Za-z0-9._\\-/]+\\.md"
fi

LLMS_CURL_BASE=(curl -fsSL --retry 3 --retry-delay 1 --retry-connrefused --http1.1)

llms_mirror "anthropic" "$INDEX_URL" "$FULL_INDEX_URL" "$PATTERN" "https://platform.claude.com/docs/" "" "$OUT_DIR" "0"
