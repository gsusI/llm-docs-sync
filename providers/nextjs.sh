#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: providers/nextjs.sh [--output DIR] [--branch BRANCH]

Fetch Next.js docs from GitHub (default branch: canary) and concatenate them
into a single markdown file inside the output directory.
USAGE
}

OUTPUT_DIR="nextjs"
BRANCH="canary"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --branch)
      BRANCH="${2:-}"
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

for cmd in git mktemp find sort; do
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

REPO_URL="https://github.com/vercel/next.js.git"

echo "[nextjs] Fetching docs from branch '$BRANCH'..."
git clone --depth=1 --filter=blob:none --sparse --branch "$BRANCH" "$REPO_URL" "$WORKDIR/nextjs" >/dev/null
cd "$WORKDIR/nextjs"
git sparse-checkout set docs >/dev/null

DOCS_DIR="$WORKDIR/nextjs/docs"
files=()
while IFS= read -r file; do
  files+=("$file")
done < <(cd "$DOCS_DIR" && find . -type f \( -name '*.md' -o -name '*.mdx' \) -print | LC_ALL=C sort)

mkdir -p "$OUT_DIR"
OUT_PATH="$OUT_DIR/index.md"
timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

{
  echo "# Next.js docs (branch: $BRANCH)"
  echo "Source: https://github.com/vercel/next.js/tree/$BRANCH/docs"
  echo "Generated: $timestamp"
} > "$OUT_PATH"

for rel in "${files[@]}"; do
  rel_path="${rel#./}"
  file_path="$DOCS_DIR/$rel_path"
  {
    echo
    echo "---"
    echo "## File: $rel_path"
    cat "$file_path"
  } >> "$OUT_PATH"
done

echo "[nextjs] Wrote ${#files[@]} files into $OUT_PATH"
