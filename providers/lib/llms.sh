#!/usr/bin/env bash
# Shared helpers for mirroring llms.txt-driven doc sets.
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

llms_default_curl_base() {
  # Use conservative defaults that work on most providers.
  # Provider scripts can override by setting LLMS_CURL_BASE=(curl ...).
  LLMS_CURL_BASE=(
    curl -fsSL
    --retry 5
    --retry-delay 2
    --retry-connrefused
    --retry-all-errors
    --retry-max-time 120
    --http1.1
  )
}

llms_fetch_with_retry() {
  local url="$1"
  local dest="$2"
  local label="$3"
  local max_attempts="${4:-5}"

  if [[ -z "${LLMS_CURL_BASE+x}" || ${#LLMS_CURL_BASE[@]} -eq 0 ]]; then
    llms_default_curl_base
  fi

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

# Join a relative URL to the index URL.
# - '/path' -> '<origin>/path'
# - './path' or 'path' -> '<index_dir>/path'
llms_join_url() {
  local index_url="$1"
  local ref="$2"

  if common_is_url "$ref"; then
    printf '%s' "$ref"
    return 0
  fi

  local origin
  origin="$(common_url_origin "$index_url")"
  local index_dir
  index_dir="$(common_url_dir "$index_url")"

  case "$ref" in
    /*)
      printf '%s%s' "$origin" "$ref"
      ;;
    ./*)
      printf '%s/%s' "$index_dir" "${ref#./}"
      ;;
    *)
      printf '%s/%s' "$index_dir" "$ref"
      ;;
  esac
}

# Extract URLs from an llms index file.
# Uses ripgrep with a regex and returns sorted, unique matches.
llms_extract_urls() {
  local index_file="$1"
  local pattern="$2"

  # ripgrep prints only the match via -o.
  # Use LC_ALL=C to keep sort stable across locales.
  rg -o "$pattern" "$index_file" | LC_ALL=C sort -u
}

# Mirror docs referenced by a provider llms.txt index.
#
# Args:
#   provider        - label for logs
#   index_url       - URL to llms.txt
#   full_index_url  - URL to llms-full.txt (optional)
#   pattern         - ripgrep regex to find doc URLs/paths
#   strip_prefix    - prefix removed from URL to form output path (optional)
#   strip_suffix    - suffix removed from URL-derived path (optional)
#   out_dir         - output directory
#   throttle        - sleep seconds between downloads (optional)
#
# Environment:
#   LLMS_CURL_BASE            - curl argv array (optional)
#   LLMS_INCLUDE_FULL_INDEX   - if '1', union URLs from llms-full.txt too
#   LLMS_FAIL_ON_MISSING      - if '1', return non-zero when any downloads fail
#   LLMS_MAX_DOCS             - if set, limit number of docs (debug)
llms_mirror() {
  local provider="$1"
  local index_url="$2"
  local full_index_url="$3"
  local pattern="$4"
  local strip_prefix="$5"
  local strip_suffix="$6"
  local out_dir="$7"
  local throttle="${8:-0}"

  common_require_cmds curl mktemp rg sort

  if [[ -z "${LLMS_CURL_BASE+x}" || ${#LLMS_CURL_BASE[@]} -eq 0 ]]; then
    llms_default_curl_base
  fi

  mkdir -p "$out_dir"

  local workdir
  workdir="$(mktemp -d)"
  # Ensure cleanup even if caller uses set -e.
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

  local urls=()
  while IFS= read -r match; do
    [[ -n "$match" ]] || continue
    urls+=("$match")
  done < <(llms_extract_urls "$index_path" "$pattern" || true)

  # If index has nothing, fall back to full index when available.
  if [[ ${#urls[@]} -eq 0 && "$full_available" == true ]]; then
    while IFS= read -r match; do
      [[ -n "$match" ]] || continue
      urls+=("$match")
    done < <(llms_extract_urls "$full_index_path" "$pattern" || true)
  fi

  # Optionally union in llms-full.txt as well.
  if [[ "${LLMS_INCLUDE_FULL_INDEX:-}" == "1" && "$full_available" == true ]]; then
    while IFS= read -r match; do
      [[ -n "$match" ]] || continue
      urls+=("$match")
    done < <(llms_extract_urls "$full_index_path" "$pattern" || true)

    # De-dupe.
    local tmp="$workdir/urls.txt"
    printf '%s\n' "${urls[@]}" | LC_ALL=C sort -u > "$tmp"
    urls=()
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      urls+=("$line")
    done < "$tmp"
  fi

  if [[ ${#urls[@]} -eq 0 ]]; then
    echo "[$provider] No doc URLs found in $index_url" >&2
    cp "$index_path" "$out_dir/llms.txt"
    if [[ "$full_available" == true ]]; then
      cp "$full_index_path" "$out_dir/llms-full.txt"
    fi
    return 0
  fi

  local max_docs="${LLMS_MAX_DOCS:-}"
  if [[ -n "$max_docs" ]]; then
    urls=("${urls[@]:0:$max_docs}")
  fi

  local missing_file="$out_dir/missing.txt"
  : > "$missing_file"
  local missing_count=0

  local origin
  origin="$(common_url_origin "$index_url")"

  local url
  for url in "${urls[@]}"; do
    local abs_url
    abs_url="$(llms_join_url "$index_url" "$url")"

    local rel="$abs_url"

    # Default strip_prefix when not provided: strip the origin so that output
    # paths look like URL paths.
    if [[ -z "$strip_prefix" ]]; then
      strip_prefix="$origin/"
    fi

    if [[ -n "$strip_prefix" && "$rel" == "$strip_prefix"* ]]; then
      rel="${rel#$strip_prefix}"
    fi

    if [[ -n "$strip_suffix" && "$rel" == *"$strip_suffix" ]]; then
      rel="${rel%"$strip_suffix"}"
    fi

    rel="$(common_sanitize_relpath "$rel")"

    local dest="$out_dir/$rel"
    mkdir -p "$(dirname "$dest")"

    echo "[$provider] Downloading $rel"
    if llms_fetch_with_retry "$abs_url" "$dest" "$rel" 2; then
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

  local index_md="$out_dir/index.md"
  {
    echo "# ${provider} docs"
    echo "Source index: $index_url"
    echo "Full index: $full_note"
    echo "Downloaded: $(common_timestamp_utc)"
    echo
    echo "## Files (${#urls[@]})"
    for url in "${urls[@]}"; do
      local abs
      abs="$(llms_join_url "$index_url" "$url")"
      local rel2="$abs"
      if [[ -n "$strip_prefix" && "$rel2" == "$strip_prefix"* ]]; then
        rel2="${rel2#$strip_prefix}"
      fi
      if [[ -n "$strip_suffix" && "$rel2" == *"$strip_suffix" ]]; then
        rel2="${rel2%"$strip_suffix"}"
      fi
      rel2="$(common_sanitize_relpath "$rel2")"
      echo "- [$rel2]($rel2)"
    done

    if [[ "$missing_count" -gt 0 ]]; then
      echo
      echo "## Missing ($missing_count)"
      cat "$missing_file"
    fi
  } > "$index_md"

  if [[ "$missing_count" -gt 0 ]]; then
    echo "[$provider] Downloaded $((${#urls[@]} - missing_count)) docs into $out_dir ($missing_count missing; see missing.txt)" >&2
    if [[ "${LLMS_FAIL_ON_MISSING:-}" == "1" ]]; then
      return 1
    fi
  else
    rm -f "$missing_file"
    echo "[$provider] Downloaded ${#urls[@]} docs into $out_dir"
  fi
}
