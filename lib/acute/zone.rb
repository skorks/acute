require "tzinfo"

module Acute
  # A zone's UTC offsets as a table compiled once from tzinfo, so lookups are a binary search over Integers.
  # Times are epoch seconds; a "local" time is wall-clock seconds counted as if the wall clock were UTC.
  class Zone
    FROM = Time.utc(1800).freeze # before any zone's first transition (1844), so local mean time is kept
    TO = Time.utc(2200).freeze
    # IANA names with an area, by their lower case, for the lexer
    NAMES = Ractor.make_shareable(TZInfo::Timezone.all_identifiers.select { _1.include?("/") }.to_h { [_1.downcase, _1.to_sym] })
    FIXED = /\A([+-])([01]\d|2[0-3]):([0-5]\d)\z/
    # Lookups start from a bucket of 2**22 seconds (about 48 days), so they skip the binary search
    BUCKET_SHIFT = 22
    BUCKET_BASE = FROM.to_i
    BUCKETS = ((TO.to_i - BUCKET_BASE) >> BUCKET_SHIFT) + 1
    # Name (or a fixed offset in seconds) => Zone. Shareable and replaced rather than changed, so every Ractor
    # can read it. Only the main Ractor can reach tzinfo, so only it adds to it; two threads adding at once
    # may drop one zone, to be built again.
    @zones = Ractor.make_shareable({})

    def self.for(zone)
      name = case zone
             when String then zone
             when TZInfo::Timezone then zone.identifier
             else raise OptionError.new("zone: must be an IANA name, a TZInfo::Timezone or an offset like \"+10:00\"", option: :zone, value: zone)
             end
      @zones[name] || add(name) { build(name) }
    end

    # The zone fixed at offset seconds from UTC, for an offset in the text
    def self.fixed(offset)
      @zones[offset] || add(offset) do
        self.for(format("%s%02d:%02d", offset < 0 ? "-" : "+", offset.abs / 3600, offset.abs / 60 % 60))
      end
    end

    def self.add(key)
      unless main_ractor?
        # Another Ractor keeps its own: fixed offsets build anywhere, and a named zone fails in build
        return ractor_zones[key] ||= Ractor.make_shareable(yield)
      end
      zone = Ractor.make_shareable(yield)
      @zones = Ractor.make_shareable(@zones.merge(key => zone))
      zone
    end
    private_class_method :add

    # Ractor.main? and Ractor.store_if_absent are Ruby 3.4's; on 3.3 two threads starting a Ractor's own cache at
    # once may each make one, and the zones of the one dropped are built again
    def self.main_ractor? = Ractor.current == Ractor.main

    def self.ractor_zones
      return Ractor.store_if_absent(:acute_zones) { {} } if Ractor.respond_to?(:store_if_absent)
      Ractor.current[:acute_zones] ||= {}
    end
    private_class_method :main_ractor?, :ractor_zones

    def self.build(name)
      raise OptionError.new("unknown zone #{name.inspect}", option: :zone, value: name) unless name.valid_encoding?
      if (m = FIXED.match(name))
        offset = (m[2].to_i * 3600 + m[3].to_i * 60) * (m[1] == "-" ? -1 : 1)
        return new(name, [], [], [], offset, name)
      end
      unless main_ractor?
        raise OptionError.new("zone #{name.inspect} is loaded from tzinfo, which only the main Ractor can use: " \
                              "parse with it there once first", option: :zone, value: name)
      end
      tz = TZInfo::Timezone.get(name)
      trs = tz.transitions_up_to(TO, FROM)
      first = trs.empty? ? tz.period_for_utc(FROM).offset : trs.first.previous_offset
      ats = trs.map(&:timestamp_value)
      offsets = trs.map { |t| t.offset.observed_utc_offset }
      abbreviations = trs.map { |t| t.offset.abbreviation }
      recurring(trs).each do |at, offset, abbreviation|
        ats << at
        offsets << offset
        abbreviations << abbreviation
      end
      new(name, ats, offsets, abbreviations, first.observed_utc_offset, first.abbreviation)
    rescue TZInfo::InvalidTimezoneIdentifier
      raise OptionError.new("unknown zone #{name.inspect}", option: :zone, value: name)
    end

    RULE_YEARS = 8
    # Every source's data runs at least this far (2038 is the 32-bit limit), and a zone whose clock changes
    # stop before it has stopped changing its clocks
    RULES_RUN_TO = Time.utc(2037).to_i

    # D47: tzinfo's data can stop decades short of TO (tzinfo-data's about fifty years out). When the last
    # 2 * RULE_YEARS changes alternate between two that each fall yearly on one weekday on or after one day of
    # their month, at one wall time, and run past RULES_RUN_TO, both are carried on to TO.
    def self.recurring(trs)
      return [] unless trs.last && trs.last.timestamp_value > RULES_RUN_TO
      changes = trs.last(2 * RULE_YEARS).map do |t|
        before = t.previous_offset.observed_utc_offset
        local = t.timestamp_value + before
        days = local.div(86_400)
        ymd = Calendar.civil_from_days(days)
        [ymd / 10_000, ymd / 100 % 100, ymd % 100, Calendar.weekday(days), local % 86_400, before,
         t.offset.observed_utc_offset, t.offset.abbreviation]
      end
      return [] if changes.size < 2 * RULE_YEARS
      [0, 1].flat_map do |s|
        years = (0...RULE_YEARS).map { changes[2 * _1 + s] }
        return [] unless years.each_cons(2).all? { |a, b| b[0] == a[0] + 1 }
        return [] unless years.map { |c| c.values_at(1, 3, 4, 5, 6, 7) }.uniq.size == 1
        day = years.map { _1[2] }.min
        return [] if years.map { _1[2] }.max - day > 6
        _, month, _, weekday, wall, before, offset, abbreviation = years[-1]
        ((years[-1][0] + 1)...TO.year).map do |y|
          first = Calendar.days_from_civil(y, month, day)
          d = first + (weekday - Calendar.weekday(first)) % 7
          d -= 7 if d - first + day > Calendar.days_in_month(y, month) # "the last Sunday of February"
          [d * 86_400 + wall - before, offset, abbreviation]
        end
      end.sort_by!(&:first)
    end
    private_class_method :recurring

    attr_reader :name

    def initialize(name, ats, offsets, abbreviations, first_offset, first_abbreviation)
      @name = name.dup.freeze
      @ats = ats.freeze
      @offsets = offsets.freeze
      @abbreviations = abbreviations.freeze
      @first_offset = first_offset
      @first_abbreviation = first_abbreviation
      @buckets = buckets(ats).freeze
      freeze
    end

    # period_index inlined, as every parse asks this at least once
    def offset_at(epoch)
      b = (epoch - BUCKET_BASE) >> BUCKET_SHIFT
      return @first_offset if b < 0
      ats = @ats
      i = @buckets[b < BUCKETS ? b : BUCKETS - 1]
      i += 1 while i + 1 < ats.size && ats[i + 1] <= epoch
      i < 0 ? @first_offset : @offsets[i]
    end

    # When the UTC offset next changes after epoch, or nil when the zone has no change to come
    def next_change(epoch)
      offset = offset_at(epoch)
      i = period_index(epoch) + 1
      i += 1 while i < @ats.size && @offsets[i] == offset
      @ats[i]
    end

    def abbreviation_at(epoch)
      i = period_index(epoch)
      i < 0 ? @first_abbreviation : @abbreviations[i]
    end

    # Temporal's "compatible" policy: a repeated wall time takes the earlier instant, a skipped one moves
    # forward by the gap. Either case is reported through notes.dst= so callers can record it. D47: policy
    # :earlier or :later takes that instant in both cases.
    def local_to_utc(local, notes, policy = nil)
      i = period_index(local - 86_400)
      return local - (i < 0 ? @first_offset : @offsets[i]) if i + 1 >= @ats.size || @ats[i + 1] > local + 86_400

      o1 = offset_at(local - 86_400)
      o2 = offset_at(local + 86_400)
      return local - o1 if o1 == o2

      u1 = local - o1
      u2 = local - o2
      ok1 = offset_at(u1) == o1
      ok2 = offset_at(u2) == o2
      if ok1 && ok2
        notes.dst = :dst_repeated_time
        policy == :later ? u2 : u1
      elsif ok1 then u1
      elsif ok2 then u2
      else
        notes.dst = :dst_skipped_time
        policy == :earlier ? u2 : u1
      end
    end

    # The offset in force from a to z, or nil when the clocks change within a day of them, so a span converts
    # with one lookup. The day's margin makes it hold for local wall times as well as epochs.
    def steady_offset(a, z)
      i = period_index(a - 86_400)
      return if i + 1 < @ats.size && @ats[i + 1] <= z + 86_400
      i < 0 ? @first_offset : @offsets[i]
    end

    def inspect = "#<Acute::Zone #{@name}>"

    private

    # Index of the last transition at or before epoch, -1 before the first
    def period_index(epoch)
      b = (epoch - BUCKET_BASE) >> BUCKET_SHIFT
      return -1 if b < 0
      ats = @ats
      i = @buckets[b < BUCKETS ? b : BUCKETS - 1]
      i += 1 while i + 1 < ats.size && ats[i + 1] <= epoch
      i
    end

    # For each bucket, the index of the last transition at or before its start
    def buckets(ats)
      i = -1
      Array.new(BUCKETS) do |b|
        start = BUCKET_BASE + (b << BUCKET_SHIFT)
        i += 1 while i + 1 < ats.size && ats[i + 1] <= start
        i
      end
    end
  end
end
