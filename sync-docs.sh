#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./sync-docs.sh [--output DIR] [provider ...]
       ./sync-docs.sh --interactive

Fetch docs for the given providers (default: openai gemini).
Outputs land in DIR/<provider>, so you can vendor docs inside your project for
LLM RAG or offline use.

Providers available:
- openai
- gemini
- nextjs

Examples:
  ./sync-docs.sh                     # fetch OpenAI + Gemini into ./docs
  ./sync-docs.sh --output vendor llm # fetch OpenAI + Gemini into ./vendor
  ./sync-docs.sh gemini              # fetch only Gemini docs
USAGE
}

OUTPUT_ROOT="docs"
providers=()
INTERACTIVE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_ROOT="${2:-}"
      shift 2
      ;;
    -i|--interactive)
      INTERACTIVE=true
      shift
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

if [[ "$INTERACTIVE" == true ]]; then
  default_providers="${providers[*]}"
  if [[ -z "$default_providers" ]]; then
    default_providers="openai gemini"
  fi

  read -r -p "Output directory [${OUTPUT_ROOT}]: " answer
  if [[ -n "${answer:-}" ]]; then
    OUTPUT_ROOT="$answer"
  fi

  echo "Available providers: openai gemini nextjs"
  read -r -p "Providers (space separated) [${default_providers}]: " answer
  if [[ -n "${answer:-}" ]]; then
    providers=($answer)
  else
    providers=($default_providers)
  fi
fi

mkdir -p "$OUTPUT_ROOT"

for provider in "${providers[@]}"; do
  case "$provider" in
    openai)
      "$SCRIPT_DIR/providers/openai.sh" --output "$OUTPUT_ROOT/openai"
      ;;
    gemini)
      "$SCRIPT_DIR/providers/gemini.sh" --output "$OUTPUT_ROOT/gemini"
      ;;
    nextjs)
      "$SCRIPT_DIR/providers/nextjs.sh" --output "$OUTPUT_ROOT/nextjs"
      ;;
    *)
      echo "Unknown provider: $provider" >&2
      exit 1
      ;;
  esac
done

echo "Done. Docs are under $OUTPUT_ROOT/"
