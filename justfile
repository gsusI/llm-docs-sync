set shell := ["bash", "-euo", "pipefail", "-c"]

package_name := "llm-docs-sync.zip"

run *ARGS:
  ./sync-docs.sh {{ARGS}}

test:
  ./sync-docs.sh --list

package:
  rm -f {{package_name}}
  zip -r {{package_name}} . \
    -x "{{package_name}}" \
    -x "docs/*" "docs/**" \
    -x "openai-api-docs/*" "openai-api-docs/**" \
    -x "gemini-api-docs/*" "gemini-api-docs/**" \
    -x ".git/*" ".git/**" \
    -x "llm-docs-sync-refactor.zip"
