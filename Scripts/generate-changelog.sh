#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CHANGELOG_FILE="${SCRIPT_DIR}/../CHANGELOG.md"
CHANGELOG_FILE="${CHANGELOG_FILE:-${DEFAULT_CHANGELOG_FILE}}"
CURRENT_VERSION="${1:-}"
DRY_RUN="${DRY_RUN:-0}"
RANGE_START="${RANGE_START:-}"
RANGE_END="${RANGE_END:-HEAD}"
GITHUB_REPO_SLUG="${GITHUB_REPO_SLUG:-Sequel-Ace/Sequel-Ace}"
GITHUB_REPO_URL="https://github.com/${GITHUB_REPO_SLUG}"

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
entries_file="$(mktemp -t sequel-ace-changelog-entries)"
trap 'rm -f "${temp_file}" "${clean_changelog_file}" "${entries_file}"' EXIT

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

ensure_ref_exists() {
  local ref="$1"
  if ! git rev-parse --verify "${ref}^{commit}" >/dev/null 2>&1; then
    echo "Unknown git ref: ${ref}" >&2
    exit 1
  fi
}

release_link() {
  local version="$1"
  printf '%s/releases?q=%%22%s+%%28*%%29%%22&expanded=true' "${GITHUB_REPO_URL}" "${version}"
}

sanitize_message() {
  local message="$1"
  message="$(printf '%s' "${message}" | sed -E 's/^#(added|fixed|changed|removed|infra|unfinished)([[:space:]]+|$)//I')"
  message="$(printf '%s' "${message}" | sed -E 's/[[:space:]]+#(added|fixed|changed|removed|infra|unfinished)([[:space:]]|$)/\2/Ig')"
  message="$(printf '%s' "${message}" | sed -E 's/^([[:space:]]*[-*]+[[:space:]]+)+//')"
  message="$(printf '%s' "${message}" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  printf '%s' "${message}"
}

classify_subject() {
  local subject="$1"
  local lower
  lower="$(printf '%s' "${subject}" | tr '[:upper:]' '[:lower:]')"

  if [[ "${lower}" =~ (^|[[:space:]])#added([[:space:]]|$) || "${lower}" =~ ^(add|added|introduce|support|enable|implement|create)([[:space:]:]|$) ]]; then
    printf 'added'
  elif [[ "${lower}" =~ (^|[[:space:]])#fixed([[:space:]]|$) || "${lower}" =~ ^(fix|fixed|resolve|resolved|recover|correct|prevent|harden)([[:space:]:]|$) ]]; then
    printf 'fixed'
  elif [[ "${lower}" =~ (^|[[:space:]])#removed([[:space:]]|$) || "${lower}" =~ ^(remove|removed|delete|deleted|drop|dropped)([[:space:]:]|$) ]]; then
    printf 'removed'
  elif [[ "${lower}" =~ (^|[[:space:]])#infra([[:space:]]|$) || "${lower}" =~ ^(build|bump|chore|ci|deps|dependency|doc|docs|document|infra|tooling)([[:space:]:]|$) ]]; then
    printf 'infra'
  else
    # Keep uncategorized items visible by defaulting them into "Changed".
    printf 'changed'
  fi
}

build_entries() {
  : > "${entries_file}"

  while IFS= read -r -d '' record; do
    [[ -z "${record}" ]] && continue

    local commit_hash record_rest subject body title pr_number pr_title entry category short_hash commit_link pr_link
    commit_hash="${record%%$'\x1f'*}"
    record_rest="${record#*$'\x1f'}"
    subject="${record_rest%%$'\x1f'*}"
    body="${record_rest#*$'\x1f'}"

    [[ -z "${commit_hash}" || -z "${subject}" ]] && continue

    title="${subject}"
    pr_number=""

    if [[ "${subject}" =~ ^Merge[[:space:]]pull[[:space:]]request[[:space:]]#([0-9]+) ]]; then
      pr_number="${BASH_REMATCH[1]}"
      pr_title="$(printf '%s\n' "${body}" | awk 'NF { print; exit }')"
      [[ -n "${pr_title}" ]] && title="${pr_title}"
    elif [[ "${subject}" =~ ^(.*)[[:space:]]\(#([0-9]+)\)$ ]]; then
      title="${BASH_REMATCH[1]}"
      pr_number="${BASH_REMATCH[2]}"
    fi

    title="$(sanitize_message "${title}")"
    [[ -z "${title}" ]] && continue

    category="$(classify_subject "${title}")"
    short_hash="${commit_hash:0:9}"
    commit_link="${GITHUB_REPO_URL}/commit/${commit_hash}"

    if [[ -n "${pr_number}" ]]; then
      pr_link="${GITHUB_REPO_URL}/pull/${pr_number}"
      entry="- ${title} ([${short_hash}](${commit_link}), [#${pr_number}](${pr_link}))"
    else
      entry="- ${title} ([${short_hash}](${commit_link}))"
    fi

    printf '%s\t%s\n' "${category}" "${entry}" >> "${entries_file}"
  done < <(git log --first-parent -z "${commit_range}" --format='%H%x1f%s%x1f%b')
}

collect_entries() {
  local category="$1"
  awk -F '\t' -v category="${category}" '$1 == category { print $2 }' "${entries_file}"
}

ensure_ref_exists "${RANGE_END}"
if [[ -n "${RANGE_START}" ]]; then
  ensure_ref_exists "${RANGE_START}"
  commit_range="${RANGE_START}..${RANGE_END}"
else
  last_release_ref="$(find_last_release_ref)"
  ensure_ref_exists "${last_release_ref}"
  commit_range="${last_release_ref}..${RANGE_END}"
fi
build_entries

added_entries="$(collect_entries "added")"
fixed_entries="$(collect_entries "fixed")"
changed_entries="$(collect_entries "changed")"
removed_entries="$(collect_entries "removed")"
infra_entries="$(collect_entries "infra")"
current_release_link="$(release_link "${CURRENT_VERSION}")"

{
  printf '## [%s](%s)\n' "${CURRENT_VERSION}" "${current_release_link}"
  printf '\n### Added\n%s\n' "${added_entries}"
  printf '\n### Fixed\n%s\n' "${fixed_entries}"
  printf '\n### Changed\n%s\n' "${changed_entries}"
  printf '\n### Removed\n%s\n' "${removed_entries}"
  printf '\n### Infra\n%s\n' "${infra_entries}"
  printf '\n'
} > "${temp_file}"

# Remove an existing section for the same version to keep generation idempotent.
awk -v version="${CURRENT_VERSION}" '
  BEGIN { skip = 0 }
  $0 ~ "^## \\[" version "\\](\\(|$)" { skip = 1; next }
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
