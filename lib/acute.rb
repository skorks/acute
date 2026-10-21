require_relative "acute/version"
require_relative "acute/errors"
require_relative "acute/context"
require_relative "acute/lexer"
require_relative "acute/grammar"
require_relative "acute/resolve"
require_relative "acute/result"
require_relative "acute/explain"
require_relative "acute/duration"
require_relative "acute/rule"
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
    raise Explain.error(out, utf8(text) || text) if Failure === out
    out
  end

  # A length of time, or nil when the text is not one ("next friday" is a time). The options are taken for
  # the same calls as everything else; a length doesn't depend on them.
  def self.duration(text, now: nil, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil,
                    fiscal_year_start: nil, strict: true, dst: nil, holidays: nil, business_days: nil, year_bias: nil)
    out = length(text)
    Duration === out ? out : nil
  end

  def self.duration!(text, now: nil, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil,
                     fiscal_year_start: nil, strict: true, dst: nil, holidays: nil, business_days: nil, year_bias: nil)
    out = length(text)
    raise Explain.error(out, utf8(text) || text) if Failure === out
    out
  end

  def self.length(given)
    raise ArgumentError, "text must be a String, got #{given.class}" unless String === given
    text = utf8(given) or return Failure.new(:invalid_encoding, 0, given.bytesize)
    return Failure.new(:too_long, 0, text.bytesize) if text.bytesize > MAX_LENGTH
    tokens = Lexer.lex(text)
    return tokens if Failure === tokens
    units = Grammar.duration(tokens)
    Failure === units ? units : Duration.from_units(units)
  end
  private_class_method :length

  # A repeating time as a Rule, or nil when the text is not one ("next friday" is a time, "twice a week" no rule)
  def self.recurrence(text, now: nil, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil,
                      fiscal_year_start: nil, strict: true, dst: nil, holidays: nil, business_days: nil, year_bias: nil)
    out = rule(text, Context.new(now, zone, context, locale, week_start, hemisphere, fiscal_year_start, strict, dst,
                                 holidays, business_days, year_bias))
    Rule === out ? out : nil
  end

  def self.recurrence!(text, now: nil, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil,
                       fiscal_year_start: nil, strict: true, dst: nil, holidays: nil, business_days: nil, year_bias: nil)
    out = rule(text, Context.new(now, zone, context, locale, week_start, hemisphere, fiscal_year_start, strict, dst,
                                 holidays, business_days, year_bias))
    raise Explain.error(out, utf8(text) || text) if Failure === out
    out
  end

  def self.rule(given, ctx, tokens = nil)
    unless tokens
      raise ArgumentError, "text must be a String, got #{given.class}" unless String === given
      text = utf8(given) or return Failure.new(:invalid_encoding, 0, given.bytesize)
      return Failure.new(:too_long, 0, text.bytesize) if text.bytesize > MAX_LENGTH
      tokens = Lexer.lex(text)
      return tokens if Failure === tokens
    end
    tree = Grammar.rule(tokens)
    return tree if Failure === tree
    out = Resolve::Recur.call(tree, ctx)
    Symbol === out ? Failure.new(out, 0, given.bytesize) : out
  end
  private_class_method :rule

  # strict: is taken and has no effect: extract always skips the words it doesn't know
  def self.extract(text, now: nil, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil,
                   fiscal_year_start: nil, strict: true, dst: nil, holidays: nil, business_days: nil, year_bias: nil)
    raise ArgumentError, "text must be a String, got #{text.class}" unless String === text
    options = [locale, week_start, hemisphere, fiscal_year_start, strict, dst, holidays, business_days, year_bias]
    Context.new(now, zone, context, *options) # bad options raise here, before any mention is found
    budget = Resolve::Period::Budget.new # D49: one for the call, not one a mention (T17)
    Extract.call(text, -> { Context.new(now, zone, context, *options).tap { _1.budget = budget } })
  end

  # The text as UTF-8, or nil when it can't be read as UTF-8: broken bytes, or an encoding such as UTF-16 whose
  # bytes the lexer would misread. Binary text that is valid UTF-8 is taken as it is.
  def self.utf8(text)
    case text.encoding
    when Encoding::UTF_8, Encoding::US_ASCII then text if text.valid_encoding?
    when Encoding::BINARY
      utf = text.dup.force_encoding(Encoding::UTF_8)
      utf if utf.valid_encoding?
    else text if text.ascii_only?
    end
  end
  private_class_method :utf8

  def self.run(given, ctx)
    raise ArgumentError, "text must be a String, got #{given.class}" unless String === given
    text = (given.valid_encoding? && given.encoding == Encoding::UTF_8 ? given : utf8(given)) or return Failure.new(:invalid_encoding, 0, given.bytesize)
    return Failure.new(:too_long, 0, text.bytesize) if text.bytesize > MAX_LENGTH
    tokens = Lexer.lex(text)
    return ctx.strict ? tokens : skipping(text, ctx, tokens) if Failure === tokens
    tree = Grammar.parse(tokens)
    return tree if Failure === tree
    readings = Resolve.call(tree, ctx, failure: true)
    return readings if Failure === readings
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
