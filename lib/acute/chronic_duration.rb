require_relative "../acute"
require_relative "shadow"

# chronic_duration's API, 0.10.6 and GitLab's 0.12.0 fork, answered by acute (D46). Text is read by acute's lexer
# and duration grammar, which also reads the gems' clock groups, a unit alone and a bare count; each unit read
# counts at the gems' fixed lengths, set by the settings below. Where acute reads text differently from the gems,
# test/chronic_duration/differences.yml says how and why.
module ChronicDuration
  extend self

  class DurationParseError < StandardError
  end

  VERSION = "0.12.0".freeze
  FULL_WEEKS_PER_MONTH = 4
  YEAR = 31_557_600
  # default_unit's names, as acute's units
  UNITS = Ractor.make_shareable({ "seconds" => :second, "minutes" => :minute, "hours" => :hour, "days" => :day,
                                  "weeks" => :week, "months" => :month, "years" => :year })
  # Each format's name for a count of each unit, and whether a count other than one takes an "s"
  NAMES = Ractor.make_shareable({
    micro: [{ years: "y", months: "mo", weeks: "w", days: "d", hours: "h", minutes: "m", seconds: "s" }, false],
    short: [{ years: "y", months: "mo", weeks: "w", days: "d", hours: "h", minutes: "m", seconds: "s" }, false],
    default: [{ years: " yr", months: " mo", weeks: " wk", days: " day", hours: " hr", minutes: " min", seconds: " sec" }, true],
    long: [{ years: " year", months: " month", weeks: " week", days: " day", hours: " hour", minutes: " minute",
             seconds: " second" }, true]
  })

  class << self
    attr_accessor :hours_per_day
    attr_reader :days_per_month, :raise_exceptions
    attr_writer :days_per_week

    def raise_exceptions=(value)
      @raise_exceptions = !!value
    end

    # upstream sets the week's days; GitLab derives them from the month's. Whichever was set last counts (D46).
    def days_per_week = @days_per_week || days_per_month / FULL_WEEKS_PER_MONTH

    def days_per_month=(value)
      @days_per_month = value
      @days_per_week = nil
    end
  end
  self.raise_exceptions = false
  self.hours_per_day = 24
  self.days_per_month = 30

  # Any token the duration grammar doesn't read is skipped, as the gems skip words, unless raise_exceptions, which
  # reads strictly and raises where acute can't read the text (D46). A fraction anywhere makes a Float, as the
  # gems' decimals do.
  def parse(string, opts = {})
    strict = ChronicDuration.raise_exceptions
    # T3: past the 512 bytes acute reads
    if string.bytesize > Acute::MAX_LENGTH
      raise DurationParseError, "The string is longer than #{Acute::MAX_LENGTH} bytes." if strict
      return
    end
    tokens = strict ? Acute::Lexer.lex(string) : Acute::Lexer.lex(string, [])
    return (0 if opts[:keep_zero]) if Array === tokens && tokens.empty?
    units = Acute::Failure === tokens ? tokens : Acute::Grammar.duration(tokens, UNITS[opts[:default_unit] || "seconds"] || :nothing, !strict)
    if Acute::Failure === units
      raise DurationParseError, refusal(units, string) if strict
      return
    end
    seconds = total(units, opts)
    !opts[:keep_zero] && seconds == 0 ? nil : seconds
  end

  def output(seconds, opts = {})
    seconds = seconds.to_i if seconds % 1 == 0
    places = seconds.to_s.split(".").last.length if Float === seconds
    weeks = opts[:weeks] && opts[:format] != :chrono
    counts = split(seconds, opts, weeks)
    counts.delete(:weeks) unless weeks
    if opts[:format] == :chrono
      chrono(counts.values.first(opts[:units] || counts.size), places)
    else
      text(counts, opts, places)
    end
  end

  private

  def refusal(failure, string)
    return Acute::Explain.error(failure, string).message if failure.start == failure.stop
    "An invalid word #{string.byteslice(failure.start, failure.stop - failure.start).inspect} was used in the string to be parsed."
  end

  def total(units, opts)
    lengths = lengths(opts)
    whole = true
    sum = units.sum do |u|
      whole = false if u.count.to_r.denominator != 1
      part, k = Acute::Duration::UNIT_PART.fetch(u.unit) { next [:nothing, 0] }
      u.count * k * lengths.fetch(part)
    end
    return sum.to_f unless whole
    Rational === sum ? sum.to_i : sum
  end

  # A unit's seconds; a business day has none of its own, so it is a day, as the gems skip "business"
  def lengths(opts)
    hours_per_day, days_per_month, days_per_week = settings(opts)
    day = 3600 * hours_per_day
    { years: YEAR, months: day * days_per_month, weeks: day * days_per_week, days: day, business_days: day,
      hours: 3600, minutes: 60, seconds: 1, nothing: 0 }
  end

  # Per-call options over the module's settings; GitLab's per-call days_per_month also sets the week
  def settings(opts)
    hours_per_day = opts[:hours_per_day] || ChronicDuration.hours_per_day
    days_per_month = opts[:days_per_month] || ChronicDuration.days_per_month
    days_per_week = opts[:days_per_week] ||
                    (opts[:days_per_month] ? days_per_month / FULL_WEEKS_PER_MONTH : ChronicDuration.days_per_week)
    [hours_per_day, days_per_month, days_per_week]
  end

  # The seconds as counts of each unit, largest first. Past a year, when whole years leave less over than whole
  # months would, they are years, months, days, hours, minutes and seconds. Otherwise each unit carries into the
  # next once it fills it: minutes into hours, hours into days (unless limit_to_hours), then days into months,
  # or with weeks into weeks and four weeks into a month.
  def split(seconds, opts, weeks)
    hours_per_day, days_per_month, days_per_week = settings(opts)
    day = 3600 * hours_per_day
    month = day * days_per_month
    counts = { years: 0, months: 0, weeks: 0, days: 0, hours: 0, minutes: 0, seconds: seconds }
    if seconds >= YEAR && seconds % YEAR < seconds % month
      { years: YEAR, months: month, days: day, hours: 3600, minutes: 60 }.each do |unit, length|
        counts[unit], counts[:seconds] = counts[:seconds].divmod(length)
        counts[unit] = counts[unit].to_i
      end
      return counts
    end
    steps = [[:minutes, 60], [:hours, 60]]
    unless opts[:limit_to_hours]
      steps << [:days, hours_per_day]
      steps.push(*(weeks ? [[:weeks, days_per_week], [:months, FULL_WEEKS_PER_MONTH]] : [[:months, days_per_month]]))
    end
    smaller = :seconds
    steps.each do |unit, size|
      break if counts[smaller] < size
      counts[unit] = (counts[smaller] / size).to_i
      counts[smaller] %= size
      counts[smaller] = counts[smaller].to_i unless smaller == :seconds
      smaller = unit
    end
    counts
  end

  # "1 hr 20 mins": the counts that aren't zero, and with keep_zero the seconds even so
  def text(counts, opts, places)
    names, plural = NAMES[opts[:format] || :default]
    parts = counts.filter_map do |unit, count|
      next if count == 0 && !(opts[:keep_zero] && unit == :seconds)
      count = format("%.#{places}f", count) if Float === count
      "#{count}#{names[unit]}#{"s" if plural && count != 1}"
    end
    parts = parts.first(opts[:units]) if opts[:units]
    parts.join(opts[:format] == :micro ? "" : opts.fetch(:joiner, " ")) unless parts.empty?
  end

  # "1:20", "6:01:00:00:00": every count from the first that isn't zero, two digits each but the first
  def chrono(counts, places)
    digits = counts.map { |c| Float === c ? format("%0#{places + 3}.#{places}f", c) : format("%02d", c) }
    digits.shift while digits.size > 1 && digits[0] == "00"
    digits[0] = digits[0].sub(/\A0+(?=[\d.])/, "")
    digits.join(":")
  end
end
Acute::Shadow.call("acute/chronic_duration", "chronic_duration", "chronic_duration", "gitlab_chronic_duration")
