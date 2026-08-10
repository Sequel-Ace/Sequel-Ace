# frozen_string_literal: true

require "open3"

module SequelAceRelease
  class CommandRunner
    Result = Struct.new(:stdout, :stderr, :status, keyword_init: true)

    def spawn(*command, chdir: Config.repo_root, env: {})
      raise ArgumentError, "command is required" if command.empty?

      program, *arguments = command.map(&:to_s)
      process_id = Process.spawn(
        env,
        [program, program],
        *arguments,
        chdir: chdir.to_s,
        in: File::NULL,
        out: File::NULL,
        err: File::NULL
      )
      Process.detach(process_id)
      process_id
    end

    def run(*command, chdir: Config.repo_root, env: {}, allow_failure: false, stdin_data: nil, redact_arguments: [], discard_output: false)
      if discard_output
        raise ArgumentError, "stdin_data cannot be combined with discard_output" unless stdin_data.nil?

        process_id = Process.spawn(
          env,
          *command.map(&:to_s),
          chdir: chdir.to_s,
          in: File::NULL,
          out: File::NULL,
          err: File::NULL
        )
        _waited_process_id, status = Process.wait2(process_id)
        stdout = ""
        stderr = ""
      else
        stdout, stderr, status = Open3.capture3(
          env,
          *command.map(&:to_s),
          chdir: chdir.to_s,
          stdin_data: stdin_data
        )
      end
      result = Result.new(stdout: stdout, stderr: stderr, status: status)
      return result if status.success? || allow_failure

      redacted_indexes = Array(redact_arguments).map { |index| Integer(index) }
      rendered = command.each_with_index.map do |part, index|
        redacted_indexes.include?(index) ? "[REDACTED]" : shell_safe_display(part.to_s)
      end.join(" ")
      detail = stderr.strip.empty? ? stdout.strip : stderr.strip
      redacted_indexes.filter_map { |index| command[index]&.to_s }
                      .reject(&:empty?)
                      .sort_by { |value| -value.bytesize }
                      .each { |value| detail = detail.gsub(value, "[REDACTED]") }
      raise CommandError, "command failed (#{status.exitstatus}): #{rendered}\n#{detail}"
    end

    private

    def shell_safe_display(value)
      return "[REDACTED]" if value.match?(/(token|private[_-]?key|password)/i)
      return value if value.match?(/\A[\w.\/:=@+-]+\z/)

      value.inspect
    end
  end
end
