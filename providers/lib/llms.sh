#!/usr/bin/env bash
# Shared helpers for mirroring llms.txt-driven doc sets.
set -euo pipefail

llms_require_cmds() {
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "Missing required command: $cmd" >&2
      exit 1
    fi
  done
}

llms_default_curl_base() {
  LLMS_CURL_BASE=(curl -fsSL --retry 5 --retry-delay 2 --retry-connrefused --retry-all-errors --retry-max-time 120 --http1.1)
}

llms_fetch_with_retry() {
  local url="$1"
  local dest="$2"
  local label="$3"
  local max_attempts="${4:-5}"

  local attempt=1
  while true; do
    if "${LLMS_CURL_BASE[@]}" "$url" -o "$dest"; then
      return 0
    fi

    if [[ "$attempt" -ge "$max_attempts" ]]; then
      echo "[llms] Failed to download $label after $attempt attempts" >&2
      return 1
    fi

    local sleep_seconds=$((attempt * 2))
    echo "[llms] Retry $attempt for $label in ${sleep_seconds}s" >&2
    sleep "$sleep_seconds"
    attempt=$((attempt + 1))
  done
}

llms_extract_urls() {
  local index_file="$1"
  local pattern="$2"
  rg -o "$pattern" "$index_file" | sort -u
}

llms_mirror() {
  local provider="$1"
  local index_url="$2"
  local full_index_url="$3"
  local pattern="$4"
  local strip_prefix="$5"
  local strip_suffix="$6"
  local out_dir="$7"
  local throttle="${8:-0}"

  llms_require_cmds curl mktemp rg sort
  if [[ -z "${LLMS_CURL_BASE+x}" || ${#LLMS_CURL_BASE[@]} -eq 0 ]]; then
    llms_default_curl_base
  fi

  mkdir -p "$out_dir"

  local workdir
  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir"' RETURN

  local index_path="$workdir/llms.txt"
  local full_index_path="$workdir/llms-full.txt"

  echo "[$provider] Downloading llms.txt index from $index_url"
  llms_fetch_with_retry "$index_url" "$index_path" "llms.txt"

  local full_available=false
  local full_note="not downloaded"
  if [[ -n "$full_index_url" ]]; then
    if llms_fetch_with_retry "$full_index_url" "$full_index_path" "llms-full.txt"; then
      full_available=true
      full_note="$full_index_url"
    else
      echo "[$provider] Warning: could not download llms-full.txt from $full_index_url" >&2
    fi
  fi

  URLS=()
  while IFS= read -r url; do
    URLS+=("$url")
  done < <(llms_extract_urls "$index_path" "$pattern")

  if [[ ${#URLS[@]} -eq 0 ]]; then
    echo "[$provider] No doc URLs found in $index_url" >&2
    return 0
  fi

  local missing_file="$out_dir/missing.txt"
  : > "$missing_file"
  local missing_count=0

  for url in "${URLS[@]}"; do
    local rel="$url"
    if [[ "$rel" == "$strip_prefix"* ]]; then
      rel="${rel#$strip_prefix}"
    fi
    if [[ -n "$strip_suffix" && "$rel" == *"$strip_suffix" ]]; then
      rel="${rel%"$strip_suffix"}"
    fi
    local dest="$out_dir/$rel"
    mkdir -p "$(dirname "$dest")"
    echo "[$provider] Downloading $rel"
    if llms_fetch_with_retry "$url" "$dest" "$rel" 2; then
      if [[ -n "$throttle" && "$throttle" != "0" ]]; then
        sleep "$throttle"
      fi
    else
      echo "$rel" >> "$missing_file"
      missing_count=$((missing_count + 1))
    fi
  done

  cp "$index_path" "$out_dir/llms.txt"
  if [[ "$full_available" == true ]]; then
    cp "$full_index_path" "$out_dir/llms-full.txt"
  fi

  local title_provider
  title_provider="$(printf '%s' "$provider" | sed 's/^./\\U&/')"
  local index_md="$out_dir/index.md"
  {
    echo "# $title_provider docs"
    echo "Source index: $index_url"
    echo "Full index: $full_note"
    echo "Downloaded: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo
    echo "## Files (${#URLS[@]})"
    for url in "${URLS[@]}"; do
      local rel="$url"
      if [[ "$rel" == "$strip_prefix"* ]]; then
        rel="${rel#$strip_prefix}"
      fi
      if [[ -n "$strip_suffix" && "$rel" == *"$strip_suffix" ]]; then
        rel="${rel%"$strip_suffix"}"
      fi
      echo "- [$rel]($rel)"
    done
    if [[ "$missing_count" -gt 0 ]]; then
      echo
      echo "## Missing ($missing_count)"
      cat "$missing_file"
    fi
  } > "$index_md"

  if [[ "$missing_count" -gt 0 ]]; then
    echo "[$provider] Downloaded $((${#URLS[@]} - missing_count)) docs into $out_dir ($missing_count missing; see missing.txt)"
  else
    rm -f "$missing_file"
    echo "[$provider] Downloaded ${#URLS[@]} docs into $out_dir"
  fi
}
