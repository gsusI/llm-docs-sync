# LLM Docs Sync

Dependency-light scripts that vendor official docs into your project so local tools
and RAG jobs can ingest them offline (OpenAI, Gemini, Anthropic, Hugging Face, OpenRouter, Cohere, Mistral, and a bunch of provider mirrors like Supabase/Groq/Stripe/Cloudflare/etc., plus Next.js).

## Features
- Deterministic, idempotent fetches from each provider’s `llms.txt` index.
- Markdown output organized per provider for easy ingestion.
- Zero Node/Python deps; only shell + curl + rg + (Ruby for OpenAI conversion).
- Extensible: drop in `providers/<name>.sh`, add a single case, ship it.

## Quick start
```bash
# clone inside or next to your project
git clone https://github.com/gsusI/llm-docs-sync.git
cd llm-docs-sync

# fetch OpenAI + Gemini + Anthropic into ./docs/
./sync-docs.sh

# fetch only Gemini into ./vendor/llm-docs
./sync-docs.sh --output vendor/llm-docs gemini

# interactive prompts for output + providers
./sync-docs.sh --interactive

# versioned output with a "latest" alias and manifest
./sync-docs.sh --timestamp-label --latest-alias latest --output docs

# Hugging Face often rate-limits anonymous access; pass a token if needed
HF_TOKEN=hf_xxx ./sync-docs.sh huggingface
```

Outputs land under `<output>/<provider>/`. Examples:
- `docs/openai/index.md` + `docs/openai/groups/*.md` generated from OpenAI’s OpenAPI spec.
- `docs/gemini/docs/*.md` mirrored from Gemini’s published markdown twins.
- `docs/anthropic/en/*.md` mirrored from Anthropic’s published Markdown docs (llms.txt-driven).
- `docs/huggingface/hub/*.md` mirrored from Hugging Face Hub docs (llms.txt-driven).
- `docs/openrouter/*.mdx` mirrored from OpenRouter docs (llms.txt-driven).
- `docs/cohere/*.mdx` mirrored from Cohere docs (llms.txt-driven).
- `docs/mistral/*.md` mirrored from Mistral docs (llms.txt-driven).
- Additional mirrors supported: Supabase, Groq, xAI, Stripe, Cloudflare, Netlify, Twilio, DigitalOcean, Railway, Neon, Turso, Prisma, Pinecone, Retool, Zapier, Perplexity, ElevenLabs, Pinata, Datadog, WorkOS, Clerk, LiteLLM, CrewAI (all via llms.txt).
- `docs/manifest.json` records provider, path, label, and fetch timestamp.

## Providers
- **openai**: Reads `https://platform.openai.com/llms.txt` to locate the OpenAPI spec, then renders Markdown reference grouped by operation tags.
- **gemini**: Reads `https://ai.google.dev/gemini-api/docs/llms.txt` and mirrors the linked `*.md.txt` docs.
- **anthropic**: Reads `https://platform.claude.com/llms.txt` (and `llms-full.txt` when available), then mirrors the linked Markdown docs. Use `--lang all` to pull all localized paths.
- **huggingface**: Reads `https://huggingface.co/docs/hub/llms.txt` (and `llms-full.txt` when available) and mirrors the linked Hub Markdown docs. Large runs may require a Hugging Face token: `HF_TOKEN=... ./sync-docs.sh huggingface`.
- **openrouter**: Reads `https://openrouter.ai/docs/llms.txt` (and `llms-full.txt` when available) and mirrors the linked `.md`/`.mdx` docs.
- **cohere**: Reads `https://docs.cohere.com/llms.txt` (and `llms-full.txt` when available) and mirrors the linked `.md`/`.mdx` docs.
- **mistral**: Reads `https://docs.mistral.ai/llms.txt` (and `llms-full.txt` when available) and mirrors the linked `.md`/`.mdx` docs.
- **supabase**, **groq**, **xai**, **stripe**, **cloudflare**, **netlify**, **twilio**, **digitalocean**, **railway**, **neon**, **turso**, **prisma**, **pinecone**, **retool**, **zapier**, **perplexity**, **elevenlabs**, **pinata**, **datadog**, **workos**, **clerk**, **litellm**, **crewai**: mirrored via their published `llms.txt` indexes with a generic mirror.
- **nextjs**: Clones the Next.js repo docs directory (default branch `canary`) and concatenates all `*.md`/`*.mdx` into a single `index.md`. Pass `--branch <tag-or-branch>` to target a specific release (e.g., `--branch v14.2.3`) and set `--output` to a versioned folder, e.g., `--output docs/nextjs-14.2.3`.

Adding a provider = drop `providers/<name>.sh` and wire a case entry in `sync-docs.sh`.

## Requirements
- bash, curl, rg (ripgrep), sort, mktemp
- Ruby (only for OpenAI conversion)

## Repo layout
- `sync-docs.sh` — entrypoint that dispatches to providers.
- `providers/openai.sh` — fetches OpenAI spec + generates Markdown groups.
- `providers/gemini.sh` — mirrors Gemini Markdown twins.
- `providers/anthropic.sh` — mirrors Anthropic/Claude Markdown docs via llms.txt.
- `providers/huggingface.sh` — mirrors Hugging Face Hub docs via llms.txt.
- `providers/openrouter.sh` — mirrors OpenRouter docs via llms.txt.
- `providers/cohere.sh` — mirrors Cohere docs via llms.txt.
- `providers/mistral.sh` — mirrors Mistral docs via llms.txt.
- `providers/generic-llms.sh` — generic llms.txt mirror used by Supabase/Groq/xAI/Stripe/Cloudflare/etc.
- `providers/nextjs.sh` — clones/concats Next.js docs for a branch or tag.
- `docs/` (ignored) — default output target when you run the scripts.
- `docs/manifest.json` — auto-written manifest describing each sync run.

## Versioned layout (recommended)
Run with `--version-label <label>` or `--timestamp-label` to nest outputs under
`<output>/<provider>/<label>`, then add `--latest-alias latest` to keep
`<output>/<provider>/latest` pointing to the newest snapshot. This keeps history
while preserving a stable path for ingestion tools.

## Extending to new providers
1. Create `providers/<name>.sh` that writes docs into the given `--output` dir.
2. Add a `case` branch in `sync-docs.sh` to invoke it.
3. Keep it dependency-light (curl/rg preferred) and document flags in `usage()`.
4. Open a PR with a short note in README if you add flags or providers.

## TODO / providers welcome
- Hugging Face Inference API
- AWS Bedrock (direct)
- Azure OpenAI
- Google Vertex AI

## Contributing
See [CONTRIBUTING.md](CONTRIBUTING.md). PRs welcome! Please keep scripts readable, small, and well-commented where non-obvious.

## License
MIT — see [LICENSE](LICENSE).
