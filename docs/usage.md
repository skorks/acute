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
| `Acute.read(text, **options)` | whichever the text is, a Result, a Duration or a Rule, or nil |
| `Acute.recurrence(text, **options)` / `recurrence!` | an `Acute::Rule` for a repeating time ([recurrence.md](recurrence.md)), or nil / raises |
| `Acute.extract(text, **options)` | an `Acute::Extraction`: every time, duration and repeating time inside other text |
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
r.date.to_s  # => "2026-10-18"
r.iso8601  # => "2026-10-18T00:00:00-04:00/2026-10-19T00:00:00-04:00"

Acute.parse("last 14 days", now:, zone:).range
# => 2026-10-03 14:00:00 -0400...2026-10-17 14:00:00 -0400
```

Without `now:` acute uses the clock. Without `zone:` it uses the zone of `now:`, then Rails' `Time.zone`, then the system's. A TimeWithZone, or a Time made with a TZInfo zone, carries its zone; a Time with only an offset, such as `Time.new(2026, 10, 17, 14, 0, 0, "-04:00")`, carries that offset, as `zone: "-04:00"` would. A local or UTC Time, a DateTime and a String carry none. On a server, pass the zone you mean.

### A Result

| Method | Gives |
|---|---|
| `time`, `begin`, `end`, `range` | the start, the span, and the span as a Range; `begin` or `end` is nil for an open-ended phrase ("after friday", "before 2027") |
| `date` | the start's local Date, in the result's zone, at any grain (for a phrase open at the start, the date of `time`) |
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

A ParseError also has `position`, the Range of the text it points at, and `unknown`, the words acute didn't know. Every offset acute gives, `position` and a mention's `offset` included, counts characters (codepoints), not bytes or UTF-16 units.

A bad option value raises `Acute::OptionError`, an `ArgumentError` that names the `option` and the `value`. It and `ParseError` both include `Acute::Error`, so `rescue Acute::Error` catches either.

Each `ParseError` has one of these codes. New codes may be added in minor releases, so treat an unknown one as a plain failure.

| `code` | Meaning | Raised by |
|---|---|---|
| `unknown_word` | a word acute doesn't know; `unknown` lists them and `hint` may suggest one | `parse!`, `duration!`, `recurrence!` |
| `invalid_date` | a date or time that doesn't exist ("feb 30", "25:00") | `parse!`, `recurrence!` |
| `incomplete` | the phrase stops short ("next") | `parse!`, `recurrence!` |
| `conflict` | words that don't fit together ("friday 3pm 4pm", "3 days hours") | `parse!`, `duration!`, `recurrence!` |
| `not_rule` | the text is not a repeating time | `recurrence!` |
| `vague_rule` | it says how often but not when ("twice a week") | `recurrence!` |
| `no_occurrence` | the rule ends before it starts | `recurrence!` |
| `dst_skipped_time` | a wall time the clocks skip, under `dst: :reject` | `parse!` |
| `dst_repeated_time` | a wall time that happens twice, under `dst: :reject` | `parse!` |
| `business_day_limit` | more than 10,000 business days counted in one call | `parse!`, `Duration#after` and `seconds(from:)` |
| `too_long` | text over 512 bytes | `parse!`, `duration!`, `recurrence!`, `Rule.from_cron!` |
| `invalid_encoding` | text that isn't valid UTF-8 | `parse!`, `duration!`, `recurrence!` |
| `occurrence_limit` | more than 1,000 occurrences asked for in one call | the Rule calls that list occurrences |
| `step_limit` | no occurrence within 100,000 steps of the search | the Rule calls that list occurrences |
| `invalid_cron` | a cron line that isn't one | `Rule.from_cron!` |
| `unsupported_cron` | a valid cron line a Rule can't hold (`@reboot`) | `Rule.from_cron!` |

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

`time`, `begin`, `end` and a rule's occurrences are plain `Time` values with a fixed offset, even when `now:` is an ActiveSupport `TimeWithZone`. Under Rails, `r.time.in_time_zone(r.zone)` gives a TimeWithZone. Convert before doing arithmetic: ActiveSupport's `+ 1.day` on a plain Time keeps its offset across a daylight saving change.

