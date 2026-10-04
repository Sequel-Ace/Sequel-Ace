# frozen_string_literal: true

require "test_helper"

class ScheduleTest < Minitest::Test
  def setup
    @cli = SequelAceRelease::CLI.new(out: StringIO.new, err: StringIO.new, env: {})
  end

  def test_selects_same_day_nine_pacific_when_it_is_the_first_valid_point
    scheduled = with_process_timezone("UTC") do
      now = Time.new(2026, 8, 8, 8, 30, 0, "-07:00")
      @cli.send(:default_schedule_time, now)
    end

    assert_equal "2026-08-11 09:00 -0700", scheduled.strftime("%Y-%m-%d %H:%M %z")
  end

  def test_moves_to_the_following_day_when_the_threshold_has_passed_nine
    scheduled = with_process_timezone("UTC") do
      now = Time.new(2026, 8, 8, 9, 1, 0, "-07:00")
      @cli.send(:default_schedule_time, now)
    end

    assert_equal "2026-08-12 09:00 -0700", scheduled.strftime("%Y-%m-%d %H:%M %z")
  end

  private

  def with_process_timezone(timezone)
    previous = ENV["TZ"]
    ENV["TZ"] = timezone
    yield
  ensure
    previous.nil? ? ENV.delete("TZ") : ENV["TZ"] = previous
  end
end
