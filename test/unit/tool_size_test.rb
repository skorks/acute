require_relative "../test_helper"
require "stringio"
require_relative "../../lib/acute/mcp"

# The model reads every char of these on every request, so growth must be a deliberate change to a cap
class ToolSizeTest < Minitest::Test
  CAPS = {
    definitions: 3_000,
    tools_list: 12_500,
    parse_result: 150,
    extract_result: 640,
    descriptions: { "parse" => 260, "duration" => 150, "extract" => 210, "verify" => 210, "describe" => 135, "now" => 170 }
  }.freeze

  TOOL = Acute::Tool.new(zone: "UTC")
  NEW_YORK = Acute::Tool.new(now: "2026-10-17T14:00", zone: "America/New_York")

  def test_definitions_fit_their_cap
    assert_operator JSON.generate(TOOL.definitions).length, :<=, CAPS[:definitions]
  end

  def test_each_description_fits_its_cap
    TOOL.definitions.each { assert_operator _1[:description].length, :<=, CAPS[:descriptions].fetch(_1[:name]), _1[:name] }
  end

  def test_the_mcp_tools_list_reply_fits_its_cap
    lines = [{ jsonrpc: "2.0", id: 1, method: "initialize",
               params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "t", version: "1" } } },
             { jsonrpc: "2.0", id: 2, method: "tools/list" }].map { JSON.generate(_1) }
    out = StringIO.new
    Acute::MCP.new(TOOL).serve(StringIO.new(lines.join("\n") << "\n"), out)
    reply = out.string.lines.find { JSON.parse(_1)["id"] == 2 }
    assert_equal 6, JSON.parse(reply).dig("result", "tools").size
    assert_operator reply.chomp.length, :<=, CAPS[:tools_list]
  end

  def test_typical_results_fit_their_caps
    assert_operator JSON.generate(NEW_YORK.call("parse", { "text" => "next friday at 3pm" })).length, :<=, CAPS[:parse_result]
    assert_operator JSON.generate(NEW_YORK.call("extract", { "text" => "lunch with Sam tomorrow at 1 for an hour" })).length, :<=, CAPS[:extract_result]
  end
end
