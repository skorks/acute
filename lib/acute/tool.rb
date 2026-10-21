require_relative "../acute"
require_relative "tool/compact"

module Acute
  # The tools an app's LLM calls, for any SDK. The app fixes the options at construction; the input schemas in
  # schema/tools/ leave them out, so the model can't set them. What the model sends is a boundary: anything wrong
  # with it comes back as a failure value. T5: no string the model reads as prose quotes its input; text
  # that needs pointing at goes in unread, which the schema marks as data.
  class Tool
    NAMES = %w[parse duration extract verify describe now].freeze
    SCHEMAS = Ractor.make_shareable(NAMES.to_h do |name|
      [name, JSON.parse(File.read(File.expand_path("../../schema/tools/#{name}.json", __dir__)))]
    end)
    UNREAD = 5
    UNREAD_LENGTH = 60
    PARSE_ERRORS = {
      unknown_word: "acute couldn't read the words in unread",
      invalid_date: "the date or time in unread doesn't exist",
      incomplete: "the phrase is incomplete",
      conflict: "the words in unread don't fit with the rest of the phrase",
      dst_skipped_time: "the time in unread is skipped as the clocks go forward: ask the user for a time either side of it",
      dst_repeated_time: "the time in unread happens twice as the clocks go back: ask the user which they meant",
      business_day_limit: "more than #{Resolve::Period::LIMIT} business days is too many to count",
      too_long: "the text is longer than #{MAX_LENGTH} bytes",
      invalid_encoding: "the text is not valid UTF-8"
    }.freeze
    OPTION_ERRORS = { value: "value must be an ISO 8601 time or date" }.freeze
    POINTED = %i[invalid_date conflict dst_skipped_time dst_repeated_time].freeze
    ISO_DURATION = /\AP(?!\z)(?:(\d+(?:\.\d+)?)Y)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)W)?(?:(\d+(?:\.\d+)?)D)?
                   (?:T(?=\d)(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?\z/x
    ISO_PARTS = %i[years months weeks days hours minutes seconds].freeze
    ISO_TIME = /\A\d{4}-\d\d-\d\d(?:[T ]|\z)/

    attr_reader :parser, :prefix

    def initialize(parser = nil, prefix: "", **options)
      raise ArgumentError, "expected a parser Acute.with made, got #{parser.class}" unless parser.nil? || Parser === parser
      # Tool names may hold letters, digits, _ and -, and no more than 64 of them
      unless String === prefix && prefix.valid_encoding? && prefix.match?(/\A[A-Za-z0-9_-]{0,56}\z/)
        raise OptionError.new("prefix: must be up to 56 letters, digits, _ or -", option: :prefix, value: prefix)
      end
      @parser = (parser || Acute).with(**options)
      @prefix = -prefix
      freeze
    end

    def definitions(format = :anthropic)
      NAMES.map do |name|
        schema = SCHEMAS[name]
        full = "#{@prefix}#{name}"
        description = schema["description"].gsub(/\{(\w+)\}/) { "#{@prefix}#{$1}" }
        input = schema.except("$schema", "$id", "title", "description")
        case format
        when :anthropic then { name: full, description: description, input_schema: input }
        when :openai then { type: "function", function: { name: full, description: description, parameters: input } }
        else raise ArgumentError, "format must be :anthropic or :openai, got #{format.inspect}"
        end
      end
    end

    # arguments as an SDK gives them: a Hash with string or symbol keys, or OpenAI's JSON string
    def call(name, arguments) = Compact.(answer(name, arguments))

    def inspect = "#<Acute::Tool #{"prefix: #{@prefix.inspect} " unless @prefix.empty?}#{@parser.inspect}>"

    private

    def answer(name, arguments)
      tool = name.delete_prefix(@prefix) if String === name && name.valid_encoding? && name.start_with?(@prefix)
      return failure(:unknown_tool, "there is no tool by the name in unread", [name]) unless NAMES.include?(tool)
      args = arguments(arguments) or return failure(:invalid_argument, "the arguments must be a JSON object")
      wrong = check(SCHEMAS[tool], args) and return wrong
      run(tool, args)
    rescue ParseError => e
      parse_failure(e, args["text"])
    rescue OptionError => e
      failure(:invalid_argument, OPTION_ERRORS.fetch(e.option, "#{e.option} isn't one acute can use"), [e.value])
    end

    def arguments(given)
      given = JSON.parse(given) if String === given
      # A null is an argument left out, as some SDKs send every optional one
      given.to_h { |k, v| [k.to_s, v] }.compact if Hash === given
    rescue JSON::ParserError, EncodingError
      nil
    end

    def check(schema, args)
      props = schema["properties"]
      unknown = args.keys - props.keys
      return failure(:unknown_argument, "there are no arguments by the names in unread", unknown) if unknown.any?
      missing = schema["required"].to_a - args.keys
      return failure(:missing_argument, "#{missing.join(" and ")} #{missing.size == 1 ? "is" : "are"} required") if missing.any?
      args.each do |key, value|
        prop = props[key]
        error =
          if prop["enum"] then "#{key} must be one of #{prop["enum"].join(", ")}" unless prop["enum"].include?(value)
          elsif !(String === value) then "#{key} must be a string"
          elsif !value.valid_encoding? then "#{key} is not valid UTF-8"
          elsif value.length > prop["maxLength"] then "#{key} is longer than #{prop["maxLength"]} characters"
          end
        return failure(:invalid_argument, error) if error
      end
      nil
    end

    def run(tool, args)
      text = args["text"]
      context = args.key?("context") ? { context: args["context"].to_sym } : {}
      case tool
      when "parse" then @parser.parse!(text, **context).as_json
      when "duration" then @parser.duration!(text).as_json
      when "extract" then @parser.extract(text, **context).as_json
      when "verify" then verify(text, args["value"], context)
      when "describe" then describe(args["value"], args.fetch("style", "relative").to_sym)
      else now
      end
    end

    def verify(text, value, context)
      @parser.verify(text, value, **context, &:tool_verdict).as_json.merge("unread" => [])
    rescue ParseError => e
      failed = parse_failure(e, text)
      message = "The text can't be read: #{failed["error"]}. Ask the user to rephrase."
      Verdict.new(text, :unparsed, message, nil).as_json.merge("unread" => failed["unread"])
    end

    def describe(value, style)
      target = duration(value) || (@parser.parse(value, strict: true) if value.match?(ISO_TIME))
      return failure(:invalid_argument, "value must be an ISO 8601 time, date or duration", [value]) unless target
      { "kind" => "description", "text" => @parser.describe(target, style: style) }
    end

    def duration(value)
      m = ISO_DURATION.match(value) or return
      Duration.new(**ISO_PARTS.zip(m.captures).to_h { |part, n| [part, n && (n.include?(".") ? n.to_r : n.to_i)] })
    end

    def now
      ctx = Context.new(@parser.options[:now], @parser.options[:zone], :future)
      zone = ctx.zone
      at = ctx.now
      change = zone.next_change(at)
      local = Time.at(at, in: zone.offset_at(at))
      { "kind" => "now", "now" => local.strftime("%FT%T%:z"), "weekday" => local.strftime("%A"), "zone" => zone.name,
        "offset" => local.strftime("%:z"), "dst" => !change.nil? && zone.offset_at(at) > zone.offset_at(change),
        "next_change" => change && Time.at(change, in: zone.offset_at(change)).strftime("%FT%T%:z") }
    end

    def parse_failure(e, text)
      unread = e.code == :unknown_word ? e.unknown : POINTED.include?(e.code) ? [text[e.position]] : []
      failure(e.code, Explain.reason(e, text) || PARSE_ERRORS.fetch(e.code), unread)
    end

    def failure(code, error, unread = [])
      words = unread.first(UNREAD).map { _1.to_s.dup.force_encoding(Encoding::UTF_8).scrub[0, UNREAD_LENGTH] }
      { "kind" => "failure", "code" => code.to_s, "error" => error, "unread" => words }
    end
  end
end
