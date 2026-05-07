#!/usr/bin/env bash
# tests/test_step2.sh — unit/integration tests for step2-analyze-tests.sh
# Sourced by run_tests.sh
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$TESTS_DIR/../scripts"

# shellcheck source=../scripts/utils.sh
source "$SCRIPTS_DIR/utils.sh"
# shellcheck source=../scripts/step2-analyze-tests.sh
source "$SCRIPTS_DIR/step2-analyze-tests.sh"

# ── _add_coverage_config — Node.js ────────────────────────────────────────────
_suite "step2 · _add_coverage_config (nodejs/jest)"

WS=$(mktemp -d)
echo '{"name":"app","scripts":{"test":"jest"}}' > "$WS/package.json"

export WORKSPACE="$WS" OVERWRITE="false"
_add_coverage_config "$WS" "nodejs" "jest"

assert_file_contains "$WS/package.json" '"collectCoverage"' \
  "jest collectCoverage added to package.json"
assert_file_contains "$WS/package.json" '"coverageDirectory"' \
  "jest coverageDirectory added to package.json"
assert_file_contains "$WS/package.json" '"coverageThreshold"' \
  "jest coverageThreshold added to package.json"
assert_file_contains "$WS/package.json" '"lcov"' \
  "jest lcov reporter added to package.json"

rm -rf "$WS"

# ── _add_coverage_config — idempotent ────────────────────────────────────────
_suite "step2 · _add_coverage_config idempotency"

WS=$(mktemp -d)
echo '{"name":"app","jest":{"collectCoverage":true}}' > "$WS/package.json"
before=$(cat "$WS/package.json")

_add_coverage_config "$WS" "nodejs" "jest"
after=$(cat "$WS/package.json")
assert_eq "$before" "$after" "package.json not modified when jest config exists"

rm -rf "$WS"

# ── _add_coverage_config — Python (pyproject.toml) ───────────────────────────
_suite "step2 · _add_coverage_config (python/pyproject.toml)"

WS=$(mktemp -d)
echo '[project]' > "$WS/pyproject.toml"
touch "$WS/requirements.txt"

export WORKSPACE="$WS"
_add_coverage_config "$WS" "python" "pytest"

assert_file_contains "$WS/pyproject.toml" '[tool.pytest.ini_options]' \
  "pytest section added to pyproject.toml"
assert_file_contains "$WS/pyproject.toml" 'fail_under' \
  "coverage fail_under added to pyproject.toml"

rm -rf "$WS"

# ── _add_coverage_config — Python (pytest.ini fallback) ──────────────────────
_suite "step2 · _add_coverage_config (python/pytest.ini fallback)"

WS=$(mktemp -d)
touch "$WS/requirements.txt"

export WORKSPACE="$WS"
_add_coverage_config "$WS" "python" "pytest"

assert_file_exists "$WS/pytest.ini" "pytest.ini created as fallback"
assert_file_contains "$WS/pytest.ini" "[pytest]" "pytest.ini has [pytest] section"

rm -rf "$WS"

# ── _scaffold_js_tests ────────────────────────────────────────────────────────
_suite "step2 · _scaffold_js_tests (TypeScript)"

WS=$(mktemp -d)
mkdir -p "$WS/src"
echo "export function add(a:number, b:number){ return a+b; }" > "$WS/src/math.ts"
echo "{}" > "$WS/tsconfig.json"

export WORKSPACE="$WS"
_scaffold_js_tests "$WS" "jest"

assert_file_exists "$WS/src/math.test.ts" "test file created for math.ts"
assert_file_contains "$WS/src/math.test.ts" "describe('math'" "test file has describe block"
assert_file_contains "$WS/src/math.test.ts" "it('module is importable'" "importable test present"
assert_file_contains "$WS/src/math.test.ts" "beforeEach" "beforeEach hook present"
assert_file_contains "$WS/src/math.test.ts" "afterEach"  "afterEach hook present"

rm -rf "$WS"