Times that daylight saving skips or repeats follow fixed rules. Each one is recorded as an assumption, and `dst:` changes the choice ([D23](rules.md#d23-future-context-two-digit-years-whole-units-arithmetic-and-dst)).

## Durations

```ruby
d = Acute.duration("1h 30m")
d.seconds   # => 5400
d.iso8601   # => "PT1H30M"
d.to_s      # => "1h 30m"
d.to_s(:long)  # => "1 hour 30 minutes"
```

`Acute.duration` reads ISO 8601 back, so `Acute.duration("PT1H30M") == d` ([D52](rules.md#durations)). A zero length is the empty Duration, and all negative parts take one leading minus:

```ruby
Acute.duration("0 seconds").iso8601   # => "PT0S"
Acute.duration("-PT2H30M").iso8601    # => "-PT2H30M"
Acute.duration("3 weeks plus 2 days").to_s   # => "3w 2d"
Acute.duration("P1H")                 # => nil
```

A month stays a month rather than becoming a guess in seconds: `parts` keeps each unit (`{months: 1}`), and `seconds` raises when a part has no fixed length. `after(time)` adds the duration on the calendar, and `seconds(from: time)` counts it from that time. Its JSON is [schema/duration.json](../schema/duration.json), where `seconds` is null for such a duration.

`Acute.read` returns whichever the text is, a time, a duration or a repeating time. Text that reads as nothing else is tried as a rule last, so "monday to friday from 9 to 5" is a Rule. Text that is both a time and a duration, such as "1530 hrs", is the time ([read](rules.md#read)).

## Dates inside other text

`Acute.extract` finds every time and duration in a longer text, such as a message or an email:

```ruby
x = Acute.extract("Lunch with Sam next friday at noon, then a 2 hour review", now:, zone:)
x.mentions.map { [_1.offset, _1.value.to_s] }
# => [[15...34, "Fri, Oct 23, 2026, 12pm EDT"], [43...49, "2h"]]
x.remainder  # => "Lunch with Sam, then a review"
```

An Extraction has `text`, `mentions` and `remainder`, the text with the mentions taken out. Each mention has `kind` (`:time`, `:duration` or `:rule`), `text`, `offset` (a Range of character positions in the text, counted in codepoints) and `value`, a Result, a Duration or a Rule. Its JSON is [schema/extraction.json](../schema/extraction.json), with `offset` as `[begin, end]`. What counts as a mention, and where one starts and ends, are the [E-rules](rules.md#extraction).

`extract` takes time in proportion to the text: about 1.5 µs a byte for an email, and up to about 13 µs a byte for text made only of times, such as "3pm 3pm 3pm…", so 1 MB of that takes about 13 seconds. It has no cap of its own. Bound text from users before you pass it in, as the `extract` tool does at 4096 chars.

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

Every call takes the same options, and checks them before it reads any text: a bad value raises `Acute::OptionError`, an unknown option Ruby's `ArgumentError`. `extract` takes no `strict:`, since it always skips unknown words (a parser's is left out). `Rule.from_cron` takes `now:`, `zone:` and `dst:`.

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
PARSER.parse("1/2/2027").date.to_s  # => "2027-02-01"
```

## JSON

Every value has `to_h`, `to_json` and `as_json` (String keys). The schemas in [schema/](../schema) describe them: [result](../schema/result.json), [duration](../schema/duration.json), [rule](../schema/rule.json), [extraction](../schema/extraction.json) and [verdict](../schema/verdict.json). The others there, and [schema/tools/](../schema/tools), are for the [agent tools](agents.md). Each schema's `$id` is its URL at the release's tag. The schemas of output are open: a later 1.x may add fields, and new values of a failure's `code`, a `grain`, a verdict's `status` or a mention's `kind`, so ignore a field you don't know and treat an unknown value as you would none of the known ones.

## The public API

The public API, which follows semantic versioning from 1.0: the `Acute` module's methods; `Acute::Parser`, `Result`, `Duration`, `Rule`, `Extraction` and its `Mention`, `Verdict` and `Assumption`, by the methods documented here and in [recurrence.md](recurrence.md); `Acute::Error`, `ParseError` and `OptionError`; `Acute::Tool`; `acute/chronic`, `acute/chronic_duration` and `acute/numerizer`; and the `acute` command with `acute mcp`. Everything else, marked `# @api private` in the source, may change in any release: the lexer, grammar, resolver, zones, tables, the CLI and MCP classes, other constants, and the constructors of the values the calls return. What each kind of release may change: [stability.md](stability.md).

`Result`, `Rule`, `Duration`, `Verdict`, `Extraction`, `Mention` and `Assumption` are frozen. A Rule, and a parser without a caller's holidays object, are Ractor-shareable; `Ractor.make_shareable` makes a Result shareable too.
