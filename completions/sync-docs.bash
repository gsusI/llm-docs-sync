# bash completion for sync-docs.sh

_sync_docs_sh_root() {
  local root=""
  if [[ -n "${LLM_DOCS_SYNC_ROOT:-}" && -x "${LLM_DOCS_SYNC_ROOT}/sync-docs.sh" ]]; then
    printf '%s\n' "$LLM_DOCS_SYNC_ROOT"
    return
  fi

  local cmd="${COMP_WORDS[0]}"
  if [[ "$cmd" == */* ]]; then
    root="$(cd "$(dirname "$cmd")" 2>/dev/null && pwd)"
  else
    local resolved
    resolved="$(command -v "$cmd" 2>/dev/null)"
    if [[ -n "$resolved" ]]; then
      root="$(cd "$(dirname "$resolved")" 2>/dev/null && pwd)"
    fi
  fi

  if [[ -n "$root" ]]; then
    printf '%s\n' "$root"
  fi
}

_sync_docs_sh_list_providers() {
  local root
  root="$(_sync_docs_sh_root)"
  if [[ -n "$root" && -x "$root/sync-docs.sh" ]]; then
    "$root/sync-docs.sh" --list 2>/dev/null
    return
  fi

  if [[ -n "$root" && -d "$root/providers/defs" ]]; then
    (cd "$root/providers/defs" && ls -1 *.sh 2>/dev/null | sed 's/[.]sh$//')
  fi
}

_sync_docs_sh() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  local opts="--output --jobs --download-jobs --force --providers --version-label --timestamp-label --latest-alias --keep-going --source --provider --type --interactive --list --install-completion --install-completions --help --pattern --full-index-url --strip-prefix --strip-suffix --throttle-seconds --token --header --spec-url --fallback-spec-url --spec-regex --title --repo-url --branch --docs-path --mode"
  local types="auto llms openapi github"
  local modes="copy concat"
  local shells="auto bash zsh zs all"

  local -a provider_list=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    provider_list+=("$line")
  done < <(_sync_docs_sh_list_providers)

  case "$prev" in
    --provider)
      COMPREPLY=( $(compgen -W "${provider_list[*]}" -- "$cur") )
      return 0
      ;;
    --providers)
      local prefix=""
      local last="$cur"
      local used=""
      if [[ "$cur" == *,* ]]; then
        prefix="${cur%,*},"
        last="${cur##*,}"
        used="${cur%,*}"
      fi

      local -a filtered=()
      local item
      for item in "${provider_list[@]}"; do
        if [[ -n "$used" && ",$used," == *",$item,"* ]]; then
          continue
        fi
        filtered+=("$item")
      done

      COMPREPLY=( $(compgen -W "${filtered[*]}" -- "$last") )
      if [[ -n "$prefix" ]]; then
        local i
        for i in "${!COMPREPLY[@]}"; do
          COMPREPLY[$i]="${prefix}${COMPREPLY[$i]}"
        done
      fi
      return 0
      ;;
    --install-completion|--install-completions)
      COMPREPLY=( $(compgen -W "$shells" -- "$cur") )
      return 0
      ;;
    --type)
      COMPREPLY=( $(compgen -W "$types" -- "$cur") )
      return 0
      ;;
    --mode)
      COMPREPLY=( $(compgen -W "$modes" -- "$cur") )
      return 0
      ;;
    --output|--docs-path)
      COMPREPLY=( $(compgen -d -- "$cur") )
      return 0
      ;;
  esac

  if [[ "$cur" == --* ]]; then
    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
    return 0
  fi

  COMPREPLY=( $(compgen -W "${provider_list[*]}" -- "$cur") )
  return 0
}

complete -F _sync_docs_sh sync-docs.sh
complete -F _sync_docs_sh ./sync-docs.sh
