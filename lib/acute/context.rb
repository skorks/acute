require "date"
require_relative "calendar"
require_relative "zone"
require_relative "assumption"
require_relative "locale"
require_relative "holidays"

module Acute
  # Everything a parse depends on besides the text: now, the zone and the direction. It also collects the
  # assumptions the resolver makes, so it is built fresh for every parse.
  class Context
    ISO = /\A(\d{4})-(\d\d)-(\d\d)(?:[T ](\d\d):(\d\d)(?::(\d\d)(?:\.\d+)?)?)?(Z|[+-]\d\d:?\d\d)?\z/

    def self.system_zone
      tz = ENV["TZ"]
      return tz if tz && !tz.empty? && TZInfo::Timezone.all_identifiers.include?(tz)
      target = File.readlink("/etc/localtime")
      target[%r{zoneinfo/(.+)\z}, 1] || "UTC"
    rescue SystemCallError
      "UTC"
    end

    SYSTEM_ZONE = system_zone.freeze
    ZONE_INFERRED = Assumption.for(:zone_inferred)
    NO_NOTES = [].freeze

    WEEK_STARTS = { sunday: 0, monday: 1 }.freeze
    HEMISPHERES = { north: false, south: true }.freeze
    DST_POLICIES = { compatible: nil, earlier: :earlier, later: :later, reject: :reject }.freeze
    YEAR_BIAS = 50

    attr_reader :now, :now_local, :zone, :today, :now_secs, :notes, :fiscal_year_start, :strict, :dst_policy,
                :holidays, :year_bias
    # past: true in past context; :back while resolve looks back for the most recent one, which adds no
    # alternatives of its own (D44)
    attr_accessor :dst, :past, :machine
    # D47: the fraction of a second a clock in the text was written with
    attr_accessor :frac

    # The zone a TimeWithZone, or a Time made with a TZInfo zone, brings with it
    def self.carried_zone(now)
      if now.respond_to?(:time_zone) then now.time_zone.tzinfo
      elsif now.is_a?(Time) && now.zone.is_a?(TZInfo::Timezone) then now.zone
      end
    end

    def initialize(now, zone, context, locale = nil, week_start = nil, hemisphere = nil, fiscal_year_start = nil,
                   strict = true, dst = nil, holidays = nil, business_days = nil, year_bias = nil)
      @past = case context
              when :future then false
              when :past then true
              else raise OptionError.new("context: must be :future or :past", option: :context, value: context)
              end
      if zone
        @zone = Zone.for(zone)
      else
        @zone = Zone.for(Context.carried_zone(now) || rails_zone || SYSTEM_ZONE)
        @inferred = true
      end
      @now = Time === now ? now.to_i : epoch(now)
      self.zone = @zone
      @locale_zone = @zone.name
      @strict = strict
      @year_bias = YEAR_BIAS
      # Most parses give none of the other options, and then skip their checks
      return unless locale || week_start || hemisphere || fiscal_year_start || strict != true || dst || holidays || business_days || year_bias
      options(now, zone, context, locale, week_start, hemisphere, fiscal_year_start, strict, dst, holidays, business_days, year_bias)
    end

    def fresh = Context.new(*@args)

    # D47: the days business-day counts step over, or nil for Monday to Friday. The built-in holidays only name
    # days; a holidays: given is taken as days off.
    def business_days = @business_days || (@holidays && (@workdays ||= Holidays::Workdays.new(@holidays)))

    # Under a zone named in the text, today and now_secs move with it; returns the block's value
    def in_zone(zone)
      home = @zone
      now_local = @now_local
      self.zone = zone
      out = yield
      @zone = home
      @now_local = now_local
      @today = now_local / 86_400
      @now_secs = now_local - @today * 86_400
      out
    end

    private def zone=(zone)
      @zone = zone
      @now_local = local = @now + zone.offset_at(@now)
      @today = local / 86_400
      @now_secs = local - @today * 86_400
    end

    # The wall time of an instant, in local seconds
    def local(utc) = utc + @zone.offset_at(utc)

    # Found only when a phrase needs it, from the zone given rather than one named in the text
    def locale = @locale ||= Locale.for_zone(@locale_zone)

    def week_start = @week_start ||= locale.week_start

    def south = @south.nil? ? (@south = locale.south) : @south

    def past? = @past

    def note(assumption)
      if @notes
        @notes << assumption unless @notes.include?(assumption)
      else
        @notes = [assumption]
      end
    end

    def unnote(assumption) = @notes&.delete(assumption)

    # The main reading's assumptions: the rules applied, then its DST adjustment, then the zone
    def assumptions(main)
      dst = main.dst unless @dst_policy # D47: a policy the caller chose is not an assumption
      return NO_NOTES unless @notes || dst || @inferred
      list = @notes || []
      list << Assumption.for(dst) if dst
      list << ZONE_INFERRED if @inferred
      list.freeze
    end

    private

    def options(now, zone, context, locale, week_start, hemisphere, fiscal_year_start, strict, dst, holidays, business_days, year_bias)
      raise OptionError.new("strict: must be true or false", option: :strict, value: strict) unless strict == true || strict == false
      @locale = Locale.for(locale) if locale
      @week_start = week_start && choice(:week_start, week_start, WEEK_STARTS, ":sunday or :monday")
      @south = hemisphere && choice(:hemisphere, hemisphere, HEMISPHERES, ":north or :south")
      @fiscal_year_start = fiscal_year_start && whole(:fiscal_year_start, fiscal_year_start, 1..12, "a month, 1 to 12")
      unless strict
        # Lenient parsing resolves each piece it tries in a fresh context
        @args = [now || Time.at(@now), zone, context, locale, week_start, hemisphere, fiscal_year_start, strict, dst,
                 holidays, business_days, year_bias]
      end
      @dst_policy = dst && choice(:dst, dst, DST_POLICIES, ":compatible, :earlier, :later or :reject")
      @holidays = holidays && Holidays.for(holidays)
      if business_days
        unless business_days.respond_to?(:business_day?)
          raise OptionError.new("business_days: must answer business_day?(date)", option: :business_days,
value: business_days)
        end
        @business_days = business_days
      end
      @year_bias = whole(:year_bias, year_bias, 0..99, "a number of years, 0 to 99") if year_bias
    end

    def choice(option, value, table, allowed)
      key = (Symbol === value || (String === value && value.valid_encoding?)) && value.to_sym
      table.fetch(key) { raise OptionError.new("#{option}: must be #{allowed}", option: option, value: value) }
    end

    def whole(option, value, range, allowed)
      n = Integer === value ? value : (String === value && Integer(value, 10, exception: false))
      return n if n && range.cover?(n)
      raise OptionError.new("#{option}: must be #{allowed}", option: option, value: value)
    end

    def rails_zone
      Time.zone&.tzinfo if defined?(ActiveSupport::TimeZone) && Time.respond_to?(:zone)
    end

    def epoch(now)
      case now
      when nil then Time.now.to_i
      when Time then now.to_i
      when DateTime then now.to_time.to_i
      when Date then @zone.local_to_utc((now.jd - 2_440_588) * 86_400, self)
      when String then iso_epoch(now)
      else
        return now.to_i if now.respond_to?(:time_zone)
        raise OptionError.new("now: must be a Time, Date or ISO 8601 String", option: :now, value: now)
      end
    end

    def iso_epoch(str)
      m = str.valid_encoding? && ISO.match(str) or raise OptionError.new("now: #{str.inspect} is not ISO 8601", option: :now, value: str)
      y, mo, d, h, mi, s = m.captures.first(6).map(&:to_i)
      unless mo.between?(1, 12) && d.between?(1, Calendar.days_in_month(y, mo)) && h < 24 && mi < 60 && s < 60
        raise OptionError.new("now: #{str.inspect} is not a valid time", option: :now, value: str)
      end
      local = Calendar.days_from_civil(y, mo, d) * 86_400 + h * 3600 + mi * 60 + s
      return @zone.local_to_utc(local, self) unless m[7]
      return local if m[7] == "Z"
      sign = m[7].start_with?("-") ? -1 : 1
      digits = m[7].delete(":")
      local - sign * (digits[1, 2].to_i * 3600 + digits[3, 2].to_i * 60)
    end
  end
end
