#!/usr/bin/env bash
# Provider registry to avoid a giant case statement and make it easy to extend.
set -euo pipefail

PROVIDERS=()
DEFAULT_PROVIDERS=(openai gemini anthropic)

CURRENT_PROVIDER=""
CURRENT_KIND=""
CURRENT_SCRIPT=""
CURRENT_INDEX=""
CURRENT_FULL_INDEX=""
CURRENT_STRIP_PREFIX=""
CURRENT_STRIP_SUFFIX=""
CURRENT_THROTTLE=""

register_custom() {
  local name="$1"
  local script="$2"
  PROVIDERS+=("$name|custom|$script")
}

register_llms() {
  local name="$1"
  local index_url="$2"
  local full_index_url="${3:-}"
  local strip_prefix="${4:-}"
  local strip_suffix="${5:-}"
  local throttle="${6:-0}"
  PROVIDERS+=("$name|llms|$index_url|$full_index_url|$strip_prefix|$strip_suffix|$throttle")
}

all_providers() {
  for entry in "${PROVIDERS[@]}"; do
    IFS="|" read -r name _ <<< "$entry"
    echo "$name"
  done | sort
}

load_provider() {
  local name="$1"
  CURRENT_PROVIDER=""
  CURRENT_KIND=""
  CURRENT_SCRIPT=""
  CURRENT_INDEX=""
  CURRENT_FULL_INDEX=""
  CURRENT_STRIP_PREFIX=""
  CURRENT_STRIP_SUFFIX=""
  CURRENT_THROTTLE=""

  for entry in "${PROVIDERS[@]}"; do
    IFS="|" read -r entry_name kind field3 field4 field5 field6 field7 <<< "$entry"
    if [[ "$entry_name" == "$name" ]]; then
      CURRENT_PROVIDER="$entry_name"
      CURRENT_KIND="$kind"
      if [[ "$kind" == "custom" ]]; then
        CURRENT_SCRIPT="$field3"
      else
        CURRENT_INDEX="$field3"
        CURRENT_FULL_INDEX="$field4"
        CURRENT_STRIP_PREFIX="$field5"
        CURRENT_STRIP_SUFFIX="$field6"
        CURRENT_THROTTLE="$field7"
      fi
      return 0
    fi
  done

  return 1
}

is_known_provider() {
  load_provider "$1"
}

# Custom handlers for non-LLM.txt flows.
register_custom openai "openai.sh"
register_custom gemini "gemini.sh"
register_custom anthropic "anthropic.sh"
register_custom huggingface "huggingface.sh"
register_custom openrouter "openrouter.sh"
register_custom cohere "cohere.sh"
register_custom nextjs "nextjs.sh"
register_custom mistral "mistral.sh"

# LLMS.txt-driven providers.
register_llms supabase "https://supabase.com/llms.txt" "https://supabase.com/llms-full.txt" "https://supabase.com/"
register_llms groq "https://console.groq.com/llms.txt" "https://console.groq.com/llms-full.txt" "https://console.groq.com/"
register_llms xai "https://docs.x.ai/llms.txt" "" "https://docs.x.ai/"
register_llms stripe "https://docs.stripe.com/llms.txt" "" "https://docs.stripe.com/"
register_llms cloudflare "https://developers.cloudflare.com/llms.txt" "" "https://developers.cloudflare.com/"
register_llms netlify "https://docs.netlify.com/llms.txt" "" "https://docs.netlify.com/"
register_llms twilio "https://www.twilio.com/docs/llms.txt" "" "https://www.twilio.com/docs/"
register_llms digitalocean "https://docs.digitalocean.com/llms.txt" "" "https://docs.digitalocean.com/"
register_llms railway "https://railway.com/llms.txt" "" "https://railway.com/"
register_llms neon "https://neon.com/llms.txt" "" "https://neon.com/"
register_llms turso "https://docs.turso.tech/llms.txt" "" "https://docs.turso.tech/"
register_llms prisma "https://www.prisma.io/docs/llms.txt" "" "https://www.prisma.io/docs/"
register_llms pinecone "https://docs.pinecone.io/llms.txt" "" "https://docs.pinecone.io/"
register_llms retool "https://docs.retool.com/llms.txt" "" "https://docs.retool.com/"
register_llms zapier "https://docs.zapier.com/llms.txt" "" "https://docs.zapier.com/"
register_llms perplexity "https://docs.perplexity.ai/llms.txt" "" "https://docs.perplexity.ai/"
register_llms elevenlabs "https://elevenlabs.io/docs/llms.txt" "" "https://elevenlabs.io/docs/"
register_llms pinata "https://docs.pinata.cloud/llms.txt" "" "https://docs.pinata.cloud/"
register_llms datadog "https://www.datadoghq.com/llms.txt" "" "https://www.datadoghq.com/"
register_llms workos "https://workos.com/docs/llms.txt" "" "https://workos.com/docs/"
register_llms clerk "https://clerk.com/docs/llms.txt" "" "https://clerk.com/docs/"
register_llms litellm "https://docs.litellm.ai/llms.txt" "" "https://docs.litellm.ai/"
register_llms crewai "https://docs.crewai.com/llms.txt" "" "https://docs.crewai.com/"
