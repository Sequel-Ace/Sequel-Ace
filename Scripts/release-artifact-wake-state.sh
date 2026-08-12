#!/bin/bash

set -euo pipefail

readonly variable_name="SA_RELEASE_PENDING_ARTIFACT_TAG"
readonly tag_pattern='^(production|beta)/[0-9]+\.[0-9]+\.[0-9]+-[1-9][0-9]*$'

usage()
{
	cat >&2 <<'USAGE'
Usage: release-artifact-wake-state.sh arm <release-tag>
       release-artifact-wake-state.sh clear <release-tag>

Requires GH_TOKEN with repository Variables write access and GITHUB_REPOSITORY.
USAGE
	exit 64
}

[[ "$#" -eq 2 ]] || usage
readonly operation="$1"
readonly release_tag="$2"
[[ "${operation}" == "arm" || "${operation}" == "clear" ]] || usage
[[ "${release_tag}" =~ ${tag_pattern} ]] || { echo "Malformed release artifact wake tag." >&2; exit 64; }
[[ "${GITHUB_REPOSITORY:-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "GITHUB_REPOSITORY must identify one repository." >&2; exit 64; }
[[ -n "${GH_TOKEN:-}" ]] || { echo "GH_TOKEN is required." >&2; exit 64; }

readonly endpoint="repos/${GITHUB_REPOSITORY}/actions/variables/${variable_name}"
current_value="$(gh api "${endpoint}" --jq .value)"

case "${operation}" in
	arm)
		if [[ "${current_value}" != "none" && "${current_value}" != "${release_tag}" ]]; then
			echo "Artifact wake state already belongs to ${current_value}; refusing to replace it with ${release_tag}." >&2
			exit 1
		fi
		new_value="${release_tag}"
		;;
	clear)
		if [[ "${current_value}" == "none" ]]; then
			echo "Artifact wake state is already clear."
			exit 0
		fi
		if [[ "${current_value}" != "${release_tag}" ]]; then
			echo "Artifact wake state now belongs to ${current_value}; leaving it unchanged."
			exit 0
		fi
		new_value="none"
		;;
esac

gh api --method PATCH "${endpoint}" --field "value=${new_value}"
verified_value="$(gh api "${endpoint}" --jq .value)"
[[ "${verified_value}" == "${new_value}" ]] || { echo "Artifact wake-state readback did not persist ${new_value}." >&2; exit 1; }
echo "Artifact wake state is ${verified_value}."
