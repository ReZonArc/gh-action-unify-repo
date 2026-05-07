#!/usr/bin/env bash
# tests/test_step3.sh — unit/integration tests for step3-integration-plan.sh
# Sourced by run_tests.sh
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$TESTS_DIR/../scripts"

# shellcheck source=../scripts/utils.sh
source "$SCRIPTS_DIR/utils.sh"
# shellcheck source=../scripts/step3-integration-plan.sh
source "$SCRIPTS_DIR/step3-integration-plan.sh"

# ── _discover_components ──────────────────────────────────────────────────────
_suite "step3 · _discover_components"

WS=$(mktemp -d)
mkdir -p "$WS/api" "$WS/web" "$WS/shared"
touch "$WS/api/server.ts" "$WS/web/app.tsx" "$WS/shared/utils.ts"

export WORKSPACE="$WS"
components=$(_discover_components "$WS" "nodejs")

assert_contains "$components" "api"    "components includes api"
assert_contains "$components" "web"    "components includes web"
assert_contains "$components" "shared" "components includes shared"

# Count occurrences — should list each once
count=$(echo "$components" | grep -c "api" || true)
assert_eq "$count" "1" "api listed exactly once"

rm -rf "$WS"

# ── _discover_components — excludes artefact dirs ────────────────────────────
_suite "step3 · _discover_components (excludes artefact dirs)"

WS=$(mktemp -d)
mkdir -p "$WS/src" "$WS/node_modules/express" "$WS/dist" "$WS/build" "$WS/.git"
touch "$WS/src/index.ts"

export WORKSPACE="$WS"
components=$(_discover_components "$WS" "nodejs")

echo "$components" | grep -q "node_modules" && result=0 || result=1
assert_eq "$result" "1" "node_modules excluded from components"

echo "$components" | grep -q "dist" && result=0 || result=1
assert_eq "$result" "1" "dist excluded from components"

echo "$components" | grep -q "build" && result=0 || result=1
assert_eq "$result" "1" "build excluded from components"

assert_contains "$components" "src" "src is included"

rm -rf "$WS"

# ── _discover_components — empty workspace ───────────────────────────────────
_suite "step3 · _discover_components (empty workspace)"

WS=$(mktemp -d)
export WORKSPACE="$WS"
components=$(_discover_components "$WS" "generic")
# Should return empty (no top-level dirs) — no crash
assert_true 0 "empty workspace does not crash _discover_components"

rm -rf "$WS"

# ── _analyze_coupling — nodejs ───────────────────────────────────────────────
_suite "step3 · _analyze_coupling (nodejs)"

WS=$(mktemp -d)
mkdir -p "$WS/src"
cat > "$WS/src/a.ts" <<'TSEOF'
import { x } from './b';
import { y } from './c';
import express from 'express';
TSEOF
cat > "$WS/src/b.ts" <<'TSEOF'
import { z } from './util';
import lodash from 'lodash';
TSEOF

export WORKSPACE="$WS"
coupling=$(_analyze_coupling "$WS" "nodejs")

assert_contains "$coupling" "Internal imports" "coupling reports internal imports"
assert_contains "$coupling" "External"         "coupling reports external imports"

rm -rf "$WS"

# ── _analyze_coupling — python ────────────────────────────────────────────────
_suite "step3 · _analyze_coupling (python)"

WS=$(mktemp -d)
cat > "$WS/service.py" <<'PYEOF'
from .models import User
from .utils import helper
import os
import requests
PYEOF

export WORKSPACE="$WS"
coupling=$(_analyze_coupling "$WS" "python")

assert_contains "$coupling" "Relative imports" "coupling reports relative imports"
assert_contains "$coupling" "Absolute imports" "coupling reports absolute imports"

rm -rf "$WS"

# ── _analyze_coupling — go ────────────────────────────────────────────────────
_suite "step3 · _analyze_coupling (go)"

WS=$(mktemp -d)
cat > "$WS/main.go" << 'GOEOF'
package main
GOEOF
cat > "$WS/handler.go" << 'GOEOF'
package handler
GOEOF

export WORKSPACE="$WS"
coupling=$(_analyze_coupling "$WS" "go")

assert_contains "$coupling" "Go packages" "coupling reports Go packages"

rm -rf "$WS"

# ── _find_entry_points ────────────────────────────────────────────────────────
_suite "step3 · _find_entry_points"

WS=$(mktemp -d)

# No entry points → fallback message
export WORKSPACE="$WS"
eps=$(_find_entry_points "$WS" "generic")
assert_contains "$eps" "No conventional" "no entry points returns fallback message"

# Node.js src/index.js
mkdir -p "$WS/src"
touch "$WS/src/index.js"
eps=$(_find_entry_points "$WS" "nodejs")
assert_contains "$eps" "src/index.js" "src/index.js detected as entry point"

# package.json main field
rm "$WS/src/index.js"
echo '{"main":"dist/server.js"}' > "$WS/package.json"
eps=$(_find_entry_points "$WS" "nodejs")
assert_contains "$eps" "dist/server.js" "package.json main field detected"
rm "$WS/package.json"

# Go main
touch "$WS/main.go"
eps=$(_find_entry_points "$WS" "go")
assert_contains "$eps" "main.go" "main.go detected as Go entry point"
rm "$WS/main.go"

# Python manage.py
touch "$WS/manage.py"
eps=$(_find_entry_points "$WS" "python")
assert_contains "$eps" "manage.py" "manage.py detected as Python entry point"

rm -rf "$WS"

