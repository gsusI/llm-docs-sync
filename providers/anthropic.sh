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

for cmd in curl mktemp rg sort; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ "$OUTPUT_DIR" = /* ]]; then
  OUT_DIR="$OUTPUT_DIR"
else
  OUT_DIR="$ROOT_DIR/$OUTPUT_DIR"
fi

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

CURL_BASE=(curl -fsSL --retry 3 --retry-delay 1 --retry-connrefused --http1.1)

echo "[anthropic] Downloading llms.txt index from $INDEX_URL"
"${CURL_BASE[@]}" "$INDEX_URL" -o "$WORKDIR/llms.txt"

FULL_AVAILABLE=false
full_note="not downloaded"
if "${CURL_BASE[@]}" "$FULL_INDEX_URL" -o "$WORKDIR/llms-full.txt"; then
  FULL_AVAILABLE=true
  full_note="$FULL_INDEX_URL"
else
  echo "[anthropic] Warning: could not download llms-full.txt from $FULL_INDEX_URL" >&2
fi

if [[ "$LANG" == "all" ]]; then
  pattern="https://platform\\.claude\\.com/docs/[A-Za-z0-9._-]+/[A-Za-z0-9._\\-/]+\\.md"
else
  lang_escaped="${LANG//\//\\/}"
  pattern="https://platform\\.claude\\.com/docs/${lang_escaped}/[A-Za-z0-9._\\-/]+\\.md"
fi

URLS=()
while IFS= read -r url; do
  URLS+=("$url")
done < <(rg -o "$pattern" "$WORKDIR/llms.txt" | sort -u)

if [[ ${#URLS[@]} -eq 0 ]]; then
  echo "No Markdown doc URLs found in $INDEX_URL for LANG=$LANG" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

for url in "${URLS[@]}"; do
  rel="${url#https://platform.claude.com/docs/}"
  dest="$OUT_DIR/$rel"
  mkdir -p "$(dirname "$dest")"
  echo "[anthropic] Downloading $rel"
  "${CURL_BASE[@]}" "$url" -o "$dest"
done

cp "$WORKDIR/llms.txt" "$OUT_DIR/llms.txt"
if [[ "$FULL_AVAILABLE" == true ]]; then
  cp "$WORKDIR/llms-full.txt" "$OUT_DIR/llms-full.txt"
fi

index_path="$OUT_DIR/index.md"
{
  echo "# Anthropic API docs"
  echo "Source index: $INDEX_URL"
  echo "Full index: $full_note"
  echo "Downloaded: $timestamp"
  echo "Language: $LANG"
  echo
  echo "## Files (${#URLS[@]})"
  for url in "${URLS[@]}"; do
    rel="${url#https://platform.claude.com/docs/}"
    echo "- [$rel]($rel)"
  done
} > "$index_path"

echo "[anthropic] Downloaded ${#URLS[@]} docs into $OUT_DIR"
