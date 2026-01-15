# LLM Docs Sync

Tiny, dependency-light scripts to vendor LLM provider docs (OpenAI & Gemini) into
your project so local tools and RAG jobs can ingest them offline.

## Why
- Keep API references close to your codebase without scraping UIs.
- Deterministic, idempotent fetches from official `llms.txt` indexes.
- Per-provider outputs so you can pick what you need.

## Quick start
```bash
# clone inside or next to your project
gh repo clone <your-org>/llm-docs-sync
cd llm-docs-sync

# fetch both providers into ./docs/
./sync-docs.sh

# fetch only Gemini into ./vendor/llm-docs
./sync-docs.sh --output vendor/llm-docs gemini
```

Outputs land under `<output>/<provider>/`. Examples:
- `docs/openai/index.md` + `docs/openai/groups/*.md` generated from OpenAI's OpenAPI spec.
- `docs/gemini/docs/*.md` mirrored from Gemini's published markdown twins.

## Providers
- **openai**: Reads `https://platform.openai.com/llms.txt` to locate the OpenAPI spec, then renders Markdown reference grouped by operation tags.
- **gemini**: Reads `https://ai.google.dev/gemini-api/docs/llms.txt` and mirrors the linked `*.md.txt` docs.

Adding a provider is as simple as dropping `providers/<name>.sh` and wiring a case
entry in `sync-docs.sh`.

## Requirements
- bash, curl, rg (ripgrep), sort, mktemp
- Ruby (only for OpenAI conversion)

## Extending
1. Create `providers/<name>.sh` that writes docs into the provided `--output` dir.
2. Add a case to `sync-docs.sh` to invoke it.
3. Keep the script POSIX-ish and dependency-light.

## Contributing
PRs welcome! Please:
- Keep scripts readable with comments where the flow isn't obvious.
- Favor small, composable helpers over monoliths.
- Add a short note to README if you change usage.

## License
MIT
