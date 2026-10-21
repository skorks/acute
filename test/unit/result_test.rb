require_relative "../test_helper"
require "json"

class ResultTest < Minitest::Test
  def test_to_s
    assert_equal "Sun, Oct 18, 2026, 9am EDT", parse("tomorrow at 9am").to_s
    assert_equal "Sat, Oct 17, 2026, 4:30pm EDT", parse("4:30pm").to_s
    assert_equal "Sat, Oct 17, 2026, 4:30:15pm EDT", parse("4:30:15pm").to_s
    assert_equal "Sun, Oct 18, 2026, 12pm EDT", parse("noon").to_s
    assert_equal "Sat, Oct 17, 2026, all day", parse("today").to_s
    assert_equal "Sun, Nov 1, 2026, 3am EST", parse("tomorrow at 3am", now: "2026-10-31T14:00").to_s
  end

  def test_an_instant
    r = parse("4pm")
    assert_equal Time.new(2026, 10, 17, 16, 0, 0, "-04:00"), r.time
    assert_equal(-14_400, r.time.utc_offset)
    assert_equal r.time, r.begin
    assert_equal r.begin...r.end, r.range
    assert_equal "2026-10-17T16:00:00-04:00", r.iso8601
    assert_equal "America/New_York", r.zone
    assert_equal "4pm", r.text
    assert_nil r.date
    assert_predicate r, :instant?
    refute_predicate r, :span?
    refute_predicate r, :open?
    refute_predicate r, :ambiguous?
    assert_empty r.alternatives
  end

  def test_a_span
    r = parse("yesterday")
    assert_equal Date.new(2026, 10, 16), r.date
    assert_equal "2026-10-16T00:00:00-04:00/2026-10-17T00:00:00-04:00", r.iso8601
    assert_predicate r, :span?
    refute_predicate r, :instant?
  end

  def test_alternatives_are_results_without_assumptions
    r = parse("at 4")
    assert_predicate r, :ambiguous?
    alt = r.alternatives.first
    assert_kind_of Acute::Result, alt
    assert_equal "2026-10-18T04:00:00-04:00", alt.iso8601
    assert_empty alt.assumptions
    refute_predicate alt, :ambiguous?
  end

  def test_assumptions_carry_code_rule_and_message
    a = parse("at 4").assumptions.first
    assert_equal [:bare_hour_window, "D4"], [a.code, a.rule]
    assert_match(%r{am/pm}, a.message)
    assert_predicate parse("at 4").assumptions, :frozen?
  end

  # Tools give the model the short form instead of message, so each must keep its gist in far fewer chars
  def test_every_assumption_has_a_short_form_shorter_than_its_message
    Acute::Assumption::ALL.each_value do |a|
      assert_operator a.short.length, :<, a.message.length, a.code
      assert_operator a.short.length, :<=, 60, a.code
    end
  end

  def test_to_h_and_to_json
    r = parse("at 4")
    expected = {
      kind: "time", text: "at 4", time: "2026-10-17T16:00:00-04:00", begin: "2026-10-17T16:00:00-04:00",
      end: "2026-10-17T16:01:00-04:00", grain: "minute", zone: "America/New_York",
      assumptions: [{ code: "bare_hour_window", rule: "D4", message: Acute::Assumption.for(:bare_hour_window).message }],
      alternatives: [{ time: "2026-10-18T04:00:00-04:00", begin: "2026-10-18T04:00:00-04:00",
                       end: "2026-10-18T04:01:00-04:00", grain: "minute" }]
    }
    assert_equal expected, r.to_h
    assert_equal JSON.parse(JSON.generate(expected)), JSON.parse(r.to_json)
    assert_equal JSON.parse(JSON.generate(expected)), r.as_json
  end

  def test_an_open_end_is_null_in_json
    assert_nil JSON.parse(parse("after 3pm").to_json)["end"]
  end

  def test_inspect
    assert_equal "#<Acute::Result Sat, Oct 17, 2026, 4pm EDT>", parse("4pm").inspect
  end
end
