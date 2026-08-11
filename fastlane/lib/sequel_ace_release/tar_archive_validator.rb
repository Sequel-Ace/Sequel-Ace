# frozen_string_literal: true

require "rubygems/package"
require "zlib"

require_relative "error"

module SequelAceRelease
  class TarArchiveValidator
    MAX_METADATA_BYTES = 1_048_576
    MAX_MEMBERS = 250_000
    MAX_PATH_BYTES = 4_096
    STRUCTURAL_PAX_KEYS = %w[hdrcharset size].freeze
    Entry = Struct.new(:path, :type, :link_target, keyword_init: true)

    def validate!(archive_path)
      entries = read_entries(archive_path)
      validate_entry_relationships!(entries)
      true
    rescue IntegrityError
      raise
    rescue StandardError => e
      raise IntegrityError, "Release archive could not be validated (#{e.class})"
    end

    private

    def read_entries(archive_path)
      entries = []
      global_pax = {}
      pending_pax = nil
      pending_long_name = nil
      pending_long_link = nil

      Zlib::GzipReader.open(archive_path) do |gzip|
        Gem::Package::TarReader.new(gzip) do |tar|
          tar.each do |entry|
            typeflag = entry.header.typeflag
            case typeflag
            when "g"
              attributes = parse_pax(read_metadata(entry, MAX_METADATA_BYTES, "PAX metadata"))
              reject_global_path_overrides!(attributes)
              global_pax.merge!(attributes)
            when "x"
              integrity_error!("Release archive contains consecutive per-file PAX headers") if pending_pax
              pending_pax = parse_pax(read_metadata(entry, MAX_METADATA_BYTES, "PAX metadata"))
            when "L"
              integrity_error!("Release archive contains ambiguous long path headers") if pending_long_name
              pending_long_name = parse_long_value(read_metadata(entry, MAX_PATH_BYTES + 1, "extended path"))
            when "K"
              integrity_error!("Release archive contains ambiguous long link headers") if pending_long_link
              pending_long_link = parse_long_value(read_metadata(entry, MAX_PATH_BYTES + 1, "extended path"))
            else
              attributes = global_pax.merge(pending_pax || {})
              reject_structural_pax_overrides!(attributes)
              if attributes.key?("path") && pending_long_name
                integrity_error!("Release archive contains conflicting path overrides")
              end
              if attributes.key?("linkpath") && pending_long_link
                integrity_error!("Release archive contains conflicting link overrides")
              end

              raw_path = attributes.fetch("path", pending_long_name || entry.full_name)
              raw_link = attributes.fetch("linkpath", pending_long_link || entry.header.linkname)
              entries << build_entry(raw_path, typeflag, raw_link)
              integrity_error!("Release archive contains too many members") if entries.length > MAX_MEMBERS

              pending_pax = nil
              pending_long_name = nil
              pending_long_link = nil
            end
          end
        end
      end

      if pending_pax || pending_long_name || pending_long_link
        integrity_error!("Release archive ends with an incomplete extended header")
      end

      entries
    end

    def build_entry(raw_path, typeflag, raw_link)
      type = case typeflag
             when "0", "\0", ""
               :file
             when "5"
               :directory
             when "2"
               :symlink
             when "1"
               :hardlink
             else
               integrity_error!("Release archive contains unsupported member type #{typeflag.inspect}")
             end
      path = canonical_member_path(raw_path, allow_root: type == :directory)
      link_target = case type
                    when :symlink
                      canonical_symlink_target(path, raw_link)
                    when :hardlink
                      canonical_hardlink_target(path, raw_link)
                    end
      Entry.new(path: path, type: type, link_target: link_target)
    end

    def validate_entry_relationships!(entries)
      by_path = {}
      entries.each do |entry|
        integrity_error!("Release archive repeats member path: #{entry.path}") if by_path.key?(entry.path)

        by_path[entry.path] = entry
      end

      manifest = by_path["manifest.json"]
      unless manifest&.type == :file
        integrity_error!("Release archive must contain one regular manifest.json")
      end

      symlink_paths = {}
      entries.each { |entry| symlink_paths[entry.path] = true if entry.type == :symlink }
      entries.each do |entry|
        path_ancestors(entry.path).each do |ancestor|
          if symlink_paths.key?(ancestor)
            integrity_error!("Release archive member traverses archive symlink: #{entry.path}")
          end
        end

        next unless entry.type == :hardlink

        target = resolve_hardlink_target(entry, by_path)
        unless target.type == :file
          integrity_error!("Release archive hard link does not resolve to a regular artifact file: #{entry.path}")
        end
        path_ancestors(entry.link_target).each do |ancestor|
          if symlink_paths.key?(ancestor)
            integrity_error!("Release archive hard link target traverses an archive symlink: #{entry.path}")
          end
        end
      end
    end

    def resolve_hardlink_target(entry, by_path)
      seen = { entry.path => true }
      current = by_path[entry.link_target]
      integrity_error!("Release archive hard link target is missing: #{entry.path}") unless current

      while current.type == :hardlink
        integrity_error!("Release archive contains a hard link cycle: #{entry.path}") if seen[current.path]

        seen[current.path] = true
        current = by_path[current.link_target]
        integrity_error!("Release archive hard link target is missing: #{entry.path}") unless current
      end
      current
    end

    def canonical_member_path(raw_path, allow_root: false)
      path = validated_text(raw_path, "member path")
      integrity_error!("Release archive contains an absolute member path") if path.start_with?("/")

      components = []
      path.split("/", -1).each do |component|
        next if component.empty? || component == "."

        integrity_error!("Release archive member path contains '..'") if component == ".."
        components << component
      end
      return "." if components.empty? && allow_root

      integrity_error!("Release archive contains an empty member path") if components.empty?
      components.join("/")
    end

    def canonical_symlink_target(member_path, raw_target)
      unless member_path.start_with?("artifacts/")
        integrity_error!("Release archive contains a symlink outside artifacts/: #{member_path}")
      end

      target = validated_text(raw_target, "symlink target")
      integrity_error!("Release archive contains an unsafe artifact symlink target: #{member_path}") if target.start_with?("/")

      components = member_path.split("/")[0...-1]
      target.split("/", -1).each do |component|
        next if component.empty? || component == "."

        if component == ".."
          integrity_error!("Release archive contains an escaping artifact symlink: #{member_path}") if components.empty?
          components.pop
        else
          components << component
        end
      end
      resolved = components.join("/")
      unless resolved.start_with?("artifacts/")
        integrity_error!("Release archive contains an escaping artifact symlink: #{member_path}")
      end
      resolved
    end

    def canonical_hardlink_target(member_path, raw_target)
      unless member_path.start_with?("artifacts/")
        integrity_error!("Release archive contains a hard link outside artifacts/")
      end

      target = canonical_member_path(raw_target)
      unless target.start_with?("artifacts/")
        integrity_error!("Release archive contains a hard link outside artifacts/")
      end
      target
    end

    def path_ancestors(path)
      components = path.split("/")
      (1...components.length).map { |length| components.first(length).join("/") }
    end

    def parse_pax(data)
      bytes = data.b
      integrity_error!("Release archive PAX metadata is too large") if bytes.bytesize > MAX_METADATA_BYTES

      attributes = {}
      offset = 0
      while offset < bytes.bytesize
        space = bytes.index(" ", offset)
        integrity_error!("Release archive contains malformed PAX metadata") unless space

        length_text = bytes.byteslice(offset, space - offset)
        unless length_text.match?(/\A[1-9][0-9]*\z/)
          integrity_error!("Release archive contains malformed PAX record length")
        end
        length = Integer(length_text, 10)
        record = bytes.byteslice(offset, length)
        unless record && record.bytesize == length && record.end_with?("\n")
          integrity_error!("Release archive contains truncated PAX metadata")
        end

        value_start = space - offset + 1
        payload = record.byteslice(value_start, length - value_start - 1)
        key, value = payload.split("=", 2)
        if key.nil? || key.empty? || value.nil?
          integrity_error!("Release archive contains malformed PAX metadata")
        end
        attributes[validated_text(key, "PAX key")] = value
        offset += length
      end
      attributes
    end

    def read_metadata(entry, maximum, label)
      integrity_error!("Release archive #{label} is too large") if entry.header.size > maximum

      entry.read
    end

    def parse_long_value(data)
      bytes = data.b
      integrity_error!("Release archive extended path is too large") if bytes.bytesize > MAX_PATH_BYTES + 1

      value, remainder = bytes.split("\0", 2)
      if remainder && !remainder.bytes.all?(&:zero?)
        integrity_error!("Release archive contains malformed GNU long-name metadata")
      end
      validated_text(value, "extended path")
    end

    def reject_global_path_overrides!(attributes)
      if attributes.key?("path") || attributes.key?("linkpath")
        integrity_error!("Release archive contains a global path override")
      end
      reject_structural_pax_overrides!(attributes)
    end

    def reject_structural_pax_overrides!(attributes)
      unsafe_key = attributes.keys.find do |key|
        STRUCTURAL_PAX_KEYS.include?(key) || key.start_with?("GNU.sparse") || key == "SCHILY.realsize"
      end
      integrity_error!("Release archive contains unsupported structural PAX metadata: #{unsafe_key}") if unsafe_key
    end

    def validated_text(value, label)
      text = value.to_s.dup.force_encoding(Encoding::UTF_8)
      unless text.valid_encoding? && text.bytesize <= MAX_PATH_BYTES && !text.bytes.any? { |byte| byte < 0x20 || byte == 0x7f }
        integrity_error!("Release archive contains an unsafe #{label}")
      end
      text
    end

    def integrity_error!(message)
      raise IntegrityError, message
    end
  end
end
