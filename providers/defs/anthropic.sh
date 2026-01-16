TYPE="llms"

INDEX_URL="https://platform.claude.com/llms.txt"
FULL_INDEX_URL="https://platform.claude.com/llms-full.txt"
STRIP_PREFIX="https://platform.claude.com/docs/"

# Override with: ANTHROPIC_LANG=all ./sync-docs.sh anthropic
LANG="${ANTHROPIC_LANG:-en}"
if [[ "$LANG" == "all" ]]; then
  PATTERN="https://platform[.]claude[.]com/docs/[A-Za-z0-9._/-]+[.]md"
else
  # LANG is usually 'en'. If you set something exotic with '/', it will be used verbatim.
  PATTERN="https://platform[.]claude[.]com/docs/${LANG}/[A-Za-z0-9._/-]+[.]md"
fi

THROTTLE_SECONDS="0"
