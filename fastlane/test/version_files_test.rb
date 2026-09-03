# frozen_string_literal: true

require "test_helper"

class VersionFilesTest < Minitest::Test
  def test_updates_every_configured_version_location_exactly
    Dir.mktmpdir do |directory|
      root = Pathname.new(directory)
      create_fixture_tree(root)
      files = SequelAceRelease::VersionFiles.new(root: root)

      assert_equal({ "version" => "5.3.1", "build" => 20_104 }, files.current)
      assert_equal "production/5.3.1-20104", files.release_tag
      assert_equal(
        { "channel" => "production", "version" => "5.3.1", "build" => 20_104, "tag" => "production/5.3.1-20104" },
        files.release_identity
      )
      result = files.update!(version: "5.3.2", build: 20_105, channel: "beta")
      assert_equal({ "version" => "5.3.2", "build" => 20_105 }, files.current)
      assert_equal "beta/5.3.2-20105", files.release_tag
      assert_equal(
        { "channel" => "beta", "version" => "5.3.2", "build" => 20_105, "tag" => "beta/5.3.2-20105" },
        files.release_identity
      )
      assert_includes root.join(SequelAceRelease::Config::APP_INFO_PLIST).read,
                      "<string>beta/5.3.2-20105</string>"
      assert_equal 20_104, result.dig("before", "build")
      assert_equal 20_105, result.dig("after", "build")
    end
  end

  def test_aborts_when_project_shape_changes
    Dir.mktmpdir do |directory|
      root = Pathname.new(directory)
      create_fixture_tree(root)
      file = root.join(SequelAceRelease::Config::PROJECT_FILES.keys.first)
      file.write(file.read.sub("CURRENT_PROJECT_VERSION = 20104;", ""))

      assert_raises(SequelAceRelease::ValidationError) do
        SequelAceRelease::VersionFiles.new(root: root).update!(
          version: "5.3.2", build: 20_105, channel: "production"
        )
      end
    end
  end

  def test_invalid_requested_build_has_a_specific_validation_error
    Dir.mktmpdir do |directory|
      root = Pathname.new(directory)
      create_fixture_tree(root)

      error = assert_raises(SequelAceRelease::ValidationError) do
        SequelAceRelease::VersionFiles.new(root: root).update!(
          version: "5.3.2", build: "not-a-build", channel: "production"
        )
      end
      assert_equal "build must be an integer", error.message
    end
  end

  def test_rejects_a_release_tag_that_disagrees_with_the_source_version
    Dir.mktmpdir do |directory|
      root = Pathname.new(directory)
      create_fixture_tree(root)
      info = root.join(SequelAceRelease::Config::APP_INFO_PLIST)
      info.write(info.read.sub("production/5.3.1-20104", "production/5.3.2-20104"))

      error = assert_raises(SequelAceRelease::ValidationError) do
        SequelAceRelease::VersionFiles.new(root: root).release_identity
      end
      assert_includes error.message, "does not match source version"
    end
  end

  private

  def create_fixture_tree(root)
    SequelAceRelease::Config::PLIST_FILES.each do |relative|
      file = root.join(relative)
      FileUtils.mkdir_p(file.dirname)
      release_tag = if relative == SequelAceRelease::Config::APP_INFO_PLIST
                      "<key>#{SequelAceRelease::Config::RELEASE_TAG_PLIST_KEY}</key><string>production/5.3.1-20104</string>"
                    else
                      ""
                    end
      file.write(<<~PLIST)
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>CFBundleShortVersionString</key><string>5.3.1</string>
        <key>CFBundleVersion</key><string>20104</string>
        #{release_tag}
        </dict></plist>
      PLIST
    end
    SequelAceRelease::Config::PROJECT_FILES.each do |relative, counts|
      file = root.join(relative)
      FileUtils.mkdir_p(file.dirname)
      lines = Array.new(counts.fetch(:current), "CURRENT_PROJECT_VERSION = 20104;")
      lines.concat(Array.new(counts.fetch(:dylib), "DYLIB_CURRENT_VERSION = 20104;"))
      file.write(lines.join("\n") + "\n")
    end
  end
end
