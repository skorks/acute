require_relative "../test_helper"
require "json"
require_relative "../../lib/acute/tool"

# The published schemas describe what to_json gives. The validator covers only the keywords they use.
class SchemaTest < Minitest::Test
  DIR = File.expand_path("../../schema", __dir__)
  TYPES = { "object" => Hash, "array" => Array, "string" => String, "number" => Numeric, "integer" => Integer, "null" => NilClass,
            "boolean" => [true, false] }.freeze
  ISO = /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?[+-]\d\d:\d\d\z/

  def schema(name) = JSON.parse(File.read(File.join(DIR, "#{name}.json")))

  def check(value, node, root, path = "$")
    if (ref = node["$ref"])
      return check(value, root = schema(ref.delete_suffix(".json")), root, path) unless ref.start_with?("#")
      node = root.dig(*ref.delete_prefix("#/").split("/"))
    end
    errors = []
    types = Array(node["type"])
    errors << "#{path}: #{value.inspect} is not #{types.join("/")}" if types.any? && types.none? { Array(TYPES.fetch(_1)).any? { |t| t === value } }
    if node["oneOf"] && node["oneOf"].count { check(value, _1, root, path).empty? } != 1
      errors << "#{path}: #{value.inspect} is not exactly one of the oneOf schemas"
    end
    errors << "#{path}: #{value.inspect} is not #{node["const"]}" if node.key?("const") && value != node["const"]
    errors << "#{path}: #{value.inspect} is not one of #{node["enum"]}" if node["enum"] && !node["enum"].include?(value)
    errors << "#{path}: #{value.inspect} is longer than #{node["maxLength"]}" if node["maxLength"] && String === value && value.length > node["maxLength"]
    errors << "#{path}: has more than #{node["maxItems"]} items" if node["maxItems"] && Array === value && value.size > node["maxItems"]
    errors << "#{path}: #{value.inspect} is not a date-time" if node["format"] == "date-time" && String === value && !ISO.match?(value)
    if Hash === value
      (node["required"] || []).each { |k| errors << "#{path}: #{k} missing" unless value.key?(k) }
      props = node["properties"] || {}
      value.each do |k, v|
        if props[k] then errors.concat(check(v, props[k], root, "#{path}.#{k}"))
        elsif node["additionalProperties"] == false then errors << "#{path}: #{k} is not in the schema"
        end
      end
    end
    value.each_with_index { |v, i| errors.concat(check(v, node["items"], root, "#{path}[#{i}]")) } if Array === value && node["items"]
    errors
  end

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

  def test_verdicts
    [["next friday", "2026-10-23"], ["this weekend", "2026-10-18"], ["this friday", "2026-10-16"],
     ["in two weeks", "2026-10-30"], ["a banana", "2026-10-30"]].each do |text, value|
      assert_valid "verdict", Acute.verify(text, value, now: "2026-10-17T14:00", zone: NY)
    end
  end

  def test_extractions
    ["lunch tomorrow at 1 for an hour", "nothing to see", "from 9 to 5 on friday, then 2 weeks off"].each do |text|
      assert_valid "extraction", Acute.extract(text, now: "2026-10-17T14:00", zone: NY)
    end
  end

  # Every tool's result, its answers and its failures, against the schema of what it returns
  def test_tool_results
    tool = Acute::Tool.new(now: "2026-10-17T14:00", zone: NY)
    {
      "result" => [["parse", { "text" => "next friday at 3" }], ["parse", { "text" => "friday", "context" => "past" }]],
      "duration" => [["duration", { "text" => "an hour and a half" }]],
      "extraction" => [["extract", { "text" => "lunch tomorrow at 1 for an hour" }]],
      "verdict" => [["verify", { "text" => "tomorrow", "value" => "2026-10-18" }], ["verify", { "text" => "a banana", "value" => "2026-10-18" }]],
      "description" => [["describe", { "value" => "2026-10-23T15:00:00-04:00" }], ["describe", { "value" => "PT90M" }]],
      "now" => [["now", {}], ["now", {}, Acute::Tool.new(zone: "Asia/Kolkata")]],
      "failure" => [["parse", { "text" => "flurb " * 20 }], ["parse", { "text" => "june 31" }], ["nope", {}], ["now", { "a" => 1 }],
                    ["verify", { "text" => "tomorrow" }], ["describe", { "value" => "x" * 64 }], ["duration", { "text" => "next friday" }]]
    }.each do |schema, calls|
      calls.each do |name, args, t = tool|
        result = t.call(name, args)
        assert_valid schema, result
      end
    end
  end

  def test_the_validator_catches_a_wrong_shape
    root = schema("result")
    bad = JSON.parse(parse("at 4").to_json).merge("grain" => "fortnight", "extra" => 1)
    bad.delete("zone")
    assert_equal 3, check(bad, root, root).size
    root = schema("verdict")
    bad = JSON.parse(Acute.verify("tomorrow", "2026-10-18", now: "2026-10-17T14:00", zone: NY).to_json)
    bad["ok"] = "yes"
    bad["expected"]["grain"] = "fortnight"
    assert_equal 2, check(bad, root, root).size
  end
end
