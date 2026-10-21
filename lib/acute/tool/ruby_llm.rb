begin
  require "ruby_llm"
rescue LoadError => e
  raise LoadError, "acute/tool/ruby_llm needs the ruby_llm gem; add it to your Gemfile (#{e.message})"
end
require_relative "../tool"

module Acute
  class Tool
    # One RubyLLM::Tool per tool, bound to this one's options: chat.with_tools(*Acute::Tool.new(zone: user.zone).ruby_llm)
    def ruby_llm = definitions.map { RubyLLMTool.new(self, _1) }

    # RubyLLM reads a tool's name, description and parameters_schema from the instance, and validates the
    # arguments against execute's keywords before calling it, so execute takes any and Acute::Tool checks them
    class RubyLLMTool < ::RubyLLM::Tool
      attr_reader :name, :description, :parameters_schema

      def initialize(tool, definition)
        super()
        @tool = tool
        @name = definition[:name]
        @description = definition[:description]
        @parameters_schema = definition[:input_schema]
      end

      def execute(**arguments) = @tool.call(@name, arguments)
    end
  end
end
