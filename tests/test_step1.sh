#!/usr/bin/env bash
# tests/test_step1.sh — unit/integration tests for step1-explain-organize.sh
# Sourced by run_tests.sh
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$TESTS_DIR/../scripts"

# shellcheck source=../scripts/utils.sh
source "$SCRIPTS_DIR/utils.sh"
# shellcheck source=../scripts/step1-explain-organize.sh
source "$SCRIPTS_DIR/step1-explain-organize.sh"

# ── _write_codebase_md ────────────────────────────────────────────────────────
_suite "step1 · _write_codebase_md (Node.js workspace)"

WS=$(mktemp -d)
echo '{"name":"my-app","version":"1.0.0"}' > "$WS/package.json"
echo '{}' > "$WS/tsconfig.json"
mkdir -p "$WS/src"
echo "export const x = 1;" > "$WS/src/index.ts"

export WORKSPACE="$WS" OVERWRITE="false"
_write_codebase_md "$WS" "nodejs typescript" "false"

assert_file_exists    "$WS/CODEBASE.md"       "CODEBASE.md created"
assert_file_contains  "$WS/CODEBASE.md" "nodejs"     "CODEBASE.md mentions nodejs"
assert_file_contains  "$WS/CODEBASE.md" "typescript" "CODEBASE.md mentions typescript"
assert_file_contains  "$WS/CODEBASE.md" "package.json" "CODEBASE.md lists package.json"
assert_file_not_empty "$WS/CODEBASE.md"       "CODEBASE.md is not empty"
assert_file_contains  "$WS/CODEBASE.md" "## Directory Tree" "CODEBASE.md has tree section"
assert_file_contains  "$WS/CODEBASE.md" "## Summary"        "CODEBASE.md has Summary section"

rm -rf "$WS"

# ── _write_codebase_md — overwrite=false skips existing ──────────────────────
_suite "step1 · _write_codebase_md (overwrite guard)"

WS=$(mktemp -d)
echo "original" > "$WS/CODEBASE.md"
_write_codebase_md "$WS" "generic" "false"
content=$(cat "$WS/CODEBASE.md")
assert_eq "$content" "original" "overwrite=false preserves existing CODEBASE.md"

_write_codebase_md "$WS" "generic" "true"
content=$(cat "$WS/CODEBASE.md")
# After overwrite=true, content should no longer be "original"
[[ "$content" != "original" ]] && result=0 || result=1
assert_eq "$result" "0" "overwrite=true regenerates CODEBASE.md"

rm -rf "$WS"

# ── _aggregate_github ─────────────────────────────────────────────────────────
_suite "step1 · _aggregate_github"

WS=$(mktemp -d)
mkdir -p "$WS/subapp/.github/workflows"
echo "name: SubApp CI" > "$WS/subapp/.github/workflows/ci.yml"
echo "version: 2" > "$WS/subapp/.github/dependabot.yml"

export WORKSPACE="$WS"
_aggregate_github "$WS"

assert_file_exists "$WS/.github/workflows/ci.yml"    "workflow moved to root .github"
assert_file_exists "$WS/.github/dependabot.yml"      "dependabot.yml moved to root .github"

content=$(cat "$WS/.github/workflows/ci.yml")
assert_eq "$content" "name: SubApp CI"  "workflow content preserved after merge"

rm -rf "$WS"

# ── _aggregate_github — non-destructive merge ─────────────────────────────────
_suite "step1 · _aggregate_github (non-destructive)"

WS=$(mktemp -d)
mkdir -p "$WS/.github/workflows"
echo "root: workflow" > "$WS/.github/workflows/ci.yml"

mkdir -p "$WS/service/.github/workflows"
echo "service: workflow" > "$WS/service/.github/workflows/ci.yml"

export WORKSPACE="$WS"
_aggregate_github "$WS"

content=$(cat "$WS/.github/workflows/ci.yml")
assert_eq "$content" "root: workflow" "root workflow not overwritten during merge"

rm -rf "$WS"

# ── _update_workflow_refs ─────────────────────────────────────────────────────
_suite "step1 · _update_workflow_refs"

WS=$(mktemp -d)
mkdir -p "$WS/.github/workflows"
cat > "$WS/.github/workflows/deploy.yml" <<'WFEOF'
uses: service/.github/workflows/reusable.yml
path: apps/.github/workflows/helpers.yml
WFEOF

export WORKSPACE="$WS"
_update_workflow_refs "$WS"

content=$(cat "$WS/.github/workflows/deploy.yml")
assert_contains "$content" ".github/workflows/reusable.yml"  "path reference updated (service)"
assert_contains "$content" ".github/workflows/helpers.yml"   "path reference updated (apps)"
# Stale subdir prefix should be gone
echo "$content" | grep -q "service/\.github" && result=0 || result=1
assert_eq "$result" "1" "stale 'service/.github' prefix removed"

