require_relative "../test_helper"
require "json"

# The published schemas describe what to_json gives. The validator covers only the keywords they use.
class SchemaTest < Minitest::Test
  DIR = File.expand_path("../../schema", __dir__)
  TYPES = { "object" => Hash, "array" => Array, "string" => String, "number" => Numeric, "null" => NilClass }.freeze
  ISO = /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d\z/

  def schema(name) = JSON.parse(File.read(File.join(DIR, "#{name}.json")))

  def check(value, node, root, path = "$")
    node = root.dig(*node["$ref"].delete_prefix("#/").split("/")) if node["$ref"]
    errors = []
    types = Array(node["type"])
    errors << "#{path}: #{value.inspect} is not #{types.join("/")}" if types.any? && types.none? { TYPES.fetch(_1) === value }
    errors << "#{path}: #{value.inspect} is not #{node["const"]}" if node.key?("const") && value != node["const"]
    errors << "#{path}: #{value.inspect} is not one of #{node["enum"]}" if node["enum"] && !node["enum"].include?(value)
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

  def test_the_validator_catches_a_wrong_shape
    root = schema("result")
    bad = JSON.parse(parse("at 4").to_json).merge("grain" => "fortnight", "extra" => 1)
    bad.delete("zone")
    assert_equal 3, check(bad, root, root).size
  end
end
