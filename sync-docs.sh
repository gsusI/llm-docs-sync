#!/usr/bin/env bash
set -euo pipefail

DEFAULT_OUTPUT_ROOT="docs"
DEFAULT_JOBS="2"
DEFAULT_DOWNLOAD_JOBS="4"

usage() {
  local script="./sync-docs.sh"
  local -a usage_lines=(
    "$script [options] [provider ...]"
    "$script --source URL [source options]"
    "$script --list"
    "$script --interactive [--providers LIST]"
    "$script --install-completion [auto|bash|zsh|zs|all]"
  )

  local -a command_options=(
    "--list|List available providers and exit"
    "--interactive, -i|Prompt for output + provider selection"
    "--install-completion [SHELL]|Install shell completion (auto|bash|zsh|zs|all); alias: --install-completions"
    "--help, -h|Show this help"
  )

  local -a options=(
    "--output DIR|Output directory (default: ${DEFAULT_OUTPUT_ROOT})"
    "--jobs N|Parallel provider jobs in provider mode (default: ${DEFAULT_JOBS})"
    "--download-jobs N|Parallel llms downloads (default: ${DEFAULT_DOWNLOAD_JOBS})"
    "--force|Re-download existing llms docs"
    "--providers LIST|Comma-separated providers (e.g. openai,gemini,anthropic)"
    "--version-label LABEL|Nest output under label"
    "--timestamp-label|Use UTC timestamp label"
    "--latest-alias NAME|Symlink alias under each provider"
    "--keep-going|Continue other providers when one fails"
  )

  local -a source_options=(
    "--source URL|Sync an arbitrary llms.txt, OpenAPI spec, or GitHub repo"
    "--provider NAME|Override provider name in --source mode"
  )

  print_section() {
    local title="$1"
    shift
    local -a items=("$@")
    local max=0
    local item left right
    for item in "${items[@]}"; do
      left="${item%%|*}"
      if [[ ${#left} -gt $max ]]; then
        max=${#left}
      fi
    done

    printf '%s\n' "$title"
    for item in "${items[@]}"; do
      left="${item%%|*}"
      right="${item#*|}"
      if [[ "$left" == "$item" ]]; then
        right=""
      fi
      if [[ -n "$right" ]]; then
        printf '  %-*s  %s\n' "$max" "$left" "$right"
      else
        printf '  %s\n' "$left"
      fi
    done
    echo ""
  }

  echo "Usage:"
  local line
  for line in "${usage_lines[@]}"; do
    printf '  %s\n' "$line"
  done
  echo ""

  print_section "Commands:" "${command_options[@]}"
  print_section "Options:" "${options[@]}"
  print_section "Source mode options:" "${source_options[@]}"

  echo "Source passthrough options (llms/openapi/github):"
  if [[ -x "$SCRIPT_DIR/providers/run.sh" ]]; then
    "$SCRIPT_DIR/providers/run.sh" --help 2>/dev/null | \
      sed -n '/^Options (source mode):/,$p' | \
      sed -e '/--download-jobs/d' -e '/--force/d' | \
      sed 's/^/  /'
  else
    echo "  See providers/run.sh --help for llms/openapi/github options."
  fi
  echo ""

  echo "Defaults:"
  echo "  If no providers are supplied, defaults to: openai gemini anthropic"
  echo ""
  echo "Notes:"
  echo "  Providers are defined by files in providers/defs/*.sh."
  echo "  Do not mix --source with named providers."
}

OUTPUT_ROOT="$DEFAULT_OUTPUT_ROOT"
INTERACTIVE=false
LIST=false
KEEP_GOING=false
INSTALL_COMPLETION=false
FORCE_DOWNLOAD=false
JOBS="$DEFAULT_JOBS"
VERSION_LABEL=""
USE_TIMESTAMP_LABEL=false
LATEST_ALIAS=""
PROVIDERS_FROM_FLAG=()
DOWNLOAD_JOBS=""
COMPLETION_SHELL="auto"

SOURCE_URL=""
SOURCE_ARGS=()
SOURCE_PROVIDER_OVERRIDE=""
SOURCE_OPTS_USED=false

providers=()
ACTIVE_PROVIDER_PIDS=()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$SCRIPT_DIR/.llm-docs-sync"
STATE_FILE="$STATE_DIR/interactive-providers.txt"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/providers/lib/common.sh"

list_providers() {
  local defs_dir="$SCRIPT_DIR/providers/defs"
  if [[ ! -d "$defs_dir" ]]; then
    return 0
  fi
  (cd "$defs_dir" && ls -1 *.sh 2>/dev/null | sed 's/[.]sh$//' | LC_ALL=C sort)
}

append_rc_snippet() {
  local rc_file="$1"
  local marker="$2"
  local snippet="$3"

  if [[ -f "$rc_file" ]]; then
    if grep -Fq "$marker" "$rc_file"; then
      return 0
    fi
  fi

  {
    echo ""
    echo "$marker"
    printf '%s\n' "$snippet"
  } >> "$rc_file"
}

install_bash_completion() {
  local completion_src="$SCRIPT_DIR/completions/sync-docs.bash"
  if [[ ! -f "$completion_src" ]]; then
    common_die "Missing completion script: $completion_src"
  fi

  local completion_dir
  if [[ -n "${BASH_COMPLETION_USER_DIR:-}" ]]; then
    completion_dir="$BASH_COMPLETION_USER_DIR/completions"
  elif [[ -n "${XDG_DATA_HOME:-}" ]]; then
    completion_dir="$XDG_DATA_HOME/bash-completion/completions"
  else
    completion_dir="$HOME/.local/share/bash-completion/completions"
  fi

  mkdir -p "$completion_dir"
  local completion_dest="$completion_dir/sync-docs.sh"
  cp "$completion_src" "$completion_dest"
  chmod 0644 "$completion_dest"

  local rc_file="$HOME/.bashrc"
  if [[ ! -f "$rc_file" && -f "$HOME/.bash_profile" ]]; then
    rc_file="$HOME/.bash_profile"
  fi

  local marker="# llm-docs-sync completion"
  local snippet
  snippet="$(cat <<EOF
if [ -f "$completion_dest" ]; then
  . "$completion_dest"
fi
EOF
)"
  append_rc_snippet "$rc_file" "$marker" "$snippet"

  echo "Installed bash completion to $completion_dest"
  echo "Loaded completion from $rc_file (open a new shell to activate)."
  echo "To activate now: source $rc_file"
}

install_zsh_completion() {
  local completion_src="$SCRIPT_DIR/completions/_sync-docs"
  if [[ ! -f "$completion_src" ]]; then
    common_die "Missing completion script: $completion_src"
  fi

  local completion_dir
  if [[ -n "${XDG_DATA_HOME:-}" ]]; then
    completion_dir="$XDG_DATA_HOME/zsh/site-functions"
  else
    completion_dir="$HOME/.local/share/zsh/site-functions"
  fi

  mkdir -p "$completion_dir"
  local completion_dest="$completion_dir/_sync-docs"
  cp "$completion_src" "$completion_dest"
  chmod 0644 "$completion_dest"

  local rc_file="$HOME/.zshrc"
  local marker="# llm-docs-sync completion"
  local snippet
  snippet="$(cat <<EOF
fpath=("$completion_dir" \$fpath)
if ! whence -w compdef >/dev/null 2>&1; then
  autoload -U compinit && compinit
fi
EOF
)"
  append_rc_snippet "$rc_file" "$marker" "$snippet"

  echo "Installed zsh completion to $completion_dest"
  echo "Updated $rc_file (open a new shell to activate)."
  echo "To activate now: source $rc_file"
}

install_completions() {
  local requested="${1:-auto}"
  local -a shells=()
  local detected=""

  case "$requested" in
    ""|auto)
      detected="$(basename "${SHELL:-}")"
      case "$detected" in
        bash|zsh) shells=("$detected") ;;
        *) shells=(bash) ;;
      esac
      ;;
    bash|zsh|zs)
      if [[ "$requested" == "zs" ]]; then
        requested="zsh"
      fi
      shells=("$requested")
      ;;
    all)
      shells=(bash zsh)
      ;;
    *)
      common_die "Unknown shell for --install-completion: $requested (use auto|bash|zsh|zs|all)"
      ;;
  esac

  local shell
  for shell in "${shells[@]}"; do
    case "$shell" in
      bash) install_bash_completion ;;
      zsh) install_zsh_completion ;;
    esac
  done
}

