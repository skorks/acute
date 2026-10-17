require "optparse"
require_relative "../acute"

module Acute
  # exe/acute: one phrase from the arguments, or one per line from stdin (D45)
  class CLI
    CLOCK_GRAINS = %i[second minute hour].freeze

    def self.run(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr) = new(stdin, stdout, stderr).run(argv)

    def initialize(stdin, stdout, stderr)
      @stdin = stdin
      @out = stdout
      @err = stderr
      @json = false
      @options = {}
    end

    def run(argv)
      args = options.parse(argv)
      return say(@say) if @say
      @parser = Acute.with(**@options)
      return phrase(args.join(" ")) if args.any?
      return usage if @stdin.tty?
      @out.sync = true
      @stdin.each_line.map { line(_1.chomp) }.all? ? 0 : 1
    rescue OptionParser::ParseError, ArgumentError => e
      @err.puts "acute: #{e.message}"
      2
    end

    private

    def options
      OptionParser.new do |o|
        o.banner = "Usage: acute [options] PHRASE\n       acute [options] < phrases.txt   (one per line)"
        o.on("--json", "Print JSON (JSON Lines for stdin)") { @json = true }
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
      value = @parser.read(text)
      return show(value) || 0 if value
      @parser.parse!(text)
    rescue ParseError => e
      @err.puts "acute: #{e.message}"
      1
    end

    def line(text)
      value = @parser.read(text)
      return show(value) || true if value
      @parser.parse!(text)
    rescue ParseError => e
      @out.puts @json ? { kind: "error", text: text, code: e.code.to_s, message: e.message }.to_json : "error: #{e.message}"
      false
    end

    def show(value)
      @out.puts @json ? value.to_json : echo(value)
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
