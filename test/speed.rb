# The speed budget, as a ratio to a fixed reference workload timed in the same rounds (test/reference.rb), so
# the verdict is the same on a busy machine as on a quiet one. Quiet µs are that ratio times the reference's
# quiet cost; absolute µs, as timed here and now, are printed alongside.
# A pass that fails is re-run, up to PASSES in all, and the verdict taken on the median of the passes for each
# phrase and for the mean: load on a shared machine moves a pass by a few percent, a real slowdown moves every
# pass. ACUTE_SPEED=report prints one pass and never fails, for noisy CI runners.
#   [ACUTE_SPEED=report] ruby test/speed.rb [--verbose]
require_relative "../lib/acute"
require_relative "reference"

module Speed
  # [slowest, mean] quiet µs by mode. The 10 µs slowest planned for 0.1 needs a native lexer; the user chose
  # these instead on 2026-10-18
  BUDGET = { "interp" => [13.0, 8.0], "yjit" => [5.0, 3.0] }.freeze
  PASSES = 3
  NOW = Time.utc(2026, 10, 17, 18)
  RULES = ["every weekday at 9am", "every other friday", "the last friday of every month"].freeze # Acute.recurrence
  PHRASES = ["tomorrow", "tomorrow at 4pm", "noon", "4:30 p.m.", "16:30", "now", "yesterday at noon",
             "4pm tomorrow", "today 9:30", "4:30:15",
             # one or two from each theme of the breadth pass
             "next friday", "friday 3pm", "march 3", "10/23/2026", "2026-10-23T14:30:00Z", "3 days ago",
             "in 2 hours", "next week", "Q3", "this evening", "second tuesday of march", "this weekend", "christmas",
             "thanksgiving 2027", "between 9 and 5", "after christmas", "early next week", "past 3 business days",
             "3pm EST", "jan 5 2027 at 9:30am", "sat", "the second monday of may", *RULES].freeze

  module_function

  # [quiet µs, absolute µs]
  def time(text)
    ratio, ns = if RULES.include?(text)
                  Reference.measure { Acute.recurrence(text, now: NOW, zone: "America/New_York") }
                else
                  Reference.measure { Acute.parse(text, now: NOW, zone: "America/New_York") }
                end
    [Reference.quiet_us(ratio), ns / 1000]
  end

  # One full pass: {phrase => [quiet µs, absolute µs]}. A phrase over budget is timed twice more and keeps the
  # median, so one disturbed timing can't fail it
  def pass(slowest)
    times = PHRASES.to_h { |text| [text, time(text)] }
    times.each do |text, t|
      times[text] = [t, time(text), time(text)].sort[1] if t[0] > slowest
    end
    times
  end

  def median(xs)
    s = xs.sort
    s.size.odd? ? s[s.size / 2] : (s[s.size / 2 - 1] + s[s.size / 2]) / 2.0
  end

  def mean(times) = times.values.sum(&:first) / times.size

  def main(argv)
    slowest, mean_budget = BUDGET.fetch(Reference.mode)
    report = ENV["ACUTE_SPEED"] == "report"
    passes = []
    loads = []
    times = quiet_mean = slow = nil
    loop do
      passes << pass(slowest)
      loads << File.read("/proc/loadavg").split[0]
      times = PHRASES.to_h { |text| [text, passes.map { _1[text] }.transpose.map { median(_1) }] }
      quiet_mean = median(passes.map { mean(_1) })
      slow = times.select { |_, (us, _)| us > slowest }
      break if report || passes.size == PASSES || (slow.empty? && quiet_mean <= mean_budget)
    end
    ok = slow.empty? && quiet_mean <= mean_budget
    times.each { |text, (us, abs)| printf("  %-26s %5.1f µs quiet %5.1f µs here\n", text, us, abs) } if argv.include?("--verbose")
    unless report
      slow.each { |text, (us, abs)| printf("SLOW %s: %.1f µs quiet (%.1f here), budget %.0f µs\n", text.inspect, us, abs, slowest) }
      puts format("MEAN %.1f µs quiet, budget %.1f µs", quiet_mean, mean_budget) if quiet_mean > mean_budget
    end
    name, (us, abs) = times.max_by { _2[0] }
    printf("speed (%s): %d phrases, mean %.1f µs, slowest %.1f µs (%s) as on a quiet machine; here %.1f µs and %.1f µs; %s, load %s%s\n",
           Reference.mode, times.size, quiet_mean, us, name, times.values.sum { _2 } / times.size, abs,
           passes.size == 1 ? "1 pass" : "median of #{passes.size} passes", loads.join(" "),
           report ? "; report only, not judged (ACUTE_SPEED=report)" : "")
    report || ok
  end
end

exit(Speed.main(ARGV.dup)) if $PROGRAM_NAME == __FILE__
