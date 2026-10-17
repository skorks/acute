require "date"
require_relative "calendar"
require_relative "zone"
require_relative "assumption"
require_relative "locale"

module Acute
  # Everything a parse depends on besides the text: now, the zone and the direction. It also collects the
  # assumptions the resolver makes, so it is built fresh for every parse.
  class Context
    ISO = /\A(\d{4})-(\d\d)-(\d\d)(?:[T ](\d\d):(\d\d)(?::(\d\d)(?:\.\d+)?)?)?(Z|[+-]\d\d:?\d\d)?\z/

    def self.system_zone
      tz = ENV["TZ"]
      return tz if tz && !tz.empty? && TZInfo::Timezone.all_identifiers.include?(tz)
      target = File.readlink("/etc/localtime")
      target[/zoneinfo\/(.+)\z/, 1] || "UTC"
    rescue SystemCallError
      "UTC"
    end

    SYSTEM_ZONE = system_zone.freeze
    ZONE_INFERRED = Assumption.for(:zone_inferred)
    NO_NOTES = [].freeze

    WEEK_STARTS = { sunday: 0, monday: 1 }.freeze
    HEMISPHERES = { north: false, south: true }.freeze

    attr_reader :now, :now_local, :zone, :today, :now_secs, :notes, :fiscal_year_start
    attr_accessor :dst, :past, :machine

    def initialize(now, zone, context, locale = nil, week_start = nil, hemisphere = nil, fiscal_year_start = nil)
      @past = case context
              when :future then false
              when :past then true
              else raise ArgumentError, "context: must be :future or :past"
              end
      if zone
        @zone = Zone.for(zone)
      else
        @zone = Zone.for(carried_zone(now) || rails_zone || SYSTEM_ZONE)
        @inferred = true
      end
      @now = Time === now ? now.to_i : epoch(now)
      self.zone = @zone
      @locale = Locale.for(locale) if locale
      @locale_zone = @zone.name
      @week_start = week_start && WEEK_STARTS.fetch(week_start.to_sym) { raise ArgumentError, "week_start: must be :sunday or :monday" }
      @south = hemisphere && HEMISPHERES.fetch(hemisphere.to_sym) { raise ArgumentError, "hemisphere: must be :north or :south" }
      @fiscal_year_start = fiscal_year_start && Integer(fiscal_year_start)
    end

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

    # The occurrences of one periodic node already found, by cycle index: "next friday" looks at the same
    # weeks several times
    def occurrences(node)
      return @occurrences if @occurrences_of.equal?(node)
      @occurrences_of = node
      @occurrences = {}
    end

    def note(assumption)
      if @notes
        @notes << assumption unless @notes.include?(assumption)
      else
        @notes = [assumption]
      end
    end

    # The main reading's assumptions: the rules applied, then its DST adjustment, then the zone
    def assumptions(main)
      return NO_NOTES unless @notes || main.dst || @inferred
      list = @notes || []
      list << Assumption.for(main.dst) if main.dst
      list << ZONE_INFERRED if @inferred
      list.freeze
    end

    private

    def carried_zone(now)
      if now.respond_to?(:time_zone) then now.time_zone.tzinfo
      elsif now.is_a?(Time) && now.zone.is_a?(TZInfo::Timezone) then now.zone
      end
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
        raise ArgumentError, "now: must be a Time, Date or ISO 8601 String"
      end
    end

    def iso_epoch(str)
      m = ISO.match(str) or raise ArgumentError, "now: #{str.inspect} is not ISO 8601"
      y, mo, d, h, mi, s = m.captures.first(6).map(&:to_i)
      unless mo.between?(1, 12) && d.between?(1, Calendar.days_in_month(y, mo)) && h < 24 && mi < 60 && s < 60
        raise ArgumentError, "now: #{str.inspect} is not a valid time"
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
