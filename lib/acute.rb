require_relative "acute/version"
require_relative "acute/errors"
require_relative "acute/context"
require_relative "acute/lexer"
require_relative "acute/grammar"
require_relative "acute/resolve"
require_relative "acute/result"
require_relative "acute/explain"
require_relative "acute/duration"
require_relative "acute/extract"
require_relative "acute/read"
require_relative "acute/describe"

module Acute
  MAX_LENGTH = 512

  # The options are spelled out rather than taken as **options, which would cost every parse a Hash
  def self.parse(text, now: nil, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil,
                 fiscal_year_start: nil)
    out = run(text, Context.new(now, zone, context, locale, week_start, hemisphere, fiscal_year_start))
    Result === out ? out : nil
  end

  def self.parse!(text, now: nil, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil,
                  fiscal_year_start: nil)
    out = run(text, Context.new(now, zone, context, locale, week_start, hemisphere, fiscal_year_start))
    raise Explain.error(out, text) if Failure === out
    out
  end

  # A length of time, or nil when the text is not one ("next friday" is a time)
  def self.duration(text)
    raise ArgumentError, "text must be a String, got #{text.class}" unless String === text
    return if text.bytesize > MAX_LENGTH
    tokens = Lexer.lex(text)
    return if Failure === tokens
    units = Grammar.duration(tokens)
    Failure === units ? nil : Duration.from_units(units)
  end

  def self.extract(text, now: nil, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil,
                   fiscal_year_start: nil)
    raise ArgumentError, "text must be a String, got #{text.class}" unless String === text
    options = [locale, week_start, hemisphere, fiscal_year_start]
    Context.new(now, zone, context, *options) # bad options raise here, before any mention is found
    Extract.call(text, -> { Context.new(now, zone, context, *options) })
  end

  def self.run(text, ctx)
    raise ArgumentError, "text must be a String, got #{text.class}" unless String === text
    return Failure.new(:too_long, 0, text.bytesize) if text.bytesize > MAX_LENGTH && text.length > MAX_LENGTH
    tokens = Lexer.lex(text)
    return tokens if Failure === tokens
    tree = Grammar.parse(tokens)
    return tree if Failure === tree
    readings = Resolve.call(tree, ctx)
    return Failure.new(:invalid_date, 0, text.bytesize) if readings.empty?
    Result.new(text, readings, ctx.zone, ctx.assumptions(readings[0]))
  end
  private_class_method :run
end
