# Contributing

Thanks for helping improve LLM Docs Sync! This project stays intentionally small
and dependency-light. Please keep that spirit when contributing.

## How to contribute
- **Bugs / requests:** Open an issue with a clear repro or proposal.
- **Small fixes:** Open a PR directly.
- **New providers:** Describe the data source (e.g., `llms.txt`, OpenAPI URL),
  required tools, and expected output structure.

## Development setup
Prereqs: bash, curl, rg (ripgrep), sort, mktemp. Ruby is needed only for the
OpenAI converter.

Recommended workflow:
```bash
git clone https://github.com/gsusI/llm-docs-sync.git
cd llm-docs-sync
./sync-docs.sh --output /tmp/llmdocs gemini   # quick smoke test
./sync-docs.sh --output /tmp/llmdocs openai   # requires Ruby
```

## Style & guidelines
- Keep scripts readable; add brief comments when flow isn’t obvious.
- Prefer POSIX-ish shell; avoid heavy dependencies.
- Validate flags in `usage()` and fail fast on missing tools.
- Keep outputs deterministic and sorted where possible.
- `.gitignore` ignores fetched docs; don’t commit generated docs.

## Adding a provider
1. Create `providers/<name>.sh` with `--output` (and other) flags documented in
   `usage()`.
2. Add a `case` entry in `sync-docs.sh`.
3. Ensure it exits non-zero on failures and cleans up temp files.
4. Update README with a one-liner about the provider.

## Code of Conduct
By participating, you agree to uphold the [Code of Conduct](CODE_OF_CONDUCT.md).
