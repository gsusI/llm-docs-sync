#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./sync-docs.sh [--output DIR] [--jobs N] [--version-label LABEL|--timestamp-label] [--latest-alias NAME] [--keep-going] [provider ...]
  ./sync-docs.sh --source URL [--output DIR] [--jobs N] [--version-label LABEL|--timestamp-label] [--latest-alias NAME] [--provider NAME] [--type auto|llms|openapi|github] [source options]
  ./sync-docs.sh --list
  ./sync-docs.sh --interactive

Defaults:
  If no providers are supplied, defaults to: openai gemini anthropic

Notes:
  - Providers are defined by files in providers/defs/*.sh.
  - Use '--source' to sync an arbitrary llms.txt, OpenAPI spec URL, or GitHub repo without adding code.
  - Use '--jobs' to run multiple providers concurrently (provider mode only).
USAGE
}

OUTPUT_ROOT="docs"
INTERACTIVE=false
LIST=false
KEEP_GOING=false
JOBS="1"
VERSION_LABEL=""
USE_TIMESTAMP_LABEL=false
LATEST_ALIAS=""

SOURCE_URL=""
SOURCE_ARGS=()
SOURCE_PROVIDER_OVERRIDE=""
SOURCE_OPTS_USED=false

providers=()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/providers/lib/common.sh"

list_providers() {
  local defs_dir="$SCRIPT_DIR/providers/defs"
  if [[ ! -d "$defs_dir" ]]; then
    return 0
  fi
  (cd "$defs_dir" && ls -1 *.sh 2>/dev/null | sed 's/[.]sh$//' | LC_ALL=C sort)
}

derive_provider_from_url() {
  local url="${1:-}"
  url="${url#http://}"
  url="${url#https://}"
  url="${url%%/*}"
  url="${url//[^A-Za-z0-9._-]/-}"
  url="${url#-}"
  url="${url%-}"
  [[ -n "$url" ]] || url="source"
  printf '%s' "$url"
}

sanitize_label() {
  echo "${1//[^A-Za-z0-9._-]/_}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_ROOT="${2:-}"; shift 2 ;;
    -i|--interactive)
      INTERACTIVE=true; shift ;;
    --list)
      LIST=true; shift ;;
    --keep-going)
      KEEP_GOING=true; shift ;;
    --jobs)
      JOBS="${2:-}"; shift 2 ;;
    --version-label)
      VERSION_LABEL="${2:-}"; shift 2 ;;
    --timestamp-label)
      USE_TIMESTAMP_LABEL=true; shift ;;
    --latest-alias)
      LATEST_ALIAS="${2:-}"; shift 2 ;;
    --source)
      SOURCE_URL="${2:-}"; shift 2 ;;
    --provider)
      SOURCE_PROVIDER_OVERRIDE="${2:-}"
      SOURCE_ARGS+=("--provider" "${2:-}")
      SOURCE_OPTS_USED=true
      shift 2 ;;
    --type)
      SOURCE_ARGS+=("--type" "${2:-}")
      SOURCE_OPTS_USED=true
      shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    --*)
      SOURCE_OPTS_USED=true
      # Flags with no value.
      case "$1" in
        --include-full-index|--fail-on-missing)
          SOURCE_ARGS+=("$1"); shift ;;
        *)
          SOURCE_ARGS+=("$1" "${2:-}")
          shift 2 ;;
      esac
      ;;
    *)
      providers+=("$1")
      shift ;;
  esac
done

if [[ "$SOURCE_OPTS_USED" == true && -z "$SOURCE_URL" ]]; then
  usage
  exit 1
fi

if ! [[ "$JOBS" =~ ^[0-9]+$ ]] || [[ "$JOBS" -lt 1 ]]; then
  common_die "--jobs must be a positive integer"
fi

if [[ -n "$SOURCE_URL" && ${#providers[@]} -gt 0 ]]; then
  common_die "Do not mix --source with named providers in one run"
fi

if [[ "$LIST" == true ]]; then
  list_providers
  exit 0
fi

if [[ "$INTERACTIVE" == true ]]; then
  default_providers=()
  if [[ ${#providers[@]} -gt 0 ]]; then
    default_providers=("${providers[@]}")
  else
    default_providers=(openai gemini anthropic)
  fi

  read -r -p "Output directory [${OUTPUT_ROOT}]: " answer
  if [[ -n "${answer:-}" ]]; then
    OUTPUT_ROOT="$answer"
  fi

  available_providers="$(list_providers | tr '\n' ' ' | sed -E 's/[ ]+$//')"
  if [[ -n "$available_providers" ]]; then
    echo "Available providers: $available_providers"
  fi

  read -r -p "Providers (space separated) [${default_providers[*]}]: " answer
  if [[ -n "${answer:-}" ]]; then
    providers=($answer)
  else
    providers=("${default_providers[@]}")
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

if [[ -z "$SOURCE_URL" && ${#providers[@]} -eq 0 ]]; then
  providers=(openai gemini anthropic)
fi

mkdir -p "$OUTPUT_ROOT"

RUN_TIMESTAMP="$(common_timestamp_utc)"
manifest_entries=()

if [[ "$USE_TIMESTAMP_LABEL" == true && -z "$VERSION_LABEL" ]]; then
  VERSION_LABEL="$(date -u +"%Y%m%d-%H%M%S")"
fi

run_one() {
  local provider="$1"
  local base_dir="$2"

  "$SCRIPT_DIR/providers/run.sh" "$provider" --output "$base_dir"
}

run_source() {
  local url="$1"
  local provider_name="$2"
  local base_dir="$3"

  "$SCRIPT_DIR/providers/run.sh" --source "$url" --output "$base_dir" --provider "$provider_name" "${SOURCE_ARGS[@]}"
}

append_manifest() {
  local provider="$1"
  local out_dir="$2"
  local label="$3"
  local status="$4"

  provider_escaped="$(common_json_escape "$provider")"
  out_dir_escaped="$(common_json_escape "$out_dir")"
  label_escaped="$(common_json_escape "$label")"
  status_escaped="$(common_json_escape "$status")"
  ts_escaped="$(common_json_escape "$RUN_TIMESTAMP")"

  manifest_entries+=("{\"provider\":\"$provider_escaped\",\"output\":\"$out_dir_escaped\",\"timestamp\":\"$ts_escaped\",\"label\":\"$label_escaped\",\"status\":\"$status_escaped\"}")
}

# --source mode
if [[ -n "$SOURCE_URL" ]]; then
  provider_name="$SOURCE_PROVIDER_OVERRIDE"
  if [[ -z "$provider_name" ]]; then
    provider_name="$(derive_provider_from_url "$SOURCE_URL")"
  fi

  base_dir="$OUTPUT_ROOT/$provider_name"
  label=""
  if [[ -n "$VERSION_LABEL" ]]; then
    label="$(sanitize_label "$VERSION_LABEL")"
    base_dir="$base_dir/$label"
  fi

  status="ok"
  if ! run_source "$SOURCE_URL" "$provider_name" "$base_dir"; then
    status="error"
    if [[ "$KEEP_GOING" != true ]]; then
      append_manifest "$provider_name" "$base_dir" "${label:-}" "$status"
      common_die "Source sync failed: $SOURCE_URL"
    fi
  fi

  if [[ -n "$LATEST_ALIAS" && -n "$label" ]]; then
    alias_path="$OUTPUT_ROOT/$provider_name/$LATEST_ALIAS"
    mkdir -p "$(dirname "$alias_path")"
    ln -sfn "$label" "$alias_path"
  fi

  append_manifest "$provider_name" "$base_dir" "${label:-}" "$status"
else
  # Provider mode
  if [[ "$JOBS" -le 1 || ${#providers[@]} -le 1 ]]; then
    for provider in "${providers[@]}"; do
      base_dir="$OUTPUT_ROOT/$provider"
      label=""
      if [[ -n "$VERSION_LABEL" ]]; then
        label="$(sanitize_label "$VERSION_LABEL")"
        base_dir="$base_dir/$label"
      fi

      status="ok"
      if ! run_one "$provider" "$base_dir"; then
        status="error"
        if [[ "$KEEP_GOING" != true ]]; then
          append_manifest "$provider" "$base_dir" "${label:-}" "$status"
          common_die "Provider sync failed: $provider"
        fi
      fi

      if [[ -n "$LATEST_ALIAS" && -n "$label" ]]; then
        alias_path="$OUTPUT_ROOT/$provider/$LATEST_ALIAS"
        mkdir -p "$(dirname "$alias_path")"
        ln -sfn "$label" "$alias_path"
      fi

      append_manifest "$provider" "$base_dir" "${label:-}" "$status"
    done
  else
    results_dir="$(mktemp -d)"
    cleanup_results() { rm -rf "$results_dir"; }
    trap cleanup_results EXIT

    semaphore="$results_dir/semaphore"
    mkfifo "$semaphore"
    exec 9<>"$semaphore"
    rm -f "$semaphore"
    for ((i=0; i<JOBS; i++)); do printf '.' >&9; done

    provider_base_dirs=()
    provider_labels=()
    provider_results=()

    for provider in "${providers[@]}"; do
      base_dir="$OUTPUT_ROOT/$provider"
      label=""
      if [[ -n "$VERSION_LABEL" ]]; then
        label="$(sanitize_label "$VERSION_LABEL")"
        base_dir="$base_dir/$label"
      fi

      result_file="$results_dir/result-${#provider_results[@]}"
      provider_base_dirs+=("$base_dir")
      provider_labels+=("$label")
      provider_results+=("$result_file")

      read -r -u 9
      (
        status="ok"
        if ! run_one "$provider" "$base_dir"; then
          status="error"
        fi

        if [[ -n "$LATEST_ALIAS" && -n "$label" ]]; then
          alias_path="$OUTPUT_ROOT/$provider/$LATEST_ALIAS"
          mkdir -p "$(dirname "$alias_path")"
          ln -sfn "$label" "$alias_path"
        fi

        printf '%s' "$status" > "$result_file"
        printf '.' >&9
      ) &
    done

    wait || true
    exec 9>&-
    exec 9<&-

    failed_provider=""
    for i in "${!providers[@]}"; do
      provider="${providers[$i]}"
      base_dir="${provider_base_dirs[$i]}"
      label="${provider_labels[$i]}"
      result_file="${provider_results[$i]}"
      status="error"
      if [[ -f "$result_file" ]]; then
        status="$(cat "$result_file")"
      fi

      append_manifest "$provider" "$base_dir" "${label:-}" "$status"
      if [[ "$status" != "ok" && -z "$failed_provider" ]]; then
        failed_provider="$provider"
      fi
    done

    if [[ -n "$failed_provider" && "$KEEP_GOING" != true ]]; then
      common_die "Provider sync failed: $failed_provider"
    fi
  fi
fi

# Manifest
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
