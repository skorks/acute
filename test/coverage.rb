# Line and branch coverage of lib/ across the unit tests and the corpus run together, against a floor. The
# generated tables are left out: every line of them runs at load.
#   ruby test/coverage.rb [--files N]
require "coverage"
Coverage.start(lines: true, branches: true)

require "stringio"
require "minitest"
# The unit tests require minitest/autorun; they are run here, once the corpus has run too
def Minitest.autorun; end
require_relative "corpus"
Dir[File.join(__dir__, "unit/*_test.rb")].each { require _1 }

module CoverageCheck
  # Just under the coverage measured on 2026-10-18, so a change that leaves code untested fails
  FLOOR = { lines: 98.5, branches: 93.1 }.freeze
  LIB = File.expand_path("../lib", __dir__)
  TABLES = File.join(LIB, "acute/tables/")

  module_function

  # {path => [covered, total]} for lines and for branches
  def tally(result)
    files = result.select { |path, _| path.start_with?(LIB) && !path.start_with?(TABLES) }
    lines = files.transform_values { |r| r[:lines].compact.then { [_1.count(&:positive?), _1.size] } }
    branches = files.transform_values do |r|
      counts = r[:branches].values.flat_map(&:values)
      [counts.count(&:positive?), counts.size]
    end
    { lines: lines, branches: branches }
  end

  def percent(pairs) = 100.0 * pairs.sum(&:first) / pairs.sum(&:last)

  def main(argv)
    top = (i = argv.index("--files")) ? Integer(argv[i + 1]) : 5
    out = StringIO.new
    $stdout = out
    ok = Corpus.main([]) & Minitest.run(["--seed", "1"])
    $stdout = STDOUT
    abort "coverage: the corpus or the unit tests failed, so coverage is not judged\n#{out.string}" unless ok

    t = tally(Coverage.result)
    pct = t.transform_values { percent(_1.values) }
    below = pct.select { |kind, p| p < FLOOR[kind] }
    below.each { |kind, p| printf("UNDER FLOOR %s: %.2f%%, floor %.2f%%\n", kind, p, FLOOR[kind]) }
    printf("coverage of lib/: lines %.2f%% (floor %.2f%%), branches %.2f%% (floor %.2f%%)\n",
           pct[:lines], FLOOR[:lines], pct[:branches], FLOOR[:branches])
    least = t[:lines].sort_by { |_, (c, n)| [c.fdiv(n), -n] }.first(top)
    files = least.map do |path, (c, n)|
      b = t[:branches][path]
      format("%s %.1f%% lines (%d uncovered), %s branches", path.delete_prefix("#{LIB}/"), 100.0 * c / n, n - c,
             b[1].zero? ? "no" : format("%.1f%%", 100.0 * b[0] / b[1]))
    end
    puts "least covered: #{files.join("; ")}"
    below.empty?
  end
end

exit(CoverageCheck.main(ARGV.dup))
