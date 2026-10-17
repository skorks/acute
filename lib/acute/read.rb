module Acute
  ALSO_DURATION = Assumption.for(:also_duration)

  # Whatever the text is: a Result, a Duration, or nil. A time wins over a duration (D45); a recurrence will
  # be tried first once there are rules.
  def self.read(text, now: nil, zone: nil, context: :future, locale: nil, week_start: nil, hemisphere: nil,
                fiscal_year_start: nil)
    ctx = Context.new(now, zone, context, locale, week_start, hemisphere, fiscal_year_start)
    length = duration(text)
    ctx.note(ALSO_DURATION) if length
    out = run(text, ctx)
    Result === out ? out : length
  end
end
