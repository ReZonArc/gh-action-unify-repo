#!/usr/bin/env bash
# tests/test_utils.sh — unit tests for scripts/utils.sh
# Sourced by run_tests.sh
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$TESTS_DIR/../scripts"

# shellcheck source=../scripts/utils.sh
source "$SCRIPTS_DIR/utils.sh"

# ── Logging functions ─────────────────────────────────────────────────────────
_suite "utils.sh · Logging functions"

out=$(log_info  "hello" 2>&1); assert_contains "$out" "hello"  "log_info includes message"
out=$(log_ok    "good"  2>&1); assert_contains "$out" "good"   "log_ok includes message"
out=$(log_warn  "warn"  2>&1); assert_contains "$out" "warn"   "log_warn includes message"
out=$(log_error "err"   2>&1); assert_contains "$out" "err"    "log_error includes message"
out=$(log_step  "step"  2>&1); assert_contains "$out" "step"   "log_step includes message"
out=$(log_skip  "skip"  2>&1); assert_contains "$out" "skip"   "log_skip includes message"

# ── timestamp ─────────────────────────────────────────────────────────────────
_suite "utils.sh · timestamp"

ts=$(timestamp)
assert_contains "$ts" "T"   "timestamp contains T separator"
assert_contains "$ts" "Z"   "timestamp ends with Z"
# Basic format check: YYYY-MM-DDTHH:MM:SSZ
echo "$ts" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
assert_true $? "timestamp matches ISO-8601 format"

# ── relative_path ─────────────────────────────────────────────────────────────
_suite "utils.sh · relative_path"

r=$(relative_path "/a/b" "/a/b/c/d.txt")
assert_eq "$r" "c/d.txt" "relative_path strips base"

r=$(relative_path "/repo" "/repo/src/foo.js")
assert_eq "$r" "src/foo.js" "relative_path for nested file"

r=$(relative_path "/repo/" "/repo/file.txt")
assert_eq "$r" "file.txt"  "relative_path with trailing slash on base"

# ── should_write ─────────────────────────────────────────────────────────────
_suite "utils.sh · should_write"

TMPDIR_W=$(mktemp -d)
TMPFILE="$TMPDIR_W/existing.txt"
touch "$TMPFILE"

# Non-existent file → should write regardless of overwrite flag
should_write "$TMPDIR_W/nonexistent.txt" "false"
assert_true $? "should_write: non-existent file returns 0 (write)"

should_write "$TMPDIR_W/nonexistent.txt" "true"
assert_true $? "should_write: non-existent file + overwrite=true returns 0"

# Existing file + overwrite=false → should NOT write
should_write "$TMPFILE" "false" && result=0 || result=1
assert_eq "$result" "1" "should_write: existing file + overwrite=false returns 1"

# Existing file + overwrite=true → should write
should_write "$TMPFILE" "true"
assert_true $? "should_write: existing file + overwrite=true returns 0"

rm -rf "$TMPDIR_W"

# ── file_exists_nonempty ──────────────────────────────────────────────────────
_suite "utils.sh · file_exists_nonempty"

TMPDIR_F=$(mktemp -d)
EMPTY="$TMPDIR_F/empty.txt"; touch "$EMPTY"
NONEMPTY="$TMPDIR_F/nonempty.txt"; echo "data" > "$NONEMPTY"

file_exists_nonempty "$NONEMPTY"
assert_true $? "file_exists_nonempty: non-empty file → true"

file_exists_nonempty "$EMPTY" && result=0 || result=1
assert_eq "$result" "1" "file_exists_nonempty: empty file → false"

file_exists_nonempty "$TMPDIR_F/missing" && result=0 || result=1
assert_eq "$result" "1" "file_exists_nonempty: missing file → false"

rm -rf "$TMPDIR_F"

# ── detect_stack ─────────────────────────────────────────────────────────────
_suite "utils.sh · detect_stack"

TMPDIR_S=$(mktemp -d)

# Empty dir → generic or shell
s=$(detect_stack "$TMPDIR_S")
assert_contains "$s" "generic" "empty workspace → generic"

# Node.js detection
touch "$TMPDIR_S/package.json"
s=$(detect_stack "$TMPDIR_S")
assert_contains "$s" "nodejs" "package.json → nodejs"
rm "$TMPDIR_S/package.json"