# ── _scaffold_js_tests — skips existing test files ───────────────────────────
_suite "step2 · _scaffold_js_tests (skip existing)"

WS=$(mktemp -d)
mkdir -p "$WS/src"
echo "export const x = 1;" > "$WS/src/utils.ts"
echo "it('exists', ()=>{})" > "$WS/src/utils.test.ts"
echo "{}" > "$WS/tsconfig.json"

export WORKSPACE="$WS"
existing=$(cat "$WS/src/utils.test.ts")
_scaffold_js_tests "$WS" "jest"
after=$(cat "$WS/src/utils.test.ts")
assert_eq "$existing" "$after" "_scaffold_js_tests does not overwrite existing test"

rm -rf "$WS"

# ── _scaffold_js_tests — skips test files themselves ─────────────────────────
_suite "step2 · _scaffold_js_tests (skips .test files)"

WS=$(mktemp -d)
mkdir -p "$WS/src"
echo "it('a',()=>{})" > "$WS/src/foo.test.ts"
echo "{}" > "$WS/tsconfig.json"

export WORKSPACE="$WS"
_scaffold_js_tests "$WS" "jest"

# A .test.test.ts should NOT have been created
[[ -f "$WS/src/foo.test.test.ts" ]] && result=0 || result=1
assert_eq "$result" "1" "test file itself not scaffolded again"

rm -rf "$WS"

# ── _scaffold_py_tests ────────────────────────────────────────────────────────
_suite "step2 · _scaffold_py_tests"

WS=$(mktemp -d)
echo "def greet(name): return f'Hello {name}'" > "$WS/greeter.py"

export WORKSPACE="$WS"
_scaffold_py_tests "$WS" "pytest"

assert_file_exists "$WS/tests/test_greeter.py" "test file created for greeter.py"
assert_file_contains "$WS/tests/test_greeter.py" "class TestGreeter" \
  "test class present"
assert_file_contains "$WS/tests/test_greeter.py" "def test_import_succeeds" \
  "import test present"
assert_file_contains "$WS/tests/test_greeter.py" "@pytest.fixture" \
  "pytest fixture present"
assert_file_contains "$WS/tests/test_greeter.py" "@pytest.mark.parametrize" \
  "parametrize decorator present"
assert_file_exists "$WS/tests/__init__.py" "tests/__init__.py created"

rm -rf "$WS"

# ── _scaffold_py_tests — skips existing test files ───────────────────────────
_suite "step2 · _scaffold_py_tests (skip existing)"

WS=$(mktemp -d)
mkdir -p "$WS/tests"
echo "def greeter(): pass" > "$WS/greeter.py"
echo "# existing" > "$WS/tests/test_greeter.py"

export WORKSPACE="$WS"
_scaffold_py_tests "$WS" "pytest"

content=$(cat "$WS/tests/test_greeter.py")
assert_eq "$content" "# existing" "_scaffold_py_tests does not overwrite existing test"

rm -rf "$WS"

# ── _scaffold_py_tests — skips __init__, setup, manage ───────────────────────
_suite "step2 · _scaffold_py_tests (skips special files)"

WS=$(mktemp -d)
touch "$WS/__init__.py" "$WS/setup.py" "$WS/manage.py"

export WORKSPACE="$WS"
_scaffold_py_tests "$WS" "pytest"

[[ -f "$WS/tests/test___init__.py" ]] && result=0 || result=1
assert_eq "$result" "1" "__init__.py not scaffolded"

[[ -f "$WS/tests/test_setup.py" ]] && result=0 || result=1
assert_eq "$result" "1" "setup.py not scaffolded"

[[ -f "$WS/tests/test_manage.py" ]] && result=0 || result=1
assert_eq "$result" "1" "manage.py not scaffolded"

rm -rf "$WS"

# ── _scaffold_go_tests ────────────────────────────────────────────────────────
_suite "step2 · _scaffold_go_tests"

WS=$(mktemp -d)
mkdir -p "$WS"
echo "package main" > "$WS/server.go"
echo "module example.com/m" > "$WS/go.mod"

