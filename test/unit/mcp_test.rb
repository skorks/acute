require_relative "../test_helper"
require "open3"
require "time"
require "stringio"
require_relative "../../lib/acute/cli"
require_relative "../../lib/acute/mcp"
require_relative "../schema_validator"

class MCPTest < Minitest::Test
  include SchemaValidator

  EXE = File.expand_path("../../exe/acute", __dir__)
  TOOL = Acute::Tool.new(now: "2026-10-17T14:00", zone: "America/New_York")
  PROSE = %w[error message description].freeze
  MODERN = { "io.modelcontextprotocol/protocolVersion" => "2026-07-28" }.freeze

  def exchange(*messages, tool: TOOL, log: nil)
    input = messages.map { String === _1 ? _1 : JSON.generate(_1) }.join("\n")
    out = StringIO.new
    Acute::MCP.new(tool, log: log).serve(StringIO.new("#{input}\n".b), out)
    out.string.lines.map { JSON.parse(_1) }
  end

  def request(method, params = nil, id: 1) = { jsonrpc: "2.0", id: id, method: method, params: params }.compact

  def call(name, arguments, tool: TOOL)
    result = exchange(request("tools/call", { name: name, arguments: arguments }), tool: tool)[0]["result"]
    result&.tap { assert_tool_valid(name, _1["structuredContent"]) }
  end

  def error_of(*messages) = exchange(*messages).map { _1["error"]&.slice("code", "message") }

  def test_initialize_answers_the_version_asked_for_when_it_speaks_it
    reply = exchange(request("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "t", version: "1" } }))[0]
    assert_equal({ "protocolVersion" => "2025-06-18", "capabilities" => { "tools" => {} },
                   "serverInfo" => { "name" => "acute", "version" => Acute::VERSION } }, reply["result"])
    assert_equal 1, reply["id"]
    %w[1999-01-01 2026-07-28].each do |asked|
      assert_equal "2025-11-25", exchange(request("initialize", { protocolVersion: asked }))[0].dig("result", "protocolVersion")
    end
  end

  def test_a_modern_request_is_served_statelessly
    tools = exchange(request("tools/list", { _meta: MODERN }))[0]["result"]
    assert_equal "complete", tools["resultType"]
    assert_equal(Acute::Tool::NAMES, tools["tools"].map { _1["name"] })
    discover = exchange(request("server/discover", { _meta: MODERN }))[0]["result"]
    assert_equal ["2026-07-28"], discover["supportedVersions"]
    assert_equal "acute", discover.dig("_meta", "io.modelcontextprotocol/serverInfo", "name")
    old = exchange(request("ping", { _meta: { "io.modelcontextprotocol/protocolVersion" => "1900-01-01" } }))[0]["error"]
    assert_equal({ "code" => -32_022, "message" => "Unsupported protocol version", "data" => { "supported" => ["2026-07-28"] } }, old)
  end

  def test_notifications_get_no_reply
    replies = exchange({ jsonrpc: "2.0", method: "notifications/initialized" }, { jsonrpc: "2.0", method: "no/such" },
                       { method: "notifications/cancelled", params: 3 }, request("ping", id: "p"))
    assert_equal [{ "jsonrpc" => "2.0", "id" => "p", "result" => {} }], replies
  end

  def test_tools_list_takes_the_tool_definitions_and_adds_zone_where_times_resolve
    listed = exchange(request("tools/list"))[0].dig("result", "tools")
    TOOL.definitions.zip(listed) do |definition, tool|
      assert_equal definition[:description], tool["description"]
      zone = tool["inputSchema"]["properties"].delete("zone")
      assert_equal definition[:input_schema], tool["inputSchema"]
      assert_equal(definition[:name] != "duration", !zone.nil?, definition[:name])
    end
  end

  def test_output_schemas_are_self_contained_and_admit_a_failure
    exchange(request("tools/list"))[0].dig("result", "tools").each do |tool|
      schema = tool["outputSchema"]
      assert_equal "object", schema["type"]
      assert_equal "failure", schema["oneOf"][1].dig("properties", "kind", "const")
      refs(schema).each { assert schema.fetch("$defs", {}).key?(_1.delete_prefix("#/$defs/")), "#{tool["name"]}: #{_1}" }
      schema.fetch("$defs", {}).each_key { assert_operator refs(schema).count("#/$defs/#{_1}"), :>, 1, "#{tool["name"]}: #{_1}" }
      refute_match(/"(description|title|examples|\$comment)":/, JSON.generate(schema), tool["name"])
    end
  end

  def test_structured_content_conforms_to_the_output_schema
    schemas = exchange(request("tools/list"))[0].dig("result", "tools").to_h { [_1["name"], _1["outputSchema"]] }
    calls = { "parse" => { "text" => "tomorrow at 3pm" }, "duration" => { "text" => "2 hours" }, "recurrence" => { "text" => "every monday at 9" },
              "extract" => { "text" => "lunch at noon" }, "verify" => { "text" => "noon", "value" => "2026-10-18T12:00:00-04:00" },
              "describe" => { "value" => "2026-10-18T15:00:00-04:00" }, "now" => {} }
    calls.each do |name, arguments|
      [arguments, arguments.merge("nope" => "x")].each do |args|
        result = call(name, args)
        assert conforms?(schemas[name], result["structuredContent"]), "#{name} #{args}"
        assert_equal result["structuredContent"], JSON.parse(result.dig("content", 0, "text"))
        assert_equal "text", result.dig("content", 0, "type")
      end
    end
  end

  def test_parses_through_the_tool
    result = call("parse", { "text" => "tomorrow at 3pm" })
    assert_equal "2026-10-18T15:00:00-04:00", result.dig("structuredContent", "time")
    refute result["isError"]
  end

  def test_recurrence_through_the_tool_in_the_zone_asked_for
    result = call("recurrence", { "text" => "every monday at 9", "zone" => "Europe/London" })
    refute result["isError"]
    assert_equal ["Europe/London", "2026-10-19T09:00:00+01:00", "0 9 * * 1"], result["structuredContent"].values_at("zone", "dtstart", "cron")
    assert_equal 3, result.dig("structuredContent", "next").size
    assert call("recurrence", { "text" => "next friday" })["isError"]
  end

  def test_a_tool_failure_is_an_error_result
    result = call("parse", { "text" => "tomorow at 3pm" })
    assert result["isError"]
    assert_equal({ "kind" => "failure", "code" => "unknown_word", "error" => "acute couldn't read the words in unread",
                   "unread" => ["tomorow"], "position" => [0, 7], "hint" => "did you mean \"tomorrow\"?" }, result["structuredContent"])
  end

  def test_zone_is_an_argument_under_mcp
    assert_equal "2026-10-18T15:00:00+09:00", call("parse", { "text" => "3pm", "zone" => "Asia/Tokyo" }).dig("structuredContent", "time")
    assert_equal "Asia/Tokyo", call("now", { "zone" => "Asia/Tokyo" }).dig("structuredContent", "zone")
    assert_equal "America/New_York", call("now", { "zone" => nil }).dig("structuredContent", "zone")
    assert_equal "unknown_argument", call("duration", { "text" => "2h", "zone" => "UTC" }).dig("structuredContent", "code")
  end

  def test_a_bad_zone_is_an_invalid_argument_that_does_not_quote_it
    failures = ["Mars/Olympus_Mons", 5, "x" * 65].map { call("parse", { "text" => "3pm", "zone" => _1 })["structuredContent"] }
    failures.each do |failure|
      assert_equal "invalid_argument", failure["code"]
      assert_equal Acute::MCP::ZONE_ERROR, failure["error"]
    end
    assert_equal ["Mars/Olympus_Mons"], call("now", { "zone" => "Mars/Olympus_Mons" }).dig("structuredContent", "unread")
  end

  def test_the_library_tool_never_lets_the_model_set_zone_or_now
    assert_equal "unknown_argument", TOOL.call("parse", { "text" => "3pm", "zone" => "UTC" })["code"]
    assert_equal "unknown_argument", call("now", { "now" => "2020-01-01T00:00" }).dig("structuredContent", "code")
    clock = Time.iso8601(call("now", {}, tool: Acute::Tool.new(zone: "UTC")).dig("structuredContent", "now"))
    assert_in_delta Time.now, clock, 5
  end

  def test_protocol_errors_never_echo_the_input
    assert_equal [{ "code" => -32_700, "message" => "Parse error" }] * 3, error_of("{nope", "\xff\"".b, "[" * 200)
    assert_equal [{ "code" => -32_601, "message" => "Method not found" }], error_of(request("nope/secret"))
    assert_equal [{ "code" => -32_602, "message" => "Unknown tool" }] * 2,
                 error_of(request("tools/call", { name: "secret" }), request("tools/call", { arguments: {} }))
    assert_equal(-32_602, error_of(request("tools/call", { name: "now", arguments: [] }))[0]["code"])
    assert_nil exchange("{nope")[0]["id"]
  end

  def test_a_prefixed_tool_is_listed_and_called_by_its_prefixed_names
    tool = Acute::Tool.new(prefix: "acute_", now: "2026-10-17T14:00", zone: "America/New_York")
    listed, parsed, zoned, bare = exchange(request("tools/list"),
                                           request("tools/call", { name: "acute_parse", arguments: { text: "noon" } }),
                                           request("tools/call", { name: "acute_now", arguments: { zone: "UTC" } }),
                                           request("tools/call", { name: "parse", arguments: { text: "noon" } }), tool: tool)
    tools = listed["result"]["tools"]
    assert_equal(Acute::Tool::NAMES.map { "acute_#{_1}" }, tools.map { _1["name"] })
    assert tools.find { _1["name"] == "acute_parse" }["inputSchema"]["properties"].key?("zone")
    assert_equal "2026-10-18T12:00:00-04:00", parsed["result"]["structuredContent"]["time"]
    assert_equal "+00:00", zoned["result"]["structuredContent"]["now"][-6..]
    assert_equal({ "code" => -32_602, "message" => "Unknown tool" }, bare["error"].slice("code", "message"))
  end

  def test_invalid_requests
    invalid = [[request("ping")], { id: 1, method: "ping" }, { jsonrpc: "1.0", id: 1, method: "ping" }, { jsonrpc: "2.0", id: nil, method: "ping" },
               request("ping", id: 1.5), request("ping", id: {}), { jsonrpc: "2.0", id: 1, method: 7 }, request("ping", [1]), 3, {}]
    replies = exchange(*invalid)
    assert_equal([-32_600] * invalid.size, replies.map { _1.dig("error", "code") })
    assert_equal([nil, 1, 1, nil, nil, nil, 1, 1, nil, nil], replies.map { _1["id"] })
  end

  def test_an_oversize_line_is_refused_and_the_server_keeps_serving
    long = JSON.generate(request("tools/call", { name: "parse", arguments: { text: "a" * Acute::MCP::LINE_LIMIT } }))
    replies = exchange(long, request("ping", id: 2))
    assert_equal([[nil, -32_600], [2, nil]], replies.map { [_1["id"], _1.dig("error", "code")] })
    exact = JSON.generate(request("ping", id: 3)).then { _1.sub("{", "{#{" " * (Acute::MCP::LINE_LIMIT - _1.bytesize)}") }
    assert_equal([3], exchange(exact).map { _1["id"] })
  end

  # T18: what a model or a client can put in a line under the cap is a JSON-RPC error or a tool failure, quickly
  def test_t18_hostile_json_under_the_line_cap
    call = ->(args) { %({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"parse","arguments":#{args}}}) }
    lines = {
      "[" * 60_000 => -32_700, "#{'{"a":' * 10_000}1#{"}" * 10_000}" => -32_700,
      call.(%({"text":"tomorrow \\ud800"})) => -32_700, call.(%({"text":"tomorrow","zone":"UTC\\udc00"})) => -32_700,
      call.(%({"text":"tomorrow \xff"})) => -32_700, call.(%({"text":"tomorrow\x00"})) => -32_700,
      %({"jsonrpc":"2.0","id":1e999999999,"method":"ping"}) => -32_600,
      call.(%({"text":1e999999999})) => "invalid_argument", call.(%({"text":#{"[" * 95}#{"]" * 95}})) => "invalid_argument",
      call.(%({"__proto__":{},"constructor":{"prototype":1},"text":"friday"})) => "unknown_argument",
      call.(%({"text":"friday","zone":"../../../../etc/passwd"})) => "invalid_argument"
    }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    replies = exchange(*lines.keys)
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1
    got = replies.map { _1.dig("error", "code") || _1.dig("result", "structuredContent", "code") }
    assert_equal lines.values, got
    big = "9" * 60_000
    assert_equal Integer(big), exchange(%({"jsonrpc":"2.0","id":#{big},"method":"ping"}))[0]["id"]
  end

  # T20: a long session keeps no more than the zone cache
  def test_t20_many_zoned_calls_leave_no_objects_behind
    # Zones other tests already load: a Ractor test relies on some staying out of the cache
    zones = %w[UTC Europe/London Asia/Tokyo America/Chicago +05:30 -03:00 +14:00]
    lines = lambda do |from|
      (from...(from + 2_000)).map do |i|
        request("tools/call", { name: "parse", arguments: { text: "in #{i} minutes", zone: zones[i % zones.size] } }, id: i)
      end
    end
    server = Acute::MCP.new(TOOL)
    session = ->(from) { server.serve(StringIO.new("#{lines.(from).map { JSON.generate(_1) }.join("\n")}\n"), StringIO.new) }
    session.(0)
    GC.start
    before = ObjectSpace.count_objects.then { _1[:TOTAL] - _1[:FREE] }
    session.(2_000)
    GC.start
    assert_operator ObjectSpace.count_objects.then { _1[:TOTAL] - _1[:FREE] } - before, :<, 1_000
  end

  def test_an_exception_in_a_call_is_an_internal_error
    broken = Class.new(Acute::Tool) { def call(*) = raise("secret") }.new(zone: "UTC")
    log = StringIO.new
    replies = exchange(request("tools/call", { name: "now", arguments: {} }), request("ping", id: 2), tool: broken, log: log)
    assert_equal([{ "code" => -32_603, "message" => "Internal error" }, nil], replies.map { _1["error"] })
    refute_includes log.string, "secret"
    assert_includes log.string, "RuntimeError"
  end

  def test_eof_ends_the_session
    out = StringIO.new
    Acute::MCP.new(TOOL).serve(StringIO.new(""), out)
    assert_empty out.string
    Acute::MCP.new(TOOL).serve(StringIO.new("\n \n#{JSON.generate(request("ping"))}"), out)
    assert_equal([{ "jsonrpc" => "2.0", "id" => 1, "result" => {} }], out.string.lines.map { JSON.parse(_1) })
  end

  # T5: text from the arguments goes in unread, never in prose
  def test_t5_no_reply_prose_quotes_the_input
    mark = "Zq9x"
    messages = [request("#{mark}/x"), request("tools/call", { name: mark }), request("initialize", { protocolVersion: mark }),
                request("ping", { _meta: { "io.modelcontextprotocol/protocolVersion" => mark } }), "{#{mark}"]
    Acute::Tool::NAMES.each do |name|
      [{ "text" => mark, "value" => mark }, { "text" => "3pm #{mark}", "zone" => mark }, { mark => mark },
       { "text" => "#{mark} at 25:00", "value" => "#{mark}T", "style" => mark }].each do |args|
        messages << request("tools/call", { name: name, arguments: args })
      end
    end
    exchange(*messages).each do |reply|
      prose(reply).each { refute_includes _1, mark, reply.to_s }
      text = reply.dig("result", "content", 0, "text")
      prose(JSON.parse(text)).each { refute_includes _1, mark, text } if text
    end
  end

  def test_fuzz_never_crashes_or_writes_a_non_json_line
    rng = Random.new(20_261_021)
    frames = [request("ping"), request("tools/call", { name: "parse", arguments: { text: "next friday 3pm" } }),
              request("tools/call", { name: "verify", arguments: { text: "noon", value: "2026-10-18", zone: "UTC" } }),
              request("initialize", { protocolVersion: "2025-11-25" })].map { JSON.generate(_1) }
    lines = Array.new(600) do
      case rng.rand(3)
      when 0 then rng.bytes(rng.rand(0..80)).delete("\n")
      when 1 then frames.sample(random: rng).b.tap { |s| rng.rand(1..4).times { s.setbyte(rng.rand(s.bytesize), rng.rand(256)) } }.delete("\n")
      else frames.sample(random: rng).then { _1[0, rng.rand(_1.size + 1)] }
      end
    end
    out = StringIO.new
    Acute::MCP.new(TOOL).serve(StringIO.new(lines.join("\n").b), out)
    out.string.each_line do |line|
      reply = JSON.parse(line)
      assert_equal "2.0", reply["jsonrpc"]
      assert_equal 1, [reply.key?("result"), reply.key?("error")].count(true)
    end
    assert_operator out.string.lines.size, :>, 300
  end

  def test_the_cli_serves_with_the_operators_options
    out = StringIO.new
    status = Acute::CLI.run(%w[mcp --zone Asia/Tokyo --week-start monday --context past --locale en-GB],
                            stdin: StringIO.new(JSON.generate(request("tools/call", { name: "now", arguments: {} }))), stdout: out, stderr: StringIO.new)
    assert_equal 0, status
    assert_equal "Asia/Tokyo", JSON.parse(out.string).dig("result", "structuredContent", "zone")
    help = StringIO.new
    assert_equal 0, Acute::CLI.run(%w[mcp --help], stdout: help)
    %w[--zone --locale --context --week-start].each { assert_includes help.string, _1 }
    refute_includes help.string, "--now"
    err = StringIO.new
    assert_equal 2, Acute::CLI.run(%w[mcp extra], stderr: err)
    assert_equal 2, Acute::CLI.run(%w[mcp --now 2026-10-17], stderr: err)
  end

  def test_end_to_end_over_stdio
    input = [request("initialize", { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "t", version: "1" } }),
             { jsonrpc: "2.0", method: "notifications/initialized" }, request("tools/list", id: 2),
             request("tools/call", { name: "parse", arguments: { text: "tomorrow at 3pm", zone: "America/New_York" } }, id: 3)]
    out, err, status = Open3.capture3(RbConfig.ruby, EXE, "mcp", "--zone", "UTC", stdin_data: input.map { "#{JSON.generate(_1)}\n" }.join)
    assert_predicate status, :success?, err
    replies = out.lines.map { JSON.parse(_1) }
    assert_equal([1, 2, 3], replies.map { _1["id"] })
    assert_equal(Acute::Tool::NAMES, replies[1].dig("result", "tools").map { _1["name"] })
    expected = Acute.parse("tomorrow at 3pm", zone: "America/New_York").begin.iso8601
    assert_equal expected, replies[2].dig("result", "structuredContent", "time")
  end

  private

  def refs(node)
    case node
    when Hash then node.flat_map { |k, v| k == "$ref" ? [v] : refs(v) }
    when Array then node.flat_map { refs(_1) }
    else []
    end
  end

  def prose(node)
    case node
    when Hash then node.flat_map { |k, v| PROSE.include?(k) && String === v ? [v] : prose(v) }
    when Array then node.flat_map { prose(_1) }
    else []
    end
  end

  # The top level of one oneOf branch: its kind, its required keys, and no others
  def conforms?(schema, value)
    schema["oneOf"].any? do |b|
      kind = b.dig("properties", "kind")
      (kind.nil? || [kind["const"], *kind["enum"]].include?(value["kind"])) && b["required"].all? { value.key?(_1) } &&
        (b["additionalProperties"] != false || (value.keys - b["properties"].keys).empty?)
    end
  end
end
