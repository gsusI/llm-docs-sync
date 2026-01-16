# LLM Docs Sync

Dependency-light scripts that vendor official docs into your project so local tools
and RAG jobs can ingest them offline (OpenAI, Gemini, Anthropic, Hugging Face,
OpenRouter, Cohere, Mistral, Next.js, and a bunch of provider mirrors like
Supabase/Groq/Stripe/Cloudflare/etc.).

## Features
- Deterministic, idempotent fetches (no timestamps unless you opt in with `--version-label`).
- Provider definitions live in `providers/defs/*.sh` and are dispatched via `providers/run.sh`.
- Ad-hoc `--source` mode for llms.txt, OpenAPI, or GitHub sources without adding code.
- Interactive provider selection with `--interactive` (checkboxes remember last selection).
- Easy provider targeting with `--providers openai,gemini` (comma-separated list).
- Parallel provider runs with `--jobs N` (default: 2).
- Parallel llms.txt downloads with `--download-jobs N` (default: 4).
- Skips existing llms docs by default; use `--force` to re-download.
- Type-specific runners for llms, OpenAPI, and GitHub sources.
- Zero Node/Python deps; bash + curl + rg + git (Ruby only for OpenAPI conversion).

## Quick start
```bash
# clone inside or next to your project
git clone https://github.com/gsusI/llm-docs-sync.git
cd llm-docs-sync

# fetch OpenAI + Gemini + Anthropic into ./docs/
./sync-docs.sh

# fetch only Gemini into ./vendor/llm-docs
./sync-docs.sh --output vendor/llm-docs gemini

# fetch a specific set of providers (comma-separated list)
./sync-docs.sh --providers openai,gemini --output docs

# parallelize llms.txt downloads for faster runs
./sync-docs.sh --download-jobs 8 gemini anthropic

# mirror an arbitrary llms.txt without editing the repo
./sync-docs.sh --source https://example.com/llms.txt --provider mydocs --output docs

# pull docs from a GitHub repo
./sync-docs.sh --source https://github.com/vercel/next.js.git --type github --docs-path docs --mode concat --output docs --provider nextjs

# interactive prompts for output + providers
./sync-docs.sh --interactive

# versioned output with a "latest" alias and manifest
./sync-docs.sh --timestamp-label --latest-alias latest --output docs

# Hugging Face often rate-limits anonymous access; pass a token if needed
HF_TOKEN=hf_xxx ./sync-docs.sh huggingface
```

Outputs land under `<output>/<provider>/`. Examples:
- `docs/openai/index.md` + `docs/openai/groups/*.md` generated from OpenAI's OpenAPI spec.
- `docs/gemini/docs/*.md` mirrored from Gemini's published markdown twins.
- `docs/anthropic/en/*.md` mirrored from Anthropic's published Markdown docs (llms.txt-driven).
- `docs/huggingface/hub/*.md` mirrored from Hugging Face Hub docs (llms.txt-driven).
- `docs/huggingface-inference-providers/*.md` mirrored from Hugging Face Inference Providers docs (llms.txt-driven).
- `docs/openrouter/*.mdx` mirrored from OpenRouter docs (llms.txt-driven).
- `docs/cohere/*.mdx` mirrored from Cohere docs (llms.txt-driven).
- `docs/mistral/*.md` mirrored from Mistral docs (llms.txt-driven).
- `docs/langchain/*.md` mirrored from LangChain docs (llms.txt-driven).
- `docs/langgraph/*` mirrored from LangGraph docs (llms.txt-driven).
- `docs/langgraphjs/*` mirrored from LangGraph JS docs (llms.txt-driven).
- `docs/nextjs/index.md` concatenated from the Next.js GitHub docs tree.
- Additional mirrors supported: Supabase, Groq, xAI, Stripe, Cloudflare, Netlify, Twilio,
  DigitalOcean, Railway, Neon, Turso, Prisma, Pinecone, Polymarket, LangChain, LangGraph,
  LangGraphJS, Hugging Face Inference Providers, Retool, Zapier, Perplexity, ElevenLabs,
  Pinata, Datadog, WorkOS, Clerk, LiteLLM, CrewAI (all via llms.txt).
- `docs/manifest.json` records provider, path, label, timestamp, and status.

## Providers
Run `./sync-docs.sh --list` to see all installed provider definitions.

- **openai**: Reads `https://platform.openai.com/llms.txt` to locate the OpenAPI spec,
  then renders Markdown reference grouped by operation tags.
- **gemini**: Reads `https://ai.google.dev/gemini-api/docs/llms.txt` and mirrors the linked
  `*.md.txt` docs.
- **anthropic**: Reads `https://platform.claude.com/llms.txt` (and `llms-full.txt` when
  available), then mirrors the linked Markdown docs. Use `ANTHROPIC_LANG=all` to pull all
  localized paths.
- **huggingface**: Reads `https://huggingface.co/docs/hub/llms.txt` (and `llms-full.txt`
  when available) and mirrors the linked Hub Markdown docs. Large runs may require a token:
  `HF_TOKEN=... ./sync-docs.sh huggingface`.
- **huggingface-inference-providers**: Reads `https://huggingface.co/docs/inference-providers/llms.txt`
  (and `llms-full.txt` when available) and mirrors the linked Inference Providers docs.
- **openrouter**: Reads `https://openrouter.ai/docs/llms.txt` (and `llms-full.txt` when
  available) and mirrors the linked `.md`/`.mdx` docs.
