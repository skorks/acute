module Acute
  def self.with(now: nil, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil,
                fiscal_year_start: nil, strict: true, dst: nil, holidays: nil, business_days: nil, year_bias: nil)
    Parser.new(now: now, zone: zone, context: context, locale: locale, week_start: week_start,
               hemisphere: hemisphere, fiscal_year_start: fiscal_year_start, strict: strict, dst: dst,
               holidays: holidays, business_days: business_days, year_bias: year_bias)
  end

  # Every entry point with the same options. Frozen and Ractor-shareable; options given to a call override
  # the parser's (D45). D47: a holidays: or business_days: object is kept as given, not frozen, so a parser
  # holding one is shareable only if the object already is.
  class Parser
    attr_reader :options

    def initialize(now: nil, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil,
                   fiscal_year_start: nil, strict: true, dst: nil, holidays: nil, business_days: nil, year_bias: nil)
      ctx = Context.new(now, zone, context, locale, week_start, hemisphere, fiscal_year_start, strict, dst, holidays,
                        business_days, year_bias)
      # A now that carries a zone (a TimeWithZone) gives the parser that zone, as each call would infer it
      zone ||= ctx.zone.name if Context.carried_zone(now)
      # Copies, so making the parser shareable freezes nothing of the caller's
      opts = { now: now && Time.at(ctx.now).utc, zone: zone && -ctx.zone.name, context: context,
               locale: locale && -locale.to_s, week_start: week_start&.to_sym, hemisphere: hemisphere&.to_sym,
               fiscal_year_start: fiscal_year_start && Integer(fiscal_year_start), strict: strict == false ? false : nil,
               dst: dst&.to_sym, year_bias: year_bias && Integer(year_bias) }
      # A region is copied; an object answering holiday? or business_day? is the caller's, so it is kept as is
      holidays = Array(holidays).map(&:to_sym) if Symbol === holidays || String === holidays || Array === holidays
      @options = opts.merge(holidays: holidays, business_days: business_days).compact
      objects = [holidays, business_days].compact.reject { Array === _1 }
      if objects.all? { Ractor.shareable?(_1) }
        Ractor.make_shareable(self)
      else
        @options.each_value { Ractor.make_shareable(_1) unless objects.include?(_1) }
        @options.freeze
        freeze
      end
    end

    def parse(text, **ctx) = Acute.parse(text, **@options, **ctx)

    def parse!(text, **ctx) = Acute.parse!(text, **@options, **ctx)

    def read(text, **ctx) = Acute.read(text, **@options, **ctx)

    def extract(text, **ctx) = Acute.extract(text, **@options, **ctx)

    def describe(value, **ctx) = Acute.describe(value, **@options, **ctx)

    def verify(text, value, **ctx) = Acute.verify(text, value, **@options, **ctx)

    def duration(text, **ctx) = Acute.duration(text, **@options, **ctx)

    def duration!(text, **ctx) = Acute.duration!(text, **@options, **ctx)

    def recurrence(text, **ctx) = Acute.recurrence(text, **@options, **ctx)

    def recurrence!(text, **ctx) = Acute.recurrence!(text, **@options, **ctx)

    def with(**more) = Parser.new(**@options, **more)

    def inspect = "#<Acute::Parser #{@options.map { "#{_1}: #{_2.inspect}" }.join(", ")}>"
  end
end
