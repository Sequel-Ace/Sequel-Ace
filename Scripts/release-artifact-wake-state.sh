#!/bin/bash

set -euo pipefail

readonly variable_name="SA_RELEASE_PENDING_ARTIFACT_TAG"
readonly tag_pattern='^(production|beta)/([0-9]+\.[0-9]+\.[0-9]+)-([1-9][0-9]*)$'
generated_token=""
private_key_path=""

usage()
{
	cat >&2 <<'USAGE'
Usage: release-artifact-wake-state.sh arm <release-tag> [expected-predecessor-tag]
       release-artifact-wake-state.sh clear <release-tag>

Requires GITHUB_REPOSITORY and either GH_TOKEN with repository Variables write
access or the following inputs for a short-lived, exact-repository GitHub App
installation token:
  SA_RELEASE_GITHUB_APP_CLIENT_ID
  SA_RELEASE_GITHUB_APP_PRIVATE_KEY
  GITHUB_REPOSITORY_ID
USAGE
	exit 64
}

retry_command()
{
	local attempt=1
	local delay=1
	local status
	while true; do
		if "$@"; then
			return 0
		else
			status="$?"
		fi
		if [[ "${attempt}" -ge 5 ]]; then
			return "${status}"
		fi
		echo "GitHub API attempt ${attempt} failed; retrying in ${delay}s." >&2
		sleep "${delay}"
		attempt="$((attempt + 1))"
		delay="$((delay * 2))"
	done
}

api_as_token()
{
	local token="$1"
	shift
	GH_TOKEN="${token}" gh api "$@"
}

base64url()
{
	openssl base64 -A | tr '+/' '-_' | tr -d '='
}

request_installation_token()
{
	printf '%s' "${installation_token_request}" |
		api_as_token "${app_jwt}" --method POST "app/installations/${installation_id}/access_tokens" --input -
}

cleanup()
{
	local status="$?"
	trap - EXIT
	if [[ -n "${generated_token}" ]]; then
		if ! retry_command api_as_token "${generated_token}" --method DELETE installation/token >/dev/null; then
			echo "Warning: the short-lived GitHub App token could not be revoked and will expire automatically." >&2
		fi
	fi
	if [[ -n "${private_key_path}" ]]; then
		rm -f -- "${private_key_path}"
	fi
	exit "${status}"
}
trap cleanup EXIT

mint_exact_repository_token()
{
	command -v jq >/dev/null || { echo "jq is required to mint a narrow GitHub App token." >&2; exit 69; }
	command -v openssl >/dev/null || { echo "openssl is required to mint a narrow GitHub App token." >&2; exit 69; }
	[[ -n "${SA_RELEASE_GITHUB_APP_CLIENT_ID:-}" ]] || { echo "SA_RELEASE_GITHUB_APP_CLIENT_ID is required." >&2; exit 64; }
	[[ -n "${SA_RELEASE_GITHUB_APP_PRIVATE_KEY:-}" ]] || { echo "SA_RELEASE_GITHUB_APP_PRIVATE_KEY is required." >&2; exit 64; }
	[[ "${GITHUB_REPOSITORY_ID:-}" =~ ^[1-9][0-9]*$ ]] || { echo "GITHUB_REPOSITORY_ID must be numeric." >&2; exit 64; }

	umask 077
	private_key_path="$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/sequel-ace-release-app-key.XXXXXX")"
	printf '%s\n' "${SA_RELEASE_GITHUB_APP_PRIVATE_KEY}" > "${private_key_path}"

	local now issued_at expires_at header payload signature
	now="$(date +%s)"
	issued_at="$((now - 60))"
	expires_at="$((now + 540))"
	header="$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | base64url)"
	payload="$(jq -cn \
		--argjson iat "${issued_at}" \
		--argjson exp "${expires_at}" \
		--arg iss "${SA_RELEASE_GITHUB_APP_CLIENT_ID}" \
		'{iat:$iat,exp:$exp,iss:$iss}' | base64url)"
	readonly app_jwt_unsigned="${header}.${payload}"
	signature="$(printf '%s' "${app_jwt_unsigned}" | openssl dgst -sha256 -sign "${private_key_path}" | base64url)"
	readonly app_jwt="${app_jwt_unsigned}.${signature}"

	local installation_json
	installation_json="$(retry_command api_as_token "${app_jwt}" "repos/${GITHUB_REPOSITORY}/installation")"
	readonly installation_id="$(jq -er '.id | select(type == "number" and . > 0)' <<< "${installation_json}")"
	readonly installation_token_request="$(jq -cn --argjson id "${GITHUB_REPOSITORY_ID}" \
		'{repository_ids:[$id],permissions:{actions_variables:"write"}}')"

	local response
	response="$(retry_command request_installation_token)"
	if ! jq -e --argjson repository_id "${GITHUB_REPOSITORY_ID}" '
		(.token | type == "string" and length > 0) and
		(.permissions.actions_variables == "write") and
		([.permissions | to_entries[] | select(.value == "write" and .key != "actions_variables")] | length == 0) and
		(.repositories | type == "array" and length == 1 and .[0].id == $repository_id)
	' <<< "${response}" >/dev/null; then
		echo "GitHub did not issue the exact-repository Variables-only installation token." >&2
		exit 1
	fi
	generated_token="$(jq -er '.token' <<< "${response}")"
	if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
		printf '::add-mask::%s\n' "${generated_token}"
	fi
	active_token="${generated_token}"
}

