module Acute
  def self.verify(text, value, now: nil, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil,
                  fiscal_year_start: nil)
    ctx = Context.new(now, zone, context, locale, week_start, hemisphere, fiscal_year_start)
    opts = { now: Time.at(ctx.now), zone: zone, context: context, locale: locale, week_start: week_start,
             hemisphere: hemisphere, fiscal_year_start: fiscal_year_start }
    Verify.new(text, value, ctx, opts).verdict
  end

  # Whether a time someone else worked out is what the text says. The message is written to go straight back
  # to a model (D45).
  class Verdict
    STATUSES = %i[match inside alternative mismatch unparsed].freeze
    OK = %i[match inside alternative].freeze

    attr_reader :text, :status, :message, :expected

    def initialize(text, status, message, expected)
      @text = text
      @status = status
      @message = message
      @expected = expected
      freeze
    end

    def ok? = OK.include?(@status)

    def to_h = { kind: "verdict", text: @text, status: @status.to_s, ok: ok?, message: @message, expected: @expected&.to_h }

    def to_json(*args) = to_h.to_json(*args)

    def as_json(*) = JSON.parse(to_json)

    def inspect = "#<Acute::Verdict #{@status} #{@message.inspect}>"
  end

  class Verify
    DAY = 86_400
    ORDINALS = %w[first second third fourth fifth sixth seventh eighth ninth tenth].freeze
    DATE = /\A\d{4}-\d\d-\d\d\z/

    def initialize(text, value, ctx, opts)
      @text = text
      @ctx = ctx
      @zone = ctx.zone
      @opts = opts
      @given = given(value)
      @value = target(value)
    end

    def verdict
      r = Acute.parse!(@text, **@opts)
      if (rel = relation(r))
        return Verdict.new(@text, rel, rel == :match ? matched(r) : inside(r), r)
      end
      r.alternatives.each_with_index do |alt, i|
        next unless relation(alt)
        return Verdict.new(@text, :alternative, "#{@given} is the #{ORDINALS[i + 1] || "#{i + 2}th"} reading of " \
                                                "#{@text.inspect}; the first is #{label(r)}. Ask the user which they meant.", r)
      end
      Verdict.new(@text, :mismatch, "#{@text.inspect} is #{label(r)}#{others(r, " (or %s)")}, not #{label(@value)}.", r)
    rescue ParseError => e
      Verdict.new(@text, :unparsed, "#{@text.inspect} can't be read as a time: #{e.message}. Ask the user to say it " \
                                    "another way.", nil)
    end

    private

    def matched(r) = "#{@given} matches #{@text.inspect}: #{label(r)}.#{others(r, " It can also mean %s; ask the user if that matters.")}"

    def inside(r) = "#{@given} is inside #{@text.inspect}, which is #{label(r)}.#{others(r, " It can also mean %s; ask the user if that matters.")}"

    def others(r, form) = r.ambiguous? ? format(form, r.alternatives.map { label(_1) }.join(" or ")) : ""

    # A date ("2026-10-23", a Date or a range of them) is checked by its days; anything else by its instants
    def target(value)
      @days = Date === value || (Range === value && (Date === value.begin || Date === value.end))
      if String === value
        @days = DATE.match?(value)
        r = (Acute.parse(value, **@opts) if value.match?(/\A\d{4}-\d\d-\d\d/))
        raise ArgumentError, "value must be a Time, Date, Range or ISO 8601 string, got #{value.inspect}" unless r && !r.ambiguous?
        value = r
      end
      Describe::Target.for(value, @ctx)
    end

    def given(value)
      case value
      when String then value
      when Date then value.iso8601
      when Range then "#{given(value.begin) if value.begin}#{value.exclude_end? ? "..." : ".."}#{given(value.end) if value.end}"
      else value.respond_to?(:to_time) ? value.to_time.getlocal(@zone.offset_at(value.to_time.to_i)).strftime("%FT%T%:z") : value.inspect
      end
    end

    # :match when the reading is the value, :inside when the value lies within it
    def relation(r)
      v = @value
      span = [r.begin&.to_i, r.end&.to_i]
      if @days
        return :match if cover(r) == [v.b, v.e]
      elsif v.instant
        return :match if r.instant? && r.time.to_i == v.point
        return r.instant? || !within?(span, v.point, v.point + 1) ? nil : :inside
      elsif !r.instant? && span == [v.b, v.e]
        return :match
      end
      :inside if !r.instant? && within?(span, v.b, v.e)
    end

    def within?((b, e), vb, ve) = (b.nil? || (vb && vb >= b)) && (e.nil? || (ve && ve <= e))

    # The whole days a reading falls on; one of a day or less ("tonight", "3pm") is its point's day
    def cover(r)
      b = r.begin&.to_i
      e = r.end&.to_i
      if b && e && e - b <= DAY
        d = day_of(r.time.to_i)
        return [day_start(d), day_start(d + 1)]
      end
      [b && day_start(day_of(b)), e && day_start(day_of(e - 1) + 1)]
    end

    # "Fri 23 Oct", "Fri 23 Oct, 3pm", "Sat 17 Oct – Sun 18 Oct", "from Sat 24 Oct": one form whatever the
    # locale, as the reader is a model
    def label(x)
      if Result === x
        return @days ? day(day_of(x.time.to_i)) : moment(x.time.to_i) if x.instant?
        b, e = @days ? cover(x) : [x.begin&.to_i, x.end&.to_i]
      else
        return moment(x.point) if x.instant
        b = x.b
        e = x.e
      end
      return "from #{edge(b)}" unless e
      return "before #{edge(e)}" unless b
      return days(b, e) if aligned?(b) && aligned?(e)
      return "#{moment(b)} – #{Describe.clock(secs_of(e))}" if day_of(b) == day_of(e)
      "#{moment(b)} – #{moment(e)}"
    end

    def days(b, e)
      first = day_of(b)
      last = day_of(e - 1)
      first == last ? day(first) : "#{day(first)} – #{day(last)}"
    end

    def edge(t) = aligned?(t) ? day(day_of(t)) : moment(t)

    def moment(t) = "#{day(day_of(t))}, #{Describe.clock(secs_of(t))}"

    def day(d)
      x = Calendar.civil_from_days(d)
      year = x / 10_000 == Calendar.civil_from_days(@ctx.today) / 10_000 ? "" : " #{x / 10_000}"
      "#{Result::WEEKDAYS[Calendar.weekday(d)]} #{x % 100} #{Result::MONTHS[x / 100 % 100 - 1]}#{year}"
    end

    def local(t) = t + @zone.offset_at(t)

    def day_of(t) = local(t).div(DAY)

    def secs_of(t) = local(t) % DAY

    def day_start(d) = @zone.local_to_utc(d * DAY, @ctx)

    def aligned?(t) = day_start(day_of(t)) == t
  end
end
