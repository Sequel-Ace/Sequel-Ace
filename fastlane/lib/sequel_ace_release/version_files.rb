# frozen_string_literal: true

module SequelAceRelease
  class VersionFiles
    VERSION_KEY = "CFBundleShortVersionString"
    BUILD_KEY = "CFBundleVersion"
    RELEASE_TAG_PATTERN = /\A(production|beta)\/(\d+\.\d+\.\d+)-([1-9]\d*)\z/.freeze

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

    def release_identity
      source = current
      tag = release_tag
      match = tag.match(RELEASE_TAG_PATTERN)
      raise ValidationError, "release tag #{tag.inspect} is malformed" unless match

      identity = {
        "channel" => match[1],
        "version" => match[2],
        "build" => Integer(match[3]),
        "tag" => tag
      }
      expected = source.slice("version", "build")
      actual = identity.slice("version", "build")
      unless actual == expected
        raise ValidationError, "release tag #{tag.inspect} does not match source version #{expected}"
      end

      identity
    end

    def self.validate_project_build_settings!(contents_by_path:, expected_build:)
      build = Integer(expected_build)
      raise ValidationError, "expected project build must be positive" unless build.positive?
      raise ValidationError, "project build evidence is malformed" unless contents_by_path.is_a?(Hash)

      Config::PROJECT_FILES.each do |path, expected_counts|
        content = contents_by_path[path]
        raise ValidationError, "#{path} is missing project build evidence" unless content.is_a?(String)

        validate_project_build_setting!(
          content: content,
          path: path,
          key: "CURRENT_PROJECT_VERSION",
          expected_count: expected_counts.fetch(:current),
          expected_build: build
        )
        validate_project_build_setting!(
          content: content,
          path: path,
          key: "DYLIB_CURRENT_VERSION",
          expected_count: expected_counts.fetch(:dylib),
          expected_build: build
        )
      end

      true
    rescue ArgumentError, TypeError
      raise ValidationError, "expected project build must be an integer"
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
      expected_identity = {
        "channel" => channel,
        "version" => version,
        "build" => build_number,
        "tag" => release_tag
      }
      unless release_identity == expected_identity
        raise ValidationError, "release tag preparation did not converge on #{expected_identity}"
      end

      { "before" => before, "after" => after }
    end

    private

    def self.validate_project_build_setting!(content:, path:, key:, expected_count:, expected_build:)
      values = content.scan(/\b#{Regexp.escape(key)} = (\d+);/).flatten
      unless values.length == expected_count && values.all? { |value| Integer(value) == expected_build }
        raise ValidationError, "#{path} has unexpected #{key} release build settings"
      end
    end

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