[[ "$#" -ge 2 && "$#" -le 3 ]] || usage
readonly operation="$1"
readonly release_tag="$2"
readonly expected_predecessor_tag="${3:-}"
[[ "${operation}" == "arm" || "${operation}" == "clear" ]] || usage
[[ "${release_tag}" =~ ${tag_pattern} ]] || { echo "Malformed release artifact wake tag." >&2; exit 64; }
readonly release_channel="${BASH_REMATCH[1]}"
readonly release_version="${BASH_REMATCH[2]}"
readonly release_build="${BASH_REMATCH[3]}"
if [[ "${operation}" == "clear" && "$#" -ne 2 ]]; then
	usage
fi
if [[ -n "${expected_predecessor_tag}" ]]; then
	[[ "${operation}" == "arm" && "${expected_predecessor_tag}" =~ ${tag_pattern} ]] || { echo "Malformed expected predecessor wake tag." >&2; exit 64; }
	readonly predecessor_channel="${BASH_REMATCH[1]}"
	readonly predecessor_version="${BASH_REMATCH[2]}"
	readonly predecessor_build="${BASH_REMATCH[3]}"
	[[ "${predecessor_channel}" == "${release_channel}" && "${predecessor_version}" == "${release_version}" ]] || {
		echo "Forward wake-state replacement must keep the predecessor channel and version." >&2
		exit 1
	}
	[[ "${release_build}" -gt "${predecessor_build}" ]] || {
		echo "Forward wake-state replacement must strictly increase the Production build." >&2
		exit 1
	}
fi
[[ "${GITHUB_REPOSITORY:-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "GITHUB_REPOSITORY must identify one repository." >&2; exit 64; }
command -v gh >/dev/null || { echo "gh is required." >&2; exit 69; }

active_token="${GH_TOKEN:-}"
if [[ -z "${active_token}" ]]; then
	mint_exact_repository_token
fi

readonly endpoint="repos/${GITHUB_REPOSITORY}/actions/variables/${variable_name}"
current_value="$(retry_command api_as_token "${active_token}" "${endpoint}" --jq .value)"

case "${operation}" in
	arm)
		if [[ "${current_value}" != "none" && "${current_value}" != "${release_tag}" ]]; then
			if [[ -z "${expected_predecessor_tag}" || "${current_value}" != "${expected_predecessor_tag}" ]]; then
				echo "Artifact wake state already belongs to ${current_value}; refusing to replace it with ${release_tag}." >&2
				exit 1
			fi
			echo "Atomically forwarding artifact wake state from ${current_value} to ${release_tag}."
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

retry_command api_as_token "${active_token}" --method PATCH "${endpoint}" --field "value=${new_value}" >/dev/null
verified_value="$(retry_command api_as_token "${active_token}" "${endpoint}" --jq .value)"
[[ "${verified_value}" == "${new_value}" ]] || { echo "Artifact wake-state readback did not persist ${new_value}." >&2; exit 1; }
echo "Artifact wake state is ${verified_value}."
