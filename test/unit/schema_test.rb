require_relative "../test_helper"
require "json"
require "stringio"
require_relative "../schema_validator"

# The published schemas describe what to_json gives. The validator covers only the keywords they use.
class SchemaTest < Minitest::Test
  include SchemaValidator

  def assert_valid(name, object)
    root = schema(name)
    assert_empty check(JSON.parse(object.to_json), root, root), object.inspect
  end

  def test_results
    ["at 4", "tomorrow", "tonight", "after 3pm", "before friday", "next friday", "this weekend", "the 80s",
     "summer", "Q3", "1530 hrs", "next 3 days", "2026-10-23T14:30:00.5Z", "4pm EST"].each do |text|
      assert_valid "result", parse(text)
    end
    assert_valid "result", Acute.parse("tomorrow", now: "2026-10-17T14:00")
  end

  def test_durations
    ["1h30m", "1 month", "123.45 sec", "5 business days", "2 weeks", "two and a half years"].each do |text|
      assert_valid "duration", Acute.duration(text)
    end
  end

  def test_rules
    ["every weekday at 9am", "every monday except november 2", "every 30 minutes until 5pm", "monthly for a year"].each do |text|
      assert_valid "rule", Acute.recurrence(text, now: "2026-10-17T14:00", zone: NY)
    end
  end

  def test_verdicts
    [["next friday", "2026-10-23"], ["this weekend", "2026-10-18"], ["this friday", "2026-10-16"],
     ["in two weeks", "2026-10-30"], ["a banana", "2026-10-30"]].each do |text, value|
      assert_valid "verdict", Acute.verify(text, value, now: "2026-10-17T14:00", zone: NY)
    end
  end

  def test_extractions
    ["lunch tomorrow at 1 for an hour", "nothing to see", "from 9 to 5 on friday, then 2 weeks off",
     "standup every weekday at 9:30"].each do |text|
      assert_valid "extraction", Acute.extract(text, now: "2026-10-17T14:00", zone: NY)
    end
  end

  # Every tool's result, its answers and its failures, against the schema of what it returns
  def test_tool_results
    tool = Acute::Tool.new(now: "2026-10-17T14:00", zone: NY)
    {
      "result" => [["parse", { "text" => "next friday at 3" }], ["parse", { "text" => "friday", "context" => "past" }]],
      "duration" => [["duration", { "text" => "an hour and a half" }]],
      "rule" => [["recurrence", { "text" => "every weekday at 9am" }], ["recurrence", { "text" => "every other tuesday except nov 3" }]],
      "extraction" => [["extract", { "text" => "lunch tomorrow at 1 for an hour" }], ["extract", { "text" => "standup every weekday at 9:30" }]],
      "verdict" => [["verify", { "text" => "tomorrow", "value" => "2026-10-18" }], ["verify", { "text" => "a banana", "value" => "2026-10-18" }]],
      "description" => [["describe", { "value" => "2026-10-23T15:00:00-04:00" }], ["describe", { "value" => "PT90M" }]],
      "now" => [["now", {}], ["now", {}, Acute::Tool.new(zone: "Asia/Kolkata")]],
      "failure" => [["parse", { "text" => "flurb " * 20 }], ["parse", { "text" => "june 31" }], ["nope", {}], ["now", { "a" => 1 }],
                    ["verify", { "text" => "tomorrow" }], ["describe", { "value" => "x" * 64 }], ["duration", { "text" => "next friday" }]]
    }.each do |schema, calls|
      calls.each do |name, args, t = tool|
        result = t.call(name, args)
        assert_equal schema, result["kind"] == "time" ? "result" : result["kind"], name
        assert_tool_valid name, result
      end
    end
  end

  def test_the_validator_catches_a_wrong_shape
    root = schema("result")
    bad = JSON.parse(parse("at 4").to_json).merge("grain" => 7)
    bad.delete("zone")
    assert_equal 2, check(bad, root, root).size
    root = schema("verdict")
    bad = JSON.parse(Acute.verify("tomorrow", "2026-10-18", now: "2026-10-17T14:00", zone: NY).to_json)
    bad["ok"] = "yes"
    bad["expected"]["time"] = nil
    assert_equal 2, check(bad, root, root).size
  end

  # The output schemas are open: a later version may add fields, codes and grains, and a reader built on 1.0's must
  # still accept them
  def test_new_fields_and_values_validate
    later = { "result" => JSON.parse(parse("at 4").to_json).merge("grain" => "fortnight", "extra" => 1),
              "failure" => { "kind" => "failure", "code" => "unknown_future", "error" => "x", "extra" => [] },
              "verdict" => JSON.parse(Acute.verify("tomorrow", "2026-10-18", now: "2026-10-17T14:00", zone: NY).to_json)
                               .merge("status" => "close", "extra" => true) }
    later.each { |name, json| assert_empty check(json, schema(name), schema(name)), name }
    tool = SchemaValidator.output("parse")
    %w[result failure].each { assert_empty check(Acute::Tool::Compact.(later[_1]), tool, tool), _1 }
  end

  def test_a_cli_failure_matches_the_schema
    require_relative "../../lib/acute/cli"
    out = StringIO.new
    Acute::CLI.run(%w[--json --zone UTC], stdin: StringIO.new("next fridya\njune 31\n"), stdout: out, stderr: StringIO.new)
    root = schema("failure")
    out.string.lines.each { assert_empty check(JSON.parse(_1), root, root), _1 }
  end

  # Each $id resolves to the schema as released: the tag is v + the version, so a version bump moves them all
  def test_every_id_names_this_version
    Dir[File.join(SchemaValidator::DIR, "**/*.json")].each do |path|
      name = path.delete_prefix("#{SchemaValidator::DIR}/")
      assert_equal "https://raw.githubusercontent.com/skorks/acute/v#{Acute::VERSION}/schema/#{name}", JSON.parse(File.read(path))["$id"]
    end
  end
end
