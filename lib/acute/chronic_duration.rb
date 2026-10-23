require_relative "../acute"
require_relative "numerize"

# chronic_duration's API, 0.10.6 and GitLab's 0.12.0 fork, on acute. Its tokeniser, number words and fixed unit
# lengths are kept, so answers match the gems. Where the gem would skip words and acute reads the whole text as
# a duration ("half an hour", "1 fortnight"), acute's reading wins, at the same fixed lengths (D46).
module ChronicDuration
  extend self

  class DurationParseError < StandardError
  end

  VERSION = "0.12.0".freeze
  FULL_WEEKS_PER_MONTH = 4
  YEAR = 31_557_600
  UNITS = Ractor.make_shareable(%w[seconds minutes hours days weeks months years])
  CHRONO_UNITS = Ractor.make_shareable(UNITS - ["weeks"])
  JOIN_WORDS = Ractor.make_shareable(%w[and with plus])
  FLOAT = /[0-9]*\.?[0-9]+/
  # "4:13:02" wherever it stands (D46). GitLab's 0.12 read it only as the whole text, so "2 days, 4:13:02" lost
  # its 4:13; upstream split the whole text at colons, so "Duration: 2 hours" gained a minute.
  CHRONO = /(?<![\d:.])\d+(?:\s*:\s*\d+){1,5}(?:\.\d*)?(?![\d:])/
  MAPPINGS = Ractor.make_shareable({
    "seconds" => "seconds", "second" => "seconds", "secs" => "seconds", "sec" => "seconds", "s" => "seconds",
    "minutes" => "minutes", "minute" => "minutes", "mins" => "minutes", "min" => "minutes", "m" => "minutes",
    "hours" => "hours", "hour" => "hours", "hrs" => "hours", "hr" => "hours", "h" => "hours",
    "days" => "days", "day" => "days", "dy" => "days", "d" => "days",
    "weeks" => "weeks", "week" => "weeks", "wks" => "weeks", "wk" => "weeks", "w" => "weeks",
    "months" => "months", "mo" => "months", "mos" => "months", "month" => "months",
    "years" => "years", "year" => "years", "yrs" => "years", "yr" => "years", "y" => "years"
  })
  DIVIDERS = Ractor.make_shareable({
    micro: { years: "y", months: "mo", weeks: "w", days: "d", hours: "h", minutes: "m", seconds: "s" },
    short: { years: "y", months: "mo", weeks: "w", days: "d", hours: "h", minutes: "m", seconds: "s" },
    default: { years: " yr", months: " mo", weeks: " wk", days: " day", hours: " hr", minutes: " min", seconds: " sec",
               pluralize: true },
    long: { years: " year", months: " month", weeks: " week", days: " day", hours: " hour", minutes: " minute",
            seconds: " second", pluralize: true },
    chrono: { years: ":", months: ":", weeks: ":", days: ":", hours: ":", minutes: ":", seconds: ":", keep_zero: true }
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

  def parse(string, opts = {})
    # T3: past the 512 bytes acute reads, before the rewrites rather than after them
    if string.bytesize > Acute::MAX_LENGTH
      raise DurationParseError, "The string is longer than #{Acute::MAX_LENGTH} bytes." if ChronicDuration.raise_exceptions
      return
    end
    words, skipped = clean(string)
    result = acute_seconds(string, opts) unless skipped.empty?
    if result.nil?
      if !skipped.empty? && ChronicDuration.raise_exceptions
        raise DurationParseError, "An invalid word #{skipped[0].inspect} was used in the string to be parsed."
      end
      result = calculate_from_words(words, opts)
    end
    !opts[:keep_zero] && result == 0 ? nil : result
  end

  def output(seconds, opts = {})
    int = seconds.to_i
    seconds = int if seconds - int == 0
    style = opts[:format] || :default
    hours_per_day, days_per_month, days_per_week = settings(opts)
    years = months = weeks = days = hours = minutes = 0
    decimal_places = seconds.to_s.split(".").last.length if seconds.is_a?(Float)

    day = hours_per_day * 3600
    month = days_per_month * day
    if seconds >= YEAR && seconds % YEAR < seconds % month
      years = seconds / YEAR
      months = seconds % YEAR / month
      days = seconds % YEAR % month / day
      hours = seconds % YEAR % month % day / 3600
      minutes = seconds % YEAR % month % day % 3600 / 60
      seconds = seconds % YEAR % month % day % 3600 % 60
    elsif seconds >= 60
      minutes = (seconds / 60).to_i
      seconds %= 60
      if minutes >= 60
        hours = (minutes / 60).to_i
        minutes = (minutes % 60).to_i
        if !opts[:limit_to_hours] && hours >= hours_per_day
          days = (hours / hours_per_day).to_i
          hours = (hours % hours_per_day).to_i
          if opts[:weeks]
            if days >= days_per_week
              weeks = (days / days_per_week).to_i
              days = (days % days_per_week).to_i
              if weeks >= FULL_WEEKS_PER_MONTH
                months = (weeks / FULL_WEEKS_PER_MONTH).to_i
                weeks = (weeks % FULL_WEEKS_PER_MONTH).to_i
              end
            end
          elsif days >= days_per_month
            months = (days / days_per_month).to_i
            days = (days % days_per_month).to_i
          end
        end
      end
    end

    dividers = DIVIDERS[style]
    joiner = %i[micro chrono].include?(style) ? "" : opts.fetch(:joiner, " ")
    counts = { years: years, months: months, weeks: weeks, days: days, hours: hours, minutes: minutes, seconds: seconds }
    # the gem's compact! returned nil when no unit was dropped, so weeks: true with every unit shown raised (D46)
    result = counts.filter_map do |unit, num|
      next if unit == :weeks && !opts[:weeks]
      num = format("%.#{decimal_places}f", num) if num.is_a?(Float) && unit == :seconds
      keep_zero = dividers[:keep_zero] || (opts[:keep_zero] if unit == :seconds)
      humanize_time_unit(num, dividers[unit], dividers[:pluralize], keep_zero)
    end
    result = result[0...opts[:units]] if opts[:units]
    result = result.join(joiner)
    result = chrono(result, decimal_places) if style == :chrono
    result.empty? ? nil : result
  end

  private

  def humanize_time_unit(number, unit, pluralize, keep_zero)
    return if number == 0 && !keep_zero
    res = "#{number}#{unit}"
    res << "s" if number != 1 && pluralize
    res
  end

  # Pad each part to two digits, then drop leading zero parts, a leading zero and the trailing colon
  def chrono(str, decimal_places)
    str.split(":").map { |n| n.include?(".") ? format("%04.#{decimal_places}f", n) : format("%02d", n) }
       .join(":").gsub(/^(00:)+/, "").gsub(/^0/, "").gsub(/:$/, "")
  end

  # Per-call options over the module's settings; GitLab's per-call days_per_month also sets the week
  def settings(opts)
    hours_per_day = opts[:hours_per_day] || ChronicDuration.hours_per_day
    days_per_month = opts[:days_per_month] || ChronicDuration.days_per_month
    days_per_week = opts[:days_per_week] ||
                    (opts[:days_per_month] ? days_per_month / FULL_WEEKS_PER_MONTH : ChronicDuration.days_per_week)
    [hours_per_day, days_per_month, days_per_week]
  end

  def lengths(opts)
    hours_per_day, days_per_month, days_per_week = settings(opts)
    day = 3600 * hours_per_day
    { "years" => YEAR, "months" => day * days_per_month, "weeks" => day * days_per_week, "days" => day,
      "hours" => 3600, "minutes" => 60, "seconds" => 1 }
  end

  def calculate_from_words(string, opts)
    seconds = lengths(opts)
    words = string.split
    words.each_with_index.sum do |v, k|
      v.match?(FLOAT) ? convert_to_number(v) * seconds.fetch(words[k + 1] || opts[:default_unit] || "seconds", 0) : 0
    end
  end

  # acute's reading of the whole text, each unit said at the gem's fixed lengths, so "2.5 weeks" of 5-day weeks
  # is 12.5 days. A business day has no such length, so the gem's answer stands. A fraction anywhere makes a
  # Float, as the gem's own decimals do.
  def acute_seconds(string, opts)
    tokens = Acute::Lexer.lex(string)
    return if Acute::Failure === tokens
    units = Acute::Grammar.duration(tokens)
    return if Acute::Failure === units
    parts = units.map { |u| [*Acute::Duration::UNIT_PART.fetch(u.unit), u.count] }
    return if parts.any? { |part, *| part == :business_days }
    seconds = lengths(opts)
    total = parts.sum { |part, k, count| count * k * seconds.fetch(part.to_s) }
    parts.all? { |*, count| count.to_r.denominator == 1 } ? total.to_i : total.to_f
  end

  def cleanup(string) = clean(string)[0]

  def clean(string)
    res = filter_by_type(Acute::Numerize.call(string.downcase))
    res = res.gsub(FLOAT) { " #{_1} " }.squeeze(" ").strip
    filter_through_white_list(res)
  end

  def convert_to_number(string) = string.to_f % 1 > 0 ? string.to_f : string.to_i

  # "3:41:59" is 3 hours 41 minutes 59 seconds
  def filter_by_type(string)
    string.gsub(CHRONO) do |chrono|
      chrono.delete(" ").split(":").reverse.each_with_index.map { |v, k| "#{v} #{CHRONO_UNITS[k]}" }.reverse.join(" ")
    end
  end

  # The units named, with numbers kept and other words skipped; the skipped words come back too
  def filter_through_white_list(string)
    res = []
    skipped = []
    string.split.each do |word|
      next res << word.strip if word.match?(FLOAT)
      stripped = word.strip.delete_prefix(",").delete_suffix(",")
      if MAPPINGS.key?(stripped) then res << MAPPINGS[stripped]
      elsif !JOIN_WORDS.include?(stripped) then skipped << word
      end
    end
    # "day" or "minute 30sec": a unit first counts one
    res.unshift(1) if !res.empty? && MAPPINGS[res[0]]
    [res.join(" "), skipped]
  end
end

# Ported from chronic_duration 0.10.6 and gitlab_chronic_duration 0.12.0:
#
# Copyright (c) Henry Poydar
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
# documentation files (the "Software"), to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or substantial portions of
# the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
# THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
