#!/usr/bin/env bash
# utils.sh — shared helper functions for unify-repo scripts.
# Sourced by every other script; must not produce side-effects on its own.
set -euo pipefail

# ─────────────────────────── Logging ────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()    { echo -e "\n${CYAN}${BOLD}━━━ $* ━━━${NC}"; }
log_skip()    { echo -e "${YELLOW}[SKIP]${NC}  $*"; }

# ─────────────────────────── Stack / technology detection ───────────────────

# detect_stack <workspace>
# Prints a space-separated list of detected technology identifiers.
detect_stack() {
  local ws="$1"
  local stack=()

  # JavaScript / TypeScript / Node
  [[ -f "$ws/package.json" ]]                        && stack+=("nodejs")
  [[ -f "$ws/tsconfig.json" ]]                       && stack+=("typescript")
  [[ -f "$ws/next.config.js" || -f "$ws/next.config.ts" ]] && stack+=("nextjs")
  [[ -f "$ws/vite.config.js" || -f "$ws/vite.config.ts" ]] && stack+=("vite")

  # Python
  if [[ -f "$ws/requirements.txt" || -f "$ws/setup.py" || \
        -f "$ws/pyproject.toml"    || -f "$ws/Pipfile"      ]]; then
    stack+=("python")
  fi
  [[ -f "$ws/manage.py" ]]                           && stack+=("django")
  [[ -f "$ws/app.py" || -f "$ws/wsgi.py" ]]          && stack+=("flask")

  # JVM
  [[ -f "$ws/pom.xml" ]]                             && stack+=("java-maven")
  if [[ -f "$ws/build.gradle" || -f "$ws/build.gradle.kts" ]]; then
    stack+=("java-gradle")
  fi
  [[ -f "$ws/build.sbt" ]]                           && stack+=("scala")
  [[ -f "$ws/build.gradle" ]] && grep -q "kotlin"    "$ws/build.gradle" 2>/dev/null && stack+=("kotlin")

  # Go
  [[ -f "$ws/go.mod" ]]                              && stack+=("go")

  # Ruby
  [[ -f "$ws/Gemfile" ]]                             && stack+=("ruby")
  [[ -f "$ws/config/application.rb" ]]               && stack+=("rails")

  # Rust
  [[ -f "$ws/Cargo.toml" ]]                          && stack+=("rust")

  # PHP
  [[ -f "$ws/composer.json" ]]                       && stack+=("php")
  [[ -f "$ws/artisan" ]]                             && stack+=("laravel")

  # .NET
  if find "$ws" -maxdepth 3 \( -name "*.csproj" -o -name "*.fsproj" -o -name "*.sln" \) \
       -print -quit 2>/dev/null | grep -q .; then
    stack+=("dotnet")
  fi

  # Containers / infra
  [[ -f "$ws/Dockerfile" ]]                          && stack+=("docker")
  [[ -f "$ws/docker-compose.yml" || -f "$ws/docker-compose.yaml" ]] && stack+=("docker-compose")
  [[ -f "$ws/terraform.tf" ]] || find "$ws" -maxdepth 2 -name "*.tf" -print -quit 2>/dev/null | \
    grep -q . && stack+=("terraform") || true
  [[ -f "$ws/Chart.yaml" ]]                          && stack+=("helm")

  # Shell / scripts only
  if [[ ${#stack[@]} -eq 0 ]]; then
    if find "$ws" -maxdepth 3 -name "*.sh" -print -quit 2>/dev/null | grep -q .; then
      stack+=("shell")
    else
      stack+=("generic")
    fi
  fi

  echo "${stack[*]}"
}

# detect_test_framework <workspace> <stack>
# Prints the primary test framework identifier.
detect_test_framework() {
  local ws="$1"
  local stack_str="$2"

  case "$stack_str" in
    *nodejs*)
      if [[ -f "$ws/package.json" ]]; then
        local pkg; pkg=$(cat "$ws/package.json")
        echo "$pkg" | grep -q '"jest"'    && { echo "jest";    return; }
        echo "$pkg" | grep -q '"vitest"'  && { echo "vitest";  return; }
        echo "$pkg" | grep -q '"mocha"'   && { echo "mocha";   return; }
        echo "$pkg" | grep -q '"jasmine"' && { echo "jasmine"; return; }
        echo "$pkg" | grep -q '"ava"'     && { echo "ava";     return; }
      fi
      echo "jest"
      ;;
    *python*)
      [[ -f "$ws/pytest.ini" || -f "$ws/setup.cfg" ]] && \
        grep -q "pytest" "$ws/setup.cfg" 2>/dev/null && { echo "pytest"; return; }
      [[ -f "$ws/pyproject.toml" ]] && \
        grep -q "pytest" "$ws/pyproject.toml" 2>/dev/null && { echo "pytest"; return; }
      echo "pytest"
      ;;
    *java*)   echo "junit"   ;;
    *go*)     echo "go-test" ;;
    *ruby*)   echo "rspec"   ;;
    *rust*)   echo "cargo-test" ;;
    *dotnet*) echo "xunit"   ;;
    *)        echo "shell-test" ;;
  esac
}

