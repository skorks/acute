require_relative "../test_helper"
require "stringio"
require_relative "../../lib/acute/cli"
require_relative "../../lib/acute/tool"
require_relative "../../lib/acute/mcp"

# T6, T2, T24, T26: hostile inputs up to the 512-byte limit, through every public entry point, each call
# within a ceiling of wall time and of objects allocated. Seeded, so the same inputs every run.
#   ACUTE_WORST=report ruby test/unit/worst_case_test.rb   prints the worst call per entry point
class WorstCaseTest < Minitest::Test
  NOW = Time.new(2026, 10, 22, 12, 0, 0, "-04:00")
  ZONE = "America/New_York".freeze
  SEED = 20_261_022

  FRAGMENTS = ["and", "except", "every", "every other", "the 3rd of the", "3rd", "third", "1st", "twenty first", "9",
               "999999999", "12", "3pm", "4:30", "noon", "midnight", "tomorrow", "next", "last", "this", "friday",
               "fridays", "christmas", "thanksgiving", "easter", "EST", "America/New_York", "UTC+5", "+05:30", "in 3 days",
               "3 days ago", "in 9999 business days", "from", "to", "until", "between", "through", "-", "/", ":", ".",
               ",", "of", "at", "on", "the", "week", "month", "year", "morning", "early", "late", "mid", "q4",
               "2026-10-22", "10/22/2026", "20261022T153000", "times", "for", "a", "an", "half", "quarter", "past",
               "before", "after", "weekday", "weekend", "monday through friday", "except holidays", "daily", "weekly",
               "nineteen ninety", "twenty", "hundred", "'26", "90's", "@", "+", "1.5", "1/2", "*", "*/5", "0-59"].freeze
  SEPARATORS = [" ", " and ", ", ", ""].freeze
  TOOLS = %w[parse recurrence verify].freeze
  SUFFIX = { 1 => "st", 2 => "nd", 3 => "rd", 21 => "st", 22 => "nd", 23 => "rd", 31 => "st" }.freeze
  # Rules that do expand, and as often or as far apart as R19 lets them
  RULES = ["every second", "every minute until december 31 9999", "every feb 29 at 3pm", "every 999999999 seconds",
           "the 31st of every month", "every day 999999999 times", "every 5th monday", "every other week on friday",
           "every #{(1..31).map { "#{_1}#{SUFFIX.fetch(_1, "th")}" }.join(", ")} of the month",
           "every monday, tuesday, wednesday, thursday, friday, saturday and sunday at #{(1..11).map { "#{_1}am" }.join(", ")} and noon"].freeze
  CRONS = ["* * * * *", "0-59/1 0-23 1-31 1-12 0-7", "#{(0..59).to_a.join(",")} * 29 2 *", "0 0 31 2 *", "0 0 30 2 1",
           "*/7 */5 */3 */2 */4", "59 23 31 12 *", "#{"1," * 120}1 * * * *"].freeze

  # [seconds, objects allocated] a call. Each is about 10x the worst seen with ACUTE_WORST=report (2026-10-22, Ruby
  # 4.0.7, a loaded machine), shown after it; in time at least 20 ms, and next 40x, as a busy machine slows it most.
  CEILINGS = {
    parse: [0.02, 6_000],          # 0.7 ms, 523
    parse!: [0.02, 15_000],        # 0.4 ms, 1,363
    read: [0.02, 12_000],          # 0.7 ms, 1,046
    duration: [0.02, 2_000],       # 0.1 ms, 70
    recurrence: [0.02, 8_000],     # 0.4 ms, 701
    recurrence!: [0.02, 15_000],   # 1.0 ms, 1,367
    from_cron: [0.02, 15_000],     # 0.6 ms, 1,294
    verify: [0.02, 15_000],        # 1.1 ms, 1,387
    describe: [0.02, 3_000],       # 0.2 ms, 201
    next: [0.2, 400_000],          # 4.9 ms, 39,336: "every feb 29 at 3pm", 1,000 occurrences 4 years apart
    between: [0.02, 45_000],       # 1.2 ms, 4,280
    to_s: [0.02, 2_000],           # 0.01 ms, 180
    extract: [1.0, 3_000_000],     # 94 ms, 301,884: "q4" 2,048 times, each a mention
    tool: [0.02, 15_000],          # 1.0 ms, 1,452
    cli: [0.02, 25_000],           # 1.5 ms, 2,068
    mcp: [0.75, 3_500_000]         # 73 ms, 335,712: an extract of 4,096 characters
  }.freeze

  def self.inputs
    rng = Random.new(SEED)
    fill = ->(unit) { unit.empty? ? unit : (unit * (Acute::MAX_LENGTH / unit.bytesize))[0, Acute::MAX_LENGTH] }
    repeats = FRAGMENTS.product(SEPARATORS).map { |f, s| fill.("#{f}#{s}") }
    nested = ["the 3rd of the ", "the first monday of the ", "3 days before ", "the day after ", "in 3 days after ",
              "every other ", "except ", "last of the ", "next week's "].flat_map do |unit|
      [fill.(unit), "#{unit * ((Acute::MAX_LENGTH - 9) / unit.size)}christmas"]
    end
    numbers = ["9" * 512, "#{"9" * 510}pm", "in #{"9" * 509}", "#{"1" * 200} days ago", "#{"9" * 250}:#{"9" * 250}",
               "every #{"9" * 300} days", "#{"0" * 500}1", "-#{"9" * 511}", "#{"9" * 200}.#{"9" * 200}", "1e999999 days",
               "every day #{"9" * 100} times", "the #{"9" * 300}th"]
    multibyte = ["日" * 170, "#{"日" * 165} tomorrow", "#{"é" * 250}3pm", "#{"​" * 165}noon", "😀" * 128,
                 "#{"‮" * 100} friday", ("\xff" * 512).b.force_encoding("UTF-8"), "#{"ä" * 200} and 3pm"]
    random = Array.new(300) do
      text = +""
      text << FRAGMENTS.sample(random: rng) << SEPARATORS.sample(random: rng) while text.bytesize < rng.rand(16..512)
      text.byteslice(0, Acute::MAX_LENGTH).scrub("")
    end
    (RULES + CRONS + repeats + nested + numbers + multibyte + random).uniq
  end

  INPUTS = inputs.freeze

  def setup
    @worst = Hash.new { |h, k| h[k] = [0, 0, nil] }
    @tool = Acute::Tool.new(now: NOW, zone: ZONE)
    measure(:parse, "warm up") { Acute.parse("tomorrow 3pm", now: NOW, zone: ZONE) }
  end

  def measure(entry, text, &)
    objects = GC.stat(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    value = yield
    took = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    made = GC.stat(:total_allocated_objects) - objects
    w = @worst[entry]
    w[0] = took if took > w[0]
    w[1], w[2] = made, text if made > w[1]
    return value if ENV["ACUTE_WORST"] == "report"

    seconds, allocations = CEILINGS.fetch(entry)
    # a GC pause or a busy machine slows one call; a super-linear cost slows it again
    took = [took, timed(&)].min if took >= seconds
    assert_operator took, :<, seconds, "#{entry} took #{(took * 1000).round(1)} ms on #{text.inspect[0, 80]}"
    assert_operator made, :<, allocations, "#{entry} allocated #{made} objects on #{text.inspect[0, 80]}"
    value
  end

  def timed
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  def options = { now: NOW, zone: ZONE }

  def test_every_entry_point_stays_within_its_ceilings
    INPUTS.each_with_index do |text, i|
      result = measure(:parse, text) { Acute.parse(text, **options) }
      measure(:parse!, text) { Acute.parse!(text, **options) rescue Acute::ParseError } # rubocop:disable Style/RescueModifier
      measure(:read, text) { Acute.read(text, **options) }
      measure(:duration, text) { Acute.duration(text) }
      measure(:verify, text) { Acute.verify(text, NOW, **options) }
      measure(:verify, text) { Acute.verify("tomorrow", "2026-10-23#{text}", **options) rescue Acute::OptionError } # rubocop:disable Style/RescueModifier
      measure(:describe, text) { Acute.describe(result, **options) } if result
      if (cron = measure(:from_cron, text) { Acute::Rule.from_cron(text) })
        measure(:next, text) { cron.next(Acute::Rule::MAX_OCCURRENCES, after: NOW) }
      end
      measure(:recurrence!, text) { Acute.recurrence!(text, **options) rescue Acute::ParseError } # rubocop:disable Style/RescueModifier
      if (rule = measure(:recurrence, text) { Acute.recurrence(text, **options, strict: false) })
        measure(:next, text) { rule.next(Acute::Rule::MAX_OCCURRENCES, after: NOW) }
        measure(:between, text) { rule.between(NOW, NOW + 366 * 86_400) }
        measure(:to_s, text) { rule.to_s }
      end
      # the tool's extract takes up to 4096 characters: eight of each input
      measure(:extract, text) { Acute.extract([text] * 8 * " ", **options) } if i.even?
      TOOLS.each do |name|
        measure(:tool, text) { @tool.call(name, { "text" => text.scrub, "value" => "2026-10-22" }.slice("text", *("value" if name == "verify"))) }
      end
      next unless (i % 5).zero?

      measure(:cli, text) { Acute::CLI.run([text.scrub], stdin: StringIO.new, stdout: StringIO.new, stderr: StringIO.new) }
      measure(:cli, text) { Acute::CLI.run(["--next", "3"], stdin: StringIO.new("#{text.scrub}\n"), stdout: StringIO.new, stderr: StringIO.new) }
      call = { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "extract", arguments: { text: ([text.scrub] * 8).join(" ")[0, 4096] } } }
      measure(:mcp, text) { Acute::MCP.new.serve(StringIO.new("#{JSON.generate(call)}\n"), StringIO.new) }
    end
    report if ENV["ACUTE_WORST"] == "report"
  end

  def report
    @worst.sort.each do |entry, (took, made, text)|
      puts format("%-12s %8.2f ms %9d objects  %s", entry, took * 1000, made, text.inspect[0, 60])
    end
    puts "#{INPUTS.size} inputs"
  end
end
