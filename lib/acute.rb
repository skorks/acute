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
require_relative "acute/verify"
require_relative "acute/parser"

module Acute
  MAX_LENGTH = 512

  SKIPPED = Assumption.for(:unknown_words_skipped)

  # The options are spelled out rather than taken as **options, which would cost every parse a Hash
  def self.parse(text, now: nil, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil,
                 fiscal_year_start: nil, strict: true, dst: nil, holidays: nil, business_days: nil, year_bias: nil)
    out = run(text, Context.new(now, zone, context, locale, week_start, hemisphere, fiscal_year_start, strict, dst,
                                holidays, business_days, year_bias))
    Result === out ? out : nil
  end

  def self.parse!(text, now: nil, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil,
                  fiscal_year_start: nil, strict: true, dst: nil, holidays: nil, business_days: nil, year_bias: nil)
    out = run(text, Context.new(now, zone, context, locale, week_start, hemisphere, fiscal_year_start, strict, dst,
                                holidays, business_days, year_bias))
    raise Explain.error(out, text) if Failure === out
    out
  end

  # A length of time, or nil when the text is not one ("next friday" is a time). The options are taken for
  # the same calls as everything else; a length doesn't depend on them.
  def self.duration(text, now: nil, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil,
                    fiscal_year_start: nil, strict: true, dst: nil, holidays: nil, business_days: nil, year_bias: nil)
    raise ArgumentError, "text must be a String, got #{text.class}" unless String === text
    return if text.bytesize > MAX_LENGTH
    tokens = Lexer.lex(text)
    return if Failure === tokens
    units = Grammar.duration(tokens)
    Failure === units ? nil : Duration.from_units(units)
  end

  # strict: is taken and has no effect: extract always skips the words it doesn't know
  def self.extract(text, now: nil, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil,
                   fiscal_year_start: nil, strict: true, dst: nil, holidays: nil, business_days: nil, year_bias: nil)
    raise ArgumentError, "text must be a String, got #{text.class}" unless String === text
    options = [locale, week_start, hemisphere, fiscal_year_start, strict, dst, holidays, business_days, year_bias]
    Context.new(now, zone, context, *options) # bad options raise here, before any mention is found
    Extract.call(text, -> { Context.new(now, zone, context, *options) })
  end

  def self.run(text, ctx)
    raise ArgumentError, "text must be a String, got #{text.class}" unless String === text
    return Failure.new(:too_long, 0, text.bytesize) if text.bytesize > MAX_LENGTH && text.length > MAX_LENGTH
    tokens = Lexer.lex(text)
    return ctx.strict ? tokens : skipping(text, ctx, tokens) if Failure === tokens
    tree = Grammar.parse(tokens)
    return tree if Failure === tree
    readings = Resolve.call(tree, ctx)
    return Failure.new(:invalid_date, 0, text.bytesize) if readings.empty?
    if ctx.dst_policy == :reject
      return Failure.new(readings[0].dst, 0, text.bytesize) if readings[0].dst
      readings = readings.reject(&:dst)
    end
    Result.new(text, readings, ctx.zone, ctx.assumptions(readings[0]))
  end
  private_class_method :run

  # D47: strict: false skips the words it doesn't know, as chronic did: the first time in the text, found as
  # extract finds it, or the lexer's failure when there is none
  def self.skipping(text, ctx, failure)
    found = Extract.call(text, -> { ctx.fresh.tap { _1.note(SKIPPED) } }, text).mentions.find { _1.kind == :time }
    found ? found.value : failure
  end
  private_class_method :skipping
end