cleanup_active_providers() {
  if [[ -z "${ACTIVE_PROVIDER_PIDS[*]-}" ]]; then
    return 0
  fi

  local pid
  for pid in "${ACTIVE_PROVIDER_PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
}

on_interrupt() {
  echo "Interrupted. Stopping active provider jobs..." >&2
  cleanup_active_providers
  exit 130
}

trap 'on_interrupt' INT TERM
trap 'cleanup_active_providers' EXIT

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

list_contains() {
  local needle="$1"; shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

add_providers_from_arg() {
  local raw="${1:-}"
  local item
  raw="${raw//,/ }"
  for item in $raw; do
    [[ -n "$item" ]] || continue
    PROVIDERS_FROM_FLAG+=("$item")
  done
}

interactive_select_providers() {
  local all_providers=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    all_providers+=("$line")
  done < <(list_providers)

  if [[ ${#all_providers[@]} -eq 0 ]]; then
    common_die "No providers available for interactive selection"
  fi

  local preselected=()
  if [[ ${#providers[@]} -gt 0 ]]; then
    preselected=("${providers[@]}")
  elif [[ -f "$STATE_FILE" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      preselected+=("$line")
    done < "$STATE_FILE"
  fi

  local selected=()
  if command -v whiptail >/dev/null 2>&1; then
    local choices=()
    local provider status
    for provider in "${all_providers[@]}"; do
      status="OFF"
      if list_contains "$provider" "${preselected[@]:-}"; then
        status="ON"
      fi
      choices+=("$provider" "" "$status")
    done

    local output
    if ! output="$(whiptail --title "LLM Docs Sync" --checklist "Select providers:" 20 78 12 --separate-output "${choices[@]}" 3>&1 1>&2 2>&3)"; then
      common_die "Interactive selection cancelled"
    fi

    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      selected+=("$line")
    done <<< "$output"
  elif command -v dialog >/dev/null 2>&1; then
    local choices=()
    local provider status
    for provider in "${all_providers[@]}"; do
      status="OFF"
      if list_contains "$provider" "${preselected[@]:-}"; then
        status="ON"
      fi
      choices+=("$provider" "" "$status")
    done

    local output
    if ! output="$(dialog --stdout --separate-output --checklist "Select providers:" 20 78 12 "${choices[@]}")"; then
      common_die "Interactive selection cancelled"
    fi

    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      selected+=("$line")
    done <<< "$output"
  else
    echo "Select providers (toggle by number, empty to keep current selection):"
    local idx=1
    local provider
    for provider in "${all_providers[@]}"; do
      local mark=" "
      if list_contains "$provider" "${preselected[@]:-}"; then
        mark="x"
      fi
      printf '%2d) [%s] %s\n' "$idx" "$mark" "$provider"
      idx=$((idx + 1))
    done

    local answer
    read -r -p "Toggle selections (e.g. 1 3 5 or 2,4): " answer
    selected=("${preselected[@]}")

    if [[ -n "${answer:-}" ]]; then
      answer="${answer//,/ }"
      local token
      for token in $answer; do
        if ! [[ "$token" =~ ^[0-9]+$ ]]; then
          continue
        fi
        local pos=$((token - 1))
        if [[ $pos -lt 0 || $pos -ge ${#all_providers[@]} ]]; then
          continue
        fi
        provider="${all_providers[$pos]}"
        if list_contains "$provider" "${selected[@]:-}"; then
          local next=()
          local item
          for item in "${selected[@]}"; do
            if [[ "$item" != "$provider" ]]; then
              next+=("$item")
            fi
          done
          selected=("${next[@]}")
        else
          selected+=("$provider")
        fi
      done
    fi
  fi

  providers=("${selected[@]}")

  mkdir -p "$STATE_DIR"
  : > "$STATE_FILE"
  if [[ ${#providers[@]} -gt 0 ]]; then
    printf '%s\n' "${providers[@]}" | LC_ALL=C sort -u > "$STATE_FILE"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_ROOT="${2:-}"; shift 2 ;;
    -i|--interactive)
      INTERACTIVE=true; shift ;;
    --list)
      LIST=true; shift ;;
    --install-completion|--install-completions)
      INSTALL_COMPLETION=true
      if [[ "${2:-}" =~ ^(auto|bash|zsh|zs|all)$ ]]; then
        COMPLETION_SHELL="${2:-}"; shift 2
      else
        COMPLETION_SHELL="auto"; shift
      fi
      ;;
    --keep-going)
      KEEP_GOING=true; shift ;;
    --jobs)
      JOBS="${2:-}"; shift 2 ;;
    --download-jobs)
      DOWNLOAD_JOBS="${2:-}"
      SOURCE_ARGS+=("--download-jobs" "${2:-}")
      shift 2 ;;
    --force)
      FORCE_DOWNLOAD=true
      SOURCE_ARGS+=("--force")
      shift ;;
    --providers)
      add_providers_from_arg "${2:-}"; shift 2 ;;
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

if [[ "$INSTALL_COMPLETION" == true ]]; then
  install_completions "$COMPLETION_SHELL"
  exit 0
fi

if [[ "$SOURCE_OPTS_USED" == true && -z "$SOURCE_URL" ]]; then
  usage
  exit 1
fi

if [[ ${#PROVIDERS_FROM_FLAG[@]} -gt 0 ]]; then
  providers+=("${PROVIDERS_FROM_FLAG[@]}")
fi

if [[ ${#providers[@]} -gt 0 ]]; then
  unique_providers=()
  for provider in "${providers[@]}"; do
    if ! list_contains "$provider" "${unique_providers[@]:-}"; then
      unique_providers+=("$provider")
    fi
  done
  providers=("${unique_providers[@]}")
fi

if ! [[ "$JOBS" =~ ^[0-9]+$ ]] || [[ "$JOBS" -lt 1 ]]; then
  common_die "--jobs must be a positive integer"
fi

if [[ -n "$DOWNLOAD_JOBS" ]] && { ! [[ "$DOWNLOAD_JOBS" =~ ^[0-9]+$ ]] || [[ "$DOWNLOAD_JOBS" -lt 1 ]]; }; then
  common_die "--download-jobs must be a positive integer"
fi

if [[ -n "$SOURCE_URL" && ${#providers[@]} -gt 0 ]]; then
  common_die "Do not mix --source with named providers in one run"
fi

if [[ "$INTERACTIVE" == true && -n "$SOURCE_URL" ]]; then
  common_die "--interactive cannot be used with --source"
fi

if [[ "$LIST" == true ]]; then
  list_providers
  exit 0
fi

if [[ "$INTERACTIVE" == true ]]; then
  read -r -p "Output directory [${OUTPUT_ROOT}]: " answer
  if [[ -n "${answer:-}" ]]; then
    OUTPUT_ROOT="$answer"
  fi

  read -r -p "Version label (empty for none): " answer
  if [[ -n "${answer:-}" ]]; then
    VERSION_LABEL="$answer"
  fi

  read -r -p "Set latest alias name (empty to skip): " answer
  if [[ -n "${answer:-}" ]]; then
    LATEST_ALIAS="$answer"
  fi

  interactive_select_providers
fi

if [[ -z "$SOURCE_URL" && ${#providers[@]} -eq 0 ]]; then
  if [[ "$INTERACTIVE" == true ]]; then
    echo "No providers selected; exiting."
    exit 0
  else
    providers=(openai gemini anthropic)
  fi
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

  local args=("$provider" --output "$base_dir")
  if [[ -n "$DOWNLOAD_JOBS" ]]; then
    args+=(--download-jobs "$DOWNLOAD_JOBS")
  fi
  if [[ "$FORCE_DOWNLOAD" == true ]]; then
    args+=(--force)
  fi

  "$SCRIPT_DIR/providers/run.sh" "${args[@]}"
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

  local provider_escaped
  local out_dir_escaped
  local label_escaped
  local status_escaped
  local ts_escaped

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

      echo "[$provider] Starting sync into $base_dir"
      status="ok"
      if ! run_one "$provider" "$base_dir"; then
        status="error"
      fi
      echo "[$provider] Finished with status $status"
      if [[ "$status" != "ok" && "$KEEP_GOING" != true ]]; then
        append_manifest "$provider" "$base_dir" "${label:-}" "$status"
        common_die "Provider sync failed: $provider"
      fi

      if [[ -n "$LATEST_ALIAS" && -n "$label" ]]; then
        alias_path="$OUTPUT_ROOT/$provider/$LATEST_ALIAS"
        mkdir -p "$(dirname "$alias_path")"
        ln -sfn "$label" "$alias_path"
      fi

      append_manifest "$provider" "$base_dir" "${label:-}" "$status"
    done
  else
    echo "Running ${#providers[@]} providers with up to $JOBS parallel jobs"
    results_dir="$(mktemp -d)"
    cleanup_results() { rm -rf "$results_dir"; }
    trap cleanup_results EXIT

    provider_base_dirs=()
    provider_labels=()
    provider_results=()
    pids=()

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

      (
        echo "[$provider] Starting sync into $base_dir"
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
        echo "[$provider] Finished with status $status"
      ) &
      pids+=("$!")
      ACTIVE_PROVIDER_PIDS+=("$!")

      if [[ ${#pids[@]} -ge "$JOBS" ]]; then
        wait "${pids[0]}" || true
        pids=("${pids[@]:1}")
      fi
    done

    for pid in "${pids[@]}"; do
      wait "$pid" || true
    done
    ACTIVE_PROVIDER_PIDS=()

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
    printf '[\n'
    last_index=$(( ${#manifest_entries[@]} - 1 ))
    for i in "${!manifest_entries[@]}"; do
      sep=","
      if [[ $i -eq $last_index ]]; then
        sep=""
      fi
      printf '  %s%s\n' "${manifest_entries[$i]}" "$sep"
    done
    printf ']\n'
  } > "$manifest_path"
  echo "Wrote manifest to $manifest_path"
fi

echo "Done. Docs are under $OUTPUT_ROOT/"