# ─────────────────────────── File-tree helpers ──────────────────────────────

# generate_tree <dir> [prefix] [max_depth] [current_depth]
# Prints a Unicode tree without needing the `tree` command.
generate_tree() {
  local dir="$1"
  local prefix="${2:-}"
  local max_depth="${3:-4}"
  local current_depth="${4:-0}"

  [[ $current_depth -ge $max_depth ]] && return

  local -a entries=()
  while IFS= read -r -d '' entry; do
    entries+=("$entry")
  done < <(find "$dir" -maxdepth 1 -mindepth 1 \
    ! -name ".git"          ! -name "node_modules" \
    ! -name ".venv"         ! -name "__pycache__"  \
    ! -name "vendor"        ! -name "dist"         \
    ! -name "build"         ! -name "target"       \
    ! -name ".gradle"       ! -name ".idea"        \
    ! -name "*.egg-info"    ! -name ".DS_Store"    \
    -print0 2>/dev/null | sort -z)

  local total=${#entries[@]}
  local idx=0
  for entry in "${entries[@]}"; do
    idx=$((idx + 1))
    local name; name=$(basename "$entry")
    local connector="├── "
    local new_prefix="${prefix}│   "
    if [[ $idx -eq $total ]]; then
      connector="└── "
      new_prefix="${prefix}    "
    fi
    echo "${prefix}${connector}${name}"
    if [[ -d "$entry" ]]; then
      generate_tree "$entry" "$new_prefix" "$max_depth" $((current_depth + 1))
    fi
  done
}

# count_files_by_extension <workspace>
# Prints "count ext" pairs, sorted descending.
count_files_by_extension() {
  local ws="$1"
  find "$ws" -type f \
    ! -path "*/.git/*"          ! -path "*/node_modules/*" \
    ! -path "*/.venv/*"         ! -path "*/__pycache__/*"  \
    ! -path "*/vendor/*"        ! -path "*/dist/*"         \
    ! -path "*/build/*"         ! -path "*/target/*"       \
    2>/dev/null \
    | sed -n 's/.*\.\([^./][^./]*\)$/\1/p' \
    | sort | uniq -c | sort -rn | head -20
}

# relative_path <base> <full_path>
# Prints the path of full_path relative to base.
relative_path() {
  local base="${1%/}"
  local full="${2}"
  echo "${full#"${base}/"}"
}

# ─────────────────────────── .github aggregation helpers ────────────────────

# find_nested_github_dirs <workspace>
# Prints paths of .github directories that are NOT at the workspace root.
find_nested_github_dirs() {
  local ws="$1"
  find "$ws" -mindepth 2 -maxdepth 6 -type d -name ".github" \
    ! -path "$ws/.github" \
    ! -path "*/.git/*"          ! -path "*/node_modules/*" \
    ! -path "*/.venv/*"         ! -path "*/vendor/*"       \
    2>/dev/null
}

# merge_github_dir <src_github_dir> <dest_github_dir>
# Copies all contents from src into dest without overwriting existing files.
merge_github_dir() {
  local src="$1"
  local dest="$2"
  mkdir -p "$dest"
  find "$src" -mindepth 1 -type f | while read -r src_file; do
    local rel; rel="${src_file#"${src}/"}"
    local dest_file="$dest/$rel"
    if [[ ! -f "$dest_file" ]]; then
      mkdir -p "$(dirname "$dest_file")"
      cp "$src_file" "$dest_file"
      log_ok "Copied: $rel  →  ${dest_file#"$(dirname "$dest")/"}"
    else
      log_skip "Already exists, skipping: ${dest_file}"
    fi
  done
}

# ─────────────────────────── GitHub API helpers ─────────────────────────────

# gh_api <method> <endpoint> [body]
# Minimal wrapper around the GitHub REST API using curl only.
gh_api() {
  local method="$1"
  local endpoint="$2"
  local body="${3:-}"
  local api_base="https://api.github.com"

  local curl_args=(
    -sSL -X "$method"
    -H "Accept: application/vnd.github+json"
    -H "Authorization: Bearer ${GITHUB_TOKEN:-}"
    -H "X-GitHub-Api-Version: 2022-11-28"
  )
  [[ -n "$body" ]] && curl_args+=(-H "Content-Type: application/json" -d "$body")
  curl "${curl_args[@]}" "${api_base}${endpoint}"
}

# ─────────────────────────── Misc helpers ───────────────────────────────────

# timestamp — ISO-8601 UTC timestamp
timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# file_exists_nonempty <path>
file_exists_nonempty() { [[ -s "$1" ]]; }

# should_write <path> <overwrite_flag>
# Returns 0 (true) if the file should be (over)written.
should_write() {
  local path="$1"
  local overwrite="${2:-false}"
  if [[ ! -f "$path" ]]; then
    return 0  # file doesn't exist → always write
  fi
  [[ "$overwrite" == "true" ]]
}

# append_section <file> <heading> <content>
append_section() {
  local file="$1"
  local heading="$2"
  local content="$3"
  printf '\n## %s\n\n%s\n' "$heading" "$content" >> "$file"
}