# ── _write_integration_plan ───────────────────────────────────────────────────
_suite "step3 · _write_integration_plan (content)"

WS=$(mktemp -d)
mkdir -p "$WS/api" "$WS/web"
export WORKSPACE="$WS"

components=$(_discover_components "$WS" "nodejs")
coupling=$(_analyze_coupling "$WS" "nodejs")
entry_pts=$(_find_entry_points "$WS" "nodejs")

_write_integration_plan "$WS" "nodejs" "$components" "$coupling" "$entry_pts" "false"

assert_file_exists "$WS/INTEGRATION_PLAN.md" "INTEGRATION_PLAN.md created"
assert_file_contains "$WS/INTEGRATION_PLAN.md" "# Integration Plan"               "title present"
assert_file_contains "$WS/INTEGRATION_PLAN.md" "## 1. Codebase Snapshot"          "section 1 present"
assert_file_contains "$WS/INTEGRATION_PLAN.md" "## 2. Component Inventory"        "section 2 present"
assert_file_contains "$WS/INTEGRATION_PLAN.md" "## 3. Entry Points"               "section 3 present"
assert_file_contains "$WS/INTEGRATION_PLAN.md" "## 4. Coupling Analysis"          "section 4 present"
assert_file_contains "$WS/INTEGRATION_PLAN.md" "## 5. Phased Integration"         "section 5 present"
assert_file_contains "$WS/INTEGRATION_PLAN.md" "## 6. Relational Fluency"         "section 6 present"
assert_file_contains "$WS/INTEGRATION_PLAN.md" "## 7. Recommended Tooling"        "section 7 present"
assert_file_contains "$WS/INTEGRATION_PLAN.md" "Phase 0"                          "Phase 0 present"
assert_file_contains "$WS/INTEGRATION_PLAN.md" "Phase 1"                          "Phase 1 present"
assert_file_contains "$WS/INTEGRATION_PLAN.md" "Phase 2"                          "Phase 2 present"
assert_file_contains "$WS/INTEGRATION_PLAN.md" "Phase 3"                          "Phase 3 present"
assert_file_contains "$WS/INTEGRATION_PLAN.md" "Phase 4"                          "Phase 4 present"
assert_file_contains "$WS/INTEGRATION_PLAN.md" "Phase 5"                          "Phase 5 present"
assert_file_contains "$WS/INTEGRATION_PLAN.md" "nodejs"                           "stack listed in plan"
assert_file_not_empty "$WS/INTEGRATION_PLAN.md" "plan is not empty"

# Verify component formatting is correct (no stray parentheses)
assert_file_contains "$WS/INTEGRATION_PLAN.md" "**api**"  "api component properly formatted"
assert_file_contains "$WS/INTEGRATION_PLAN.md" "**web**"  "web component properly formatted"
# Malformed entry would look like "**api **  —  1 files)  1 files)" — verify it doesn't
plan_content=$(cat "$WS/INTEGRATION_PLAN.md")
echo "$plan_content" | grep -qF "**  —" && result=0 || result=1
assert_eq "$result" "1" "no malformed bold-with-trailing-space pattern"

rm -rf "$WS"

# ── _write_integration_plan — overwrite guard ────────────────────────────────
_suite "step3 · _write_integration_plan (overwrite guard)"

WS=$(mktemp -d)
export WORKSPACE="$WS"
echo "# manual plan" > "$WS/INTEGRATION_PLAN.md"

_write_integration_plan "$WS" "generic" "" "" "" "false"
content=$(cat "$WS/INTEGRATION_PLAN.md")
assert_eq "$content" "# manual plan" "overwrite=false preserves existing plan"

_write_integration_plan "$WS" "generic" "" "" "" "true"
content=$(cat "$WS/INTEGRATION_PLAN.md")
[[ "$content" != "# manual plan" ]] && result=0 || result=1
assert_eq "$result" "0" "overwrite=true regenerates INTEGRATION_PLAN.md"

rm -rf "$WS"

# ── _write_integration_plan — stack-specific content ─────────────────────────
_suite "step3 · _write_integration_plan (stack-specific coupling notes)"

for stack_test in "nodejs" "python" "go"; do
  WS=$(mktemp -d)
  export WORKSPACE="$WS"
  _write_integration_plan "$WS" "$stack_test" "" "" "" "false"

  assert_file_exists "$WS/INTEGRATION_PLAN.md" "plan created for stack: $stack_test"
  rm -rf "$WS"
done

# ── run_step3 end-to-end ──────────────────────────────────────────────────────
_suite "step3 · run_step3 end-to-end (multi-component workspace)"

WS=$(mktemp -d)
mkdir -p "$WS/api/routes" "$WS/web/components" "$WS/shared/utils"
echo '{"name":"monorepo"}' > "$WS/package.json"
touch "$WS/api/routes/users.ts"
touch "$WS/web/components/Button.tsx"
touch "$WS/shared/utils/format.ts"
mkdir -p "$WS/src"
echo "export const x = 1;" > "$WS/src/index.ts"

export WORKSPACE="$WS" OVERWRITE="false"
run_step3

assert_file_exists "$WS/INTEGRATION_PLAN.md"                  "end-to-end: plan created"
assert_file_contains "$WS/INTEGRATION_PLAN.md" "api"          "end-to-end: api component listed"
assert_file_contains "$WS/INTEGRATION_PLAN.md" "web"          "end-to-end: web component listed"
assert_file_contains "$WS/INTEGRATION_PLAN.md" "shared"       "end-to-end: shared component listed"

rm -rf "$WS"
