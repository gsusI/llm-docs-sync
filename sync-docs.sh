#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./sync-docs.sh [--output DIR] [--version-label LABEL|--timestamp-label] [--latest-alias NAME] [provider ...]
       ./sync-docs.sh --interactive

Fetch docs for the given providers (default: openai gemini anthropic).
Outputs land in DIR/<provider>, so you can vendor docs inside your project for
LLM RAG or offline use.

Providers available:
- openai
- gemini
- anthropic
- huggingface
- openrouter
- cohere
- mistral
- supabase
- groq
- xai
- stripe
- cloudflare
- netlify
- twilio
- digitalocean
- railway
- neon
- turso
- prisma
- pinecone
- retool
- zapier
- perplexity
- elevenlabs
- pinata
- datadog
- workos
- clerk
- litellm
- crewai
- nextjs

Examples:
  ./sync-docs.sh                                 # fetch OpenAI + Gemini + Anthropic into ./docs
  ./sync-docs.sh --output vendor llm             # fetch OpenAI + Gemini + Anthropic into ./vendor
  ./sync-docs.sh gemini anthropic                # fetch only Gemini + Anthropic docs
  ./sync-docs.sh --version-label 2025-01-15      # write into ./docs/<provider>/2025-01-15 and keep ./docs/<provider> unchanged
  ./sync-docs.sh --timestamp-label --latest-alias latest # timestamped subfolders + refresh ./docs/<provider>/latest symlink
USAGE
}

OUTPUT_ROOT="docs"
providers=()
INTERACTIVE=false
VERSION_LABEL=""
USE_TIMESTAMP_LABEL=false
LATEST_ALIAS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_ROOT="${2:-}"
      shift 2
      ;;
    -i|--interactive)
      INTERACTIVE=true
      shift
      ;;
    --version-label)
      VERSION_LABEL="${2:-}"
      shift 2
      ;;
    --timestamp-label)
      USE_TIMESTAMP_LABEL=true
      shift
      ;;
    --latest-alias)
      LATEST_ALIAS="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      providers+=("$1")
      shift
      ;;
  esac
done

