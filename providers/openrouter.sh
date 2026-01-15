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

CURL_BASE=(curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused --retry-all-errors --retry-max-time 120 --http1.1)

fetch_with_retry() {
  local url="$1"
  local dest="$2"
  local label="$3"

  local attempt=1
  local max_attempts=6
  while true; do
    if "${CURL_BASE[@]}" "$url" -o "$dest"; then
      return 0
    fi

    if [[ "$attempt" -ge "$max_attempts" ]]; then
      echo "[openrouter] Failed to download $label after $attempt attempts" >&2
      return 1
    fi

    sleep_seconds=$((attempt * 2))
    echo "[openrouter] Retry $attempt for $label in ${sleep_seconds}s" >&2
    sleep "$sleep_seconds"
    attempt=$((attempt + 1))
  done
}

echo "[openrouter] Downloading llms.txt index from $INDEX_URL"
fetch_with_retry "$INDEX_URL" "$WORKDIR/llms.txt" "llms.txt"

FULL_AVAILABLE=false
full_note="not downloaded"
if fetch_with_retry "$FULL_INDEX_URL" "$WORKDIR/llms-full.txt" "llms-full.txt"; then
  FULL_AVAILABLE=true
  full_note="$FULL_INDEX_URL"
else
  echo "[openrouter] Warning: could not download llms-full.txt from $FULL_INDEX_URL" >&2
fi

pattern="https://openrouter\\.ai/docs/[A-Za-z0-9._\\-/]+\\.mdx?"
URLS=()
while IFS= read -r url; do
  URLS+=("$url")
done < <(rg -o "$pattern" "$WORKDIR/llms.txt" | sort -u)

if [[ ${#URLS[@]} -eq 0 ]]; then
  echo "No Markdown doc URLs found in $INDEX_URL" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

for url in "${URLS[@]}"; do
  rel="${url#https://openrouter.ai/docs/}"
  dest="$OUT_DIR/$rel"
  mkdir -p "$(dirname "$dest")"
  echo "[openrouter] Downloading $rel"
  fetch_with_retry "$url" "$dest" "$rel"
  if [[ -n "$THROTTLE_SECONDS" && "$THROTTLE_SECONDS" != "0" ]]; then
    sleep "$THROTTLE_SECONDS"
  fi
done

cp "$WORKDIR/llms.txt" "$OUT_DIR/llms.txt"
if [[ "$FULL_AVAILABLE" == true ]]; then
  cp "$WORKDIR/llms-full.txt" "$OUT_DIR/llms-full.txt"
fi

index_path="$OUT_DIR/index.md"
{
  echo "# OpenRouter docs"
  echo "Source index: $INDEX_URL"
  echo "Full index: $full_note"
  echo "Downloaded: $timestamp"
  echo
  echo "## Files (${#URLS[@]})"
  for url in "${URLS[@]}"; do
    rel="${url#https://openrouter.ai/docs/}"
    echo "- [$rel]($rel)"
  done
} > "$index_path"

echo "[openrouter] Downloaded ${#URLS[@]} docs into $OUT_DIR"
