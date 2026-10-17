require_relative "../test_helper"
require_relative "../../lib/acute/chronic"
require "date"

# The chronic 0.10.2 API on acute (D46). The layer builds times in the process's zone, as chronic does.
class ChronicTest < Minitest::Test
  FakeZone = Struct.new(:tzinfo) do
    def at(epoch) = Time.at(epoch, in: tzinfo.period_for_utc(Time.at(epoch)).observed_utc_offset)
  end

  def setup
    @tz = ENV["TZ"]
    ENV["TZ"] = NY
    @now = Time.local(2026, 10, 17, 14)
  end

  def teardown
    ENV["TZ"] = @tz
    Chronic.time_class = ::Time
  end

  def chronic(text, **opts) = Chronic.parse(text, { now: @now }.merge(opts))

  def test_d46_a_day_guesses_its_middle_on_the_wall_clock
    assert_equal Time.local(2026, 10, 18, 12), chronic("tomorrow")
    assert_equal Time.local(2026, 11, 1, 12), chronic("2026-11-01")
    assert_equal Time.local(2026, 11, 16), chronic("november")
  end

  def test_d46_each_guess_mode
    assert_equal Time.local(2026, 10, 18), chronic("tomorrow", guess: :begin)
    assert_equal Time.local(2026, 10, 19), chronic("tomorrow", guess: :end)
    assert_equal Time.local(2026, 10, 18, 12), chronic("tomorrow", guess: :middle)
    span = chronic("tomorrow", guess: false)
    assert_kind_of Chronic::Span, span
    assert_equal [Time.local(2026, 10, 18), Time.local(2026, 10, 19), 86_400], [span.begin, span.end, span.width]
  end

  def test_d46_a_clock_time_is_its_instant_and_a_span_when_unguessed
    assert_equal Time.local(2026, 10, 17, 15), chronic("3pm")
    assert_equal Time.local(2026, 10, 17, 15), chronic("3pm", guess: :end)
    span = chronic("3pm", guess: false)
    assert_equal [Time.local(2026, 10, 17, 15), Time.local(2026, 10, 17, 15, 1)], [span.begin, span.end]
  end

  def test_d47_every_span_but_a_said_clock_is_guessed
    assert_equal Time.local(2026, 10, 17, 14, 30), chronic("next hour")
    assert_equal Time.local(2026, 10, 17, 14, 0, 30), chronic("this minute")
    assert_equal Time.local(2026, 10, 17, 14), chronic("next hour", guess: :begin)
    assert_equal Time.local(2026, 10, 17, 15), chronic("next hour", guess: :end)
    assert_equal Time.local(2026, 10, 18, 12), chronic("noon")
    assert_equal Time.local(2026, 10, 17, 17, 30), chronic("at 5:30")
    assert_equal Time.local(2026, 10, 19, 15), chronic("monday 3pm")
    assert_equal Time.local(2026, 10, 17, 17), chronic("in 3 hours")
  end

  def test_guess_takes_the_middle_as_chronic_does
    parser = Chronic::Parser.new
    assert_equal Time.local(2006, 8, 16, 12), parser.guess(Chronic::Span.new(Time.local(2006, 8, 16), Time.local(2006, 8, 17)))
    assert_equal Time.local(2006, 8, 16, 12), parser.guess(Chronic::Span.new(Time.local(2006, 8, 16), Time.local(2006, 8, 17, 0, 0, 1)))
    assert_equal Time.local(2006, 11, 16), parser.guess(Chronic::Span.new(Time.local(2006, 11), Time.local(2006, 12)))
    day = Chronic::Span.new(Time.local(2026, 11, 1), Time.local(2026, 11, 2))
    assert_equal Time.local(2026, 11, 1, 12), parser.guess(day)
    assert_equal day.begin, parser.guess(day, :begin)
    assert_equal day.end, parser.guess(day, :end)
    assert_same day, parser.guess(day, false)
  end

  def test_span_arithmetic
    span = Chronic::Span.new(Time.local(2026, 1, 1), Time.local(2026, 1, 2))
    assert_equal Time.local(2026, 1, 1, 0, 0, 10), (span + 10).begin
    assert_equal Time.local(2026, 1, 1, 23, 59, 50), (span - 10).end
    assert_kind_of Range, span
  end

  def test_options_are_not_changed
    opts = { now: @now, guess: :begin, context: :past }.freeze
    Chronic.parse("friday", opts)
    parser = Chronic::Parser.new(opts)
    assert_equal @now, parser.now
    assert_equal :past, parser.options[:context]
    assert_equal %i[context now hours24 week_start guess ambiguous_time_range endian_precedence ambiguous_year_future_bias],
                 Chronic::Parser::DEFAULT_OPTIONS.keys
    assert_equal "0.10.2", Chronic::VERSION
  end

  def test_d46_context_past_and_anything_else
    assert_equal Time.local(2026, 10, 16, 17), chronic("5pm", context: :past)
    assert_equal Time.local(2026, 10, 17, 17), chronic("5pm", context: :none)
  end

  # whenever's patterns: Chronic.parse(time, chronic_options)
  def test_hours_without_meridiem
    assert_equal Time.local(2026, 10, 17, 15, 15), chronic("3:15")
    assert_equal Time.local(2026, 10, 17, 15, 15), chronic("3:15", hours24: false)
    assert_equal Time.local(2026, 10, 18, 3, 15), chronic("3:15", hours24: true)
    assert_equal Time.local(2026, 10, 18, 6, 30), chronic("6:30")
    assert_equal Time.local(2026, 10, 18, 9), chronic("9", ambiguous_time_range: :none)
    assert_equal Time.local(2026, 10, 17, 21), chronic("9", ambiguous_time_range: 10)
  end

  def test_d46_endian_precedence_only_when_given
    assert_equal Time.local(2027, 2, 3, 10, 15), chronic("02/03 10:15")
    assert_equal Time.local(2027, 3, 2, 10, 15), chronic("02/03 10:15", endian_precedence: :little)
    assert_equal Time.local(2027, 3, 2, 10, 15), chronic("02/03 10:15", endian_precedence: %i[little middle])
  end

  def test_ambiguous_year_future_bias
    assert_equal Time.local(1979, 1, 6), chronic("1/6/79", guess: :begin)
    assert_equal Time.local(2079, 1, 6), chronic("1/6/79", guess: :begin, ambiguous_year_future_bias: 10)
    assert_equal Time.local(1979, 1, 6), chronic("1/6/1979", guess: :begin, ambiguous_year_future_bias: 10)
  end

  def test_week_start
    span = chronic("this week", guess: false, week_start: :monday)
    assert_equal Time.local(2026, 10, 12), span.begin
  end

  def test_d46_words_acute_does_not_know_are_skipped
    assert_equal Time.local(2026, 10, 20, 12), chronic("meet bob tuesday")
    assert_nil chronic("foo")
    assert_nil chronic("a banana")
    assert_nil chronic("5th tuesday in february")
  end

  def test_time_class_date_and_a_zone
    Chronic.time_class = ::Date
    assert_equal Date.new(2026, 10, 18), chronic("tomorrow")
    Chronic.time_class = ::DateTime
    assert_kind_of DateTime, chronic("tomorrow")
    # ActiveSupport's Time.zone answers tzinfo and at
    Chronic.time_class = FakeZone.new(TZInfo::Timezone.get("Asia/Tokyo"))
    t = chronic("tomorrow 9am")
    assert_equal ["2026-10-18 09:00:00 +09:00"], [t.strftime("%F %T %:z")]
  end
end
