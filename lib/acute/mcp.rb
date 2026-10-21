require "json"
require_relative "tool"

module Acute
  # acute mcp: Acute::Tool as an MCP server, one JSON-RPC message per line of stdin and stdout. Dual-era: a request
  # whose _meta names a modern version is served statelessly as that version; an initialize opens a legacy session.
  # T5: no error message quotes the input. The tool's own failures put it in unread.
  class MCP
    MODERN = %w[2026-07-28].freeze
    LEGACY = %w[2025-11-25 2025-06-18].freeze
    VERSION_KEY = "io.modelcontextprotocol/protocolVersion".freeze
    LINE_LIMIT = 64 * 1024
    PARSE_ERROR = -32_700
    INVALID_REQUEST = -32_600
    METHOD_NOT_FOUND = -32_601
    INVALID_PARAMS = -32_602
    INTERNAL_ERROR = -32_603
    UNSUPPORTED_VERSION = -32_022
    ZONED = %w[parse extract verify describe now].freeze
    ZONE_LENGTH = 64
    ZONE = {
      "type" => "string", "maxLength" => ZONE_LENGTH,
      "description" => "Only if the user names a zone not their own (\"3pm London time\"): IANA or UTC offset"
    }.freeze
    ZONE_ERROR = "zone must be an IANA time zone or a UTC offset such as +05:30".freeze
    OUTPUTS = { "parse" => "result", "duration" => "duration", "extract" => "extraction", "verify" => "verdict",
                "describe" => "description", "now" => "now" }.freeze
    ANNOTATIONS = %w[title description examples $comment].freeze
    NAMED = %w[properties $defs].freeze
    SCHEMAS = File.expand_path("../../schema", __dir__)

    Refusal = Class.new(StandardError) do
      attr_reader :code, :data

      def initialize(code, message, data = nil)
        super(message)
        @code = code
        @data = data
      end
    end

    # A tool's own schema or a failure, in one self-contained document: the schemas it refers to are inlined, so a
    # client resolves everything without fetching
    def self.output_schema(name)
      defs = {}
      hoist = lambda do |file|
        return if defs.key?(file)
        defs[file] = nil
        schema = JSON.parse(File.read(File.join(SCHEMAS, "#{file}.json")))
        defs.merge!(schema.delete("$defs") || {})
        defs[file] = localise(schema.except("$schema", "$id"), hoist)
      end
      own = OUTPUTS.fetch(name)
      [own, "failure"].each(&hoist)
      defs = bare(Tool::Compact.schema(defs), names: true)
      root = [own, "failure"].map { { "$ref" => "#/$defs/#{_1}" } }
      uses = JSON.generate([root, defs]).scan(%r{"#/\$defs/(\w+)"}).flatten.tally
      schema = { "type" => "object", "oneOf" => inline(root, defs, uses) }
      shared = defs.select { uses.fetch(_1, 0) > 1 }.transform_values { inline(_1, defs, uses) }
      shared.empty? ? schema : schema.merge("$defs" => shared)
    end

    # The model's host pays for every char of a listing, and the annotations are for people: validation needs only
    # the structure. Under properties and $defs the keys are names, never annotations.
    def self.bare(node, names: false)
      case node
      when Hash
        node.each_with_object({}) do |(key, value), out|
          out[key] = bare(value, names: !names && NAMED.include?(key)) if names || !ANNOTATIONS.include?(key)
        end
      when Array then node.map { bare(_1) }
      else node
      end
    end

    # A schema referred to once is written in place; only those referred to more than once stay in $defs
    def self.inline(node, defs, uses)
      case node
      when Hash
        ref = node["$ref"]&.delete_prefix("#/$defs/")
        return inline(defs.fetch(ref), defs, uses).merge(node.except("$ref")) if ref && uses[ref] == 1
        node.transform_values { inline(_1, defs, uses) }
      when Array then node.map { inline(_1, defs, uses) }
      else node
      end
    end

    def self.localise(node, hoist)
      case node
      when Hash
        node.to_h do |key, value|
          next [key, localise(value, hoist)] unless key == "$ref" && value.end_with?(".json")
          file = value.delete_suffix(".json")
          hoist.(file)
          [key, "#/$defs/#{file}"]
        end
      when Array then node.map { localise(_1, hoist) }
      else node
      end
    end

    def initialize(tool = Tool.new, log: nil)
      @tool = tool
      @log = log
      @tools = tool.definitions.map { listing(_1) }
    end

    def serve(input, output)
      while (line = read(input))
        next if String === line && line.strip.empty?
        reply = line == :oversize ? error(nil, INVALID_REQUEST, "Invalid request: the line is too long") : handle(line)
        next unless reply
        output.write("#{JSON.generate(reply)}\n")
        output.flush
      end
    end

    private

    def handle(line)
      line = line.dup.force_encoding(Encoding::UTF_8)
      return error(nil, PARSE_ERROR, "Parse error") unless line.valid_encoding?
      respond(JSON.parse(line))
    rescue JSON::ParserError
      error(nil, PARSE_ERROR, "Parse error")
    end

    def read(input)
      line = input.gets("\n", LINE_LIMIT + 1) or return
      return line if line.end_with?("\n") || line.bytesize <= LINE_LIMIT
      while (rest = input.gets("\n", LINE_LIMIT))
        break if rest.end_with?("\n")
      end
      :oversize
    end

    def respond(message)
      return error(nil, INVALID_REQUEST, "Invalid request") unless Hash === message
      # Notifications get no reply, whatever they are
      return if !message.key?("id") && String === message["method"]
      id = message["id"]
      return error(nil, INVALID_REQUEST, "Invalid request") unless String === id || Integer === id
      params = message.fetch("params", {})
      unless message["jsonrpc"] == "2.0" && String === message["method"] && Hash === params
        return error(id, INVALID_REQUEST, "Invalid request")
      end
      { "jsonrpc" => "2.0", "id" => id, "result" => dispatch(message["method"], params) }
    rescue Refusal => e
      error(id, e.code, e.message, e.data)
    rescue StandardError => e
      @log&.puts "acute mcp: #{e.class} at #{e.backtrace&.first}"
      error(id, INTERNAL_ERROR, "Internal error")
    end

    def dispatch(method, params)
      meta = params["_meta"]
      version = meta[VERSION_KEY] if Hash === meta && meta.key?(VERSION_KEY)
      if version && !MODERN.include?(version)
        raise Refusal.new(UNSUPPORTED_VERSION, "Unsupported protocol version", { "supported" => MODERN })
      end
      result =
        case method
        when "initialize" then opening(params["protocolVersion"])
        when "server/discover" then discovery
        when "ping" then {}
        when "tools/list" then { "tools" => @tools }
        when "tools/call" then call(params["name"], params.fetch("arguments", {}))
        else raise Refusal.new(METHOD_NOT_FOUND, "Method not found")
        end
      version ? result.merge("resultType" => "complete") : result
    end

    def server_info = { "name" => "acute", "version" => VERSION }

    # A legacy client asking for a version this server doesn't speak gets the latest legacy one: the modern
    # versions have no initialize
    def opening(asked)
      { "protocolVersion" => LEGACY.include?(asked) ? asked : LEGACY.first, "capabilities" => { "tools" => {} },
        "serverInfo" => server_info }
    end

    def discovery
      { "supportedVersions" => MODERN, "capabilities" => { "tools" => {} },
        "_meta" => { "io.modelcontextprotocol/serverInfo" => server_info } }
    end

    def call(name, args)
      raise Refusal.new(INVALID_PARAMS, "Unknown tool") unless Tool::NAMES.include?(name)
      raise Refusal.new(INVALID_PARAMS, "Invalid params: arguments must be an object") unless Hash === args
      zone = args["zone"] if ZONED.include?(name)
      value = zone.nil? ? @tool.call(name, args) : zoned(zone)&.call(name, args.except("zone")) || zone_failure(zone)
      { "content" => [{ "type" => "text", "text" => JSON.generate(value) }], "structuredContent" => value,
        "isError" => value["kind"] == "failure" }
    end

    def zoned(zone)
      return unless String === zone && zone.length <= ZONE_LENGTH
      Tool.new(@tool.parser, zone: zone)
    rescue OptionError
      nil
    end

    def zone_failure(zone)
      unread = String === zone ? [zone[0, Tool::UNREAD_LENGTH]] : []
      Tool::Compact.({ "kind" => "failure", "code" => "invalid_argument", "error" => ZONE_ERROR, "unread" => unread })
    end

    def listing(definition)
      name = definition[:name]
      input = definition[:input_schema]
      input = input.merge("properties" => input["properties"].merge("zone" => ZONE)) if ZONED.include?(name)
      { "name" => name, "description" => definition[:description], "inputSchema" => input,
        "outputSchema" => self.class.output_schema(name) }
    end

    def error(id, code, message, data = nil)
      { "jsonrpc" => "2.0", "id" => id, "error" => { "code" => code, "message" => message, "data" => data }.compact }
    end
  end
end
