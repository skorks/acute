require_relative "../acute"

# chronic 0.10.2's API on acute's parser, for code written against chronic. It takes chronic's options and
# returns what chronic returns, but the answers follow acute's rules (D46).
module Chronic
  VERSION = "0.10.2"

  class << self
    attr_accessor :time_class, :debug

    def parse(text, options = {}) = Parser.new(options).parse(text)
  end
  self.time_class = ::Time
  self.debug = false

  class Span < Range
    def width = (self.end - self.begin).to_i

    def +(other) = Span.new(self.begin + other, self.end + other)

    def -(other) = self + -other

    def to_s = "(#{self.begin}..#{self.end})"
  end

  class Parser
    DEFAULT_OPTIONS = {
      context: :future, now: nil, hours24: nil, week_start: nil, guess: true, ambiguous_time_range: 6,
      endian_precedence: %i[middle little], ambiguous_year_future_bias: 50
    }.freeze

    Reading = Struct.new(:begin, :end, :point, :span, :frac)
    Notes = Struct.new(:dst)
    NUMERIC_DATE = %r{(?<!\d)(\d{1,2})[/\-.](\d{1,2})(?!\d)}

    attr_accessor :now
    attr_reader :options

    def initialize(options = {})
      @options = DEFAULT_OPTIONS.merge(options)
      @endian = options[:endian_precedence]
      @now = @options[:now] || Chronic.time_class.now
    end

    def parse(text)
      zone = Acute::Zone.for(zone_name)
      result = read(text.to_s, zone) or return
      reading = choose(result, text.to_s, zone)
      out = guess_reading(reading, zone, @options[:guess])
      Range === out ? Span.new(at(out.begin), at(out.end)) : at(out)
    end

    def guess(span, mode = :middle)
      return span unless mode
      return span.end if mode == :end
      return span.begin unless span.width > 1 && (mode == true || mode == :middle)
      # the middle on the wall clock, so a day with a DST change still guesses 12:00 (D46)
      shift = span.begin.utc_offset - span.end.utc_offset
      late = span.begin + (span.width + shift) / 2
      late.utc_offset == span.end.utc_offset ? late : span.begin + (span.width - shift) / 2
    end

    private

    # Chronic skips words it doesn't know, as acute does with strict: false: text with such words gives the
    # first time mentioned in it; text acute knows every word of and still refuses ("5th tuesday in february")
    # stays nil (D46)
    def read(text, zone)
      Acute.parse(text, now: @now, zone: zone.name, context: @options[:context] == :past ? :past : :future,
                        week_start: @options[:week_start], strict: false,
                        year_bias: @options[:ambiguous_year_future_bias])
    end

    # Chronic's options for ambiguous text pick among acute's readings; acute's order stands where they don't
    def choose(result, text, zone)
      codes = result.assumptions.map(&:code)
      clock = nil
      all = ([result] + result.alternatives).map do |r|
        # D47: chronic guesses inside every span but a clock time someone said ("4pm", "at 5:30"), so "next
        # hour", one grain long and an instant to acute, is guessed too
        long = !r.span? && r.end - r.begin > 1
        clock = said_clock?(result.matched) if long && clock.nil?
        span = r.span? || (long && !clock)
        Reading.new(r.begin&.to_i, r.end&.to_i, r.time.to_i, span, r.time.subsec)
      end
      all = prefer(all) { |r| hour_window.include?(wall(r.point, zone) / 3600 % 24) } if codes.include?(:bare_hour_window)
      # only when given: without it the locale decides, as D10 says
      if @endian && codes.include?(:numeric_date_order) && (m = NUMERIC_DATE.match(text))
        a, b = m[1].to_i, m[2].to_i
        Array(@endian).reverse_each do |endian|
          all = prefer(all) do |r|
            _, month, day = civil(r.point, zone)
            endian == :little ? [day, month] == [a, b] : [month, day] == [a, b]
          end
        end
      end
      all.first
    end

    def said_clock?(text) = clock_in?(Acute::Grammar.parse(Acute::Lexer.lex(text)))

    def clock_in?(node)
      case node
      when Acute::Grammar::Clock then true
      when Struct, Array then node.each.any? { clock_in?(_1) }
      else false
      end
    end

    def prefer(all)
      hits = all.select { yield _1 }
      hits.empty? ? all : hits + (all - hits)
    end

    # The hours an hour written without am/pm may mean: chronic's window from ambiguous_time_range, or the
    # hour as written under hours24
    def hour_window
      range = @options[:ambiguous_time_range]
      start = @options[:hours24] == true || range == :none ? 1 : Integer(range)
      start...start + 12
    end

    # Epochs, or a Range of them when guess is false, which in chronic always returns a Span; an instant keeps
    # its written fraction of a second (D47)
    def guess_reading(r, zone, mode)
      return (r.begin && r.begin + r.frac)..(r.end && r.end + r.frac) unless mode || (r.begin.nil? && r.end.nil?)
      return r.point + r.frac unless r.span && r.begin && r.end
      return r.end if mode == :end
      return r.begin unless mode == true || mode == :middle
      mid = (wall(r.begin, zone) + wall(r.end, zone)) / 2
      zone.local_to_utc(mid, Notes.new)
    end

    def wall(epoch, zone) = epoch + zone.offset_at(epoch)

    def civil(epoch, zone)
      ymd = Acute::Calendar.civil_from_days(wall(epoch, zone).div(86_400))
      [ymd / 10_000, ymd / 100 % 100, ymd % 100]
    end

    # Chronic builds times in time_class: Time's local zone, or a zone like Time.zone
    def zone_name
      klass = Chronic.time_class
      return klass.tzinfo if klass.respond_to?(:tzinfo)
      tz = ENV["TZ"]
      cached = Parser.system_zone
      return cached[1] if cached && cached[0] == tz
      Parser.system_zone = [tz, Acute::Context.system_zone]
      Parser.system_zone[1]
    end

    def at(epoch)
      return if epoch.nil?
      klass = Chronic.time_class
      return klass.at(epoch) if klass.respond_to?(:tzinfo)
      time = Time.at(epoch)
      if klass == ::Date then time.to_date
      elsif klass == ::DateTime then time.to_datetime
      else time
      end
    end

    class << self
      attr_accessor :system_zone
    end
  end
end
