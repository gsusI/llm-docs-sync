#!/usr/bin/env bash
set -euo pipefail

# Common helpers shared across provider implementations.
# Keep this file dependency-light: bash + coreutils + curl.

common_die() {
  echo "${1:-error}" >&2
  exit 1
}

common_require_cmds() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      common_die "Missing required command: $cmd"
    fi
  done
}

common_is_url() {
  case "${1:-}" in
    http://*|https://*) return 0 ;;
    *) return 1 ;;
  esac
}

# Extract the URL origin (scheme + host + optional port).
#   https://example.com/path -> https://example.com
common_url_origin() {
  local url="${1:-}"
  # Use sed because bash string ops choke on the '//' after scheme.
  printf '%s' "$url" | sed -E 's#^(https?://[^/]+).*#\1#'
}

# Extract the URL "directory" (everything up to the last '/'), without
# the trailing filename. Includes scheme+host and path.
#   https://example.com/a/b/c.txt -> https://example.com/a/b
common_url_dir() {
  local url="${1:-}"
  printf '%s' "${url%/*}"
}

common_strip_query_fragment() {
  local s="${1:-}"
  # Remove fragment first, then query.
  s="${s%%#*}"
  s="${s%%\?*}"
  printf '%s' "$s"
}

# Convert a URL (or relative URL) to a safe relative path for writing to disk.
# - Drops query string + fragment.
# - Removes any leading '/'.
# - Replaces characters that create weird paths.
# - Neutralizes '..' segments.
common_sanitize_relpath() {
  local rel="${1:-}"
  rel="$(common_strip_query_fragment "$rel")"

  # Strip leading slashes.
  while [[ "$rel" == /* ]]; do
    rel="${rel#/}"
  done

  # Replace backslashes (Windows paths) and colon (drive letters).
  rel="${rel//\\/_}"
  rel="${rel//:/_}"

  # Neutralize parent traversal.
  # We don't try to be clever here; just make it impossible.
  rel="${rel//..\//_dotdot_/}"
  rel="${rel//../_dotdot_}"

  # Collapse any accidental empty path.
  if [[ -z "$rel" ]]; then
    rel="index"
  fi

  printf '%s' "$rel"
}


common_timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Minimal JSON string escaper (enough for paths/labels).
# Escapes backslash, double quote, and control characters.
common_json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}
