# frozen_string_literal: true

require "digest"
require "fileutils"
require "tmpdir"

module SequelAceRelease
  class ArtifactVerifier
    def initialize(runner: CommandRunner.new)
      @runner = runner
    end

    def verify(path:, version:, build: nil, channel:, launch: false, output_zip: nil, any_build: false, expected_sha256: nil)
      Config.validate_channel!(channel)
      Version.validate!(version)
      raise ValidationError, "build is required unless --any-build is used" if build.nil? && !any_build
      expected_build = build && Integer(build).to_s
      source = Pathname.new(path).expand_path
      raise ValidationError, "artifact does not exist: #{source}" unless source.exist?
      artifact_digest = sha256(source)
      if expected_sha256
        unless expected_sha256.to_s.match?(/\A[0-9a-f]{64}\z/i) && artifact_digest.casecmp?(expected_sha256.to_s)
          raise ValidationError, "artifact checksum does not match the recorded download"
        end
      end

      Dir.mktmpdir("sequel-ace-release-artifact") do |temporary_directory|
        app = locate_app(source, Pathname.new(temporary_directory))
        info = app.join("Contents/Info.plist")
        raise ValidationError, "artifact is missing Contents/Info.plist" unless info.file?

        bundle_id = plist(info, "CFBundleIdentifier")
        actual_version = plist(info, "CFBundleShortVersionString")
        actual_build = plist(info, "CFBundleVersion")
        executable_name = plist(info, "CFBundleExecutable")
        executable = app.join("Contents/MacOS", executable_name)

        expected_bundle_id = Config.bundle_id(channel)
        raise ValidationError, "bundle identifier #{bundle_id} does not match #{expected_bundle_id}" unless bundle_id == expected_bundle_id
        raise ValidationError, "artifact version #{actual_version} does not match #{version}" unless actual_version == version
        if !any_build && actual_build != expected_build
          raise ValidationError, "artifact build #{actual_build} does not match #{expected_build}"
        end
        raise ValidationError, "artifact executable is missing" unless executable.file?

        architectures = @runner.run("/usr/bin/lipo", "-archs", executable).stdout.split.sort
        missing_architectures = %w[arm64 x86_64] - architectures
        raise ValidationError, "artifact is missing architectures: #{missing_architectures.join(', ')}" unless missing_architectures.empty?

        @runner.run("/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", app)
        signature = @runner.run("/usr/bin/codesign", "-d", "--verbose=4", app, allow_failure: true)
        signature_text = [signature.stdout, signature.stderr].join("\n")
        team = signature_text[/^TeamIdentifier=(.+)$/, 1]
        authorities = signature_text.scan(/^Authority=(.+)$/).flatten
        raise ValidationError, "artifact TeamIdentifier #{team || 'missing'} does not match #{Config::TEAM_ID}" unless team == Config::TEAM_ID
        unless authorities.any? { |authority| authority.include?("Developer ID Application") && authority.include?("Moballo") }
          raise ValidationError, "artifact is not signed with a Moballo Developer ID Application certificate"
        end

        @runner.run("/usr/bin/xcrun", "stapler", "validate", app)
        @runner.run("/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=4", app)
        launch_and_quit(app, executable_name) if launch
        package(app, output_zip) if output_zip

        {
          "app_name" => app.basename.to_s,
          "bundle_id" => bundle_id,
          "version" => actual_version,
          "build" => Integer(actual_build),
          "architectures" => architectures,
          "team_id" => team,
          "authorities" => authorities,
          "artifact_sha256" => artifact_digest,
          "zip_path" => output_zip && Pathname.new(output_zip).expand_path.to_s,
          "zip_sha256" => output_zip && Digest::SHA256.file(output_zip).hexdigest,
          "launched" => launch
        }.compact
      end
    rescue ArgumentError, TypeError
      raise ValidationError, "artifact build must be an integer"
    end

    private

    def locate_app(source, temporary_directory)
      search_root = if source.directory?
                      source
                    elsif source.extname.downcase == ".zip"
                      @runner.run("/usr/bin/ditto", "-x", "-k", source, temporary_directory)
                      temporary_directory
                    else
                      raise ValidationError, "artifact must be an .app, .xcarchive, directory, or .zip"
                    end
      return search_root if search_root.extname == ".app"

      applications = Dir.glob(search_root.join("**/*.app").to_s).map { |path| Pathname.new(path) }
      applications.select! { |path| path.basename.to_s.start_with?("Sequel Ace") }
      top_level = applications.reject do |candidate|
        applications.any? { |parent| parent != candidate && candidate.to_s.start_with?("#{parent}/") }
      end
      raise ValidationError, "expected exactly one Sequel Ace app, found #{top_level.length}" unless top_level.length == 1

      top_level.first
    end

    def plist(path, key)
      @runner.run("/usr/bin/plutil", "-extract", key, "raw", "-o", "-", path).stdout.strip
    end

    def launch_and_quit(app, process_name)
      started = false
      existing = @runner.run("/usr/bin/pgrep", "-x", process_name, allow_failure: true)
      raise ValidationError, "#{process_name} is already running; refusing to quit an unrelated process" if existing.status.success?

      @runner.run("/usr/bin/open", "-n", app)
      started = true
      sleep(5)
      running = @runner.run("/usr/bin/pgrep", "-x", process_name, allow_failure: true)
      raise ValidationError, "artifact did not remain running after launch" unless running.status.success?

      escaped = process_name.gsub('"', '\\"')
      @runner.run("/usr/bin/osascript", "-e", "tell application \"#{escaped}\" to quit")
      deadline = Time.now + 20
      loop do
        stopped = !@runner.run("/usr/bin/pgrep", "-x", process_name, allow_failure: true).status.success?
        return if stopped
        raise ValidationError, "artifact did not quit cleanly" if Time.now >= deadline

        sleep(1)
      end
    ensure
      @runner.run("/usr/bin/pkill", "-TERM", "-x", process_name, allow_failure: true) if process_name && started
    end

    def package(app, output_zip)
      destination = Pathname.new(output_zip).expand_path
      FileUtils.mkdir_p(destination.dirname)
      raise ValidationError, "refusing to overwrite existing zip: #{destination}" if destination.exist?

      @runner.run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, destination)
    end

    def sha256(path)
      return Digest::SHA256.file(path).hexdigest if path.file?

      digest = Digest::SHA256.new
      Dir.glob(path.join("**/*"), File::FNM_DOTMATCH).sort.each do |entry|
        next unless File.file?(entry)

        digest << entry.delete_prefix(path.to_s)
        File.open(entry, "rb") { |file| digest << file.read(1024 * 1024) until file.eof? }
      end
      digest.hexdigest
    end
  end
end
