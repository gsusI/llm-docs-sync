#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  providers/run.sh PROVIDER --output DIR
  providers/run.sh --source URL [--provider NAME] --output DIR [--type auto|llms|openapi|github] [options]

Options (source mode):
  --type TYPE             Force a type (default: auto)
  --pattern REGEX         llms: regex for doc links
  --full-index-url URL    llms: optional llms-full.txt URL
  --strip-prefix PREFIX   llms: strip prefix
  --strip-suffix SUFFIX   llms: strip suffix
  --throttle-seconds S    llms: sleep between downloads
  --token TOKEN           llms: bearer token
  --header 'K: V'         llms: additional header (repeatable)

  --spec-url URL          openapi: direct spec URL
  --spec-regex REGEX      openapi: regex to find spec URL inside --source index
  --title TITLE           openapi: title for generated index

  --repo-url URL          github: repo URL (default: --source)
  --branch BRANCH         github: branch/tag (default: main)
  --docs-path PATH        github: sparse docs path (default: docs)
  --mode copy|concat      github: output mode (default: copy)
USAGE
}

# Named provider mode.
PROVIDER=""
OUT_DIR=""

# Source mode.
SOURCE_URL=""
TYPE="auto"

# llms options
PATTERN=""
FULL_INDEX_URL=""
STRIP_PREFIX=""
STRIP_SUFFIX=""
THROTTLE_SECONDS=""
TOKEN=""
HEADERS=()

# openapi options
SPEC_URL=""
FALLBACK_SPEC_URL=""
SPEC_REGEX=""
TITLE=""

# github options
REPO_URL=""
BRANCH=""
DOCS_PATH=""
MODE=""

positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUT_DIR="${2:-}"; shift 2 ;;
    --source)
      SOURCE_URL="${2:-}"; shift 2 ;;
    --provider)
      PROVIDER="${2:-}"; shift 2 ;;
    --type)
      TYPE="${2:-}"; shift 2 ;;

    --pattern)
      PATTERN="${2:-}"; shift 2 ;;
    --full-index-url)
      FULL_INDEX_URL="${2:-}"; shift 2 ;;
    --strip-prefix)
      STRIP_PREFIX="${2:-}"; shift 2 ;;
    --strip-suffix)
      STRIP_SUFFIX="${2:-}"; shift 2 ;;
    --throttle-seconds)
      THROTTLE_SECONDS="${2:-}"; shift 2 ;;
    --token)
      TOKEN="${2:-}"; shift 2 ;;
    --header)
      HEADERS+=("${2:-}"); shift 2 ;;

    --spec-url)
      SPEC_URL="${2:-}"; shift 2 ;;
    --fallback-spec-url)
      FALLBACK_SPEC_URL="${2:-}"; shift 2 ;;
    --spec-regex)
      SPEC_REGEX="${2:-}"; shift 2 ;;
    --title)
      TITLE="${2:-}"; shift 2 ;;

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
    --)
      shift
      while [[ $# -gt 0 ]]; do positional+=("$1"); shift; done
      ;;
    -* )
      usage; exit 1 ;;
    *)
      positional+=("$1"); shift ;;
  esac
done

