# acute

[![check](https://github.com/skorks/acute/actions/workflows/check.yml/badge.svg)](https://github.com/skorks/acute/actions/workflows/check.yml)

Plain-English date and time parsing for Ruby: a successor to [chronic](https://github.com/mojombo/chronic).

```ruby
require "acute"

Acute.parse("next tuesday at 3pm", zone: "America/New_York").time
# => 2026-10-20 15:00:00 -0400
```

## Why acute exists

chronic made parsing "next tuesday at 3pm" a one-liner for more than a decade, and it has over 130 million downloads. But it has stood still:

- **It is unmaintained.** There has been no release since 0.10.2 in 2013, and more than 120 issues are open.
- **It doesn't really do time zones.** The zone is one global setting, `Chronic.time_class`, so there is no per-call zone and no thread-safe way to change it (its top open issue, [#182](https://github.com/mojombo/chronic/issues/182)). It also assumes every day has 24 hours, which breaks around daylight-saving changes.
- **It guesses silently.** Words it doesn't know are skipped, so "a banana" parses as a time and "4/32" as a date in 2032.
- **It isn't comprehensive enough.** Many everyday phrases return nil or raise.

Said on Saturday 17 October 2026 at 14:00 in New York:

| Phrase | chronic 0.10.2 | acute |
|---|---|---|
| "a banana" | today 13:00 | nil |
| "4/32" | 16 April 2032 | nil |
| "last 14 days" | yesterday 14:00 | 3 Oct 14:00 to 17 Oct 14:00 |
| "2nd thursday of june" | nil | 10 June 2027 |
| "christmas eve" | nil | 24 December 2026 |
| "1 year, 7 months ago" | raises NoMethodError | 17 March 2025, 14:00 |
| "1 day from now", at noon on 31 Oct | 11:00 on 1 Nov (24 hours across the clock change) | 12:00 on 1 Nov |
| "march 8 2026 2:30am" (skipped by DST) | 01:30 EST | 03:30 EDT |

acute is a rewrite from scratch, with a different design:

- every call takes its own `now` and zone, and daylight saving is handled properly;
- it reads a wide range of phrases, checked against more than 18,000 cases gathered from chronic and a dozen other date parsers;
- when a phrase could mean more than one thing, it says which reading it chose, and why;
- it runs tens of times faster than chronic.

**About the name.** In medicine, a *chronic* condition lingers for years, and an *acute* one is short and sharp. chronic has lingered since 2013. acute is short, sharp and over in a few microseconds.

## Installation

```ruby
gem "acute"
```

acute needs Ruby 3.3 or later. Its only dependency is [tzinfo](https://github.com/tzinfo/tzinfo).

## Usage

The examples are said on Saturday 17 October 2026 at 14:00 in New York:

```ruby
now = "2026-10-17T14:00"
zone = "America/New_York"
```

### Parsing

`Acute.parse` returns an `Acute::Result`, or nil when the text isn't a time.

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

### Ambiguity: assumptions and alternatives

Many phrases can be read more than one way. acute settles each with a numbered rule. The result records the rule it used, and keeps the other readings as alternatives:

```ruby
r = Acute.parse("at 9", now:, zone:)
r.time                         # => 2026-10-18 09:00:00 -0400
r.alternatives.map(&:time)     # => [2026-10-17 21:00:00 -0400]
r.assumptions.map(&:code)      # => [:bare_hour_window, :next_occurrence]
r.assumptions.first.rule       # => "D4"
r.assumptions.first.message
# => "no am/pm given: 6-11 read as am, 12 and 1-5 as pm; the other half of the day is an alternative"
```

Every rule is on [the rules page](docs/rules.md).

### Failures

`parse` returns nil. `parse!` raises an `Acute::ParseError` that says what went wrong:

```ruby
Acute.parse!("tomorow at 3", now:, zone:)
# Acute::ParseError: unknown word "tomorow"
#   e.code => :unknown_word, e.hint => "did you mean \"tomorrow\"?"
```

By default, text with a word acute doesn't know fails. `strict: false` skips unknown words, as chronic did, and records that it did:

```ruby
Acute.parse("meet bob tuesday", now:, zone:)                 # => nil
Acute.parse("meet bob tuesday", now:, zone:, strict: false)  # => #<Acute::Result Tue, Oct 20, 2026, all day>
```

### Time zones

A zone written in the text wins over the zone you pass, and the answer comes back in yours:

```ruby
Acute.parse("tomorrow 3pm PST", now:, zone:).time  # => 2026-10-18 19:00:00 -0400
Acute.parse("friday 9am", now:, zone: "Europe/London").time  # => 2026-10-23 09:00:00 +0100
```

Times that daylight saving skips or repeats follow fixed rules. Each one is recorded as an assumption, and `dst:` changes the choice.

### Durations

```ruby
d = Acute.duration("1h 30m")
d.seconds   # => 5400
d.iso8601   # => "PT1H30M"
d.to_s(:long)  # => "1 hour 30 minutes"
```

A month stays a month rather than becoming a guess in seconds. `Acute.read` returns whichever the text is, a time or a duration.

### Dates inside other text

```ruby
x = Acute.extract("Lunch with Sam next friday at noon, then a 2 hour review", now:, zone:)
x.mentions.map { [_1.offset, _1.value.to_s] }
# => [[15...34, "Fri, Oct 23, 2026, 12pm EDT"], [43...49, "2h"]]
x.remainder  # => "Lunch with Sam, then a review"
```

### Writing and checking dates

`describe` writes a time back as the most natural phrase that reads back to it exactly. `verify` checks a time that someone or something else worked out, such as an LLM. Its message is written to be passed straight back:

```ruby
Acute.describe(Time.new(2026, 10, 20, 15, 0, 0, "-04:00"), now:, zone:)
# => "Tuesday at 3pm"

Acute.verify("next friday at noon", "2026-10-24T12:00", now:, zone:).message
# => "\"next friday at noon\" is Fri 23 Oct, 12pm, not Sat 24 Oct, 12pm."
```

### Options

Every call takes the same options:

| Option | What it sets |
|---|---|
| `now:` | the time phrases are relative to (a Time or an ISO 8601 string) |
| `zone:` | an IANA zone name or an offset |
| `context:` | `:future` (default) or `:past`, for times that could be either |
| `locale:` | `"en-US"`, `"en-GB"`, `"en-AU"`…: date order, week start, holidays, seasons. By default it comes from the zone |
| `week_start:`, `hemisphere:` | override the locale's |
| `fiscal_year_start:` | the month a fiscal year starts, for "FY27" |
| `strict:` | `false` skips unknown words |
| `dst:` | `:earlier`, `:later` or `:reject`, for wall times daylight saving repeats or skips |
| `holidays:`, `business_days:` | a holidays-gem region, or your own calendar object |
| `year_bias:` | where two-digit years fall |

`Acute.with` checks a set of options once and returns a parser. The parser is frozen, so it can be shared across threads and Ractors:

```ruby
PARSER = Acute.with(zone: "Australia/Sydney")
PARSER.parse("1/2/2027").date  # => #<Date: 2027-02-01>
```

### Command line

```
$ acute --zone America/New_York "next friday 3pm"
Fri, Oct 23, 3pm EDT

$ acute --json < phrases.txt    # one JSON line per phrase
```

## Coming from chronic

`require "acute/chronic"` gives you chronic's API, `Chronic.parse` with chronic's options, answered by acute. `require "acute/chronic_duration"` does the same for chronic_duration.

```ruby
require "acute/chronic"

Chronic.parse("tomorrow 3pm", now: Time.now)
```

The answers follow acute's rules, so a few differ from chronic's. chronic's own test suite runs against this layer, and every place it disagrees is listed, with its rule, in [test/chronic/differences.yml](test/chronic/differences.yml). The [compatibility notes](docs/rules.md#compatibility-layers) explain how each option is read.

## Performance

These are CPU time per parse over ten everyday phrases ("tomorrow", "next tuesday 3pm", "3 days ago", "27/5/1979"…). They were measured on Ruby 4.0.7 on an i5-13600K:

| | chronic 0.10.2 | acute | faster by |
|---|---|---|---|
| interpreter | 210–450 µs | 9–16 µs | about 20–25× |
| YJIT | 175–420 µs | 3.5–4 µs | about 50–100× |

The ranges come from repeated runs on a busy machine, so read the ratios rather than the last digit. Roughly, chronic manages a few thousand parses a second per core, and acute around a hundred thousand, or a quarter of a million with YJIT. acute's own speed budget is checked on every commit.

## Documentation

- [docs/rules.md](docs/rules.md): every convention acute follows, by topic, with examples.
- [schema/](schema): JSON Schemas for `to_json` of a Result, a Duration and a Verdict.

## Contributing

`bin/check` runs everything: lint, unit tests, the phrase corpus, chronic's tests, fuzzing, coverage and speed. To add a phrase, see [test/cases/FORMAT.md](test/cases/FORMAT.md).

## License

MIT; see [LICENSE](LICENSE). The test suite draws on other projects' work, credited in [NOTICE](NOTICE).
