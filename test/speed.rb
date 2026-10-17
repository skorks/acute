# The speed budget, as a ratio to a fixed reference workload timed in the same rounds (test/reference.rb), so
# the verdict is the same on a busy machine as on a quiet one. Quiet µs are that ratio times the reference's
# quiet cost; absolute µs, as timed here and now, are printed alongside.
#   ruby test/speed.rb [--verbose]
require_relative "../lib/acute"
require_relative "reference"

module Speed
  # An alarm for structural slowness during the depth pass, until the pre-0.1 performance pass restores the
  # budget: 10 µs slowest, 6.65 µs mean (2x the 11.1 slice: 0.665 of a reference run, 3.3 quiet µs)
  SLOWEST_US = 30.0
  MEAN_US = 15.0
  TARGET_US = 10.0
  NOW = Time.utc(2026, 10, 17, 18)
  PHRASES = ["tomorrow", "tomorrow at 4pm", "noon", "4:30 p.m.", "16:30", "now", "yesterday at noon",
             "4pm tomorrow", "today 9:30", "4:30:15",
             # one or two from each theme of the breadth pass
             "next friday", "friday 3pm", "march 3", "10/23/2026", "2026-10-23T14:30:00Z", "3 days ago",
             "in 2 hours", "next week", "Q3", "this evening", "second tuesday of march", "this weekend", "christmas",
             "thanksgiving 2027", "between 9 and 5", "after christmas", "early next week", "past 3 business days",
             "3pm EST", "jan 5 2027 at 9:30am", "sat", "the second monday of may"].freeze

  module_function

  # [quiet µs, absolute µs]
  def time(text)
    ratio, ns = Reference.measure { Acute.parse(text, now: NOW, zone: "America/New_York") }
    [Reference.quiet_us(ratio), ns / 1000]
  end

  # A phrase over budget is timed twice more and keeps the median, so one disturbed pass can't fail it
  def main(argv)
    times = PHRASES.to_h { |text| [text, time(text)] }
    times.each do |text, t|
      times[text] = [t, time(text), time(text)].sort[1] if t[0] > TARGET_US
    end
    quiet = times.values.map(&:first)
    mean = quiet.sum / quiet.size
    slow = times.select { |_, (us, _)| us > SLOWEST_US }
    times.each { |text, (us, abs)| printf("  %-26s %5.1f µs quiet %5.1f µs here\n", text, us, abs) } if argv.include?("--verbose")
    over = times.select { |_, (us, _)| us > TARGET_US }.keys - slow.keys
    puts "over the #{TARGET_US.to_i} µs target: #{over.map(&:inspect).join(", ")}" unless over.empty?
    slow.each { |text, (us, abs)| printf("SLOW %s: %.1f µs quiet (%.1f here), alarm %.0f µs\n", text.inspect, us, abs, SLOWEST_US) }
    puts format("MEAN %.1f µs quiet, alarm %.2f µs", mean, MEAN_US) if mean > MEAN_US
    name, (us, abs) = times.max_by { _2[0] }
    printf("speed: %d phrases, mean %.1f µs, slowest %.1f µs (%s) as on a quiet machine; here %.1f µs and %.1f µs, load %s\n",
           times.size, mean, us, name, times.values.sum { _2 } / times.size, abs, File.read("/proc/loadavg").split[0])
    slow.empty? && mean <= MEAN_US
  end
end

exit(Speed.main(ARGV.dup)) if $PROGRAM_NAME == __FILE__