- **cohere**: Reads `https://docs.cohere.com/llms.txt` (and `llms-full.txt` when available)
  and mirrors the linked `.md`/`.mdx` docs.
- **mistral**: Reads `https://docs.mistral.ai/llms.txt` (and `llms-full.txt` when available)
  and mirrors the linked `.md`/`.mdx` docs.
- **langchain**: Reads `https://docs.langchain.com/llms.txt` (and `llms-full.txt` when
  available) and mirrors the linked `.md` docs.
- **langgraph**: Reads `https://langchain-ai.github.io/langgraph/llms.txt` (and
  `llms-full.txt` when available) and mirrors the linked docs pages.
- **langgraphjs**: Reads `https://langchain-ai.github.io/langgraphjs/llms.txt` (and
  `llms-full.txt` when available) and mirrors the linked docs pages.
- **polymarket**: Reads `https://docs.polymarket.com/llms.txt` (and `llms-full.txt` when
  available) and mirrors the linked `.md` docs.
- **nextjs**: Pulls docs from the Next.js repo (default branch `canary`) and concatenates
  all `*.md`/`*.mdx` into a single `index.md`. Override with `NEXTJS_BRANCH=...`.
- **supabase**, **groq**, **xai**, **stripe**, **cloudflare**, **netlify**, **twilio**,
  **digitalocean**, **railway**, **neon**, **turso**, **prisma**, **pinecone**, **retool**,
  **zapier**, **perplexity**, **elevenlabs**, **pinata**, **datadog**, **workos**, **clerk**,
  **litellm**, **crewai**: mirrored via their published `llms.txt` indexes.

## Interactive mode
Run `./sync-docs.sh --interactive` to pick providers with checkboxes. The last
selection is saved to `.llm-docs-sync/interactive-providers.txt` so subsequent
runs preselect your previous choices. If `whiptail` or `dialog` are unavailable,
the script falls back to a numbered prompt.

## Shell completions
Completions include flags plus provider names from `./sync-docs.sh --list`.

```bash
# install for your current shell (auto-detected)
./sync-docs.sh --install-completion

# bash (run once per shell session)
source completions/sync-docs.bash
```

```zsh
# zsh (run once per shell session)
fpath+=(/path/to/llm-docs-sync/completions)
autoload -U compinit && compinit
compdef _sync-docs ./sync-docs.sh sync-docs.sh
```

If the completion cannot locate the repo automatically, set `LLM_DOCS_SYNC_ROOT`
to the repo path so provider names can be resolved.

## Ad-hoc sources
Use `--source` to sync docs without adding provider definitions. The `--type` flag controls
how the source is processed (default: `auto`). Some examples:

```bash
# llms.txt mirror
./sync-docs.sh --source https://example.com/llms.txt --provider example --output docs

# OpenAPI spec direct
./sync-docs.sh --source https://example.com/openapi.yaml --type openapi --provider example-api --output docs

# GitHub docs
./sync-docs.sh --source https://github.com/org/repo.git --type github --docs-path docs --mode copy --provider repo-docs --output docs
```

See `providers/run.sh --help` for all source-mode options.

## Requirements
- bash, curl, rg (ripgrep), sort, mktemp, git
- Ruby (only for OpenAPI conversion)

## Repo layout
- `sync-docs.sh` - entrypoint that dispatches to providers and handles `--source`.
- `providers/run.sh` - resolves providers and routes to type handlers.
- `providers/defs/*.sh` - declarative provider definitions.
- `providers/types/*.sh` - type handlers (`llms`, `openapi`, `github`).
- `providers/lib/*` - shared utilities and OpenAPI-to-Markdown converter.
- `docs/` (ignored) - default output target when you run the scripts.
- `docs/manifest.json` - auto-written manifest describing each sync run.

## Versioned layout (recommended)
Run with `--version-label <label>` or `--timestamp-label` to nest outputs under
`<output>/<provider>/<label>`, then add `--latest-alias latest` to keep
`<output>/<provider>/latest` pointing to the newest snapshot. This keeps history
while preserving a stable path for ingestion tools.

## Extending to new providers
1. For llms.txt sources, add a `providers/defs/<name>.sh` with `TYPE="llms"` and
   `INDEX_URL`, plus optional `FULL_INDEX_URL`, `PATTERN`, `STRIP_PREFIX`, `STRIP_SUFFIX`,
   `THROTTLE_SECONDS`, `TOKEN`, or `HEADERS`.
2. For OpenAPI sources, set `TYPE="openapi"` and provide `SPEC_URL` or `INDEX_URL` with
   optional `SPEC_REGEX`/`FALLBACK_SPEC_URL`/`TITLE`.
3. For GitHub sources, set `TYPE="github"` and provide `REPO_URL` plus optional
   `BRANCH`, `DOCS_PATH`, and `MODE`.
4. For a new flow type, add a handler under `providers/types/<type>.sh` and wire it into
   `providers/run.sh`, then define `TYPE="<type>"` in your provider def.
5. Update README with a one-liner about the provider.

## TODO / providers welcome
- AWS Bedrock (direct)
- Azure OpenAI / Azure AI Foundry
- Google Vertex AI
- Hugging Face Inference API
- Meta Llama docs (official site once available)
- Vercel AI SDK / LangChain / LlamaIndex doc mirrors

## Contributing
See [CONTRIBUTING.md](CONTRIBUTING.md). PRs welcome! Please keep scripts readable, small,
and well-commented where non-obvious.

## License
MIT - see [LICENSE](LICENSE).
