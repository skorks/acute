require_relative "../test_helper"
require "stringio"
require_relative "../../lib/acute/tool"
require_relative "../../lib/acute/mcp"

# Each hard limit at its value and one past it. The rest are tested beside their rule: parse's 512 bytes in
# errors_test, R19's occurrences and steps in rule_occurrences_test, business days in business_limit_test,
# --next in cli_test, the MCP line in mcp_test, the tool's text and unread in tool_test.
class LimitsTest < Minitest::Test
  OPTS = { now: "2026-10-22T12:00", zone: "America/New_York" }.freeze

  def padded(text, size) = text + (" " * (size - text.bytesize))

  def test_every_text_entry_point_takes_512_bytes_and_not_513
    at, past = [Acute::MAX_LENGTH, Acute::MAX_LENGTH + 1].map { |n| ->(text) { padded(text, n) } }
    assert Acute.duration(at.("3 days"))
    assert_nil Acute.duration(past.("3 days"))
    assert_equal :too_long, assert_raises(Acute::ParseError) { Acute.duration!(past.("3 days")) }.code
    assert Acute.recurrence(at.("every day"), **OPTS)
    assert_nil Acute.recurrence(past.("every day"), **OPTS)
    assert_equal :too_long, assert_raises(Acute::ParseError) { Acute.recurrence!(past.("every day"), **OPTS) }.code
    assert_kind_of Acute::Rule, Acute.read(at.("every day"), **OPTS)
    assert_kind_of Acute::Result, Acute.read(at.("tomorrow"), **OPTS)
    assert_nil Acute.read(past.("tomorrow"), **OPTS)
    cron = "#{"0," * 251}59 * * * *"
    assert_equal 512, cron.bytesize
    assert Acute::Rule.from_cron(cron)
    assert_equal :too_long, assert_raises(Acute::ParseError) { Acute::Rule.from_cron!("#{"0," * 252}9 * * * *") }.code
  end

  def test_a_number_keeps_nine_digits_and_counts_up_to_fifteen
    lex = ->(digits) { Acute::Lexer.lex(digits)[1, 2] }
    assert_equal [999_999_999, 9], lex.("9" * 9)
    assert_equal [999_999_999, 10], lex.("9" * 10)
    assert_equal [999_999_999, 15], lex.("9" * 15)
    assert_equal [999_999_999, 15], lex.("9" * 16) # the count never spills into the flags above it
    assert_equal "every 999999999 days", Acute.recurrence!("every #{"9" * 10} days", **OPTS).to_s
  end

  # T13: only a valid zone is cached, so the cache holds at most every shipped name and fixed offset
  def test_t13_the_zone_cache_takes_offsets_to_23_59_and_no_further
    zones = -> { Acute::Zone.instance_variable_get(:@zones) }
    %w[+23:59 -23:59 +00:00].each { |z| assert Acute.parse("3pm", **OPTS, zone: z) }
    before = zones.().size
    %w[+23:59 +24:00 -24:00 +23:60 +2359 +23:59:00].each do |z|
      Acute.parse("3pm", **OPTS, zone: z) rescue Acute::OptionError # rubocop:disable Style/RescueModifier
    end
    assert_equal before, zones.().size
    ceiling = Acute::Tables::ZONES.size + Acute::Tables::ZONE_LINKS.size + 2 * (24 * 60 * 2 - 1)
    assert_operator zones.().size, :<=, ceiling
  end

  def test_the_tools_take_their_lengths_and_not_one_more
    tool = Acute::Tool.new(**OPTS)
    assert_equal "extraction", tool.call("extract", { "text" => "a" * 4096 })["kind"]
    assert_equal "text is longer than 4096 characters", tool.call("extract", { "text" => "a" * 4097 })["error"]
    assert_equal "value must be an ISO 8601 time, date or duration", tool.call("describe", { "value" => "x" * 64 })["error"]
    assert_equal "value is longer than 64 characters", tool.call("describe", { "value" => "x" * 65 })["error"]
  end

  # T18: JSON nested 100 deep is read, deeper is a parse error (json 3.1 lets one more level through)
  def test_t18_mcp_reads_json_nested_100_deep_and_no_deeper
    reply = lambda do |depth|
      line = JSON.generate({ jsonrpc: "2.0", id: 1, method: "ping", params: { x: "PLACE" } }).sub('"PLACE"', "#{"[" * (depth - 2)}#{"]" * (depth - 2)}")
      out = StringIO.new
      Acute::MCP.new.serve(StringIO.new("#{line}\n"), out)
      JSON.parse(out.string)
    end
    assert_equal({}, reply.(100)["result"])
    assert_equal(-32_700, reply.(102).dig("error", "code"))
  end
end
