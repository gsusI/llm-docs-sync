TYPE="llms"

INDEX_URL="https://huggingface.co/docs/hub/llms.txt"
FULL_INDEX_URL="https://huggingface.co/docs/hub/llms-full.txt"
STRIP_PREFIX="https://huggingface.co/docs/hub/"
THROTTLE_SECONDS="0.1"

# Hugging Face often rate-limits anonymous access.
TOKEN="${HF_TOKEN:-}"

PATTERN="https://huggingface[.]co/docs/hub/[A-Za-z0-9._/-]+[.](?:md|mdx)"
