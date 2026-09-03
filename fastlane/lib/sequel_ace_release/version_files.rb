# frozen_string_literal: true

module SequelAceRelease
  class VersionFiles
    VERSION_KEY = "CFBundleShortVersionString"
    BUILD_KEY = "CFBundleVersion"

    attr_reader :root

    def initialize(root: Config.repo_root)
      @root = Pathname.new(root)
    end

    def current
      versions = Config::PLIST_FILES.map { |path| read_plist_value(path, VERSION_KEY) }.uniq
      builds = Config::PLIST_FILES.map { |path| read_plist_value(path, BUILD_KEY) }.uniq
      project_builds = project_values("CURRENT_PROJECT_VERSION").uniq
      dylib_builds = project_values("DYLIB_CURRENT_VERSION").uniq

      raise ValidationError, "version plist values disagree: #{versions.join(', ')}" unless versions.length == 1
      raise ValidationError, "build plist values disagree: #{builds.join(', ')}" unless builds.length == 1
      raise ValidationError, "CURRENT_PROJECT_VERSION values disagree: #{project_builds.join(', ')}" unless project_builds == builds
      unless dylib_builds.empty? || dylib_builds == builds
        raise ValidationError, "DYLIB_CURRENT_VERSION values disagree: #{dylib_builds.join(', ')}"
      end

      { "version" => versions.first, "build" => Integer(builds.first) }
    end

    def release_tag
      read_plist_value(Config::APP_INFO_PLIST, Config::RELEASE_TAG_PLIST_KEY)
    end

    def update!(version:, build:, channel:)
      Version.validate!(version)
      Config.validate_channel!(channel)
      build_number = begin
        Integer(build)
      rescue ArgumentError, TypeError
        raise ValidationError, "build must be an integer"
      end
      raise ValidationError, "build must be positive" unless build_number.positive?

      before = current
      Config::PLIST_FILES.each do |path|
        replace_plist_value!(path, VERSION_KEY, version)
        replace_plist_value!(path, BUILD_KEY, build_number.to_s)
      end
      release_tag = "#{channel}/#{version}-#{build_number}"
      replace_plist_value!(Config::APP_INFO_PLIST, Config::RELEASE_TAG_PLIST_KEY, release_tag)
      Config::PROJECT_FILES.each do |path, expected|
        replace_project_value!(path, "CURRENT_PROJECT_VERSION", build_number, expected.fetch(:current))
        replace_project_value!(path, "DYLIB_CURRENT_VERSION", build_number, expected.fetch(:dylib))
      end
      after = current
      expected_after = { "version" => version, "build" => build_number }
      raise ValidationError, "version preparation did not converge on #{expected_after}" unless after == expected_after
      unless self.release_tag == release_tag
        raise ValidationError, "release tag preparation did not converge on #{release_tag}"
      end

      { "before" => before, "after" => after }
    end

    private

    def read_plist_value(relative_path, key)
      content = read(relative_path)
      match = content.match(%r{<key>#{Regexp.escape(key)}</key>\s*<string>([^<]+)</string>})
      raise ValidationError, "#{relative_path} is missing #{key}" unless match

      match[1]
    end

    def replace_plist_value!(relative_path, key, value)
      file = root.join(relative_path)
      content = file.read
      pattern = %r{(<key>#{Regexp.escape(key)}</key>\s*<string>)([^<]+)(</string>)}
      count = content.scan(pattern).length
      raise ValidationError, "expected one #{key} in #{relative_path}, found #{count}" unless count == 1

      file.write(content.sub(pattern, "\\1#{value}\\3"))
    end

    def replace_project_value!(relative_path, key, value, expected_count)
      file = root.join(relative_path)
      content = file.read
      pattern = /(\b#{Regexp.escape(key)} = )\d+(;)/
      count = content.scan(pattern).length
      unless count == expected_count
        raise ValidationError, "expected #{expected_count} #{key} values in #{relative_path}, found #{count}"
      end
      return if count.zero?

      file.write(content.gsub(pattern, "\\1#{value}\\2"))
    end

    def project_values(key)
      Config::PROJECT_FILES.keys.flat_map do |path|
        read(path).scan(/\b#{Regexp.escape(key)} = (\d+);/).flatten
      end
    end

    def read(relative_path)
      file = root.join(relative_path)
      raise ValidationError, "missing release version file: #{relative_path}" unless file.file?

      file.read
    end
  end
end
