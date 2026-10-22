require "json"
require "date"

module Acute
  # A repeating time as an iCalendar rule (RFC 5545): a DTSTART, an RRULE and any EXDATE (R1). Frozen and
  # Ractor-shareable.
  class Rule
    DAYS = Ractor.make_shareable(%w[SU MO TU WE TH FR SA])
    DAY_NAMES = Ractor.make_shareable(%w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday])
    MONTH_NAMES = Ractor.make_shareable(%w[_ January February March April May June July August September October November December])
    ORDINALS = Ractor.make_shareable(%w[_ first second third fourth fifth])
    UNITS = Ractor.make_shareable({ secondly: "second", minutely: "minute", hourly: "hour", daily: "day", weekly: "week",
                                    monthly: "month", yearly: "year" })
    DAY = 86_400

    # What repeats: secs are seconds of the day, sorted, each hour said with each minute said (R4)
    Parts = Struct.new(:freq, :interval, :month, :monthdays, :days, :nths, :setpos, :secs) do
      def on?(day)
        ymd = Calendar.civil_from_days(day)
        m = ymd / 100 % 100
        return false if month && month != m
        d = ymd % 100
        wday = Calendar.weekday(day)
        dim = Calendar.days_in_month(ymd / 10_000, m) unless monthdays.empty? && nths.empty? && !setpos
        return false unless monthdays.empty? || monthdays.any? { |md| md > 0 ? md == d : dim + md + 1 == d }
        return false unless nths.empty? || nths.any? { |n, w| w == wday && (n > 0 ? (d - 1) / 7 + 1 == n : (dim - d) / 7 + 1 == -n) }
        return false unless days.empty? || days.include?(wday)
        return true unless setpos
        picked = (1..dim).select { |x| days.include?(Calendar.weekday(day - d + x)) }
        setpos.any? { |n| picked[n > 0 ? n - 1 : n] == d }
      end
    end

    attr_reader :zone

    # start: local wall seconds when timed, else a day number; until_: a UTC epoch when timed, else a day number;
    # exdates: as start; dst: the dst: policy occurrences follow (R18)
    def initialize(parts, zone, start, timed, count, until_, exdates, started, dst = nil)
      @parts = parts
      @zone = zone
      @start = start
      @timed = timed
      @count = count
      @until = until_
      @exdates = exdates
      @started = started
      @dst = dst
      Ractor.make_shareable(self)
    end

    def kind = :rule

    def rrule
      p = @parts
      out = ["FREQ=#{p.freq.upcase}"]
      out << "INTERVAL=#{p.interval}" if p.interval > 1
      out << "BYMONTH=#{p.month}" if p.month
      out << "BYMONTHDAY=#{p.monthdays.join(",")}" unless p.monthdays.empty?
      byday = p.nths.map { |n, w| "#{n}#{DAYS[w]}" } + sorted_days.map { DAYS[_1] }
      out << "BYDAY=#{byday.join(",")}" unless byday.empty?
      out << "BYSETPOS=#{p.setpos.join(",")}" if p.setpos
      unless p.secs.empty?
        out << "BYHOUR=#{p.secs.map { _1 / 3600 }.uniq.join(",")}"
        out << "BYMINUTE=#{p.secs.map { _1 / 60 % 60 }.uniq.sort.join(",")}"
        out << "BYSECOND=#{p.secs[0] % 60}" if p.secs[0] % 60 != 0
      end
      out << "COUNT=#{@count}" if @count
      out << "UNTIL=#{@timed ? Time.at(@until).utc.strftime("%Y%m%dT%H%M%SZ") : ymd(@until)}" if @until
      out.join(";")
    end

    # A Time in the zone when the rule has a clock, else a Date
    def dtstart
      return ::Date.new(*civil(@start)) unless @timed
      utc = Zone.for(@zone).local_to_utc(@start, Notes.new)
      Time.at(utc, in: Zone.for(@zone).offset_at(utc))
    end

    def to_ical
      lines = ["DTSTART#{form}:#{stamp(@start)}", "RRULE:#{rrule}"]
      lines << "EXDATE#{form}:#{@exdates.map { stamp(_1) }.join(",")}" unless @exdates.empty?
      lines.join("\n")
    end

    def to_s
      p = @parts
      if (window = steps)
        return "#{window}#{tail}" if p.freq == :daily && p.interval == 1
        return "#{window} on #{weekdays(plural: true)}#{tail}" if p.freq == :weekly && p.interval == 1 && !p.days.empty?
      end
      out = +if !p.nths.empty?
               "the #{list(p.nths.sort_by(&:first).map { ordinal(_1[0]) })} #{DAY_NAMES[p.nths[0][1]]} of #{every("month")}"
             elsif p.setpos
               "the #{list(p.setpos.map { ordinal(_1) })} weekday of #{every("month")}"
             elsif p.month
               "#{every("year")} on #{MONTH_NAMES[p.month]} #{p.monthdays[0]}"
             elsif !p.monthdays.empty?
               "the #{list(p.monthdays.map { _1 == -1 ? "last day" : nth(_1) })} of #{every("month")}"
             elsif !p.days.empty?
               "#{every(nil)} #{weekdays}"
             else
               every(UNITS[p.freq])
             end
      if window then out << " #{window}"
      elsif !p.secs.empty? then out << " at #{list(p.secs.map { Describe.clock(_1) })}"
      end
      out << tail
    end

    def to_h
      line, reason = cron_or_reason
      { kind: "rule", text: to_s, rrule: rrule, dtstart: @timed ? dtstart.iso8601 : dtstart.to_s, zone: @zone, ical: to_ical,
        cron: line, cron_reason: reason }
    end

    def to_json(*args) = to_h.to_json(*args)

    def as_json(*) = JSON.parse(to_json)

    def ==(other) = Rule === other && other.to_ical == to_ical

    alias eql? ==

    def hash = to_ical.hash

    def inspect = "#<Acute::Rule #{to_ical.tr("\n", " ")}>"

    private

    Notes = Struct.new(:dst)

    # The count, start and end, as to_s ends with them
    def tail
      out = +""
      out << " #{@count} times" if @count
      out << " starting #{date(@timed ? @start.div(DAY) : @start)}" if @started
      out << " until #{@timed ? until_local : date(@until)}" if @until
      out
    end

    # R4: several minutes past the hour, evenly spaced through a window of the day, as "every 15 minutes from
    # 9am to 6pm", its end left out (R27); nil for one minute, two times, or times no step reaches
    def steps
      secs = @parts.secs
      return if secs.size < 3 || secs.map { _1 / 60 % 60 }.uniq.size < 2
      step = secs[1] - secs[0]
      return unless 3600 % step == 0 && secs.each_cons(2).all? { _2 - _1 == step }
      stop = secs[-1] + step >= DAY ? "midnight" : Describe.clock(secs[-1] + step)
      "every #{step / 60} minutes from #{Describe.clock(secs[0])} to #{stop}"
    end

    def form = @timed ? ";TZID=#{@zone}" : ";VALUE=DATE"

    def stamp(t)
      return ymd(t) unless @timed
      s = t % DAY
      format("%sT%02d%02d%02d", ymd(t.div(DAY)), s / 3600, s / 60 % 60, s % 60)
    end

    def ymd(day) = format("%08d", Calendar.civil_from_days(day))

    def civil(day)
      x = Calendar.civil_from_days(day)
      [x / 10_000, x / 100 % 100, x % 100]
    end

    def date(day)
      y, m, d = civil(day)
      "#{Result::MONTHS[m - 1]} #{d}, #{y}"
    end

    # The day an UNTIL ends, or the instant when it isn't a day's last second (R10)
    def until_local
      t = @until + Zone.for(@zone).offset_at(@until)
      t % DAY == DAY - 1 ? date(t.div(DAY)) : "#{date(t.div(DAY))} #{Describe.clock(t % DAY)}"
    end

    def sorted_days = @parts.days.sort_by { (_1 + 6) % 7 }

    def weekdays(plural: false)
      days = sorted_days
      s = plural ? "s" : ""
      return "weekday#{s}" if days == [1, 2, 3, 4, 5]
      return "weekend#{s}" if days == [6, 0]
      list(days.map { "#{DAY_NAMES[_1]}#{s}" })
    end

    # "every month", "every other week", "every 3 days"; unit nil for weekdays, which take the interval in weeks
    def every(unit)
      n = @parts.interval
      return "every" if unit.nil? && n == 1
      return "every #{unit}".rstrip if n == 1
      return "every other #{unit}".rstrip if n == 2
      unit ? "every #{n} #{unit}s" : "every #{n} weeks on"
    end

    def ordinal(n) = n == -1 ? "last" : n < 0 ? "#{ORDINALS[-n]} to last" : ORDINALS[n]

    def nth(n) = "#{n}#{n % 100 / 10 == 1 ? "th" : { 1 => "st", 2 => "nd", 3 => "rd" }.fetch(n % 10, "th")}"

    def list(items) = items.size == 1 ? items[0] : "#{items[0..-2].join(", ")} and #{items[-1]}"
  end
end
require_relative "rule/cron"
