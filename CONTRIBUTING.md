# Contributing

Thanks for helping improve LLM Docs Sync! This project stays intentionally small
and dependency-light. Please keep that spirit when contributing.

## How to contribute
- **Bugs / requests:** Open an issue with a clear repro or proposal.
- **Small fixes:** Open a PR directly.
- **New providers:** Describe the data source (e.g., `llms.txt`, OpenAPI URL),
  required tools, and expected output structure.

## Development setup
Prereqs: bash, curl, rg (ripgrep), sort, mktemp, git. Ruby is needed only for the
OpenAPI converter.

Recommended workflow:
```bash
git clone https://github.com/gsusI/llm-docs-sync.git
cd llm-docs-sync
./sync-docs.sh --output /tmp/llmdocs gemini   # quick smoke test
./sync-docs.sh --output /tmp/llmdocs openai   # requires Ruby
./sync-docs.sh --output /tmp/llmdocs nextjs   # clones docs from Next.js repo
```

## Style & guidelines
- Keep scripts readable; add brief comments when flow isn't obvious.
- Prefer POSIX-ish shell; avoid heavy dependencies.
- Validate flags in `usage()` and fail fast on missing tools.
- Keep outputs deterministic and sorted where possible.
- `.gitignore` ignores fetched docs; don't commit generated docs.

## Adding a provider
1. For llms.txt sources, add a `providers/defs/<name>.sh` with `TYPE="llms"` and
   `INDEX_URL` (plus optional `FULL_INDEX_URL`, `PATTERN`, `STRIP_PREFIX`,
   `STRIP_SUFFIX`, `THROTTLE_SECONDS`, `TOKEN`, or `HEADERS`).
2. For OpenAPI sources, set `TYPE="openapi"` and define `SPEC_URL` or `INDEX_URL`
   with optional `SPEC_REGEX`/`FALLBACK_SPEC_URL`/`TITLE`.
3. For GitHub sources, set `TYPE="github"` and define `REPO_URL` plus optional
   `BRANCH`, `DOCS_PATH`, and `MODE`.
4. For a new flow type, add a handler under `providers/types/<type>.sh` and wire it
   into `providers/run.sh`, then define `TYPE="<type>"` in your provider def.
5. Update README with a one-liner about the provider.

## Code of Conduct
By participating, you agree to uphold the [Code of Conduct](CODE_OF_CONDUCT.md).
