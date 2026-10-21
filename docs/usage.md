# Using acute

The full Ruby API. The conventions behind each answer are on [the rules page](rules.md); the JSON forms are in [schema/](../schema).

The examples are said on Saturday 17 October 2026 at 14:00 in New York:

```ruby
now = "2026-10-17T14:00"
zone = "America/New_York"
```

## The calls

| Call | Returns |
|---|---|
| `Acute.parse(text, **options)` | an `Acute::Result`, or nil when the text isn't a time |
| `Acute.parse!(text, **options)` | an `Acute::Result`, or raises `Acute::ParseError` |
| `Acute.duration(text, **options)` / `duration!` | an `Acute::Duration`, or nil / raises |
| `Acute.read(text, **options)` | whichever the text is, a Result or a Duration, or nil |
| `Acute.extract(text, **options)` | an `Acute::Extraction`: every time and duration inside other text |
| `Acute.describe(value, style: :relative, **options)` | the most natural phrase that reads back to the value |
| `Acute.verify(text, value, **options)` | an `Acute::Verdict`: whether the value is what the text says |
| `Acute.with(**options)` | an `Acute::Parser` with the options fixed, which has all of the above |

## Parsing

```ruby
r = Acute.parse("next tuesday at 3pm", now:, zone:)
r.time     # => 2026-10-20 15:00:00 -0400
r.grain    # => :minute
r.to_s     # => "Tue, Oct 20, 2026, 3pm EDT"
```

A phrase means the whole period it names. `time` is its start, and `begin` and `end` give the span. `end` is the first moment after the span.

```ruby
r = Acute.parse("tomorrow", now:, zone:)
r.begin    # => 2026-10-18 00:00:00 -0400
r.end      # => 2026-10-19 00:00:00 -0400
r.date     # => #<Date: 2026-10-18>
r.iso8601  # => "2026-10-18T00:00:00-04:00/2026-10-19T00:00:00-04:00"

Acute.parse("last 14 days", now:, zone:).range
# => 2026-10-03 14:00:00 -0400...2026-10-17 14:00:00 -0400
```

Without `now:` acute uses the clock. Without `zone:` it uses the zone of `now:`, then Rails' `Time.zone`, then the system's. On a server, pass the zone you mean.

### A Result

| Method | Gives |
|---|---|
| `time`, `begin`, `end`, `range` | the start, the span, and the span as a Range; `begin` or `end` is nil for an open-ended phrase ("after friday", "before 2027") |
| `date` | the start's Date |
| `grain` | the unit the phrase was said in: `:minute`, `:day`, `:month`… |
| `zone` | the zone the answer is in |
| `text`, `matched` | the input, and the part of it read (they differ under `strict: false`) |
| `assumptions`, `alternatives`, `ambiguous?` | the rules applied and the other readings; see below |
| `instant?`, `span?`, `open?` | the shape of the answer |
| `to_s`, `iso8601` | a readable form, and ISO 8601 (an interval for a span) |
| `to_h`, `to_json`, `as_json` | the JSON form, [schema/result.json](../schema/result.json) |

## Ambiguity: assumptions and alternatives

Many phrases can be read more than one way. acute settles each with a numbered rule. The result records the rule it used, and keeps the other readings as alternatives:

```ruby
r = Acute.parse("at 9", now:, zone:)
r.time                         # => 2026-10-18 09:00:00 -0400
r.alternatives.map(&:time)     # => [2026-10-17 21:00:00 -0400]
r.assumptions.map(&:code)      # => [:bare_hour_window, :next_occurrence]
r.assumptions.first.rule       # => "D4"
r.assumptions.first.message
# => "no am/pm given: 6-11 read as am, 12 and 1-5 as pm; the other half of the day is an alternative"
r.assumptions.first.short
# => "no am/pm: 6-11 am, 12-5 pm; the other is an alternative"
```

