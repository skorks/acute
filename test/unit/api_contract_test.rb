require_relative "../test_helper"

# The 1.0 contract: every entry point checks its options the same way, and what it returns can't be changed
class ApiContractTest < Minitest::Test
  AT = { now: "2026-10-17T14:00", zone: NY }.freeze
  RULE = Acute.recurrence("every monday at 9am", **AT)
  PARSER = Acute.with(**AT)

  CALLS = {
    parse: ->(o) { Acute.parse("tomorrow", **o) },
    parse!: ->(o) { Acute.parse!("tomorrow", **o) },
    duration: ->(o) { Acute.duration("3 days", **o) },
    duration!: ->(o) { Acute.duration!("3 days", **o) },
    extract: ->(o) { Acute.extract("see you tomorrow", **o) },
    recurrence: ->(o) { Acute.recurrence("every monday", **o) },
    recurrence!: ->(o) { Acute.recurrence!("every monday", **o) },
    describe: ->(o) { Acute.describe(Date.new(2026, 10, 18), **o) },
    describe_duration: ->(o) { Acute.describe(Acute.duration("3 days"), **o) },
    describe_rule: ->(o) { Acute.describe(RULE, **o) },
    verify: ->(o) { Acute.verify("tomorrow", "2026-10-18", **o) },
    with: ->(o) { Acute.with(**o) },
    parser_new: ->(o) { Acute::Parser.new(**o) },
    parser_parse: ->(o) { PARSER.parse("tomorrow", **o) },
    parser_duration: ->(o) { PARSER.duration("3 days", **o) },
    parser_extract: ->(o) { PARSER.extract("see you tomorrow", **o) },
    parser_describe: ->(o) { PARSER.describe(Acute.duration("3 days"), **o) },
    parser_with: ->(o) { PARSER.with(**o) },
    tool: ->(o) { Acute::Tool.new(**o) },
    from_cron: ->(o) { Acute::Rule.from_cron("0 9 * * 1", **o) },
    from_cron!: ->(o) { Acute::Rule.from_cron!("0 9 * * 1", **o) }
  }.freeze

  def test_every_entry_point_rejects_a_bad_zone_with_an_option_error
    CALLS.each do |name, call|
      e = assert_raises(Acute::OptionError, name.to_s) { call.({ zone: "Bad/Zone" }) }
      assert_equal :zone, e.option, name.to_s
    end
  end

  def test_every_entry_point_rejects_a_bad_now_and_dst
    CALLS.each do |name, call|
      assert_equal :now, assert_raises(Acute::OptionError, name.to_s) { call.({ now: "tomorrow" }) }.option, name.to_s
      assert_equal :dst, assert_raises(Acute::OptionError, name.to_s) { call.({ dst: :nearest }) }.option, name.to_s
    end
  end

  def test_every_entry_point_but_cron_checks_the_other_options
    CALLS.except(:from_cron, :from_cron!).each do |name, call|
      assert_equal :locale, assert_raises(Acute::OptionError, name.to_s) { call.({ locale: "x" }) }.option, name.to_s
      assert_equal :context, assert_raises(Acute::OptionError, name.to_s) { call.({ context: :sideways }) }.option, name.to_s
    end
  end

  # Ruby's own error for an unknown keyword: an ArgumentError, as OptionError is, so one rescue serves both
  def test_every_entry_point_rejects_an_unknown_option
    CALLS.except(:tool).each do |name, call|
      e = assert_raises(ArgumentError, name.to_s) { call.({ bogus: 1 }) }
      assert_match(/unknown keyword: :bogus/, e.message, name.to_s)
    end
    assert_raises(ArgumentError) { Acute::Tool.new(bogus: 1) }
  end

  def test_extract_takes_no_strict_but_a_lenient_parser_still_extracts
    assert_raises(ArgumentError) { Acute.extract("see you tomorrow", **AT, strict: false) }
    assert_raises(ArgumentError) { PARSER.extract("see you tomorrow", strict: false) }
    assert_equal 1, Acute.with(**AT, strict: false).extract("see you tomorrow").mentions.size
  end

  def test_from_cron_takes_now_zone_and_dst_only
    on = ->(dst) { Acute::Rule.from_cron("30 2 * * *", **AT, dst:).each(after: Time.utc(2027, 3, 14)).first }
    assert_equal Time.new(2027, 3, 14, 1, 30, 0, "-05:00"), on.(:earlier)
    assert_equal Time.new(2027, 3, 14, 3, 30, 0, "-04:00"), on.(:later)
    assert_raises(ArgumentError) { Acute::Rule.from_cron("0 9 * * 1", locale: "en-GB") }
    # options are checked before the line is read
    assert_raises(Acute::OptionError) { Acute::Rule.from_cron("x" * 10_000, zone: "Bad/Zone") }
  end

  def test_a_result_is_frozen_and_shareable
    r = Acute.parse("at 9", **AT)
    assert_predicate r, :frozen?
    assert_predicate r.assumptions, :frozen?
    assert_predicate r.alternatives, :frozen?
    assert_equal r.time, r.time
    assert Ractor.shareable?(Ractor.make_shareable(Acute.parse("tomorrow 3pm", **AT, now: Time.utc(2026, 10, 17))))
  end

  def test_assumptions_and_mentions_are_frozen_values
    a = Acute.parse("at 9", **AT).assumptions.first
    assert_predicate a, :frozen?
    assert_equal %i[code rule message short], a.to_h.keys
    m = Acute.extract("see you tomorrow", **AT).mentions.first
    assert_predicate m, :frozen?
    assert_equal({ kind: :time, text: "tomorrow", offset: 8...16 }, m.to_h.except(:value))
    assert_raises(NoMethodError) { m.offset = 0...1 }
    assert_predicate Acute.extract("see you tomorrow", **AT), :frozen?
  end

  def test_date_is_the_local_date_of_the_start_at_any_grain
    assert_equal Date.new(2026, 10, 17), Acute.parse("4pm", **AT).date
    assert_equal Date.new(2026, 10, 18), Acute.parse("1am", **AT).date
    assert_equal Date.new(2026, 10, 18), Acute.parse("tomorrow 11pm", **AT, zone: "Asia/Tokyo").date
    r = Acute.parse("before friday", **AT)
    assert_nil r.begin
    assert_equal r.time.to_date, r.date
  end

  def test_internals_are_private_constants
    %i[Describe Verify Extract SKIPPED VAGUE_CODES ALSO_DURATION].each { refute_includes Acute.constants, _1 }
    assert_raises(NameError) { Acute::Describe }
    refute_includes Acute::Tool.constants, :PARSE_ERRORS
    refute_includes Acute::Rule.constants, :Cron
  end
end
