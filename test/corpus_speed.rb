# Whole-corpus timing, to find the slowness the 32 phrases of test/speed.rb don't show: every passing time
# case's parse in quiet µs (as test/speed.rb measures them), with p50, p99, max and the slowest phrases;
# allocations a parse; extraction µs a case; and the time `require "acute"` takes. A report, not a gate.
#   ruby [--yjit] test/corpus_speed.rb [--top N]
require "rbconfig"
require_relative "corpus"
require_relative "reference"

module CorpusSpeed
  # Every case is timed in a few short rounds, then the slowest again in full ones
  QUICK = { rounds: 7, batch: 4 }.freeze
  RETIME = 3

  module_function

  def quiet(**rounds, &block) = Reference.quiet_us(Reference.measure(**rounds, &block)[0])

  def allocations
    before = GC.stat(:total_allocated_objects)
    yield
    GC.stat(:total_allocated_objects) - before
  end

  def percentile(sorted, p) = sorted[((sorted.size - 1) * p).round]

  def load_ms
    lib = File.expand_path("../lib/acute", __dir__)
    code = "t = Process.clock_gettime(Process::CLOCK_MONOTONIC); require #{lib.dump}; " \
           "print Process.clock_gettime(Process::CLOCK_MONOTONIC) - t"
    Array.new(5) { IO.popen([RbConfig.ruby, *(["--yjit"] if Reference.mode == "yjit"), "-e", code], &:read).to_f }.min * 1000
  end

  def main(argv)
    top = (i = argv.index("--top")) ? Integer(argv[i + 1]) : 20
    passing = File.readlines(Corpus::RATCHET, chomp: true).to_h { [_1, true] }
    all = Corpus.load
    cases = all.select { |c| passing[c["id"]] && !c["expect"].key?("duration") }
                 .map { |c| [c["text"], Corpus.context(c)] }
    times = cases.map do |text, ctx|
      Acute.parse(text, **ctx)
      [quiet(**QUICK) { Acute.parse(text, **ctx) }, text, ctx]
    end
    times.sort_by! { -_1[0] }
    slowest = times.first(top * RETIME).map { |_, text, ctx| [quiet { Acute.parse(text, **ctx) }, text] }.sort_by { -_1[0] }
    sorted = times.map(&:first).sort
    printf "corpus: %d passing time cases (%s), quiet µs a parse: mean %.1f, p50 %.1f, p99 %.1f, max %.1f\n",
           times.size, Reference.mode, sorted.sum / sorted.size, percentile(sorted, 0.5), percentile(sorted, 0.99), slowest[0][0]
    puts "slowest #{top}:"
    slowest.first(top).each { |us, text| printf "  %5.1f  %s\n", us, text.inspect }

    allocs = cases.map { |text, ctx| [allocations { Acute.parse(text, **ctx) }, text] }.sort_by { -_1[0] }
    printf "allocations a parse: mean %.1f, p99 %d, max %d (%s)\n", allocs.sum(&:first).fdiv(allocs.size),
           percentile(allocs.map(&:first).sort, 0.99), allocs[0][0], allocs.first(5).map { "#{_2.inspect} #{_1}" }.join(", ")

    extracts = all.select { |c| c["expect"].key?("extract") && !(c["options"] || {}).keys.intersect?(Corpus::CHRONIC_ONLY) }
                  .map { |c| [c["text"], Corpus.context(c)] }
    us = extracts.sum { |text, ctx| quiet(**QUICK) { Acute.extract(text, **ctx) } }
    printf "extraction: %d cases, mean %.1f quiet µs a case\n", extracts.size, us / extracts.size
    printf "require \"acute\": %.0f ms\n", load_ms
  end
end

CorpusSpeed.main(ARGV.dup) if $PROGRAM_NAME == __FILE__
