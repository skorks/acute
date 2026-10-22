# Gotchas

Read this when acute gave an answer you didn't expect. Each answer follows a numbered rule, and each rule has an option or an alternative reading when the other answer is the one you meant. The examples are said on Saturday 17 October 2026 at 14:00, in New York:

```ruby
now = "2026-10-17T14:00"
zone = "America/New_York"
```

## "at 9" gave tomorrow

A time that could be past or future means the future one, the next time the clock shows it. Said at 14:00, "at 9" is 9am tomorrow, with 9pm tonight as the alternative ([D4](rules.md#d4-a-time-of-day-without-ampm)), and "at 3pm" is today. For things that already happened, pass `context: :past` ([D23](rules.md#d23-future-context-two-digit-years-whole-units-arithmetic-and-dst)):

```ruby
Acute.parse("at 9", now:, zone:).time                   # => 2026-10-18 09:00:00 -0400
Acute.parse("at 9", now:, zone:).alternatives.map(&:time)  # => [2026-10-17 21:00:00 -0400]
Acute.parse("at 3pm", now:, zone:, context: :past).time    # => 2026-10-16 15:00:00 -0400
```

## "next friday" has two answers

Said early in the week, "next friday" can mean the coming Friday or the one a week later. acute gives the coming one first and the other as an alternative. Said on a Saturday, the coming Friday is already next week's, so there is one answer ([D20](rules.md#d20-next-friday)):

```ruby
wednesday = "2026-10-14T14:00"
r = Acute.parse("next friday", now: wednesday, zone:)
r.time                       # => 2026-10-16 00:00:00 -0400
r.alternatives.map(&:time)   # => [2026-10-23 00:00:00 -0400]
Acute.parse("next friday", now:, zone:).alternatives  # => []
```

If your users mean the later Friday, check `alternatives`, or confirm with them using `Acute.describe`.

## "monday midnight" is Tuesday

Midnight with a day is the end of that day, so "monday midnight" is Tuesday 00:00, with Monday 00:00 as the alternative. "12am" written out is the start of the day ([D6](rules.md#d6-midnight-with-a-day)). Any 12 o'clock without am/pm is noon ([D30](rules.md#d30-the-12-oclock-hour)):

```ruby
Acute.parse("monday midnight", now:, zone:).time   # => 2026-10-20 00:00:00 -0400
Acute.parse("at 12", now:, zone:).time             # => 2026-10-18 12:00:00 -0400
Acute.parse("12am", now:, zone:).time              # => 2026-10-18 00:00:00 -0400
```

## "1/2/2015" depends on the zone

Slashed dates follow the locale's order, and the locale comes from the zone: month first in the US, day first in the UK and Australia. The other order is an alternative when it is a valid date. Dotted dates are always day first ([D10](rules.md#d10-numeric-dates)). Pass `locale:` to fix the order:

```ruby
Acute.parse("1/2/2015", now:, zone:).time                         # => 2015-01-02 00:00:00 -0500
Acute.parse("1/2/2015", now:, zone: "Australia/Sydney").time      # => 2015-02-01 00:00:00 +1100
Acute.parse("1/2/2015", now:, zone:, locale: "en-GB").time        # => 2015-02-01 00:00:00 -0500
Acute.parse("1.2.2015", now:, zone:).time                         # => 2015-02-01 00:00:00 -0500
```

## "1/2/75" is 2075

A two-digit year falls in the 100 years that start 50 years before now: said in 2026, 75 is 2075 and 76 is 1976. For birthdays and other past dates, move the window back with `year_bias:` ([D23](rules.md#d23-future-context-two-digit-years-whole-units-arithmetic-and-dst)):

```ruby
Acute.parse("1/2/75", now:, zone:).time.year                  # => 2075
Acute.parse("1/2/76", now:, zone:).time.year                  # => 1976
Acute.parse("1/2/75", now:, zone:, year_bias: 80).time.year   # => 1975
```

## "this week" starts on Sunday

The week starts on Sunday in the US and on Monday in the UK, Europe and Australia, again from the zone's locale. `week_start:` overrides it ([D19](rules.md#d19-week-start)). ISO week numbers always start on Monday:

```ruby
Acute.parse("this week", now:, zone:).begin                        # => 2026-10-11 00:00:00 -0400
Acute.parse("this week", now:, zone: "Europe/London").begin        # => 2026-10-12 00:00:00 +0100
Acute.parse("this week", now:, zone:, week_start: :monday).begin   # => 2026-10-12 00:00:00 -0400
```

## "tomorrow" ends at midnight, and "mon to wed" ends on Thursday

A phrase means the whole period it names. `time` is its start and `end` is the first moment after it, so a day ends at the next day's 00:00. A range of days includes its last day, so "mon to wed" ends at Thursday 00:00; a range of clock times ends at the stated time ([D9](rules.md#d9-where-ranges-end)):

```ruby
Acute.parse("tomorrow", now:, zone:).end     # => 2026-10-19 00:00:00 -0400
Acute.parse("mon to wed", now:, zone:).end   # => 2026-10-22 00:00:00 -0400
Acute.parse("2 to 4pm", now:, zone:).end     # => 2026-10-17 16:00:00 -0400
```

## 2:30am on the night the clocks go forward is 3:30

New York's clocks skip from 2:00 to 3:00 on 8 March 2026, so 2:30 that night never happens. acute moves it forward by the gap. On 1 November the clocks go back and 1:30 happens twice; acute takes the first. `dst:` picks another instant, or `dst: :reject` fails instead ([D23](rules.md#d23-future-context-two-digit-years-whole-units-arithmetic-and-dst)):

```ruby
Acute.parse("march 8 2026 2:30am", now:, zone:).time                # => 2026-03-08 03:30:00 -0400
Acute.parse("march 8 2026 2:30am", now:, zone:, dst: :earlier).time  # => 2026-03-08 01:30:00 -0500
Acute.parse("nov 1 2026 1:30am", now:, zone:).time                  # => 2026-11-01 01:30:00 -0400
Acute.parse("nov 1 2026 1:30am", now:, zone:, dst: :later).time      # => 2026-11-01 01:30:00 -0500

Acute.parse!("march 8 2026 2:30am", now:, zone:, dst: :reject)
# Acute::ParseError: "march 8 2026 2:30am" names a wall time the clocks skip as they go forward
#   e.code => :dst_skipped_time
```

## "1530" is a year

Four digits alone are a year. "at", a leading zero, am/pm or "hrs" make them a time ([D5](rules.md#d5-a-bare-four-digit-number)):

```ruby
Acute.parse("1530", now:, zone:).grain        # => :year
Acute.parse("at 1530", now:, zone:).time      # => 2026-10-17 15:30:00 -0400
```

## Adding days under Rails jumps an hour

Times come back as plain `Time` values with a fixed offset, so `+ 86_400` across a clock change keeps the old offset. Under Rails, convert first: `r.time.in_time_zone(r.zone)` ([time zones](usage.md#time-zones)).

## "soon" gave nil

acute fails rather than guess. A phrase it can't pin to an exact time returns nil, and `parse!` raises with the reason ([failures](usage.md#failures)):

```ruby
Acute.parse("soon", now:, zone:)                        # => nil
Acute.parse("the day after the meeting", now:, zone:)   # => nil
Acute.parse("satterday", now:, zone:)                   # => nil
Acute.parse("mon, wed and fri", now:, zone:)            # => nil
Acute.parse("FY27", now:, zone:)                        # => nil
Acute.parse("FY27", now:, zone:, fiscal_year_start: 7).date.to_s  # => "2026-07-01"
```

- **No time named**: "soon", "sometime next week".
- **Words it doesn't know**, such as an event or a name: "the day after the meeting". `strict: false` skips unknown words ([D22](rules.md#d22-strict-by-default)).
- **Misspellings** outside a small fixed table. There is no fuzzy matching: "tommorow" reads, "satterday" doesn't (D22).
- **Several dates in one phrase**: "mon, wed and fri", "tonight or tomorrow" (D22). `extract` reads dates out of text instead.
- **Other languages**: "mañana", "demain". A locale sets date order, week start and holidays, not the words.
- **Holidays outside the built-in set**, such as "chinese new year", without a `holidays:` calendar ([D15](rules.md#d15-holidays)); fiscal years without `fiscal_year_start:` ([D17](rules.md#d17-business-days-and-fiscal-years)); year 0 and BC ([D12](rules.md#d12-centuries-and-decades)).
- **A repeat that says how often but not when**: "twice a week", "every morning" ([what isn't a rule](recurrence.md#what-isnt-a-rule)).
- **Text over 512 bytes** fails with `too_long`.
