#!/usr/bin/env bash
# step3-integration-plan.sh
# ─────────────────────────────────────────────────────────────────────────────
# Step 3 — Integration Plan
#   • Maps component / package relationships across the codebase
#   • Identifies coupling points, shared utilities, and entry-point wiring
#   • Writes INTEGRATION_PLAN.md with a phased implementation road-map
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "$SCRIPT_DIR/utils.sh"

# ── Entry point ──────────────────────────────────────────────────────────────
run_step3() {
  local ws="${WORKSPACE:?WORKSPACE must be set}"
  local overwrite="${OVERWRITE:-false}"

  log_step "Step 3 · Integration Plan"

  local stack; stack=$(detect_stack "$ws")
  log_info "Detected stack: $stack"

  local components; components=$(_discover_components "$ws" "$stack")
  local coupling;   coupling=$(_analyze_coupling     "$ws" "$stack")
  local entry_pts;  entry_pts=$(_find_entry_points   "$ws" "$stack")

  _write_integration_plan "$ws" "$stack" "$components" "$coupling" "$entry_pts" "$overwrite"
}

# ── Component discovery ──────────────────────────────────────────────────────

# _discover_components <workspace> <stack>
# Returns a multi-line list of component descriptions.
_discover_components() {
  local ws="$1" stack="$2"
  local parts=()

  # Top-level directories (excluding artefacts & tooling) are treated as components
  while IFS= read -r dir; do
    local name; name=$(basename "$dir")
    local file_count; file_count=$(find "$dir" -type f 2>/dev/null | wc -l | tr -d ' ')
    parts+=("$name ($file_count files)")
  done < <(find "$ws" -mindepth 1 -maxdepth 1 -type d \
             ! -name ".git"          ! -name "node_modules" \
             ! -name ".venv"         ! -name "__pycache__"  \
             ! -name "vendor"        ! -name "dist"         \
             ! -name "build"         ! -name "target"       \
             ! -name ".gradle"       ! -name ".idea"        \
             2>/dev/null | sort)

  printf '%s\n' "${parts[@]}"
}

# ── Coupling analysis ────────────────────────────────────────────────────────

# _analyze_coupling <workspace> <stack>
# Returns a short summary of import/dependency relationships.
_analyze_coupling() {
  local ws="$1" stack="$2"
  local summary=()

  case "$stack" in
    *nodejs*|*typescript*)
      # Count internal relative imports ('./') vs external ('package') imports
      local internal=0 external=0
      while IFS= read -r f; do
        local i; i=$(grep -cE "^(import|require).*'\./" "$f" 2>/dev/null || true)
        local e; e=$(grep -cE "^(import|require).*'[a-zA-Z@]" "$f" 2>/dev/null || true)
        internal=$((internal + i))
        external=$((external + e))
      done < <(find "$ws/src" "$ws/lib" "$ws/app" "$ws" -maxdepth 4 \
                 \( -name "*.ts" -o -name "*.js" -o -name "*.tsx" -o -name "*.jsx" \) \
                 ! -path "*/node_modules/*" ! -path "*/dist/*" \
                 -print 2>/dev/null | head -100)
      summary+=("Internal imports: ${internal}")
      summary+=("External (package) imports: ${external}")
      ;;

    *python*)
      local relative_imports=0 absolute_imports=0
      while IFS= read -r f; do
        local r; r=$(grep -cE "^from \." "$f" 2>/dev/null || true)
        local a; a=$(grep -cE "^import |^from [a-zA-Z]" "$f" 2>/dev/null || true)
        relative_imports=$((relative_imports + r))
        absolute_imports=$((absolute_imports + a))
      done < <(find "$ws" -maxdepth 5 -name "*.py" \
                 ! -path "*/.venv/*" ! -path "*/__pycache__/*" \
                 -print 2>/dev/null | head -100)
      summary+=("Relative imports: ${relative_imports}")
      summary+=("Absolute imports: ${absolute_imports}")
      ;;

    *go*)
      local pkg_count; pkg_count=$(find "$ws" -name "*.go" ! -path "*/vendor/*" \
        -exec head -1 {} \; 2>/dev/null | grep "^package" | sort -u | wc -l | tr -d ' ')
      summary+=("Distinct Go packages: ${pkg_count}")
      ;;

    *java*)
      local pkg_count; pkg_count=$(find "$ws/src" -name "*.java" \
        -exec head -5 {} \; 2>/dev/null | grep "^package " | sort -u | wc -l | tr -d ' ')
      summary+=("Distinct Java packages: ${pkg_count}")
      ;;

    *)
      summary+=("Coupling analysis not available for stack: $stack")
      ;;
  esac

  printf '%s\n' "${summary[@]}"
}

