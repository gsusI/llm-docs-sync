#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: providers/types/github.sh --provider NAME --output DIR --repo-url URL [options]

Options:
  --branch BRANCH        Git branch/tag (default: main)
  --docs-path PATH       Sparse-checkout path (default: docs). Use '.' to keep whole repo.
  --mode copy|concat     copy: write individual files (default)
                        concat: concatenate into index.md
USAGE
}

PROVIDER=""
OUT_DIR=""
REPO_URL=""
BRANCH="main"
DOCS_PATH="docs"
MODE="copy"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      PROVIDER="${2:-}"; shift 2 ;;
    --output)
      OUT_DIR="${2:-}"; shift 2 ;;
    --repo-url)
      REPO_URL="${2:-}"; shift 2 ;;
    --branch)
      BRANCH="${2:-}"; shift 2 ;;
    --docs-path)
      DOCS_PATH="${2:-}"; shift 2 ;;
    --mode)
      MODE="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      usage; exit 1 ;;
  esac
done

if [[ -z "$PROVIDER" || -z "$OUT_DIR" || -z "$REPO_URL" ]]; then
  usage
  exit 1
fi

common_require_cmds git mktemp find sort

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

REPO_DIR="$WORKDIR/repo"

# Clone shallow + sparse when possible to keep it fast.
echo "[$PROVIDER] Cloning $REPO_URL (branch: $BRANCH)"

git clone --depth=1 --filter=blob:none --sparse --branch "$BRANCH" "$REPO_URL" "$REPO_DIR" >/dev/null 2>&1 || \
  common_die "[$PROVIDER] Failed to clone repo (url=$REPO_URL branch=$BRANCH)"

cd "$REPO_DIR"

if [[ -n "$DOCS_PATH" && "$DOCS_PATH" != "." ]]; then
  git sparse-checkout set "$DOCS_PATH" >/dev/null 2>&1 || common_die "[$PROVIDER] Sparse-checkout failed for path: $DOCS_PATH"
fi

BASE_DIR="$REPO_DIR"
if [[ -n "$DOCS_PATH" && "$DOCS_PATH" != "." ]]; then
  BASE_DIR="$REPO_DIR/$DOCS_PATH"
fi

if [[ ! -d "$BASE_DIR" ]]; then
  common_die "[$PROVIDER] Docs path not found: $DOCS_PATH"
fi

files=()
while IFS= read -r file; do
  files+=("$file")
done < <(cd "$BASE_DIR" && find . -type f \( -name '*.md' -o -name '*.mdx' \) -print | LC_ALL=C sort)

mkdir -p "$OUT_DIR"

if [[ "$MODE" == "concat" ]]; then
  OUT_PATH="$OUT_DIR/index.md"
  timestamp="$(common_timestamp_utc)"

  {
    echo "# $PROVIDER docs"
    echo "Source: $REPO_URL"
    echo "Branch: $BRANCH"
    echo "Docs path: $DOCS_PATH"
    echo "Generated: $timestamp"
  } > "$OUT_PATH"

  for rel in "${files[@]}"; do
    rel_path="${rel#./}"
    src_path="$BASE_DIR/$rel_path"
    {
      echo
      echo "---"
      echo "## File: $rel_path"
      cat "$src_path"
    } >> "$OUT_PATH"
  done

  echo "[$PROVIDER] Wrote ${#files[@]} files into $OUT_PATH"
  exit 0
fi

# copy mode
INDEX_MD="$OUT_DIR/index.md"
{
  echo "# $PROVIDER docs"
  echo "Source: $REPO_URL"
  echo "Branch: $BRANCH"
  echo "Docs path: $DOCS_PATH"
  echo "Generated: $(common_timestamp_utc)"
  echo
  echo "## Files (${#files[@]})"
} > "$INDEX_MD"

for rel in "${files[@]}"; do
  rel_path="${rel#./}"
  src_path="$BASE_DIR/$rel_path"

  safe_rel="$(common_sanitize_relpath "$rel_path")"
  dest_path="$OUT_DIR/$safe_rel"
  mkdir -p "$(dirname "$dest_path")"
  cp "$src_path" "$dest_path"

  echo "- [$safe_rel]($safe_rel)" >> "$INDEX_MD"
done

echo "[$PROVIDER] Copied ${#files[@]} files into $OUT_DIR"
