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

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

login() {
  [[ -n "${GHCR_TOKEN:-}" && -n "${GHCR_USERNAME:-}" ]] || {
    echo "GHCR_TOKEN and GHCR_USERNAME are required" >&2
    exit 78
  }
  printf '%s' "${GHCR_TOKEN}" | oras login ghcr.io --username "${GHCR_USERNAME}" --password-stdin >/dev/null
}

validate_archive_tree() {
  local archive_root="$1"
  local ruby_path
  ruby_path="$(command -v ruby || true)"
  [[ -n "${ruby_path}" && -x "${ruby_path}" ]] || {
    echo "ruby is required to validate the release archive" >&2
    exit 69
  }

  /usr/bin/env -i PATH=/usr/bin:/bin "${ruby_path}" - "${archive_root}" <<'RUBY'
require "find"

root = File.realpath(ARGV.fetch(0))
manifest = File.join(root, "manifest.json")
unless File.file?(manifest) && !File.symlink?(manifest)
  warn "Release archive must contain a regular manifest.json"
  exit 74
end

regular_files = Hash.new { |hash, key| hash[key] = [] }
Find.find(root) do |path|
  next if path == root

  relative = path.delete_prefix("#{root}/")
  if relative.match?(/[[:cntrl:]]/)
    warn "Release archive contains a control character in a path"
    exit 74
  end

  stat = File.lstat(path)
  unless stat.file? || stat.directory? || stat.symlink?
    warn "Release archive contains an unsupported filesystem object: #{relative}"
    exit 74
  end
  regular_files[[stat.dev, stat.ino]] << [relative, stat.nlink] if stat.file?
  next unless stat.symlink?

  unless relative.start_with?("artifacts/")
    warn "Release archive contains a symlink outside artifacts/: #{relative}"
    exit 74
  end

  link_target = File.readlink(path)
  if link_target.start_with?("/") || link_target.match?(/[[:cntrl:]]/)
    warn "Release archive contains an unsafe artifact symlink target: #{relative}"
    exit 74
  end

  begin
    target = File.realpath(path)
  rescue SystemCallError
    warn "Release archive contains a broken artifact symlink: #{relative}"
    exit 74
  end
  unless target == root || target.start_with?("#{root}/")
    warn "Release archive contains an escaping artifact symlink: #{relative}"
    exit 74
  end
end

regular_files.each_value do |entries|
  link_counts = entries.map(&:last).uniq
  unless link_counts.length == 1 && link_counts.first == entries.length
    warn "Release archive contains an incompletely contained hard link: #{entries.map(&:first).join(', ')}"
    exit 74
  end
  next if entries.length == 1

  paths = entries.map(&:first)
  unless paths.all? { |relative| relative.start_with?("artifacts/") }
    warn "Release archive contains a hard link outside artifacts/: #{paths.join(', ')}"
    exit 74
  end
end
RUBY
}

validate_archive_members() {
  local archive_path="$1"
  local ruby_path
  ruby_path="$(command -v ruby || true)"
  [[ -n "${ruby_path}" && -x "${ruby_path}" ]] || {
    echo "ruby is required to validate the release archive" >&2
    exit 69
  }

  /usr/bin/env -i PATH=/usr/bin:/bin "${ruby_path}" \
    -I "${script_directory}/../fastlane/lib" \
    -r sequel_ace_release/tar_archive_validator \
    - "${archive_path}" <<'RUBY'
begin
  SequelAceRelease::TarArchiveValidator.new.validate!(ARGV.fetch(0))
rescue SequelAceRelease::IntegrityError => e
  warn e.message
  exit 74
end
RUBY
}

