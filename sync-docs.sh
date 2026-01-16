#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/providers/registry.sh"

usage() {
  local provider_preview
  provider_preview="$(all_providers | tr '\n' ' ')"
  cat <<USAGE
Usage: ./sync-docs.sh [--output DIR] [--version-label LABEL|--timestamp-label] [--latest-alias NAME] [provider ...]
       ./sync-docs.sh --interactive
       ./sync-docs.sh --llms-provider name index_url [full_index_url] [strip_prefix] [strip_suffix]
       ./sync-docs.sh --list

Fetch docs for the given providers (default: openai gemini anthropic).
Outputs land in DIR/<provider>, so you can vendor docs inside your project for
LLM RAG or offline use.

Providers available (use --list to print): ${provider_preview:-none}

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
ADHOC_LLMS=()
LIST_ONLY=false
ADHOC_PROVIDER_NAMES=()

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
    --llms-provider)
      shift
      # Usage: --llms-provider name index_url [full_index_url] [strip_prefix] [strip_suffix]
      name="${1:-}"
      index_url="${2:-}"
      if [[ -z "$name" || -z "$index_url" ]]; then
        echo "--llms-provider requires at least: name index_url" >&2
        exit 1
      fi
      shift 2
      full_index_url=""
      strip_prefix=""
      strip_suffix=""
      if [[ $# -gt 0 && "${1:0:2}" != "--" ]]; then
        full_index_url="$1"
        shift
      fi
      if [[ $# -gt 0 && "${1:0:2}" != "--" ]]; then
        strip_prefix="$1"
        shift
      fi
      if [[ $# -gt 0 && "${1:0:2}" != "--" ]]; then
        strip_suffix="$1"
        shift
      fi
      ADHOC_LLMS+=("$name|$index_url|$full_index_url|$strip_prefix|$strip_suffix")
      ADHOC_PROVIDER_NAMES+=("$name")
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
    --list)
      LIST_ONLY=true
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

if [[ "$LIST_ONLY" == true ]]; then
  all_providers
  exit 0
fi

if [[ ${#ADHOC_LLMS[@]} -gt 0 ]]; then
  for entry in "${ADHOC_LLMS[@]}"; do
    IFS="|" read -r name index_url full_index_url strip_prefix strip_suffix <<< "$entry"
    register_llms "$name" "$index_url" "$full_index_url" "$strip_prefix" "$strip_suffix"
  done
fi

if [[ ${#providers[@]} -eq 0 ]]; then
  providers=("${DEFAULT_PROVIDERS[@]}")
fi

if [[ "$INTERACTIVE" == true ]]; then
  default_providers="${providers[*]}"
  if [[ -z "$default_providers" ]]; then
    default_providers="openai gemini anthropic"
  fi
  if [[ ${#ADHOC_PROVIDER_NAMES[@]} -gt 0 ]]; then
    default_providers+=" ${ADHOC_PROVIDER_NAMES[*]}"
  fi

  read -r -p "Output directory [${OUTPUT_ROOT}]: " answer
  if [[ -n "${answer:-}" ]]; then
    OUTPUT_ROOT="$answer"
  fi

  echo "Available providers: $(all_providers | tr '\\n' ' ')"
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

in_list() {
  local needle="$1"; shift
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

merge_adhoc_providers() {
  if [[ ${#ADHOC_PROVIDER_NAMES[@]} -gt 0 ]]; then
    for name in "${ADHOC_PROVIDER_NAMES[@]}"; do
      if ! in_list "$name" "${providers[@]}"; then
        providers+=("$name")
      fi
    done
  fi
}

run_provider() {
  local provider="$1"
  local base_dir="$2"

  if ! load_provider "$provider"; then
    echo "Unknown provider: $provider" >&2
    exit 1
  fi

  local kind="$CURRENT_KIND"
  case "$kind" in
    custom)
      "$SCRIPT_DIR/providers/$CURRENT_SCRIPT" --output "$base_dir"
      ;;
    llms)
      "$SCRIPT_DIR/providers/generic-llms.sh" \
        --provider "$provider" \
        --index-url "$CURRENT_INDEX" \
        --full-index-url "$CURRENT_FULL_INDEX" \
        --strip-prefix "$CURRENT_STRIP_PREFIX" \
        --strip-suffix "$CURRENT_STRIP_SUFFIX" \
        --throttle-seconds "$CURRENT_THROTTLE" \
        --output "$base_dir"
      ;;
    *)
      echo "Unknown provider kind for $provider: $kind" >&2
      exit 1
      ;;
  esac
}

merge_adhoc_providers

for provider in "${providers[@]}"; do
  base_dir="$OUTPUT_ROOT/$provider"
  label=""
  if [[ -n "$VERSION_LABEL" ]]; then
    label="$(sanitize_label "$VERSION_LABEL")"
    base_dir="$base_dir/$label"
  fi

  run_provider "$provider" "$base_dir"

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