rm -rf "$WS"

# ── _generate_build_ci — Node.js ─────────────────────────────────────────────
_suite "step1 · _generate_build_ci (nodejs)"

WS=$(mktemp -d)
echo '{"name":"app"}' > "$WS/package.json"

export WORKSPACE="$WS"
_generate_build_ci "$WS" "nodejs" "false"

assert_file_exists   "$WS/.github/workflows/build.yml"       "build.yml created for nodejs"
assert_file_contains "$WS/.github/workflows/build.yml" "npm ci" "npm ci install step present"
assert_file_contains "$WS/.github/workflows/build.yml" "npm test" "npm test step present"
assert_file_contains "$WS/.github/workflows/build.yml" "on:"     "workflow trigger present"
assert_file_contains "$WS/.github/workflows/build.yml" "push:"   "push trigger present"
assert_file_contains "$WS/.github/workflows/build.yml" "pull_request:" "PR trigger present"

rm -rf "$WS"

# ── _generate_build_ci — Python ──────────────────────────────────────────────
_suite "step1 · _generate_build_ci (python)"

WS=$(mktemp -d)
touch "$WS/requirements.txt"

export WORKSPACE="$WS"
_generate_build_ci "$WS" "python" "false"

assert_file_exists   "$WS/.github/workflows/build.yml"    "build.yml created for python"
assert_file_contains "$WS/.github/workflows/build.yml" "setup-python"    "python setup step"
assert_file_contains "$WS/.github/workflows/build.yml" "pytest"          "pytest step present"
assert_file_contains "$WS/.github/workflows/build.yml" "flake8"          "flake8 lint step"

rm -rf "$WS"

# ── _generate_build_ci — Go ──────────────────────────────────────────────────
_suite "step1 · _generate_build_ci (go)"

WS=$(mktemp -d)
echo "module example.com/mymod\ngo 1.22" > "$WS/go.mod"

export WORKSPACE="$WS"
_generate_build_ci "$WS" "go" "false"

assert_file_contains "$WS/.github/workflows/build.yml" "setup-go"          "go setup step"
assert_file_contains "$WS/.github/workflows/build.yml" "go test"           "go test step"
assert_file_contains "$WS/.github/workflows/build.yml" "go build"          "go build step"

rm -rf "$WS"

# ── _generate_build_ci — Rust ────────────────────────────────────────────────
_suite "step1 · _generate_build_ci (rust)"

WS=$(mktemp -d)
touch "$WS/Cargo.toml"

export WORKSPACE="$WS"
_generate_build_ci "$WS" "rust" "false"

assert_file_contains "$WS/.github/workflows/build.yml" "rust-toolchain"    "rust toolchain step"
assert_file_contains "$WS/.github/workflows/build.yml" "cargo test"        "cargo test step"
assert_file_contains "$WS/.github/workflows/build.yml" "cargo build"       "cargo build step"
assert_file_contains "$WS/.github/workflows/build.yml" "clippy"            "clippy lint step"

rm -rf "$WS"

# ── _generate_build_ci — overwrite guard ─────────────────────────────────────
_suite "step1 · _generate_build_ci (overwrite guard)"

WS=$(mktemp -d)
mkdir -p "$WS/.github/workflows"
echo "# manual" > "$WS/.github/workflows/build.yml"

export WORKSPACE="$WS"
_generate_build_ci "$WS" "generic" "false"

content=$(cat "$WS/.github/workflows/build.yml")
assert_eq "$content" "# manual" "overwrite=false preserves existing build.yml"

rm -rf "$WS"

# ── _generate_build_ci — Docker job added when docker detected ───────────────
_suite "step1 · _generate_build_ci (docker)"

WS=$(mktemp -d)
touch "$WS/Dockerfile"

export WORKSPACE="$WS"
_generate_build_ci "$WS" "docker" "false"

assert_file_contains "$WS/.github/workflows/build.yml" "docker/build-push-action" \
  "docker build-push action present"
assert_file_contains "$WS/.github/workflows/build.yml" "docker/setup-buildx-action" \
  "buildx setup present"

rm -rf "$WS"

# ── run_step1 end-to-end ──────────────────────────────────────────────────────
_suite "step1 · run_step1 end-to-end (generic workspace)"

WS=$(mktemp -d)
echo '# My Repo' > "$WS/README.md"
mkdir -p "$WS/.github/workflows" "$WS/lib/.github/actions"
echo "action:" > "$WS/lib/.github/actions/my-action.yml"

export WORKSPACE="$WS" OVERWRITE="false"
run_step1

assert_file_exists "$WS/CODEBASE.md"                        "end-to-end: CODEBASE.md created"
assert_file_exists "$WS/.github/workflows/build.yml"        "end-to-end: build.yml created"
assert_file_exists "$WS/.github/actions/my-action.yml"      "end-to-end: nested action merged"

rm -rf "$WS"