# ── Entry-point detection ─────────────────────────────────────────────────────

_find_entry_points() {
  local ws="$1" stack="$2"
  local eps=()

  # Common entry-point file names
  local candidates=(
    "main.go" "cmd/main.go"
    "main.py" "app.py" "manage.py" "wsgi.py" "asgi.py" "run.py"
    "src/index.ts" "src/index.js" "src/main.ts" "src/main.js"
    "index.ts" "index.js" "server.ts" "server.js"
    "src/app.ts" "src/app.js"
    "src/main.rs" "src/lib.rs"
    "Program.cs"
    "Makefile"
    "entrypoint.sh" "start.sh" "run.sh"
  )

  for c in "${candidates[@]}"; do
    [[ -f "$ws/$c" ]] && eps+=("$c")
  done

  # For Node.js, check "main" field in package.json
  if [[ -f "$ws/package.json" ]]; then
    local pkg_main; pkg_main=$(python3 -c \
      "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('main',''))" \
      "$ws/package.json" 2>/dev/null || true)
    if [[ -n "$pkg_main" ]]; then
      local pkg_main_pattern=" ${pkg_main} "
      if [[ ! " ${eps[*]} " =~ $pkg_main_pattern ]]; then
        eps+=("$pkg_main (from package.json#main)")
      fi
    fi
  fi

  [[ ${#eps[@]} -eq 0 ]] && eps+=("_No conventional entry points detected_")
  printf '%s\n' "${eps[@]}"
}

# ── Write INTEGRATION_PLAN.md ─────────────────────────────────────────────────
_write_integration_plan() {
  local ws="$1" stack="$2" components="$3" coupling="$4" entry_pts="$5" overwrite="$6"
  local out="$ws/INTEGRATION_PLAN.md"

  if ! should_write "$out" "$overwrite"; then
    log_skip "INTEGRATION_PLAN.md already exists (set overwrite=true to replace)"
    return
  fi

  log_info "Writing INTEGRATION_PLAN.md …"

  # Count items for summary
  local component_count; component_count=$(echo "$components" | grep -c . || true)
  local entry_count;     entry_count=$(echo "$entry_pts" | grep -c . || true)

  cat > "$out" <<MDEOF
# Integration Plan

> Generated by [unify-repo](https://github.com/ReZonArc/gh-action-unify-repo) on $(timestamp)
>
> This document provides a phased, actionable road-map for integrating the
> components of this codebase into a unified, coherent whole with relational
> fluency throughout.

---

## 1. Codebase Snapshot

| Dimension | Value |
|-----------|-------|
| Detected stack | \`${stack}\` |
| Top-level components | ${component_count} |
| Entry points identified | ${entry_count} |

---

## 2. Component Inventory

The following top-level directories (components) were identified:

$(echo "$components" | while read -r line; do
    [[ -z "$line" ]] && continue
    _name="${line% (*}"
    _count="${line##*(}"
    _count="${_count%)}"
    echo "- **${_name}** — ${_count}"
  done || echo "_No components detected._")

---

## 3. Entry Points

$(echo "$entry_pts" | while read -r ep; do
    [[ -z "$ep" ]] && continue
    echo "- \`$ep\`"
  done)

---

## 4. Coupling Analysis

$(echo "$coupling" | while read -r line; do
    [[ -z "$line" ]] && continue
    echo "- $line"
  done || echo "_No coupling data available._")

### Coupling observations

$(if echo "$stack" | grep -q "nodejs\|typescript"; then cat <<'OBS'
- **High internal coupling** (many relative imports) suggests tight component
  dependencies. Consider introducing an interface or facade layer.
- **High external coupling** (many package imports) may lead to dependency-drift.
  Pin versions and audit regularly.
OBS
fi
if echo "$stack" | grep -q python; then cat <<'OBS'
- **Relative imports** (`from .module import …`) keep packages self-contained —
  prefer these for internal wiring.
- **Absolute imports** from external packages should be declared in
  `pyproject.toml` / `requirements.txt` with pinned versions.
OBS
fi
if echo "$stack" | grep -q go; then cat <<'OBS'
- Follow the standard **`internal/`** convention for code that must not be
  imported by external modules.
- Use **`pkg/`** for intentionally exportable APIs.
OBS
fi
echo "- Review the dependency graph regularly to prevent circular imports.")

---

## 5. Phased Integration Road-map

### Phase 0 — Foundation (do first)

- [ ] Ensure all components build cleanly with zero warnings.
- [ ] Establish and enforce a consistent code-style / lint configuration.
- [ ] Confirm ≥ 70 % test coverage across all components (see \`TEST_COVERAGE_GUIDE.md\`).
- [ ] Centralise logging / error-handling so all components use the same approach.
- [ ] Pin all external dependency versions.

### Phase 1 — Shared Kernel

- [ ] Extract shared types, constants, and utilities into a single
      \`core/\` (or \`shared/\` / \`common/\`) package.
- [ ] Eliminate duplicate code across components by migrating to the shared kernel.
- [ ] Add unit tests for every exported symbol in the shared kernel.

### Phase 2 — Interface Contracts

- [ ] Define clear, typed interfaces / protocols / traits for every public API.
- [ ] Replace direct struct/object usage across component boundaries with the
      interface types defined in Phase 1.
- [ ] Generate or maintain API documentation from code comments (JSDoc, Sphinx,
      godoc, Javadoc, rustdoc, etc.).

### Phase 3 — Dependency Injection & Wiring

- [ ] Introduce a single **composition root** (main entry point) that wires all
      components together using dependency injection (DI).
- [ ] Avoid global state; pass dependencies explicitly.
- [ ] Write integration tests that exercise at least two components together.

### Phase 4 — Observability

- [ ] Add structured logging to every component using a shared logger.
- [ ] Emit metrics / traces at component boundaries.
- [ ] Add health-check endpoints / readiness probes if applicable.

### Phase 5 — CI / CD Hardening

- [ ] Ensure the generated \`.github/workflows/build.yml\` covers all components.
- [ ] Add a **required status check** on the default branch.
- [ ] Configure branch protection rules (require PR review + passing CI).
- [ ] Add a release workflow (semantic versioning + changelog generation).
- [ ] Publish artefacts (Docker image, npm package, PyPI package, etc.) on tag push.

---

## 6. Relational Fluency Checklist

Relational fluency means every component *knows* exactly what it needs from its
neighbours, and nothing more.

| Principle | Action |
|-----------|--------|
| **Single Responsibility** | Each component owns one concern. |
| **Open/Closed** | Extend via interfaces, not modification. |
| **Dependency Inversion** | High-level modules depend on abstractions. |
| **DRY** | One canonical location for every piece of logic. |
| **Explicit over implicit** | Prefer explicit wiring (DI) over globals / service locators. |
| **Fail fast** | Validate inputs at component boundaries; surface errors early. |
| **Backward compatibility** | Version all public APIs; use deprecation notices before removal. |

---

## 7. Recommended Tooling

| Concern | Tool(s) |
|---------|---------|
| Dependency graph | \`madge\` (JS), \`pydeps\` (Python), \`go mod graph\` (Go) |
| Dead-code detection | \`ts-prune\` (TS), \`vulture\` (Python), \`deadcode\` (Go) |
| Circular-import detection | \`madge --circular\`, \`isort --check\`, \`go vet\` |
| API docs | TypeDoc, Sphinx, godoc, Javadoc, rustdoc |
| Code-coverage gating | Jest threshold, pytest-cov fail_under, tarpaulin |

---

_This file is auto-generated. Re-run the [unify-repo](https://github.com/ReZonArc/gh-action-unify-repo)
action to refresh it (set \`overwrite: true\` to replace an existing file)._
MDEOF

  log_ok "Created INTEGRATION_PLAN.md"
}

# Run when executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_step3
fi
