require "json"
require_relative "../lib/acute/mcp"

# A validator for the keywords acute's schemas use, and the tools' compact output schemas to check results against
module SchemaValidator
  def self.output(name) = (@outputs ||= {})[name] ||= Acute::MCP.output_schema(Acute::MCP::OUTPUTS.key?(name) ? name : "parse")

  DIR = File.expand_path("../schema", __dir__)
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

  def assert_tool_valid(name, result)
    root = SchemaValidator.output(name.to_s[/[a-z]*\z/])
    assert_empty check(JSON.parse(JSON.generate(result)), root, root), "#{name}: #{result.inspect}"
  end
end
