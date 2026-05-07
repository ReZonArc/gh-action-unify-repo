#!/usr/bin/env bash
# tests/run_tests.sh
# ─────────────────────────────────────────────────────────────────────────────
# Zero-dependency bash test runner for the unify-repo action.
# Usage:  bash tests/run_tests.sh [pattern]
#   pattern — optional grep pattern to run only matching test files
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Test framework ────────────────────────────────────────────────────────────
PASS=0; FAIL=0; SKIP=0; _CURRENT_SUITE=""

_suite() { _CURRENT_SUITE="$1"; echo ""; echo "  ▶  $_CURRENT_SUITE"; }

_pass() { PASS=$((PASS+1)); echo "    ✔  $1"; }
_fail() { FAIL=$((FAIL+1)); echo "    ✘  $1"; echo "       └─ $2"; }
_skip() { SKIP=$((SKIP+1)); echo "    ○  SKIP: $1"; }

assert_eq() {
  local actual="$1" expected="$2" label="${3:-assert_eq}"
  if [[ "$actual" == "$expected" ]]; then
    _pass "$label"
  else
    _fail "$label" "expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" label="${3:-assert_contains}"
  if echo "$haystack" | grep -qF "$needle"; then
    _pass "$label"
  else
    _fail "$label" "'$needle' not found in output"
  fi
}

assert_true() {
  local expr_result="$1" label="${2:-assert_true}"
  if [[ "$expr_result" == "0" ]]; then
    _pass "$label"
  else
    _fail "$label" "expected exit 0, got $expr_result"
  fi
}

assert_false() {
  local expr_result="$1" label="${2:-assert_false}"
  if [[ "$expr_result" != "0" ]]; then
    _pass "$label"
  else
    _fail "$label" "expected non-zero exit, got 0"
  fi
}

assert_file_exists() {
  local path="$1" label="${2:-file exists: $1}"
  if [[ -f "$path" ]]; then
    _pass "$label"
  else
    _fail "$label" "file not found: $path"
  fi
}

assert_dir_exists() {
  local path="$1" label="${2:-dir exists: $1}"
  if [[ -d "$path" ]]; then
    _pass "$label"
  else
    _fail "$label" "directory not found: $path"
  fi
}

assert_file_contains() {
  local path="$1" needle="$2" label="${3:-file contains: $2}"
  if [[ -f "$path" ]] && grep -qF "$needle" "$path"; then
    _pass "$label"
  else
    _fail "$label" "'$needle' not found in $path"
  fi
}

assert_file_not_empty() {
  local path="$1" label="${2:-file not empty: $1}"
  if [[ -s "$path" ]]; then
    _pass "$label"
  else
    _fail "$label" "file is empty or missing: $path"
  fi
}

export -f _suite _pass _fail _skip assert_eq assert_contains assert_true \
          assert_false assert_file_exists assert_dir_exists assert_file_contains \
          assert_file_not_empty

# ── Discover and run test files ───────────────────────────────────────────────
PATTERN="${1:-}"
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║          unify-repo test suite                       ║"
echo "╚══════════════════════════════════════════════════════╝"

for test_file in "$TESTS_DIR"/test_*.sh; do
  [[ -f "$test_file" ]] || continue
  if [[ -n "$PATTERN" ]] && ! echo "$test_file" | grep -q "$PATTERN"; then
    continue
  fi
  echo ""
  echo "── $(basename "$test_file") ──────────────────────────"
  # shellcheck disable=SC1090
  source "$test_file"
done

echo ""
echo "══════════════════════════════════════════════════════"
echo "  Results: ${PASS} passed  ·  ${FAIL} failed  ·  ${SKIP} skipped"
echo "══════════════════════════════════════════════════════"

[[ $FAIL -eq 0 ]]
