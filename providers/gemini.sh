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

echo "[gemini] Downloading llms.txt index from $INDEX_URL"
CURL_BASE=(curl -fsSL --retry 3 --retry-delay 1 --retry-connrefused --http1.1)
"${CURL_BASE[@]}" "$INDEX_URL" -o "$WORKDIR/llms.txt"

URLS=()
while IFS= read -r line; do
  URLS+=("$line")
done < <(rg -o "https://ai\\.google\\.dev/gemini-api/[A-Za-z0-9._\-/]+\\.md\\.txt" "$WORKDIR/llms.txt" | sort -u)

if [[ ${#URLS[@]} -eq 0 ]]; then
  echo "No Markdown doc URLs found in $INDEX_URL" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

for url in "${URLS[@]}"; do
  rel="${url#https://ai.google.dev/gemini-api/}"
  rel="${rel%.txt}"
  dest="$OUT_DIR/$rel"
  mkdir -p "$(dirname "$dest")"
  echo "[gemini] Downloading $rel"
  "${CURL_BASE[@]}" "$url" -o "$dest"
done

cp "$WORKDIR/llms.txt" "$OUT_DIR/llms.txt"

index_path="$OUT_DIR/index.md"
{
  echo "# Gemini API docs"
  echo "Source index: $INDEX_URL"
  echo "Downloaded: $timestamp"
  echo
  echo "## Files"
  for url in "${URLS[@]}"; do
    rel="${url#https://ai.google.dev/gemini-api/}"
    rel="${rel%.txt}"
    echo "- [$rel]($rel)"
  done
} > "$index_path"

echo "[gemini] Downloaded ${#URLS[@]} docs into $OUT_DIR"
