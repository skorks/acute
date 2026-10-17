require "tzinfo"

module Acute
  # A zone's UTC offsets as a table compiled once from tzinfo, so lookups are a binary search over Integers.
  # Times are epoch seconds; a "local" time is wall-clock seconds counted as if the wall clock were UTC.
  class Zone
    FROM = Time.utc(1800).freeze # before any zone's first transition (1844), so local mean time is kept
    TO = Time.utc(2200).freeze
    # IANA names with an area, by their lower case, for the lexer
    NAMES = Ractor.make_shareable(TZInfo::Timezone.all_identifiers.select { _1.include?("/") }.to_h { [_1.downcase, _1.to_sym] })
    FIXED = /\A([+-])(\d\d):(\d\d)\z/
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
             else raise ArgumentError, "zone: must be an IANA name, a TZInfo::Timezone or an offset like \"+10:00\""
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
      unless Ractor.main?
        # Another Ractor keeps its own: fixed offsets build anywhere, and a named zone fails in build
        return Ractor.store_if_absent(:acute_zones) { {} }[key] ||= Ractor.make_shareable(yield)
      end
      zone = Ractor.make_shareable(yield)
      @zones = Ractor.make_shareable(@zones.merge(key => zone))
      zone
    end
    private_class_method :add

    def self.build(name)
      if (m = FIXED.match(name))
        offset = (m[2].to_i * 3600 + m[3].to_i * 60) * (m[1] == "-" ? -1 : 1)
        return new(name, [], [], [], offset, name)
      end
      unless Ractor.main?
        raise ArgumentError, "zone #{name.inspect} is loaded from tzinfo, which only the main Ractor can use: " \
                             "parse with it there once first"
      end
      tz = TZInfo::Timezone.get(name)
      trs = tz.transitions_up_to(TO, FROM)
      first = trs.empty? ? tz.period_for_utc(FROM).offset : trs.first.previous_offset
      new(name, trs.map(&:timestamp_value), trs.map { |t| t.offset.observed_utc_offset },
          trs.map { |t| t.offset.abbreviation }, first.observed_utc_offset, first.abbreviation)
    rescue TZInfo::InvalidTimezoneIdentifier
      raise ArgumentError, "unknown zone #{name.inspect}"
    end

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