# Python detection (requirements.txt)
touch "$TMPDIR_S/requirements.txt"
s=$(detect_stack "$TMPDIR_S")
assert_contains "$s" "python" "requirements.txt → python"
rm "$TMPDIR_S/requirements.txt"

# Python detection (pyproject.toml)
touch "$TMPDIR_S/pyproject.toml"
s=$(detect_stack "$TMPDIR_S")
assert_contains "$s" "python" "pyproject.toml → python"
rm "$TMPDIR_S/pyproject.toml"

# Go detection
touch "$TMPDIR_S/go.mod"
s=$(detect_stack "$TMPDIR_S")
assert_contains "$s" "go" "go.mod → go"
rm "$TMPDIR_S/go.mod"

# Rust detection
touch "$TMPDIR_S/Cargo.toml"
s=$(detect_stack "$TMPDIR_S")
assert_contains "$s" "rust" "Cargo.toml → rust"
rm "$TMPDIR_S/Cargo.toml"

# Docker detection
touch "$TMPDIR_S/Dockerfile"
s=$(detect_stack "$TMPDIR_S")
assert_contains "$s" "docker" "Dockerfile → docker"
rm "$TMPDIR_S/Dockerfile"

# TypeScript detection (alongside Node)
touch "$TMPDIR_S/package.json" "$TMPDIR_S/tsconfig.json"
s=$(detect_stack "$TMPDIR_S")
assert_contains "$s" "typescript" "tsconfig.json → typescript"
rm "$TMPDIR_S/package.json" "$TMPDIR_S/tsconfig.json"

# Multiple stacks
touch "$TMPDIR_S/package.json" "$TMPDIR_S/Dockerfile"
s=$(detect_stack "$TMPDIR_S")
assert_contains "$s" "nodejs" "multi-stack: nodejs present"
assert_contains "$s" "docker" "multi-stack: docker present"
rm "$TMPDIR_S/package.json" "$TMPDIR_S/Dockerfile"

rm -rf "$TMPDIR_S"

# ── detect_test_framework ────────────────────────────────────────────────────
_suite "utils.sh · detect_test_framework"

TMPDIR_TF=$(mktemp -d)

# Python → pytest default
f=$(detect_test_framework "$TMPDIR_TF" "python")
assert_eq "$f" "pytest" "python stack → pytest default"

# Go → go-test
f=$(detect_test_framework "$TMPDIR_TF" "go")
assert_eq "$f" "go-test" "go stack → go-test"

# Ruby → rspec
f=$(detect_test_framework "$TMPDIR_TF" "ruby")
assert_eq "$f" "rspec" "ruby stack → rspec"

# Rust → cargo-test
f=$(detect_test_framework "$TMPDIR_TF" "rust")
assert_eq "$f" "cargo-test" "rust stack → cargo-test"

# .NET → xunit
f=$(detect_test_framework "$TMPDIR_TF" "dotnet")
assert_eq "$f" "xunit" "dotnet stack → xunit"

# Node.js with jest in package.json
echo '{"devDependencies":{"jest":"^29"}}' > "$TMPDIR_TF/package.json"
f=$(detect_test_framework "$TMPDIR_TF" "nodejs")
assert_eq "$f" "jest" "package.json with jest → jest"
rm "$TMPDIR_TF/package.json"

# Node.js with vitest
echo '{"devDependencies":{"vitest":"^1"}}' > "$TMPDIR_TF/package.json"
f=$(detect_test_framework "$TMPDIR_TF" "nodejs")
assert_eq "$f" "vitest" "package.json with vitest → vitest"
rm "$TMPDIR_TF/package.json"

rm -rf "$TMPDIR_TF"

# ── generate_tree ─────────────────────────────────────────────────────────────
_suite "utils.sh · generate_tree"

TMPDIR_G=$(mktemp -d)
mkdir -p "$TMPDIR_G/src/lib"
touch    "$TMPDIR_G/src/index.ts" "$TMPDIR_G/src/lib/util.ts" "$TMPDIR_G/README.md"

tree=$(generate_tree "$TMPDIR_G" "" 3 0)
assert_contains "$tree" "src"          "tree contains src"
assert_contains "$tree" "README.md"    "tree contains README.md"
assert_contains "$tree" "lib"          "tree contains lib"
assert_contains "$tree" "index.ts"     "tree contains index.ts"
assert_contains "$tree" "util.ts"      "tree contains util.ts"

