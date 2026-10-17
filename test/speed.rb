# Fastest-of-N thread CPU time per parse, so a busy machine slows the check down rather than failing it.
#   ruby test/speed.rb [--verbose]
require_relative "../lib/acute"

module Speed
  BUDGET_NS = 10_000
  BATCH = 500
  ROUNDS = 15
  NOW = Time.utc(2026, 10, 17, 18)
  PHRASES = ["tomorrow", "tomorrow at 4pm", "noon", "4:30 p.m.", "16:30", "now", "yesterday at noon",
             "4pm tomorrow", "today 9:30", "4:30:15",
             # one or two from each theme of the breadth pass
             "next friday", "friday 3pm", "march 3", "10/23/2026", "2026-10-23T14:30:00Z", "3 days ago",
             "in 2 hours", "next week", "Q3", "this evening", "second tuesday of march", "this weekend", "christmas",
             "thanksgiving 2027", "between 9 and 5", "after christmas", "early next week", "past 3 business days",
             "3pm EST", "jan 5 2027 at 9:30am", "sat", "the second monday of may"].freeze

  module_function

  def clock = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)

  def ns_per_parse(text)
    best = Float::INFINITY
    ROUNDS.times do
      t0 = clock
      i = 0
      while i < BATCH
        Acute.parse(text, now: NOW, zone: "America/New_York")
        i += 1
      end
      dt = clock - t0
      best = dt if dt < best
    end
    best / BATCH * 1e9
  end

  def main(argv)
    times = PHRASES.to_h { |text| [text, ns_per_parse(text)] }
    slow = times.select { |_, ns| ns > BUDGET_NS }
    times.each { |text, ns| printf("  %-20s %6.0f ns\n", text, ns) } if argv.include?("--verbose")
    slow.each { |text, ns| printf("SLOW %s: %.0f ns, budget %d ns\n", text.inspect, ns, BUDGET_NS) }
    printf("speed: %d phrases, slowest %.1f µs (%s), budget %d µs\n", times.size, times.values.max / 1000,
           times.max_by { _2 }[0], BUDGET_NS / 1000)
    slow.empty?
  end
end

exit(Speed.main(ARGV.dup)) if $PROGRAM_NAME == __FILE__
