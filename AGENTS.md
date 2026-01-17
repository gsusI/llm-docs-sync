# Repository Guidelines

## Project Structure & Module Organization
- `sync-docs.sh` is the entrypoint that parses flags and dispatches providers.
- `providers/defs/*.sh` holds provider definitions (llms/OpenAPI/GitHub).
- `providers/run.sh` routes to type handlers in `providers/types/*.sh`.
- `providers/lib/*` contains shared helpers and the OpenAPI Markdown converter (Ruby).
- `completions/` provides shell completion scripts.
- `docs/` is the default output target (generated, ignored by git); manifests live in
  `docs/manifest.json`.

## Build, Test, and Development Commands
- `./sync-docs.sh --list` lists installed providers (quick smoke check).
- `./sync-docs.sh gemini` syncs a provider into `./docs/gemini`.
- `./sync-docs.sh --output /tmp/llmdocs nextjs` writes into a custom directory.
- `just run -- gemini` wrapper for `sync-docs.sh`.
- `just test` runs the provider list command.
- `just package` builds `llm-docs-sync.zip` excluding generated docs.

## Coding Style & Naming Conventions
- Bash scripts use `set -euo pipefail` and prefer POSIX-ish shell.
- Keep scripts small, readable, and dependency-light; add brief comments only when flow
  is non-obvious.
- Provider defs use uppercase config vars (e.g., `TYPE`, `INDEX_URL`, `REPO_URL`).
- Keep outputs deterministic and sorted where possible.

## Testing Guidelines
- No formal test suite. Use `./sync-docs.sh --list` plus a small sync run
  (e.g., `./sync-docs.sh --output /tmp/llmdocs gemini`) to validate behavior.
- OpenAPI conversions require Ruby; verify `docs/<provider>/index.md` and
  `docs/manifest.json` exist after runs.

## Commit & Pull Request Guidelines
- Commit messages are short and imperative; history shows both plain and type-prefixed
  forms (e.g., `feat:`). Either is OK—keep it consistent within a PR.
- PRs should describe the data source (llms.txt/OpenAPI/GitHub), list new env vars or
  requirements, include a sample sync command, and update `README.md` for new providers.
- Do not commit generated docs under `docs/`.

## Security & Configuration Tips
- Keep tokens in env vars (e.g., `HF_TOKEN`) and avoid committing secrets.
- Sync runs perform network fetches; ensure you have access to target sources.