if [[ ${#positional[@]} -gt 0 ]]; then
  if [[ -z "$PROVIDER" ]]; then
    PROVIDER="${positional[0]}"
  else
    # extra positional args are not supported.
    usage
    exit 1
  fi
fi

if [[ -z "$OUT_DIR" ]]; then
  usage
  exit 1
fi

# Helpers

derive_provider_from_url() {
  local url="${1:-}"
  # Strip scheme
  url="${url#http://}"
  url="${url#https://}"
  # Keep host only
  url="${url%%/*}"
  # Sanitize to a filesystem-ish slug
  url="${url//[^A-Za-z0-9._-]/-}"
  url="${url#-}"
  url="${url%-}"
  [[ -n "$url" ]] || url="source"
  printf '%s' "$url"
}

auto_detect_type() {
  local url="${1:-}"

  if [[ "$url" == *"github.com/"* ]] || [[ "$url" == *".git" ]]; then
    printf '%s' "github"
    return 0
  fi

  if [[ "$url" == *"llms.txt" ]] || [[ "$url" == *"llms-full.txt" ]]; then
    printf '%s' "llms"
    return 0
  fi

  case "$url" in
    *.yaml|*.yml|*.json)
      printf '%s' "openapi"
      return 0
      ;;
  esac

  printf '%s' "unknown"
}

run_llms() {
  local args=(
    --provider "$PROVIDER"
    --output "$OUT_DIR"
    --index-url "$INDEX_URL"
  )

  [[ -n "$FULL_INDEX_URL" ]] && args+=(--full-index-url "$FULL_INDEX_URL")
  [[ -n "$PATTERN" ]] && args+=(--pattern "$PATTERN")
  [[ -n "$STRIP_PREFIX" ]] && args+=(--strip-prefix "$STRIP_PREFIX")
  [[ -n "$STRIP_SUFFIX" ]] && args+=(--strip-suffix "$STRIP_SUFFIX")
  [[ -n "$THROTTLE_SECONDS" ]] && args+=(--throttle-seconds "$THROTTLE_SECONDS")
  [[ -n "$TOKEN" ]] && args+=(--token "$TOKEN")

  if [[ ${#HEADERS[@]} -gt 0 ]]; then
    local h
    for h in "${HEADERS[@]}"; do
      [[ -n "$h" ]] || continue
      args+=(--header "$h")
    done
  fi

  exec "$SCRIPT_DIR/types/llms.sh" "${args[@]}"
}

run_openapi() {
  local args=(
    --provider "$PROVIDER"
    --output "$OUT_DIR"
  )

  if [[ -n "$SPEC_URL" ]]; then
    args+=(--spec-url "$SPEC_URL")
  else
    args+=(--index-url "$INDEX_URL")
  fi

  [[ -n "$SPEC_REGEX" ]] && args+=(--spec-regex "$SPEC_REGEX")
  [[ -n "$FALLBACK_SPEC_URL" ]] && args+=(--fallback-spec-url "$FALLBACK_SPEC_URL")
  [[ -n "$TITLE" ]] && args+=(--title "$TITLE")

  exec "$SCRIPT_DIR/types/openapi.sh" "${args[@]}"
}

run_github() {
  local args=(
    --provider "$PROVIDER"
    --output "$OUT_DIR"
    --repo-url "$REPO_URL"
  )

  [[ -n "$BRANCH" ]] && args+=(--branch "$BRANCH")
  [[ -n "$DOCS_PATH" ]] && args+=(--docs-path "$DOCS_PATH")
  [[ -n "$MODE" ]] && args+=(--mode "$MODE")

  exec "$SCRIPT_DIR/types/github.sh" "${args[@]}"
}

# Main
if [[ -n "$SOURCE_URL" ]]; then
  INDEX_URL="$SOURCE_URL"

  if [[ -z "$PROVIDER" ]]; then
    PROVIDER="$(derive_provider_from_url "$SOURCE_URL")"
  fi

  if [[ "$TYPE" == "auto" ]]; then
    TYPE="$(auto_detect_type "$SOURCE_URL")"
  fi

  case "$TYPE" in
    llms)
      [[ -n "$THROTTLE_SECONDS" ]] || THROTTLE_SECONDS="0.1"
      run_llms
      ;;
    openapi)
      # If --source is the spec URL, set it.
      if [[ -z "$SPEC_URL" ]]; then
        case "$SOURCE_URL" in
          *.yaml|*.yml|*.json) SPEC_URL="$SOURCE_URL" ;;
        esac
      fi
      run_openapi
      ;;
    github)
      [[ -n "$REPO_URL" ]] || REPO_URL="$SOURCE_URL"
      [[ -n "$BRANCH" ]] || BRANCH="main"
      [[ -n "$DOCS_PATH" ]] || DOCS_PATH="docs"
      [[ -n "$MODE" ]] || MODE="copy"
      run_github
      ;;
    *)
      common_die "Cannot auto-detect source type for: $SOURCE_URL"
      ;;
  esac
fi

# Named provider mode
if [[ -z "$PROVIDER" ]]; then
  usage
  exit 1
fi

DEF_FILE="$SCRIPT_DIR/defs/$PROVIDER.sh"
if [[ ! -f "$DEF_FILE" ]]; then
  common_die "Unknown provider: $PROVIDER (missing $DEF_FILE)"
fi

# Reset config vars to avoid bleeding between providers.
TYPE=""
INDEX_URL=""
FULL_INDEX_URL=""
PATTERN=""
STRIP_PREFIX=""
STRIP_SUFFIX=""
THROTTLE_SECONDS=""
TOKEN=""
HEADERS=()
SPEC_URL=""
FALLBACK_SPEC_URL=""
SPEC_REGEX=""
TITLE=""
REPO_URL=""
BRANCH=""
DOCS_PATH=""
MODE=""

# shellcheck disable=SC1090
source "$DEF_FILE"

if [[ -z "${TYPE:-}" ]]; then
  common_die "Provider definition did not set TYPE: $DEF_FILE"
fi

case "$TYPE" in
  llms)
    [[ -n "${INDEX_URL:-}" ]] || common_die "Provider $PROVIDER is llms but INDEX_URL is empty"
    [[ -n "${THROTTLE_SECONDS:-}" ]] || THROTTLE_SECONDS="0.1"
    run_llms
    ;;
  openapi)
    # Either SPEC_URL or INDEX_URL must be present.
    if [[ -z "${SPEC_URL:-}" && -z "${INDEX_URL:-}" ]]; then
      common_die "Provider $PROVIDER is openapi but neither SPEC_URL nor INDEX_URL is set"
    fi
    run_openapi
    ;;
  github)
    [[ -n "${REPO_URL:-}" ]] || common_die "Provider $PROVIDER is github but REPO_URL is empty"
    [[ -n "${BRANCH:-}" ]] || BRANCH="main"
    [[ -n "${DOCS_PATH:-}" ]] || DOCS_PATH="docs"
    [[ -n "${MODE:-}" ]] || MODE="copy"
    run_github
    ;;
  *)
    common_die "Unknown provider TYPE '$TYPE' in $DEF_FILE"
    ;;
esac
