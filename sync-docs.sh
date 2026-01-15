#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./sync-docs.sh [--output DIR] [--version-label LABEL|--timestamp-label] [--latest-alias NAME] [provider ...]
       ./sync-docs.sh --interactive

Fetch docs for the given providers (default: openai gemini anthropic).
Outputs land in DIR/<provider>, so you can vendor docs inside your project for
LLM RAG or offline use.

Providers available:
- openai
- gemini
- anthropic
- huggingface
- openrouter
- cohere
- nextjs

Examples:
  ./sync-docs.sh                                 # fetch OpenAI + Gemini + Anthropic into ./docs
  ./sync-docs.sh --output vendor llm             # fetch OpenAI + Gemini + Anthropic into ./vendor
  ./sync-docs.sh gemini anthropic                # fetch only Gemini + Anthropic docs
  ./sync-docs.sh --version-label 2025-01-15      # write into ./docs/<provider>/2025-01-15 and keep ./docs/<provider> unchanged
  ./sync-docs.sh --timestamp-label --latest-alias latest # timestamped subfolders + refresh ./docs/<provider>/latest symlink
USAGE
}

OUTPUT_ROOT="docs"
providers=()
INTERACTIVE=false
VERSION_LABEL=""
USE_TIMESTAMP_LABEL=false
LATEST_ALIAS=""

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
    --version-label)
      VERSION_LABEL="${2:-}"
      shift 2
      ;;
    --timestamp-label)
      USE_TIMESTAMP_LABEL=true
      shift
      ;;
    --latest-alias)
      LATEST_ALIAS="${2:-}"
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
  providers=(openai gemini anthropic)
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$INTERACTIVE" == true ]]; then
  default_providers="${providers[*]}"
  if [[ -z "$default_providers" ]]; then
    default_providers="openai gemini anthropic"
  fi

  read -r -p "Output directory [${OUTPUT_ROOT}]: " answer
  if [[ -n "${answer:-}" ]]; then
    OUTPUT_ROOT="$answer"
  fi

  echo "Available providers: openai gemini anthropic huggingface openrouter cohere nextjs"
  read -r -p "Providers (space separated) [${default_providers}]: " answer
  if [[ -n "${answer:-}" ]]; then
    providers=($answer)
  else
    providers=($default_providers)
  fi

  read -r -p "Version label (empty for none): " answer
  if [[ -n "${answer:-}" ]]; then
    VERSION_LABEL="$answer"
  fi

  read -r -p "Set latest alias name (empty to skip): " answer
  if [[ -n "${answer:-}" ]]; then
    LATEST_ALIAS="$answer"
  fi
fi

mkdir -p "$OUTPUT_ROOT"

RUN_TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
manifest_entries=()

sanitize_label() {
  echo "${1//[^A-Za-z0-9._-]/_}"
}

if [[ "$USE_TIMESTAMP_LABEL" == true && -z "$VERSION_LABEL" ]]; then
  VERSION_LABEL="$(date -u +"%Y%m%d-%H%M%S")"
fi

for provider in "${providers[@]}"; do
  base_dir="$OUTPUT_ROOT/$provider"
  label=""
  if [[ -n "$VERSION_LABEL" ]]; then
    label="$(sanitize_label "$VERSION_LABEL")"
    base_dir="$base_dir/$label"
  fi

  case "$provider" in
    openai)
      "$SCRIPT_DIR/providers/openai.sh" --output "$base_dir"
      ;;
    gemini)
      "$SCRIPT_DIR/providers/gemini.sh" --output "$base_dir"
      ;;
    anthropic)
      "$SCRIPT_DIR/providers/anthropic.sh" --output "$base_dir"
      ;;
    huggingface)
      "$SCRIPT_DIR/providers/huggingface.sh" --output "$base_dir"
      ;;
    openrouter)
      "$SCRIPT_DIR/providers/openrouter.sh" --output "$base_dir"
      ;;
    cohere)
      "$SCRIPT_DIR/providers/cohere.sh" --output "$base_dir"
      ;;
    nextjs)
      "$SCRIPT_DIR/providers/nextjs.sh" --output "$base_dir"
      ;;
    *)
      echo "Unknown provider: $provider" >&2
      exit 1
      ;;
  esac

  if [[ -n "$LATEST_ALIAS" && -n "$label" ]]; then
    alias_path="$OUTPUT_ROOT/$provider/$LATEST_ALIAS"
    mkdir -p "$(dirname "$alias_path")"
    ln -sfn "$label" "$alias_path"
  fi

  manifest_entries+=("{\"provider\":\"$provider\",\"output\":\"$base_dir\",\"timestamp\":\"$RUN_TIMESTAMP\",\"label\":\"${label:-}\"}")
done

if [[ ${#manifest_entries[@]} -gt 0 ]]; then
  manifest_path="$OUTPUT_ROOT/manifest.json"
  {
    echo "["
    for i in "${!manifest_entries[@]}"; do
      sep=","
      if [[ $i -eq $((${#manifest_entries[@]} - 1)) ]]; then
        sep=""
      fi
      echo "  ${manifest_entries[$i]}$sep"
    done
    echo "]"
  } > "$manifest_path"
  echo "Wrote manifest to $manifest_path"
fi

echo "Done. Docs are under $OUTPUT_ROOT/"