case "${mode}" in
  push)
    [[ -d "${directory}" && ! -L "${directory}" ]] || {
      echo "Archive directory does not exist: ${directory}" >&2
      exit 66
    }
    [[ -f "${directory}/manifest.json" && ! -L "${directory}/manifest.json" ]] || {
      echo "Archive directory must contain manifest.json" >&2
      exit 66
    }
    validate_archive_tree "${directory}"
    login
    temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/sequel-ace-ghcr-push.XXXXXX")"
    trap 'rm -rf "${temporary_directory}"' EXIT
    archive_file="${temporary_directory}/sequel-ace-release-archive.tar.gz"
    manifest_file="${temporary_directory}/manifest.json"
    /usr/bin/tar -czf "${archive_file}" -C "${directory}" .
    /bin/cp "${directory}/manifest.json" "${manifest_file}"
    archive_sha="$(/usr/bin/shasum -a 256 "${archive_file}" | /usr/bin/awk '{print $1}')"
    manifest_sha="$(/usr/bin/shasum -a 256 "${manifest_file}" | /usr/bin/awk '{print $1}')"
    (
      cd "${temporary_directory}"
      oras push "${reference}" \
        "sequel-ace-release-archive.tar.gz:application/vnd.sequel-ace.release.archive.v1+tar+gzip" \
        "manifest.json:application/vnd.sequel-ace.release.manifest.v1+json" >/dev/null
    )
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
    [[ ! -L "${directory}" ]] || {
      echo "Refusing symlink GHCR destination: ${directory}" >&2
      exit 65
    }
    if [[ -e "${directory}" && ! -d "${directory}" ]]; then
      echo "GHCR destination is not a directory: ${directory}" >&2
      exit 65
    fi
    mkdir -p "${directory}"
    [[ -z "$(/usr/bin/find "${directory}" -mindepth 1 -maxdepth 1 -print -quit)" ]] || {
      echo "GHCR destination must be empty: ${directory}" >&2
      exit 65
    }
    resolved_directory="$(cd "${directory}" && pwd -P)"
    [[ "${resolved_directory}" != "/" ]] || {
      echo "Refusing unsafe GHCR destination" >&2
      exit 65
    }
    login
    oras pull "${reference}" --output "${directory}" >/dev/null
    pulled_manifest="${directory}/manifest.json"
    pulled_archive="${directory}/sequel-ace-release-archive.tar.gz"
    pulled_layers=0
    while IFS= read -r -d '' pulled_entry; do
      case "${pulled_entry}" in
        "${resolved_directory}/manifest.json"|"${resolved_directory}/sequel-ace-release-archive.tar.gz")
          pulled_layers=$((pulled_layers + 1))
          ;;
        *)
          echo "Pulled GHCR artifact contains an unexpected top-level layer" >&2
          exit 74
          ;;
      esac
    done < <(/usr/bin/find "${resolved_directory}" -mindepth 1 -maxdepth 1 -print0)
    [[ "${pulled_layers}" == "2" ]] || {
      echo "Pulled GHCR artifact must contain exactly two layers" >&2
      exit 74
    }
    [[ -f "${pulled_manifest}" && ! -L "${pulled_manifest}" ]] || {
      echo "Pulled GHCR artifact is missing manifest.json" >&2
      exit 74
    }
    [[ -f "${pulled_archive}" && ! -L "${pulled_archive}" ]] || {
      echo "Pulled GHCR artifact is missing its archive layer" >&2
      exit 74
    }
    pulled_manifest_sha="$(/usr/bin/shasum -a 256 "${pulled_manifest}" | /usr/bin/awk '{print $1}')"
    destination_parent="$(cd "${resolved_directory}/.." && pwd -P)"
    destination_name="$(/usr/bin/basename "${resolved_directory}")"
    extraction_directory="$(mktemp -d "${destination_parent}/.${destination_name}.extract.XXXXXX")"
    trap '/bin/rm -rf "${extraction_directory}"' EXIT
    validate_archive_members "${pulled_archive}"
    /usr/bin/tar --no-same-owner --no-same-permissions -xzf "${pulled_archive}" -C "${extraction_directory}"
    validate_archive_tree "${extraction_directory}"
    extracted_manifest="${extraction_directory}/manifest.json"
    extracted_manifest_sha="$(/usr/bin/shasum -a 256 "${extracted_manifest}" | /usr/bin/awk '{print $1}')"
    [[ "${extracted_manifest_sha}" == "${pulled_manifest_sha}" ]] || {
      echo "Pulled GHCR archive manifest does not match its manifest layer" >&2
      exit 74
    }
    /bin/rm -f "${pulled_manifest}" "${pulled_archive}"
    while IFS= read -r -d '' entry; do
      /bin/mv -- "${entry}" "${resolved_directory}/"
    done < <(/usr/bin/find "${extraction_directory}" -mindepth 1 -maxdepth 1 -print0)
    [[ -f "${resolved_directory}/manifest.json" && ! -L "${resolved_directory}/manifest.json" ]] || {
      echo "Validated GHCR archive lost its regular manifest.json" >&2
      exit 74
    }
    ;;
  *)
    usage
    ;;
esac
