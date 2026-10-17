require "date"
require_relative "calendar"
require_relative "zone"
require_relative "assumption"

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

    attr_reader :now, :zone, :today, :now_secs, :notes
    attr_accessor :dst

    def initialize(now, zone, context)
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
      @now = epoch(now)
      local = @now + @zone.offset_at(@now)
      @today = local.div(86_400)
      @now_secs = local - @today * 86_400
      @dst = nil
    end

    def past? = @past

    def note(assumption)
      if @notes
        @notes << assumption unless @notes.include?(assumption)
      else
        @notes = [assumption]
      end
    end

    # The main reading's assumptions: the rules applied, then its DST adjustment, then the zone
    def assumptions(main)
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
