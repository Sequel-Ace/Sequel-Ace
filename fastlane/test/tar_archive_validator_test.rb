# frozen_string_literal: true

require "test_helper"

class TarArchiveValidatorTest < Minitest::Test
  def test_accepts_a_manifest_and_contained_artifact_links
    with_archive(
      directory("."),
      file("manifest.json", "{}\n"),
      directory("artifacts"),
      directory("artifacts/Versions"),
      directory("artifacts/Versions/A"),
      file("artifacts/Versions/A/binary", "verified\n"),
      symlink("artifacts/Versions/Current", "A"),
      hardlink("artifacts/binary-copy", "artifacts/Versions/A/binary")
    ) do |archive|
      assert SequelAceRelease::TarArchiveValidator.new.validate!(archive)
    end
  end

  def test_rejects_a_parent_traversal_member
    error = assert_invalid(file("manifest.json", "{}\n"), file("../outside", "unsafe\n"))

    assert_includes error.message, "member path contains '..'"
  end

  def test_rejects_an_absolute_member
    error = assert_invalid(file("manifest.json", "{}\n"), file("/tmp/outside", "unsafe\n"))

    assert_includes error.message, "absolute member path"
  end

  def test_rejects_an_escaping_symlink_before_extraction
    error = assert_invalid(
      file("manifest.json", "{}\n"),
      directory("artifacts"),
      symlink("artifacts/pivot", "../../outside")
    )

    assert_includes error.message, "escaping artifact symlink"
  end

  def test_rejects_a_member_nested_below_an_archive_symlink
    error = assert_invalid(
      file("manifest.json", "{}\n"),
      directory("artifacts"),
      directory("artifacts/real"),
      symlink("artifacts/pivot", "real"),
      file("artifacts/pivot/payload", "unsafe\n")
    )

    assert_includes error.message, "traverses archive symlink"
  end

  def test_rejects_a_hardlink_outside_artifacts
    error = assert_invalid(
      file("manifest.json", "{}\n"),
      directory("artifacts"),
      hardlink("artifacts/manifest-copy", "manifest.json")
    )

    assert_includes error.message, "hard link outside artifacts/"
  end

  def test_rejects_a_hardlink_member_outside_artifacts
    error = assert_invalid(
      file("manifest.json", "{}\n"),
      directory("artifacts"),
      file("artifacts/payload", "verified\n"),
      hardlink("payload-copy", "artifacts/payload")
    )

    assert_includes error.message, "hard link outside artifacts/"
  end

  def test_rejects_a_missing_hardlink_target
    error = assert_invalid(
      file("manifest.json", "{}\n"),
      directory("artifacts"),
      hardlink("artifacts/copy", "artifacts/missing")
    )

    assert_includes error.message, "hard link target is missing"
  end

  def test_rejects_normalized_duplicate_paths
    error = assert_invalid(file("manifest.json", "{}\n"), file("./manifest.json", "duplicate\n"))

    assert_includes error.message, "repeats member path"
  end

  def test_applies_a_pax_path_override_before_validation
    pax = pax_record("path", "../outside")
    error = assert_invalid(
      file("manifest.json", "{}\n"),
      entry(name: "PaxHeader", typeflag: "x", data: pax),
      file("placeholder", "unsafe\n")
    )

    assert_includes error.message, "member path contains '..'"
  end

  def test_rejects_structural_pax_size_overrides
    pax = pax_record("size", "4096")
    error = assert_invalid(
      file("manifest.json", "{}\n"),
      entry(name: "PaxHeader", typeflag: "x", data: pax),
      file("artifacts/payload", "unsafe\n")
    )

    assert_includes error.message, "unsupported structural PAX metadata"
  end

  def test_rejects_a_concatenated_gzip_stream_after_an_unterminated_tar
    error = assert_concatenated_archive_invalid(first_terminated: false)

    assert_includes error.message, "complete tar terminator"
  end

  def test_rejects_a_concatenated_gzip_stream_after_a_complete_tar
    error = assert_concatenated_archive_invalid(first_terminated: true)

    assert_includes error.message, "trailing or concatenated gzip data"
  end

  def test_rejects_an_excessive_compressed_zero_suffix
    captured = nil
    Dir.mktmpdir do |directory|
      archive = File.join(directory, "release.tar.gz")
      write_archive(
        archive,
        [file("manifest.json", "{}\n")],
        trailing_zero_bytes: SequelAceRelease::TarArchiveValidator::MAX_TRAILING_TAR_BYTES + 1_024
      )

      captured = assert_raises(SequelAceRelease::IntegrityError) do
        SequelAceRelease::TarArchiveValidator.new.validate!(archive)
      end
    end

    assert_includes captured.message, "excessive data after its tar terminator"
  end

  private

  def assert_concatenated_archive_invalid(first_terminated:)
    captured = nil
    Dir.mktmpdir do |directory|
      first = File.join(directory, "first.tar.gz")
      second = File.join(directory, "second.tar.gz")
      archive = File.join(directory, "release.tar.gz")
      write_archive(first, [file("manifest.json", "{}\n")], terminator: first_terminated)
      write_archive(second, [file("hidden-after-first-stream", "unsafe\n")])
      File.binwrite(archive, File.binread(first) + File.binread(second))

      captured = assert_raises(SequelAceRelease::IntegrityError) do
        SequelAceRelease::TarArchiveValidator.new.validate!(archive)
      end
    end
    captured
  end

  def assert_invalid(*entries)
    captured = nil
    with_archive(*entries) do |archive|
      captured = assert_raises(SequelAceRelease::IntegrityError) do
        SequelAceRelease::TarArchiveValidator.new.validate!(archive)
      end
    end
    captured
  end

  def with_archive(*entries)
    Dir.mktmpdir do |directory|
      archive = File.join(directory, "release.tar.gz")
      write_archive(archive, entries)
      yield archive
    end
  end

  def write_archive(path, entries, terminator: true, trailing_zero_bytes: nil)
    Zlib::GzipWriter.open(path) do |gzip|
      entries.each do |entry|
        data = entry.fetch(:data)
        header = Gem::Package::TarHeader.new(
          name: entry.fetch(:name),
          prefix: "",
          mode: entry.fetch(:mode, 0o644),
          size: data.bytesize,
          typeflag: entry.fetch(:typeflag),
          linkname: entry.fetch(:linkname, "")
        )
        gzip.write(header.to_s)
        gzip.write(data)
        gzip.write("\0" * ((512 - (data.bytesize % 512)) % 512))
      end
      zero_bytes = trailing_zero_bytes || (terminator ? 1_024 : 0)
      gzip.write("\0" * zero_bytes)
    end
  end

  def entry(name:, typeflag:, data: "", linkname: "", mode: 0o644)
    { name: name, typeflag: typeflag, data: data, linkname: linkname, mode: mode }
  end

  def file(name, data)
    entry(name: name, typeflag: "0", data: data)
  end

  def directory(name)
    entry(name: name, typeflag: "5", mode: 0o755)
  end

  def symlink(name, target)
    entry(name: name, typeflag: "2", linkname: target, mode: 0o777)
  end

  def hardlink(name, target)
    entry(name: name, typeflag: "1", linkname: target)
  end

  def pax_record(key, value)
    payload = "#{key}=#{value}\n"
    length = payload.bytesize + 2
    loop do
      record = "#{length} #{payload}"
      return record if record.bytesize == length

      length = record.bytesize
    end
  end
end
