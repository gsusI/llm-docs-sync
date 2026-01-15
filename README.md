# LLM Docs Sync

Dependency-light scripts that vendor official LLM provider docs (OpenAI & Gemini) into
your project so local tools and RAG jobs can ingest them offline.

## Features
- Deterministic, idempotent fetches from each provider’s `llms.txt` index.
- Markdown output organized per provider for easy ingestion.
- Zero Node/Python deps; only shell + curl + rg + (Ruby for OpenAI conversion).
- Extensible: drop in `providers/<name>.sh`, add a single case, ship it.

## Quick start
```bash
# clone inside or next to your project
gh repo clone gsusI/llm-docs-sync
cd llm-docs-sync

# fetch both providers into ./docs/
./sync-docs.sh

# fetch only Gemini into ./vendor/llm-docs
./sync-docs.sh --output vendor/llm-docs gemini
```

Outputs land under `<output>/<provider>/`. Examples:
- `docs/openai/index.md` + `docs/openai/groups/*.md` generated from OpenAI’s OpenAPI spec.
- `docs/gemini/docs/*.md` mirrored from Gemini’s published markdown twins.

## Providers
- **openai**: Reads `https://platform.openai.com/llms.txt` to locate the OpenAPI spec, then renders Markdown reference grouped by operation tags.
- **gemini**: Reads `https://ai.google.dev/gemini-api/docs/llms.txt` and mirrors the linked `*.md.txt` docs.

Adding a provider = drop `providers/<name>.sh` and wire a case entry in `sync-docs.sh`.

## Requirements
- bash, curl, rg (ripgrep), sort, mktemp
- Ruby (only for OpenAI conversion)

## Repo layout
- `sync-docs.sh` — entrypoint that dispatches to providers.
- `providers/openai.sh` — fetches OpenAI spec + generates Markdown groups.
- `providers/gemini.sh` — mirrors Gemini Markdown twins.
- `docs/` (ignored) — default output target when you run the scripts.

## Extending to new providers
1. Create `providers/<name>.sh` that writes docs into the given `--output` dir.
2. Add a `case` branch in `sync-docs.sh` to invoke it.
3. Keep it dependency-light (curl/rg preferred) and document flags in `usage()`.
4. Open a PR with a short note in README if you add flags or providers.

## Contributing
See [CONTRIBUTING.md](CONTRIBUTING.md). PRs welcome! Please keep scripts readable, small, and well-commented where non-obvious.

## License
MIT — see [LICENSE](LICENSE).
