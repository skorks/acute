module Acute
  def self.with(now: nil, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil,
                fiscal_year_start: nil)
    Parser.new(now: now, zone: zone, context: context, locale: locale, week_start: week_start,
               hemisphere: hemisphere, fiscal_year_start: fiscal_year_start)
  end

  # Every entry point with the same options. Frozen and Ractor-shareable; options given to a call override
  # the parser's (D45).
  class Parser
    attr_reader :options

    def initialize(now: nil, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil,
                   fiscal_year_start: nil)
      ctx = Context.new(now, zone, context, locale, week_start, hemisphere, fiscal_year_start)
      # A now that carries a zone (a TimeWithZone) gives the parser that zone, as each call would infer it
      zone ||= ctx.zone.name if Context.carried_zone(now)
      # Copies, so making the parser shareable freezes nothing of the caller's
      opts = { now: now && Time.at(ctx.now).utc, zone: zone && -ctx.zone.name, context: context,
               locale: locale && -locale.to_s, week_start: week_start&.to_sym, hemisphere: hemisphere&.to_sym,
               fiscal_year_start: fiscal_year_start && Integer(fiscal_year_start) }
      @options = opts.compact
      Ractor.make_shareable(self)
    end

    def parse(text, **ctx) = Acute.parse(text, **@options, **ctx)

    def parse!(text, **ctx) = Acute.parse!(text, **@options, **ctx)

    def read(text, **ctx) = Acute.read(text, **@options, **ctx)

    def extract(text, **ctx) = Acute.extract(text, **@options, **ctx)

    def describe(value, **ctx) = Acute.describe(value, **@options, **ctx)

    def verify(text, value, **ctx) = Acute.verify(text, value, **@options, **ctx)

    def duration(text) = Acute.duration(text)

    def with(**more) = Parser.new(**@options, **more)

    def inspect = "#<Acute::Parser #{@options.map { "#{_1}: #{_2.inspect}" }.join(", ")}>"
  end
end