if [[ ${#providers[@]} -eq 0 ]]; then
  providers=(openai gemini anthropic)
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$INTERACTIVE" == true ]]; then
  default_providers="${providers[*]}"
  if [[ -z "$default_providers" ]]; then
    default_providers="openai gemini anthropic"
  fi

  read -r -p "Output directory [${OUTPUT_ROOT}]: " answer
  if [[ -n "${answer:-}" ]]; then
    OUTPUT_ROOT="$answer"
  fi

  echo "Available providers: openai gemini anthropic huggingface openrouter cohere mistral supabase groq xai stripe cloudflare netlify twilio digitalocean railway neon turso prisma pinecone retool zapier perplexity elevenlabs pinata datadog workos clerk litellm crewai nextjs"
  read -r -p "Providers (space separated) [${default_providers}]: " answer
  if [[ -n "${answer:-}" ]]; then
    providers=($answer)
  else
    providers=($default_providers)
  fi

  read -r -p "Version label (empty for none): " answer
  if [[ -n "${answer:-}" ]]; then
    VERSION_LABEL="$answer"
  fi

  read -r -p "Set latest alias name (empty to skip): " answer
  if [[ -n "${answer:-}" ]]; then
    LATEST_ALIAS="$answer"
  fi
fi

mkdir -p "$OUTPUT_ROOT"

RUN_TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
manifest_entries=()

sanitize_label() {
  echo "${1//[^A-Za-z0-9._-]/_}"
}

if [[ "$USE_TIMESTAMP_LABEL" == true && -z "$VERSION_LABEL" ]]; then
  VERSION_LABEL="$(date -u +"%Y%m%d-%H%M%S")"
fi

for provider in "${providers[@]}"; do
  base_dir="$OUTPUT_ROOT/$provider"
  label=""
  if [[ -n "$VERSION_LABEL" ]]; then
    label="$(sanitize_label "$VERSION_LABEL")"
    base_dir="$base_dir/$label"
  fi

  case "$provider" in
    openai)
      "$SCRIPT_DIR/providers/openai.sh" --output "$base_dir"
      ;;
    gemini)
      "$SCRIPT_DIR/providers/gemini.sh" --output "$base_dir"
      ;;
    anthropic)
      "$SCRIPT_DIR/providers/anthropic.sh" --output "$base_dir"
      ;;
    huggingface)
      "$SCRIPT_DIR/providers/huggingface.sh" --output "$base_dir"
      ;;
    openrouter)
      "$SCRIPT_DIR/providers/openrouter.sh" --output "$base_dir"
      ;;
    cohere)
      "$SCRIPT_DIR/providers/cohere.sh" --output "$base_dir"
      ;;
    mistral)
      "$SCRIPT_DIR/providers/mistral.sh" --output "$base_dir"
      ;;
    supabase)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider supabase --index-url https://supabase.com/llms.txt --full-index-url https://supabase.com/llms-full.txt --strip-prefix https://supabase.com/ --output "$base_dir"
      ;;
    groq)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider groq --index-url https://console.groq.com/llms.txt --full-index-url https://console.groq.com/llms-full.txt --strip-prefix https://console.groq.com/ --output "$base_dir"
      ;;
    xai)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider xai --index-url https://docs.x.ai/llms.txt --strip-prefix https://docs.x.ai/ --output "$base_dir"
      ;;
    stripe)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider stripe --index-url https://docs.stripe.com/llms.txt --strip-prefix https://docs.stripe.com/ --output "$base_dir"
      ;;
    cloudflare)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider cloudflare --index-url https://developers.cloudflare.com/llms.txt --strip-prefix https://developers.cloudflare.com/ --output "$base_dir"
      ;;
    netlify)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider netlify --index-url https://docs.netlify.com/llms.txt --strip-prefix https://docs.netlify.com/ --output "$base_dir"
      ;;
    twilio)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider twilio --index-url https://www.twilio.com/docs/llms.txt --strip-prefix https://www.twilio.com/docs/ --output "$base_dir"
      ;;
    digitalocean)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider digitalocean --index-url https://docs.digitalocean.com/llms.txt --strip-prefix https://docs.digitalocean.com/ --output "$base_dir"
      ;;
    railway)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider railway --index-url https://railway.com/llms.txt --strip-prefix https://railway.com/ --output "$base_dir"
      ;;
    neon)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider neon --index-url https://neon.com/llms.txt --strip-prefix https://neon.com/ --output "$base_dir"
      ;;
    turso)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider turso --index-url https://docs.turso.tech/llms.txt --strip-prefix https://docs.turso.tech/ --output "$base_dir"
      ;;
    prisma)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider prisma --index-url https://www.prisma.io/docs/llms.txt --strip-prefix https://www.prisma.io/docs/ --output "$base_dir"
      ;;
    pinecone)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider pinecone --index-url https://docs.pinecone.io/llms.txt --strip-prefix https://docs.pinecone.io/ --output "$base_dir"
      ;;
    retool)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider retool --index-url https://docs.retool.com/llms.txt --strip-prefix https://docs.retool.com/ --output "$base_dir"
      ;;
    zapier)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider zapier --index-url https://docs.zapier.com/llms.txt --strip-prefix https://docs.zapier.com/ --output "$base_dir"
      ;;
    perplexity)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider perplexity --index-url https://docs.perplexity.ai/llms.txt --strip-prefix https://docs.perplexity.ai/ --output "$base_dir"
      ;;
    elevenlabs)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider elevenlabs --index-url https://elevenlabs.io/docs/llms.txt --strip-prefix https://elevenlabs.io/docs/ --output "$base_dir"
      ;;
    pinata)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider pinata --index-url https://docs.pinata.cloud/llms.txt --strip-prefix https://docs.pinata.cloud/ --output "$base_dir"
      ;;
    datadog)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider datadog --index-url https://www.datadoghq.com/llms.txt --strip-prefix https://www.datadoghq.com/ --output "$base_dir"
      ;;
    workos)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider workos --index-url https://workos.com/docs/llms.txt --strip-prefix https://workos.com/docs/ --output "$base_dir"
      ;;
    clerk)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider clerk --index-url https://clerk.com/docs/llms.txt --strip-prefix https://clerk.com/docs/ --output "$base_dir"
      ;;
    litellm)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider litellm --index-url https://docs.litellm.ai/llms.txt --strip-prefix https://docs.litellm.ai/ --output "$base_dir"
      ;;
    crewai)
      "$SCRIPT_DIR/providers/generic-llms.sh" --provider crewai --index-url https://docs.crewai.com/llms.txt --strip-prefix https://docs.crewai.com/ --output "$base_dir"
      ;;
    nextjs)
      "$SCRIPT_DIR/providers/nextjs.sh" --output "$base_dir"
      ;;
    *)
      echo "Unknown provider: $provider" >&2
      exit 1
      ;;
  esac

  if [[ -n "$LATEST_ALIAS" && -n "$label" ]]; then
    alias_path="$OUTPUT_ROOT/$provider/$LATEST_ALIAS"
    mkdir -p "$(dirname "$alias_path")"
    ln -sfn "$label" "$alias_path"
  fi

  manifest_entries+=("{\"provider\":\"$provider\",\"output\":\"$base_dir\",\"timestamp\":\"$RUN_TIMESTAMP\",\"label\":\"${label:-}\"}")
done

if [[ ${#manifest_entries[@]} -gt 0 ]]; then
  manifest_path="$OUTPUT_ROOT/manifest.json"
  {
    echo "["
    for i in "${!manifest_entries[@]}"; do
      sep=","
      if [[ $i -eq $((${#manifest_entries[@]} - 1)) ]]; then
        sep=""
      fi
      echo "  ${manifest_entries[$i]}$sep"
    done
    echo "]"
  } > "$manifest_path"
  echo "Wrote manifest to $manifest_path"
fi

echo "Done. Docs are under $OUTPUT_ROOT/"
