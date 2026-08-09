# frozen_string_literal: true

require "test_helper"
require "open3"

class GitRepositoryTest < Minitest::Test
  def test_finds_the_release_commit_after_unrelated_main_changes
    Dir.mktmpdir do |directory|
      git(directory, "init", "--initial-branch=main")
      git(directory, "config", "user.name", "Release Test")
      git(directory, "config", "user.email", "release@example.invalid")
      %w[project.pbxproj Info.plist CHANGELOG.md].each do |path|
        File.write(File.join(directory, path), "initial\n")
      end
      commit_all(directory, "initial")

      git(directory, "checkout", "-b", "prepare-release")
      %w[project.pbxproj Info.plist CHANGELOG.md].each do |path|
        File.write(File.join(directory, path), "release\n")
      end
      commit_all(directory, "prepare release")
      git(directory, "checkout", "main")
      git(directory, "-c", "commit.gpgsign=false", "merge", "--no-ff", "prepare-release", "-m", "merge release")
      release_sha = git(directory, "rev-parse", "HEAD")
      File.write(File.join(directory, "README.md"), "unrelated\n")
      commit_all(directory, "unrelated change")

      repository = SequelAceRelease::GitRepository.new(root: directory)
      assert_equal release_sha,
                   repository.latest_commit_changing_all(%w[project.pbxproj Info.plist CHANGELOG.md])
    end
  end

  def test_rejects_a_candidate_if_a_release_path_changed_later
    Dir.mktmpdir do |directory|
      git(directory, "init", "--initial-branch=main")
      git(directory, "config", "user.name", "Release Test")
      git(directory, "config", "user.email", "release@example.invalid")
      %w[project.pbxproj Info.plist CHANGELOG.md].each do |path|
        File.write(File.join(directory, path), "initial\n")
      end
      commit_all(directory, "initial")
      %w[project.pbxproj Info.plist CHANGELOG.md].each do |path|
        File.write(File.join(directory, path), "release\n")
      end
      commit_all(directory, "prepare release")
      File.write(File.join(directory, "CHANGELOG.md"), "later release change\n")
      commit_all(directory, "later changelog change")

      repository = SequelAceRelease::GitRepository.new(root: directory)
      assert_nil repository.latest_commit_changing_all(%w[project.pbxproj Info.plist CHANGELOG.md])
    end
  end

  def test_checks_release_tag_ancestry
    Dir.mktmpdir do |directory|
      git(directory, "init", "--initial-branch=main")
      git(directory, "config", "user.name", "Release Test")
      git(directory, "config", "user.email", "release@example.invalid")
      File.write(File.join(directory, "README.md"), "stable\n")
      commit_all(directory, "stable release")
      git(directory, "tag", "production/5.3.1-20104")

      File.write(File.join(directory, "README.md"), "beta\n")
      commit_all(directory, "first beta")
      git(directory, "tag", "beta/5.4.0-20105")

      File.write(File.join(directory, "README.md"), "later production\n")
      commit_all(directory, "unrelated later production")
      git(directory, "tag", "production/5.3.9-20106")

      repository = SequelAceRelease::GitRepository.new(root: directory)
      assert repository.ancestor?("production/5.3.1-20104", "beta/5.4.0-20105")
      refute repository.ancestor?("production/5.3.9-20106", "beta/5.4.0-20105")
    end
  end

  def test_changed_paths_consumes_the_original_path_for_a_rename
    Dir.mktmpdir do |directory|
      git(directory, "init", "--initial-branch=main")
      git(directory, "config", "user.name", "Release Test")
      git(directory, "config", "user.email", "release@example.invalid")
      File.write(File.join(directory, "old-name.txt"), "fixture\n")
      commit_all(directory, "initial file")
      git(directory, "mv", "old-name.txt", "new-name.txt")

      paths = SequelAceRelease::GitRepository.new(root: directory).changed_paths
      assert_equal [{
        "status" => "R ",
        "path" => "new-name.txt",
        "original_path" => "old-name.txt"
      }], paths
    end
  end

  private

  def commit_all(directory, message)
    git(directory, "add", ".")
    git(directory, "-c", "commit.gpgsign=false", "commit", "-m", message)
    git(directory, "rev-parse", "HEAD")
  end

  def git(directory, *arguments)
    stdout, stderr, status = Open3.capture3("git", "-C", directory, *arguments)
    raise "git #{arguments.join(' ')} failed: #{stderr}" unless status.success?

    stdout.strip
  end
end
