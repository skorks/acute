require "optparse"
require_relative "../acute"

module Acute
  # exe/acute: one phrase from the arguments, or one per line from stdin (D45)
  # @api private
  class CLI
    CLOCK_GRAINS = %i[second minute hour].freeze
    # the library's DST hints name its Ruby option; the command's name its flag
    DST_HINTS = { dst_skipped_time: "--dst earlier, later or compatible picks an instant for it",
                  dst_repeated_time: "--dst earlier or later picks one" }.freeze

    def self.run(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr) = new(stdin, stdout, stderr).run(argv)

    def initialize(stdin, stdout, stderr)
      @stdin = stdin
      @out = stdout
      @err = stderr
      @json = false
      @next = nil
      @options = {}
    end

    def run(argv)
      return mcp(argv.drop(1)) if argv.first == "mcp"
      args = options.parse(argv)
      return say(@say) if @say
      @parser = Acute.with(**@options)
      return phrase(args.join(" ")) if args.any?
      return usage if @stdin.tty?
      @out.sync = true
      @stdin.each_line.map { _1.b.strip.empty? || line(_1.chomp) }.all? ? 0 : 1
    rescue OptionParser::ParseError, ArgumentError => e
      @err.puts "acute: #{Acute.visible(e.message.scrub)}"
      2
    end

    private

    def options
      OptionParser.new do |o|
        o.banner = "Usage: acute [options] PHRASE\n       acute [options] < phrases.txt   (one per line)\n       " \
                   "acute mcp [options]             (an MCP server: acute mcp --help)"
        o.on("--json", "Print JSON (JSON Lines for stdin)") { @json = true }
        o.on("--next N", Integer, "A rule's first N occurrences, 1–#{Rule::MAX_OCCURRENCES}") do |n|
          raise OptionParser::InvalidArgument, n.to_s unless (1..Rule::MAX_OCCURRENCES).cover?(n)
          @next = n
        end
        o.on("--now TIME", "Now, in ISO 8601 (default: the clock)") { @options[:now] = _1 }
        o.on("--zone ZONE", "IANA zone or offset (default: the system's)") { @options[:zone] = _1 }
        o.on("--locale LOCALE", "en-US, en-GB, en-AU… (default: from the zone)") { @options[:locale] = _1 }
        o.on("--context CONTEXT", %w[future past], "future or past") { @options[:context] = _1.to_sym }
        o.on("--week-start DAY", %w[sunday monday], "sunday or monday") { @options[:week_start] = _1.to_sym }
        o.on("--hemisphere SIDE", %w[north south], "north or south, for seasons") { @options[:hemisphere] = _1.to_sym }
        o.on("--fiscal-year-start MONTH", Integer, "1–12") { @options[:fiscal_year_start] = _1 }
        o.on("--lenient", "Skip unknown words (strict: false)") { @options[:strict] = false }
        o.on("--dst POLICY", %w[compatible earlier later reject], "compatible, earlier, later or reject") { @options[:dst] = _1.to_sym }
        o.on("--holidays REGION", "A holidays-gem region, such as us (needs the gem)") { @options[:holidays] = _1 }
        o.on("--year-bias YEARS", Integer, "Two-digit years: the 100 from this many years ago (default 50)") { @options[:year_bias] = _1 }
        o.on("-v", "--version") { @say = Acute::VERSION }
        o.on("-h", "--help") { @say = o.to_s }
      end
    end

    # The options an operator fixes for every call. now is always the clock; the model may pass zone per call.
    def mcp(argv)
      options = {}
      parser = OptionParser.new do |o|
        o.banner = "Usage: acute mcp [options]\n" \
                   "Serves acute's tools to an MCP client over stdio: one JSON-RPC message per line."
        o.on("--zone ZONE", "IANA zone or offset when a call names none (default: the system's)") { options[:zone] = _1 }
        o.on("--locale LOCALE", "en-US, en-GB, en-AU… (default: from the zone)") { options[:locale] = _1 }
        o.on("--context CONTEXT", %w[future past], "Default for calls that give none: future or past") { options[:context] = _1.to_sym }
        o.on("--week-start DAY", %w[sunday monday], "sunday or monday") { options[:week_start] = _1.to_sym }
        o.on("-h", "--help") { return say(o.to_s) }
      end
      extra = parser.parse(argv)
      raise OptionParser::NeedlessArgument, extra.join(" ") if extra.any?
      require_relative "mcp"
      server = MCP.new(Tool.new(**options), log: @err)
      @stdin.binmode
      server.serve(@stdin, @out)
      0
    end

    def say(text)
      @out.puts text
      0
    end

    def usage
      @err.puts options
      2
    end

    # A single phrase that fails exits 1 with parse!'s reason
    def phrase(text)
      value = reading(text)
      return show(value) || 0 if value
      @parser.parse!(text)
    rescue ParseError => e
      @json ? @out.puts(failure(e, text)) : @err.puts(["acute: #{e.message}", *hint(e)].join("\n"))
      1
    end

    def line(text)
      value = reading(text)
      return show(value, batch: true) || true if value
      @parser.parse!(text)
    rescue ParseError => e
      @out.puts @json ? failure(e, text) : ["error: #{e.message}", *hint(e)].join("   ")
      false
    end

    # schema/failure.json, as the tools give it, plus the input line, which a tool never echoes. Like the tools, a
    # position over the whole phrase is left out.
    def failure(e, text)
      text = text.dup.force_encoding(Encoding::UTF_8).scrub
      json = { kind: "failure", text:, code: e.code.to_s, error: e.message }
      json[:position] = [e.position.begin, e.position.end] unless whole?(e.position, text)
      json[:hint] = flag_hint(e) if e.hint
      JSON.generate(json)
    end

    def flag_hint(e) = DST_HINTS.fetch(e.code, e.hint)

    def hint(e) = e.hint && "hint: #{flag_hint(e)}"

    def whole?(span, text) = text[0...span.begin].strip.empty? && text[span.end..].to_s.strip.empty?

    # --next asks for a rule, so a phrase that isn't one fails with recurrence!'s reason
    def reading(text) = @next ? @parser.recurrence!(text) : @parser.read(text)

    # A rule is several lines, joined into one for stdin's one line per phrase
    def show(value, batch: false)
      return @out.puts(@json ? value.to_json : echo(value)) unless Rule === value
      at = @next && occurrences(value)
      return @out.puts(at ? value.to_h.merge(next: at.map(&:iso8601)).to_json : value.to_json) if @json
      lines = [value.to_s, *value.to_ical.lines(chomp: true)]
      lines << "cron: #{value.cron} (CRON_TZ=#{value.zone})" if value.cron
      lines.concat(at.map { occurrence(_1, value.zone) }) if at
      @out.puts batch ? lines.join("   ") : lines
    end

    # The rule's first n occurrences, DTSTART's included: the Date before it starts the search
    def occurrences(rule) = rule.next!(@next, after: rule.dtstart.to_date - 1)

    def occurrence(at, zone)
      text = @parser.describe(at, zone: zone, style: :calendar)
      Time === at ? "#{text} #{Zone.for(zone).abbreviation_at(at.to_i)}" : text
    end

    # "Fri, Oct 23, 3pm EDT   (also: Fri, Oct 16, 3pm)"
    def echo(value)
      return @parser.describe(value) if Duration === value
      text = described(value)
      return text unless value.ambiguous?
      said = abbreviation(value)
      "#{text}   (also: #{value.alternatives.map { described(_1, said) }.join("; ")})"
    end

    # A time of day names its zone, unless describe already did or the echo already has
    def described(r, said = nil)
      text = @parser.describe(r, zone: r.zone, style: :calendar)
      abbr = abbreviation(r)
      return text if abbr.nil? || abbr == said || text.end_with?(abbr) || text.match?(/[+-]\d\d:\d\d\z/)
      "#{text} #{abbr}"
    end

    def abbreviation(r) = CLOCK_GRAINS.include?(r.grain) ? Zone.for(r.zone).abbreviation_at(r.time.to_i) : nil
  end
end