export WORKSPACE="$WS"
_scaffold_go_tests "$WS" "go-test"

assert_file_exists   "$WS/server_test.go"                    "Go test file created"
assert_file_contains "$WS/server_test.go" "package main"     "correct package in test"
assert_file_contains "$WS/server_test.go" "import"           "import block present"
assert_file_contains "$WS/server_test.go" '"testing"'        "testing package imported"
assert_file_contains "$WS/server_test.go" "func Test"        "Test function present"
assert_file_contains "$WS/server_test.go" "func Benchmark"   "Benchmark function present"
assert_file_contains "$WS/server_test.go" "t.Run"            "sub-tests with t.Run present"

rm -rf "$WS"

# ── _scaffold_go_tests — skips existing _test.go ─────────────────────────────
_suite "step2 · _scaffold_go_tests (skip existing)"

WS=$(mktemp -d)
echo "package main" > "$WS/calc.go"
echo "// existing" > "$WS/calc_test.go"

export WORKSPACE="$WS"
_scaffold_go_tests "$WS" "go-test"

content=$(cat "$WS/calc_test.go")
assert_contains "$content" "existing" "existing Go test not overwritten"

rm -rf "$WS"

# ── _scaffold_shell_tests ─────────────────────────────────────────────────────
_suite "step2 · _scaffold_shell_tests"

WS=$(mktemp -d)

export WORKSPACE="$WS"
_scaffold_shell_tests "$WS"

assert_file_exists "$WS/tests/run_tests.sh" "shell test runner created"
assert_file_contains "$WS/tests/run_tests.sh" "assert_eq"     "assert_eq in runner"
assert_file_contains "$WS/tests/run_tests.sh" "assert_true"   "assert_true in runner"
assert_file_contains "$WS/tests/run_tests.sh" "bash -n"       "syntax-check loop present"

# Test runner must be executable
[[ -x "$WS/tests/run_tests.sh" ]]
assert_true $? "run_tests.sh is executable"

rm -rf "$WS"

# ── _scaffold_shell_tests — idempotent ────────────────────────────────────────
_suite "step2 · _scaffold_shell_tests (idempotent)"

WS=$(mktemp -d)
mkdir -p "$WS/tests"
echo "# manual runner" > "$WS/tests/run_tests.sh"

export WORKSPACE="$WS"
_scaffold_shell_tests "$WS"

content=$(cat "$WS/tests/run_tests.sh")
assert_eq "$content" "# manual runner" "_scaffold_shell_tests does not overwrite existing runner"

rm -rf "$WS"

# ── _write_test_guide ─────────────────────────────────────────────────────────
_suite "step2 · _write_test_guide"

for fw in jest pytest go-test cargo-test junit rspec shell-test; do
  WS=$(mktemp -d)
  export WORKSPACE="$WS"
  _write_test_guide "$WS" "generic" "$fw" "false"

  assert_file_exists  "$WS/TEST_COVERAGE_GUIDE.md" "guide created for framework: $fw"
  assert_file_contains "$WS/TEST_COVERAGE_GUIDE.md" "## Framework detected" "header present ($fw)"
  assert_file_contains "$WS/TEST_COVERAGE_GUIDE.md" "$fw" "framework name in guide ($fw)"
  rm -rf "$WS"
done

# ── run_step2 end-to-end ──────────────────────────────────────────────────────
_suite "step2 · run_step2 end-to-end (Python workspace)"

WS=$(mktemp -d)
touch "$WS/requirements.txt"
echo '[project]' > "$WS/pyproject.toml"
echo "def add(a, b): return a + b" > "$WS/calculator.py"

export WORKSPACE="$WS" OVERWRITE="false"
run_step2

assert_file_exists "$WS/tests/test_calculator.py"   "end-to-end: test file created"
assert_file_exists "$WS/TEST_COVERAGE_GUIDE.md"     "end-to-end: guide created"
assert_file_contains "$WS/pyproject.toml" "[tool.pytest" \
  "end-to-end: pytest config added"

rm -rf "$WS"