# .git should be excluded
mkdir -p "$TMPDIR_G/.git"
tree=$(generate_tree "$TMPDIR_G" "" 3 0)
echo "$tree" | grep -q "\.git" && result=0 || result=1
assert_eq "$result" "1" "tree excludes .git"

# node_modules should be excluded
mkdir -p "$TMPDIR_G/node_modules/some-pkg"
tree=$(generate_tree "$TMPDIR_G" "" 3 0)
echo "$tree" | grep -q "node_modules" && result=0 || result=1
assert_eq "$result" "1" "tree excludes node_modules"

# Depth limiting
tree_d1=$(generate_tree "$TMPDIR_G" "" 1 0)
echo "$tree_d1" | grep -q "util.ts" && result=0 || result=1
assert_eq "$result" "1" "tree respects max_depth (deep file absent at depth 1)"

rm -rf "$TMPDIR_G"

# ── count_files_by_extension ──────────────────────────────────────────────────
_suite "utils.sh · count_files_by_extension"

TMPDIR_C=$(mktemp -d)
touch "$TMPDIR_C/a.ts" "$TMPDIR_C/b.ts" "$TMPDIR_C/c.js" "$TMPDIR_C/d.md" "$TMPDIR_C/LICENSE"

counts=$(count_files_by_extension "$TMPDIR_C")
assert_contains "$counts" "ts"  "counts include ts extension"
assert_contains "$counts" "js"  "counts include js extension"
assert_contains "$counts" "md"  "counts include md extension"

# Files without extension (LICENSE) must NOT appear in output
echo "$counts" | grep -q "LICENSE" && result=0 || result=1
assert_eq "$result" "1" "extension-less files not included in counts"

# Check sorting: ts (2 files) should appear before js (1 file)
first=$(echo "$counts" | head -1)
assert_contains "$first" "ts" "ts (most frequent) is listed first"

rm -rf "$TMPDIR_C"

# ── find_nested_github_dirs ───────────────────────────────────────────────────
_suite "utils.sh · find_nested_github_dirs"

TMPDIR_N=$(mktemp -d)

# Root .github should NOT be returned
mkdir -p "$TMPDIR_N/.github/workflows"
result=$(find_nested_github_dirs "$TMPDIR_N")
assert_eq "$result" "" "root .github is not considered nested"

# Nested .github SHOULD be returned
mkdir -p "$TMPDIR_N/subdir/.github/workflows"
result=$(find_nested_github_dirs "$TMPDIR_N")
assert_contains "$result" "subdir/.github" "nested .github is returned"

# Deeper nesting
mkdir -p "$TMPDIR_N/a/b/.github"
result=$(find_nested_github_dirs "$TMPDIR_N")
assert_contains "$result" "a/b/.github" "deeply nested .github is returned"

rm -rf "$TMPDIR_N"

# ── merge_github_dir ─────────────────────────────────────────────────────────
_suite "utils.sh · merge_github_dir"

TMPDIR_M=$(mktemp -d)
SRC="$TMPDIR_M/src_github"
DST="$TMPDIR_M/dst_github"
mkdir -p "$SRC/workflows"
echo "job: src" > "$SRC/workflows/ci.yml"
echo "dep: src" > "$SRC/dependabot.yml"

mkdir -p "$DST/workflows"
echo "job: dst" > "$DST/workflows/ci.yml"  # pre-existing file — must NOT be overwritten

merge_github_dir "$SRC" "$DST"

# Pre-existing file must NOT be overwritten
content=$(cat "$DST/workflows/ci.yml")
assert_eq "$content" "job: dst" "merge_github_dir does not overwrite existing files"

# New file from src must be copied
assert_file_exists "$DST/dependabot.yml" "merge_github_dir copies new files"
content2=$(cat "$DST/dependabot.yml")
assert_eq "$content2" "dep: src" "merge_github_dir copied content correctly"

rm -rf "$TMPDIR_M"

# ── append_section ────────────────────────────────────────────────────────────
_suite "utils.sh · append_section"

TMPDIR_A=$(mktemp -d)
DOC="$TMPDIR_A/doc.md"
echo "# Title" > "$DOC"

append_section "$DOC" "New Section" "Some content here."
assert_file_contains "$DOC" "## New Section" "append_section adds heading"
assert_file_contains "$DOC" "Some content here." "append_section adds content"

append_section "$DOC" "Another" "More content."
assert_file_contains "$DOC" "## Another" "append_section adds second heading"

rm -rf "$TMPDIR_A"
