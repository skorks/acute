require_relative "../test_helper"
require_relative "../../lib/acute/tool/ruby_llm"
require "open3"

class ToolRubyLLMTest < Minitest::Test
  OPTS = { now: "2026-10-17T14:00", zone: NY }.freeze
  TOOL = Acute::Tool.new(**OPTS, prefix: "acute_")
  LIB = File.expand_path("../../lib", __dir__)

  def test_ruby_llm_sends_the_tools_as_acute_defines_them
    tools = TOOL.ruby_llm
    assert(tools.all?(RubyLLM::Tool))
    assert_equal(TOOL.definitions(:anthropic), tools.map { RubyLLM::Protocols::Anthropic::Tools.function_for(_1) })
    assert_equal(TOOL.definitions(:openai), tools.map { RubyLLM::Protocols::ChatCompletions::Tools.tool_for(_1) })
  end

  # Chat#execute_tool is where ruby_llm runs the tool call a model's reply asks for
  def test_a_chat_runs_each_tool_as_a_model_calls_it
    chat = RubyLLM.context { _1.openai_api_key = "offline" }.chat(model: "gpt-4.1-nano", provider: :openai, assume_model_exists: true)
    chat.with_tools(*TOOL.ruby_llm)
    assert_equal(Acute::Tool::NAMES.map { :"acute_#{_1}" }, chat.tools.keys)
    run = ->(name, args) { chat.send(:execute_tool, RubyLLM::ToolCall.new(id: "call_1", name: name, arguments: args)) }
    assert_equal TOOL.call("acute_parse", { "text" => "next friday at 3" }), run.("acute_parse", { "text" => "next friday at 3" })
    assert_equal TOOL.call("acute_verify", { "text" => "tomorrow", "value" => "2026-10-18" }),
                 run.("acute_verify", { "text" => "tomorrow", "value" => "2026-10-18" })
    assert_equal "unknown_argument", run.("acute_parse", { "text" => "today", "zone" => "UTC" })["code"]
    assert_equal "missing_argument", run.("acute_parse", {})["code"]
    assert_equal "now", run.("acute_now", {})["kind"]
    assert_equal TOOL.call("acute_recurrence", { "text" => "every monday at 9" }), run.("acute_recurrence", { "text" => "every monday at 9" })
  end

  def test_each_acute_tool_gives_its_own_instances
    kolkata = Acute::Tool.new(zone: "Asia/Kolkata").ruby_llm.find { _1.name == "parse" }
    assert_equal "Asia/Kolkata", kolkata.call(text: "today")["zone"]
    assert_equal NY, TOOL.ruby_llm.first.call(text: "today")["zone"]
  end

  def test_requiring_it_loads_the_tool_or_says_ruby_llm_is_missing
    out, status = Open3.capture2e(RbConfig.ruby, "-I", LIB, "-e", 'require "acute/tool/ruby_llm"; print Acute::Tool.new(zone: "UTC").ruby_llm.size')
    assert_predicate status, :success?, out
    assert_equal "7", out
    hide = 'Object.prepend(Module.new { def require(name) = name == "ruby_llm" ? raise(LoadError, "cannot load such file -- ruby_llm") : super })'
    out, status = Open3.capture2e(RbConfig.ruby, "-I", LIB, "-e", "#{hide}; require 'acute/tool/ruby_llm'")
    refute_predicate status, :success?
    assert_includes out, "acute/tool/ruby_llm needs the ruby_llm gem; add it to your Gemfile (cannot load such file -- ruby_llm) (LoadError)"
  end
end
