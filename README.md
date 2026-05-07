# gh-action-unify-repo

> **Marketplace-ready · Zero dependencies · Context-agnostic**

A GitHub Action that performs three Copilot repo-enrichment steps against _any_ repository, regardless of language or framework:

1. **Explain & Organize** — scans the codebase, writes `CODEBASE.md`, aggregates nested `.github` sub-directories into the workspace root, updates stale path references in workflow files, and generates a comprehensive CI workflow tailored to the detected stack.
2. **Analyze & Improve Test Coverage** — identifies source files with missing tests, scaffolds exhaustive test templates (happy-path, edge-cases, error-cases, parametrized, async), and adds coverage configuration.
3. **Create Integration Plan** — maps component relationships, detects entry points, and writes a phased `INTEGRATION_PLAN.md` road-map for achieving relational fluency throughout the codebase.

All enrichment changes can be optionally committed to a new branch and surfaced as a pull request.

---

## Table of Contents

- [Quick start](#quick-start)
- [Inputs](#inputs)
- [Outputs](#outputs)
- [Generated files](#generated-files)
- [Examples](#examples)
  - [Run all steps and open a PR](#run-all-steps-and-open-a-pr)
  - [Run a single step without a PR](#run-a-single-step-without-a-pr)
  - [Scheduled weekly enrichment](#scheduled-weekly-enrichment)
  - [Refresh generated files](#refresh-generated-files)
- [Supported stacks](#supported-stacks)
- [Architecture](#architecture)
- [Contributing](#contributing)
- [License](#license)

---

## Quick start

```yaml
# .github/workflows/enrich.yml
name: Enrich repo

on:
  workflow_dispatch:

jobs:
  enrich:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: ReZonArc/gh-action-unify-repo@v1
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

This runs all three enrichment steps and opens a pull request with the results.

---

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `github-token` | No | `${{ github.token }}` | Token used for API calls and creating pull requests. Needs `contents: write` and `pull-requests: write` permissions. |
| `workspace` | No | `${{ github.workspace }}` | Absolute path to the repository root to enrich. |
| `steps` | No | `explain,tests,plan` | Comma-separated list of steps to run. Allowed values: `explain`, `tests`, `plan`. |
| `create-pr` | No | `true` | When `true`, commits all generated changes and opens a pull request. |
| `pr-branch` | No | `copilot/unify-repo` | Branch name used when `create-pr` is `true`. |
| `commit-message` | No | `chore: apply unify-repo enrichment` | Commit message used when `create-pr` is `true`. |
| `overwrite` | No | `false` | When `true`, regenerates all previously generated files. When `false`, skips files that already exist. |

---

## Outputs

| Output | Description |
|--------|-------------|
| `report-path` | Workspace-relative path to `ENRICHMENT_REPORT.md`. |
| `changes-made` | `"true"` if any files were created or modified. |
| `pr-url` | URL of the pull request created (only set when `create-pr` is `true`). |

---

## Generated files

| File | Step | Description |
|------|------|-------------|
| `CODEBASE.md` | `explain` | Codebase overview: stack, entry points, config files, directory tree. |
| `.github/workflows/build.yml` | `explain` | Comprehensive CI workflow tailored to the detected stack. |
| `TEST_COVERAGE_GUIDE.md` | `tests` | Coverage targets, how to run tests, and what was scaffolded. |
| `tests/test_<name>.*` or `spec/<name>_spec.rb` | `tests` | Scaffolded test files for uncovered source files. |
| `INTEGRATION_PLAN.md` | `plan` | Phased road-map for integrating components with relational fluency. |
| `ENRICHMENT_REPORT.md` | _(always)_ | Summary of all steps run and files generated. |

---

## Examples

### Run all steps and open a PR

```yaml
- uses: ReZonArc/gh-action-unify-repo@v1
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    steps: 'explain,tests,plan'
    create-pr: 'true'
    pr-branch: 'copilot/enrichment-2024'
```

### Run a single step without a PR

```yaml
- uses: ReZonArc/gh-action-unify-repo@v1
  with:
    steps: 'explain'
    create-pr: 'false'
```

### Scheduled weekly enrichment

```yaml
on:
  schedule:
    - cron: '0 9 * * 1'   # every Monday at 09:00 UTC

jobs:
  enrich:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: ReZonArc/gh-action-unify-repo@v1
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          overwrite: 'true'   # refresh all generated files each week
```

### Refresh generated files

```yaml
- uses: ReZonArc/gh-action-unify-repo@v1
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    overwrite: 'true'
    commit-message: 'chore: refresh unify-repo enrichment'
```

### Use outputs in subsequent steps

```yaml
- id: enrich
  uses: ReZonArc/gh-action-unify-repo@v1
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}

- name: Print results
  run: |
    echo "Report at: ${{ steps.enrich.outputs.report-path }}"
    echo "Changes:   ${{ steps.enrich.outputs.changes-made }}"
    echo "PR URL:    ${{ steps.enrich.outputs.pr-url }}"
```

---

## Supported stacks

The action auto-detects the technology stack from well-known config files.
Multiple stacks can be active simultaneously (e.g. a Node.js monorepo with Docker).

| Stack | Detection file(s) | CI job | Test scaffold |
|-------|-------------------|--------|---------------|
| Node.js | `package.json` | `npm ci` + `npm test` | Jest / Vitest / Mocha |
| TypeScript | `tsconfig.json` | _(with Node.js)_ | `.test.ts` templates |
| Python | `requirements.txt`, `pyproject.toml`, `Pipfile`, `setup.py` | `pytest` + `flake8` | pytest class templates |
| Django | `manage.py` | _(with Python)_ | pytest templates |
| Go | `go.mod` | `go test -race -cover` | `_test.go` templates |
| Java (Maven) | `pom.xml` | `mvn test` + `mvn package` | JUnit 5 templates |
| Java (Gradle) | `build.gradle` | `./gradlew test` | JUnit 5 templates |
| Rust | `Cargo.toml` | `cargo test` + `clippy` | inline `#[cfg(test)]` blocks |
| Ruby | `Gemfile` | `rspec` | `_spec.rb` templates |
| .NET | `*.csproj`, `*.sln` | `dotnet test` | xUnit templates |
| Docker | `Dockerfile` | `docker/build-push-action` | _(N/A)_ |
| Shell | `*.sh` | `shellcheck` | `run_tests.sh` template |
| Generic | _(fallback)_ | syntax check | `run_tests.sh` template |

---

## Architecture

```
gh-action-unify-repo/
├── action.yml                       # GitHub Action metadata & wiring
├── scripts/
│   ├── main.sh                      # Orchestrator: reads env vars, calls steps
│   ├── utils.sh                     # Shared utilities (logging, stack detection, …)
│   ├── step1-explain-organize.sh    # Step 1: CODEBASE.md, .github merge, CI gen
│   ├── step2-analyze-tests.sh       # Step 2: test scaffolding, coverage config
│   ├── step3-integration-plan.sh    # Step 3: INTEGRATION_PLAN.md
│   └── create-pr.sh                 # Git commit + GitHub API PR creation
├── tests/
│   ├── run_tests.sh                 # Zero-dependency bash test runner
│   ├── test_utils.sh                # Unit tests for utils.sh
│   ├── test_step1.sh                # Unit + integration tests for step 1
│   ├── test_step2.sh                # Unit + integration tests for step 2
│   └── test_step3.sh                # Unit + integration tests for step 3
└── .github/
    └── workflows/
        └── ci.yml                   # CI: shellcheck + unit tests + integration smoke-test
```

### Design principles

- **Zero external dependencies** — every script is pure bash. No `npm`, `pip`, or other package managers are invoked during enrichment itself.
- **Context-agnostic** — stack detection is heuristic; every code-path has a generic fallback.
- **Non-destructive** — existing files are never overwritten unless `overwrite: true` is explicitly set.
- **Idempotent** — the action can be run repeatedly without accumulating noise.
- **Minimal permissions** — only `contents: write` and `pull-requests: write` are needed.

---

## Contributing

1. Fork the repository and create a feature branch.
2. Make your changes in `scripts/`.
3. Add or update tests in `tests/`.
4. Run the test suite locally:
   ```bash
   chmod +x scripts/*.sh tests/*.sh
   bash tests/run_tests.sh
   ```
5. Run shellcheck:
   ```bash
   shellcheck scripts/*.sh tests/*.sh
   ```
6. Open a pull request — the CI will run automatically.

---

## License

[MIT](LICENSE)
