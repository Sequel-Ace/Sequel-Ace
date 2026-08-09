#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: $0 push <ghcr-reference> <archive-directory> | pull <ghcr-reference> <destination-directory>" >&2
  exit 64
}

mode="${1:-}"
reference="${2:-}"
directory="${3:-}"

[[ -n "${mode}" && -n "${reference}" && -n "${directory}" ]] || usage
[[ "${reference}" =~ ^ghcr\.io/sequel-ace/[a-z0-9._/-]+:[a-zA-Z0-9._-]+$ ]] || {
  echo "Refusing unexpected GHCR reference: ${reference}" >&2
  exit 65
}
command -v oras >/dev/null 2>&1 || {
  echo "oras is required" >&2
  exit 69
}

login() {
  [[ -n "${GHCR_TOKEN:-}" && -n "${GHCR_USERNAME:-}" ]] || {
    echo "GHCR_TOKEN and GHCR_USERNAME are required" >&2
    exit 78
  }
  printf '%s' "${GHCR_TOKEN}" | oras login ghcr.io --username "${GHCR_USERNAME}" --password-stdin >/dev/null
}

case "${mode}" in
  push)
    [[ -d "${directory}" ]] || {
      echo "Archive directory does not exist: ${directory}" >&2
      exit 66
    }
    [[ -f "${directory}/manifest.json" ]] || {
      echo "Archive directory must contain manifest.json" >&2
      exit 66
    }
    login
    temporary_directory="$(mktemp -d -t sequel-ace-ghcr-push)"
    trap 'rm -rf "${temporary_directory}"' EXIT
    archive_file="${temporary_directory}/sequel-ace-release-archive.tar.gz"
    /usr/bin/tar -czf "${archive_file}" -C "${directory}" .
    archive_sha="$(/usr/bin/shasum -a 256 "${archive_file}" | /usr/bin/awk '{print $1}')"
    manifest_sha="$(/usr/bin/shasum -a 256 "${directory}/manifest.json" | /usr/bin/awk '{print $1}')"
    oras push "${reference}" \
      "${archive_file}:application/vnd.sequel-ace.release.archive.v1+tar+gzip" \
      "${directory}/manifest.json:application/vnd.sequel-ace.release.manifest.v1+json" >/dev/null
    verification_directory="${temporary_directory}/verification"
    mkdir -p "${verification_directory}"
    oras pull "${reference}" --output "${verification_directory}" >/dev/null
    pulled_archive="${verification_directory}/$(basename "${archive_file}")"
    pulled_manifest="${verification_directory}/manifest.json"
    [[ -f "${pulled_archive}" && -f "${pulled_manifest}" ]] || {
      echo "GHCR verification pull is incomplete" >&2
      exit 74
    }
    [[ "$(/usr/bin/shasum -a 256 "${pulled_archive}" | /usr/bin/awk '{print $1}')" == "${archive_sha}" ]] || {
      echo "GHCR archive checksum mismatch" >&2
      exit 74
    }
    [[ "$(/usr/bin/shasum -a 256 "${pulled_manifest}" | /usr/bin/awk '{print $1}')" == "${manifest_sha}" ]] || {
      echo "GHCR manifest checksum mismatch" >&2
      exit 74
    }
    printf '{"reference":"%s","archive_sha256":"%s","manifest_sha256":"%s"}\n' "${reference}" "${archive_sha}" "${manifest_sha}"
    ;;
  pull)
    login
    mkdir -p "${directory}"
    oras pull "${reference}" --output "${directory}" >/dev/null
    [[ -f "${directory}/manifest.json" ]] || {
      echo "Pulled GHCR artifact is missing manifest.json" >&2
      exit 74
    }
    pulled_archive="${directory}/sequel-ace-release-archive.tar.gz"
    if [[ -f "${pulled_archive}" ]]; then
      /usr/bin/tar -xzf "${pulled_archive}" -C "${directory}"
      /bin/rm -f "${pulled_archive}"
    fi
    ;;
  *)
    usage
    ;;
esac
