module Acute
  ALSO_DURATION = Assumption.for(:also_duration)
  private_constant :ALSO_DURATION

  # Whatever the text is: a Rule, a Result, a Duration, or nil. A rule comes first, then a time, which wins over
  # a duration (D45). The rule is tried first only when a word that makes one is there, and last when nothing
  # else reads, for R29's days with hours ("monday to friday from 9 to 5"), which no such word marks.
  def self.read(text, now: nil, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil,
                fiscal_year_start: nil, strict: true, dst: nil, holidays: nil, business_days: nil, year_bias: nil)
    ctx = Context.new(now, zone, context, locale, week_start, hemisphere, fiscal_year_start, strict, dst, holidays,
                      business_days, year_bias)
    marked = false
    if String === text && (t = utf8(text)) && t.bytesize <= MAX_LENGTH && Array === (tokens = Lexer.lex(t)) &&
       (marked = Grammar.rule?(tokens))
      out = rule(t, Context.new(now, zone, context, locale, week_start, hemisphere, fiscal_year_start, strict, dst,
                                holidays, business_days, year_bias), tokens)
      return out if Rule === out
    end
    length = duration(text)
    ctx.note(ALSO_DURATION) if length
    out = run(text, ctx)
    return out if Result === out
    return length if length || marked || !(Array === tokens)
    out = rule(t, Context.new(now, zone, context, locale, week_start, hemisphere, fiscal_year_start, strict, dst,
                              holidays, business_days, year_bias), tokens)
    out if Rule === out
  end
end
