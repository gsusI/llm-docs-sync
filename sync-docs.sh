#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./sync-docs.sh [--output DIR] [provider ...]

Fetch LLM API docs for the given providers (default: openai gemini).
Outputs land in DIR/<provider>, so you can vendor docs inside your project for
LLM RAG or offline use.

Providers available:
- openai
- gemini

Examples:
  ./sync-docs.sh                     # fetch OpenAI + Gemini into ./docs
  ./sync-docs.sh --output vendor llm # fetch OpenAI + Gemini into ./vendor
  ./sync-docs.sh gemini              # fetch only Gemini docs
USAGE
}

OUTPUT_ROOT="docs"
providers=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_ROOT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      providers+=("$1")
      shift
      ;;
  esac
done

if [[ ${#providers[@]} -eq 0 ]]; then
  providers=(openai gemini)
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$OUTPUT_ROOT"

for provider in "${providers[@]}"; do
  case "$provider" in
    openai)
      "$SCRIPT_DIR/providers/openai.sh" --output "$OUTPUT_ROOT/openai"
      ;;
    gemini)
      "$SCRIPT_DIR/providers/gemini.sh" --output "$OUTPUT_ROOT/gemini"
      ;;
    *)
      echo "Unknown provider: $provider" >&2
      exit 1
      ;;
  esac
done

echo "Done. Docs are under $OUTPUT_ROOT/"