`short` is the gist in about 50 characters, which the [agent tools](agents.md) use. Every rule is on [the rules page](rules.md), and every assumption code in [its table](rules.md#assumptions).

## Failures

`parse` returns nil. `parse!` raises an `Acute::ParseError` that says what went wrong:

```ruby
Acute.parse!("tomorow at 3", now:, zone:)
# Acute::ParseError: unknown word "tomorow"
#   e.code => :unknown_word, e.hint => "did you mean \"tomorrow\"?"
```

A ParseError also has `position`, the Range of the text it points at, and `unknown`, the words acute didn't know.

A bad option value raises `Acute::OptionError`, an `ArgumentError` that names the `option` and the `value`. It and `ParseError` both include `Acute::Error`, so `rescue Acute::Error` catches either.

By default, text with a word acute doesn't know fails. `strict: false` skips unknown words, as chronic did, and records that it did:

```ruby
Acute.parse("meet bob tuesday", now:, zone:)                 # => nil
Acute.parse("meet bob tuesday", now:, zone:, strict: false)  # => #<Acute::Result Tue, Oct 20, 2026, all day>
```

## Time zones

A zone written in the text wins over the zone you pass, and the answer comes back in yours:

```ruby
Acute.parse("tomorrow 3pm PST", now:, zone:).time  # => 2026-10-18 19:00:00 -0400
Acute.parse("friday 9am", now:, zone: "Europe/London").time  # => 2026-10-23 09:00:00 +0100
```

Times that daylight saving skips or repeats follow fixed rules. Each one is recorded as an assumption, and `dst:` changes the choice ([D23](rules.md#d23-future-context-two-digit-years-whole-units-arithmetic-and-dst)).

## Durations

```ruby
d = Acute.duration("1h 30m")
d.seconds   # => 5400
d.iso8601   # => "PT1H30M"
d.to_s      # => "1h 30m"
d.to_s(:long)  # => "1 hour 30 minutes"
```

A month stays a month rather than becoming a guess in seconds: `parts` keeps each unit (`{months: 1}`), and `seconds` raises when a part has no fixed length. `after(time)` adds the duration on the calendar, and `seconds(from: time)` counts it from that time. Its JSON is [schema/duration.json](../schema/duration.json), where `seconds` is null for such a duration.

`Acute.read` returns whichever the text is, a time or a duration. Text that is both, such as "1530 hrs", is the time ([read](rules.md#read)).

## Dates inside other text

`Acute.extract` finds every time and duration in a longer text, such as a message or an email:

```ruby
x = Acute.extract("Lunch with Sam next friday at noon, then a 2 hour review", now:, zone:)
x.mentions.map { [_1.offset, _1.value.to_s] }
# => [[15...34, "Fri, Oct 23, 2026, 12pm EDT"], [43...49, "2h"]]
x.remainder  # => "Lunch with Sam, then a review"
```

An Extraction has `text`, `mentions` and `remainder`, the text with the mentions taken out. Each mention has `kind` (`:time` or `:duration`), `text`, `offset` (a Range of character positions in the text) and `value`, a Result or a Duration. Its JSON is [schema/extraction.json](../schema/extraction.json), with `offset` as `[begin, end]`. What counts as a mention, and where one starts and ends, are the [E-rules](rules.md#extraction).

## Writing and checking dates

`describe` writes a time back as the most natural phrase that reads back to it exactly. It takes a Time, a Date, a Range of either, a Result or a Duration. `style: :calendar` never uses words relative to now:

```ruby
Acute.describe(Time.new(2026, 10, 20, 15, 0, 0, "-04:00"), now:, zone:)
# => "Tuesday at 3pm"
Acute.describe(Time.new(2026, 10, 20, 15, 0, 0, "-04:00"), now:, zone:, style: :calendar)
# => "Tue, Oct 20, 3pm"
```

`verify` checks a time that someone or something else worked out, such as an LLM. Its message is written to be passed straight back:

```ruby
v = Acute.verify("next friday at noon", "2026-10-24T12:00", now:, zone:)
v.status   # => :mismatch
v.ok?      # => false
v.message  # => "\"next friday at noon\" is Fri 23 Oct, 12pm, not Sat 24 Oct, 12pm."
```

The value may be a Time, a Date, a Range of either, or an ISO 8601 string. A Verdict has `text`, `status`, `ok?`, `message` and `expected`, acute's own reading. The statuses and how each is decided are in [the rules](rules.md#verify); the JSON is [schema/verdict.json](../schema/verdict.json), and describe's rules are [here](rules.md#describe).

## Options

Every call takes the same options:

| Option | What it sets |
|---|---|
| `now:` | the time phrases are relative to (a Time or an ISO 8601 string) |
| `zone:` | an IANA zone name, an offset, or a `TZInfo::Timezone` (read by its name) |
| `context:` | `:future` (default) or `:past`, for times that could be either |
| `locale:` | `"en-US"`, `"en-GB"`, `"en-AU"`…: date order, week start, holidays, seasons. By default it comes from the zone |
| `week_start:`, `hemisphere:` | override the locale's |
| `fiscal_year_start:` | the month a fiscal year starts, for "FY27" |
| `strict:` | `false` skips unknown words |
| `dst:` | `:compatible` (default), `:earlier`, `:later` or `:reject`, for wall times daylight saving repeats or skips |
| `holidays:`, `business_days:` | a holidays-gem region, or your own calendar object. A call counts at most 10,000 business days in all, across every count in it; past that a count fails with `business_day_limit` |
| `year_bias:` | where two-digit years fall (default 50: the 100 years from 50 years ago) |

`Acute.with` checks a set of options once and returns a parser. The parser is frozen, so it can be shared across threads and Ractors. Options given to a call override the parser's, and `Parser#with(**more)` makes a new parser ([with](rules.md#with)):

```ruby
PARSER = Acute.with(zone: "Australia/Sydney")
PARSER.parse("1/2/2027").date  # => #<Date: 2027-02-01>
```

## JSON

Every value has `to_h`, `to_json` and `as_json` (String keys). The schemas in [schema/](../schema) describe them: [result](../schema/result.json), [duration](../schema/duration.json), [extraction](../schema/extraction.json) and [verdict](../schema/verdict.json). The others there, and [schema/tools/](../schema/tools), are for the [agent tools](agents.md).
