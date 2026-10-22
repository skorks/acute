require_relative "../test_helper"
require_relative "../schema_validator"

# The model reads every char of a tool result, so the tools leave out what the library's JSON repeats
class ToolCompactTest < Minitest::Test
  include SchemaValidator

  OPTS = { now: "2026-10-17T14:00", zone: NY }.freeze
  TOOL = Acute::Tool.new(**OPTS)
  CASES = Dir[File.expand_path("../cases/*.jsonl", __dir__)].flat_map { File.readlines(_1) }
  SEED = 20_261_021
  SAMPLE = 300
  SHORT = Acute::Assumption.for(:bare_hour_window).short

  def call(name, args, tool = TOOL) = tool.call(name, args).tap { assert_tool_valid(name, _1) }

  def test_a_reading_drops_the_echo_a_begin_equal_to_time_and_empty_lists
    assert_equal({ "kind" => "time", "time" => "2026-10-23T15:00:00-04:00", "end" => "2026-10-23T15:01:00-04:00",
                   "grain" => "minute", "zone" => NY }, call("parse", { "text" => "next friday at 3pm" }))
  end

  def test_a_begin_that_differs_from_time_is_kept
    morning = call("parse", { "text" => "saturday morning" })
    assert_equal "2026-10-24T06:00:00-04:00", morning["begin"]
    assert_equal "2026-10-17T06:00:00-04:00", morning.dig("alternatives", 0, "begin")
    before = call("parse", { "text" => "before saturday" })
    assert_equal [true, nil], [before.key?("begin"), before["begin"]]
    assert_nil before.dig("alternatives", 0).fetch("begin")
  end

  def test_an_extraction_drops_the_echo_and_what_each_mention_repeats
    assert_equal({ "kind" => "extraction", "remainder" => "lunch with Sam",
                   "mentions" => [{ "text" => "tomorrow at 1", "offset" => [15, 28],
                                    "value" => { "kind" => "time", "time" => "2026-10-18T13:00:00-04:00", "end" => "2026-10-18T13:01:00-04:00",
                                                 "grain" => "minute", "zone" => NY,
                                                 "assumptions" => [{ "code" => "bare_hour_window", "rule" => "D4", "message" => SHORT }],
                                                 "alternatives" => [{ "time" => "2026-10-18T01:00:00-04:00",
                                                                      "end" => "2026-10-18T01:01:00-04:00", "grain" => "minute" }] } },
                                  { "text" => "for an hour", "offset" => [29, 40],
                                    "value" => { "kind" => "duration", "parts" => { "hours" => 1 }, "iso8601" => "PT1H", "seconds" => 3600 } }] },
                 call("extract", { "text" => "lunch with Sam tomorrow at 1 for an hour" }))
  end

  def test_a_verdict_keeps_expected_only_when_it_does_not_hold
    assert_equal({ "kind" => "verdict", "status" => "match", "ok" => true, "message" => "The value matches the text: Fri 23 Oct, 3pm." },
                 call("verify", { "text" => "next friday at 3pm", "value" => "2026-10-23T15:00:00-04:00" }))
    mismatch = call("verify", { "text" => "next friday at 3pm", "value" => "2026-10-24T15:00:00-04:00" })
    assert_equal call("parse", { "text" => "next friday at 3pm" }), mismatch["expected"]
    refute mismatch.key?("text")
    unparsed = call("verify", { "text" => "flurb", "value" => "2026-10-23" })
    assert_equal [true, nil, ["flurb"]], [unparsed.key?("expected"), unparsed["expected"], unparsed["unread"]]
  end

  def test_now_drops_the_offset_its_now_ends_with
    now = call("now", {})
    refute now.key?("offset")
    assert_equal "2026-10-17T14:00:00-04:00", now["now"]
  end

  def test_a_failure_drops_unread_only_when_empty
    assert_equal({ "kind" => "failure", "code" => "too_long", "error" => "the text is longer than 512 bytes",
                   "position" => [0, 300] },
                 call("parse", { "text" => "é" * 300 }))
    assert_equal ["tomorow"], call("parse", { "text" => "tomorow" })["unread"]
  end

  def test_an_assumption_message_is_its_short_form_and_the_library_keeps_the_long_one
    short = [{ "code" => "bare_hour_window", "rule" => "D4", "message" => SHORT }]
    assert_equal short, call("parse", { "text" => "at 4" })["assumptions"]
    assert_equal short, call("verify", { "text" => "at 4", "value" => "2026-10-20" }).dig("expected", "assumptions")
    assert_equal Acute::Assumption.for(:bare_hour_window).message, Acute.parse("at 4", **OPTS).as_json.dig("assumptions", 0, "message")
  end

  def test_the_library_json_keeps_every_field
    assert_equal %w[kind text time begin end grain zone assumptions alternatives], Acute.parse("next friday at 3pm", **OPTS).as_json.keys
  end

  def test_tool_results_across_the_corpus_fit_the_compact_output_schemas
    CASES.sample(SAMPLE, random: Random.new(SEED)).each do |line|
      c = JSON.parse(line)
      tool = Acute::Tool.new(now: c["now"], zone: c["tz"])
      text = c["text"][0, 512]
      call("parse", { "text" => text }, tool)
      call("extract", { "text" => text }, tool)
      call("duration", { "text" => text }, tool)
      call("verify", { "text" => text, "value" => c.dig("expect", "time") || "2026-10-23" }, tool)
    end
  end
end
