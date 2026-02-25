#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CHANGELOG_FILE="${SCRIPT_DIR}/../CHANGELOG.md"
CHANGELOG_FILE="${CHANGELOG_FILE:-${DEFAULT_CHANGELOG_FILE}}"
CURRENT_VERSION="${1:-}"
DRY_RUN="${DRY_RUN:-0}"

if [[ -z "${CURRENT_VERSION}" ]]; then
  echo "Usage: $0 <version>" >&2
  exit 1
fi

if [[ ! -f "${CHANGELOG_FILE}" ]]; then
  echo "Missing changelog file: ${CHANGELOG_FILE}" >&2
  exit 1
fi

temp_file="$(mktemp -t sequel-ace-changelog)"
clean_changelog_file="$(mktemp -t sequel-ace-changelog-existing)"
trap 'rm -f "${temp_file}" "${clean_changelog_file}"' EXIT

find_last_release_ref() {
  local release_ref
  release_ref="$(git describe --match "production/*" --tags --abbrev=0 2>/dev/null || true)"

  if [[ -z "${release_ref}" ]] && git remote get-url origin >/dev/null 2>&1; then
    # Release runners can start from clones without tags; fetch tags and retry.
    git fetch --tags --quiet origin >/dev/null 2>&1 || true
    release_ref="$(git describe --match "production/*" --tags --abbrev=0 2>/dev/null || true)"
  fi

  if [[ -n "${release_ref}" ]]; then
    printf '%s' "${release_ref}"
    return
  fi

  # Fallback for clones without tags: use last commit that touched CHANGELOG.md.
  release_ref="$(git log --format=%H -n 1 -- CHANGELOG.md 2>/dev/null || true)"
  if [[ -n "${release_ref}" ]]; then
    printf '%s' "${release_ref}"
    return
  fi

  git rev-list --max-parents=0 HEAD | tail -n 1
}

sanitize_message() {
  local message="$1"
  message="$(printf '%s' "${message}" | sed -E 's/[[:space:]]+#(added|fixed|changed|removed|infra|unfinished)([[:space:]]|$)/\2/Ig')"
  message="$(printf '%s' "${message}" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  printf '%s' "${message}"
}

collect_entries() {
  local category="$1"

  printf '%s\n' "${raw_commits}" | awk -F '\t' -v category="${category}" '
    BEGIN { IGNORECASE = 1 }
    {
      hash = $1
      subject = $2
      if (subject ~ /^Merge /) next

      if (category == "added") {
        if (subject ~ /#added([[:space:]]|$)/ || subject ~ /^(Add|Added|Introduce|Support|Enable|Implement|Create)([[:space:]:]|$)/) print hash "\t" subject
      } else if (category == "fixed") {
        if (subject ~ /#fixed([[:space:]]|$)/ || subject ~ /^(Fix|Fixed|Resolve|Resolved|Recover|Correct|Prevent|Harden)([[:space:]:]|$)/) print hash "\t" subject
      } else if (category == "changed") {
        if (subject ~ /#changed([[:space:]]|$)/ || subject ~ /^(Change|Changed|Update|Updated|Improve|Improved|Refactor|Rewrite|Move|Migrate|Adjust|Simplify|Detect|Respect|Clarify)([[:space:]:]|$)/) print hash "\t" subject
      } else if (category == "removed") {
        if (subject ~ /#removed([[:space:]]|$)/ || subject ~ /^(Remove|Removed|Delete|Deleted|Drop|Dropped)([[:space:]:]|$)/) print hash "\t" subject
      } else if (category == "infra") {
        if (subject ~ /#infra([[:space:]]|$)/ || subject ~ /^(Build|Bump|Chore|CI|Deps|Dependency|Doc|Docs|Document|Infra|Tooling)([[:space:]:]|$)/) print hash "\t" subject
      } else if (category == "unfinished") {
        if (subject ~ /#unfinished([[:space:]]|$)/) print hash "\t" subject
      }
    }
  ' | while IFS=$'\t' read -r hash subject; do
    [[ -z "${hash}" ]] && continue
    printf -- '- %s, %s\n' "${hash}" "$(sanitize_message "${subject}")"
  done
}

last_release_ref="$(find_last_release_ref)"
commit_range="${last_release_ref}..HEAD"
raw_commits="$(git log --first-parent "${commit_range}" --pretty=format:'%h%x09%s')"

added_entries="$(collect_entries "added")"
fixed_entries="$(collect_entries "fixed")"
changed_entries="$(collect_entries "changed")"
removed_entries="$(collect_entries "removed")"
infra_entries="$(collect_entries "infra")"
unfinished_entries="$(collect_entries "unfinished")"

{
  printf '## [%s]\n' "${CURRENT_VERSION}"
  printf '\n### Added\n%s\n' "${added_entries}"
  printf '\n### Fixed\n%s\n' "${fixed_entries}"
  printf '\n### Changed\n%s\n' "${changed_entries}"
  printf '\n### Removed\n%s\n' "${removed_entries}"
  printf '\n### Infra\n%s\n' "${infra_entries}"
  printf '\n### Unfinished\n%s\n' "${unfinished_entries}"
  printf '\n'
} > "${temp_file}"

# Remove an existing section for the same version to keep generation idempotent.
awk -v version="${CURRENT_VERSION}" '
  BEGIN { skip = 0 }
  $0 == "## [" version "]" { skip = 1; next }
  skip && /^## \[/ { skip = 0 }
  !skip { print }
' "${CHANGELOG_FILE}" > "${clean_changelog_file}"

cat "${clean_changelog_file}" >> "${temp_file}"
if [[ "${DRY_RUN}" != "1" ]]; then
  cp "${temp_file}" "${CHANGELOG_FILE}"
fi

printf '\n### Added\n%s\n' "${added_entries}"
printf '\n### Fixed\n%s\n' "${fixed_entries}"
printf '\n### Changed\n%s\n' "${changed_entries}"
printf '\n### Removed\n%s\n' "${removed_entries}"
printf '\n### Infra\n%s\n' "${infra_entries}"
printf '\n### Unfinished\n%s\n' "${unfinished_entries}"
