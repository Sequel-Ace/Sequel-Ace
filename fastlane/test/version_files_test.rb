# frozen_string_literal: true

require "test_helper"

class VersionFilesTest < Minitest::Test
  def test_updates_every_configured_version_location_exactly
    Dir.mktmpdir do |directory|
      root = Pathname.new(directory)
      create_fixture_tree(root)
      files = SequelAceRelease::VersionFiles.new(root: root)

      assert_equal({ "version" => "5.3.1", "build" => 20_104 }, files.current)
      result = files.update!(version: "5.3.2", build: 20_105)
      assert_equal({ "version" => "5.3.2", "build" => 20_105 }, files.current)
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
        SequelAceRelease::VersionFiles.new(root: root).update!(version: "5.3.2", build: 20_105)
      end
    end
  end

  private

  def create_fixture_tree(root)
    SequelAceRelease::Config::PLIST_FILES.each do |relative|
      file = root.join(relative)
      FileUtils.mkdir_p(file.dirname)
      file.write(<<~PLIST)
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>CFBundleShortVersionString</key><string>5.3.1</string>
        <key>CFBundleVersion</key><string>20104</string>
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
