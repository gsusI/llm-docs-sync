TYPE="llms"

INDEX_URL="https://huggingface.co/docs/inference-providers/llms.txt"
FULL_INDEX_URL="https://huggingface.co/docs/inference-providers/llms-full.txt"
STRIP_PREFIX="https://huggingface.co/docs/inference-providers/"
THROTTLE_SECONDS="0.1"

# Hugging Face often rate-limits anonymous access.
TOKEN="${HF_TOKEN:-}"

PATTERN="https://huggingface[.]co/docs/inference-providers/[A-Za-z0-9._/-]+[.](?:md|mdx)"
