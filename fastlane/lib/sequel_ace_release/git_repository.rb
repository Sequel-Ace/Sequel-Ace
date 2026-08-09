# frozen_string_literal: true

module SequelAceRelease
  class GitRepository
    Change = Struct.new(:sha, :subject, :body, :author_name, :author_email, :pr_number, :title, :category, keyword_init: true) do
      def to_h
        {
          "sha" => sha,
          "subject" => subject,
          "pr_number" => pr_number,
          "title" => title,
          "category" => category,
          "author_name" => author_name
        }
      end
    end

    CATEGORY_ORDER = %w[added fixed changed removed infra].freeze

    def initialize(runner: CommandRunner.new, root: Config.repo_root)
      @runner = runner
      @root = root
    end

    def sha(ref = "HEAD")
      git("rev-parse", "#{ref}^{commit}").strip
    end

    def branch
      git("branch", "--show-current").strip
    end

    def clean?
      git("status", "--porcelain").strip.empty?
    end

    def ensure_clean!
      return if clean?

      raise ValidationError, "working tree must be clean before release preparation"
    end

    def tag_exists?(tag)
      @runner.run("git", "rev-parse", "--verify", "refs/tags/#{tag}", chdir: @root, allow_failure: true).status.success?
    end

    def tags(pattern)
      git("tag", "--list", pattern).lines.map(&:strip).reject(&:empty?)
    end

    def latest_release_tag(channel: "production", before_version: nil)
      Config.validate_channel!(channel)
      parsed = tags("#{channel}/*").filter_map do |tag|
        match = tag.match(%r{\A#{Regexp.escape(channel)}/(\d+\.\d+\.\d+)-(\d+)\z})
        next unless match
        next if before_version && !Version.compare(match[1], before_version).negative?

        [tag, match[1], Integer(match[2], 10)]
      end
      parsed.max_by { |(_, version, build)| [Version.parts(version), build] }&.first
    end

    def changed_paths
      output = git("status", "--porcelain=v1", "-z")
      output.split("\0").filter_map do |entry|
        next if entry.empty?

        status = entry[0, 2]
        path = entry[3..]
        { "status" => status, "path" => path }
      end
    end

    def head_changes_all?(paths)
      changed = git("diff-tree", "--no-commit-id", "--name-only", "-r", "-m", "HEAD").lines.map(&:strip).reject(&:empty?)
      (Array(paths) - changed).empty?
    end

    def changes(base_ref:, head_ref: "HEAD")
      sha(base_ref)
      sha(head_ref)
      separator = "\x1f"
      record_separator = "\x1e"
      format = ["%H", "%s", "%b", "%an", "%ae"].join("%x1f") + "%x1e"
      raw = git("log", "--first-parent", "--format=#{format}", "#{base_ref}..#{head_ref}")
      raw.split(record_separator).filter_map do |record|
        fields = record.strip.split(separator, 5)
        next if fields.length < 5

        commit_sha, subject, body, author_name, author_email = fields
        pr_number, title = extract_pr(subject, body)
        cleaned_title = clean_title(title)
        next if cleaned_title.empty?

        Change.new(
          sha: commit_sha,
          subject: subject,
          body: body,
          author_name: author_name,
          author_email: author_email,
          pr_number: pr_number,
          title: cleaned_title,
          category: classify(title)
        )
      end
    end

    def remote_url(name = "origin")
      git("remote", "get-url", name).strip
    end

    private

    def git(*arguments)
      @runner.run("git", *arguments, chdir: @root).stdout
    end

    def extract_pr(subject, body)
      if (match = subject.match(/\AMerge pull request #(\d+)/i))
        body_title = body.lines.find { |line| !line.strip.empty? }&.strip
        [Integer(match[1], 10), body_title || subject]
      elsif (match = subject.match(/\A(.+?)\s*\(#(\d+)\)\z/))
        [Integer(match[2], 10), match[1]]
      else
        [nil, subject]
      end
    end

    def clean_title(title)
      title.to_s
           .gsub(/(?:\A|\s)#(?:added|fixed|changed|removed|infra|unfinished)(?=\s|\z)/i, " ")
           .gsub(/\A\s*[-*]+\s*/, "")
           .gsub(/\s+/, " ")
           .strip
    end

    def classify(title)
      lower = title.to_s.downcase
      return "added" if lower.match?(/(?:\A|\s)#added(?:\s|\z)/) || lower.match?(/\A(add|introduce|support|enable|implement|create)(?:\s|:)/)
      return "fixed" if lower.match?(/(?:\A|\s)#fixed(?:\s|\z)/) || lower.match?(/\A(fix|resolve|recover|correct|prevent|harden)(?:\s|:)/)
      return "removed" if lower.match?(/(?:\A|\s)#removed(?:\s|\z)/) || lower.match?(/\A(remove|delete|drop)(?:\s|:)/)
      return "infra" if lower.match?(/(?:\A|\s)#infra(?:\s|\z)/) || lower.match?(/\A(build|bump|chore|ci|deps?|docs?|infra|tooling)(?:\s|:)/)

      "changed"
    end
  end

  module Version
    module_function

    def validate!(value)
      return value if value.to_s.match?(/\A\d+\.\d+\.\d+\z/)

      raise ValidationError, "version must use numeric MAJOR.MINOR.PATCH form"
    end

    def parts(value)
      validate!(value).split(".").map { |part| Integer(part, 10) }
    end

    def compare(left, right)
      parts(left) <=> parts(right)
    end

    def bump(value, type)
      major, minor, patch = parts(value)
      case type.to_s
      when "patch" then [major, minor, patch + 1]
      when "minor" then [major, minor + 1, 0]
      else raise ValidationError, "automatic recommendations only support patch or minor"
      end.join(".")
    end
  end
end
