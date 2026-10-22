# acute

[![check](https://github.com/skorks/acute/actions/workflows/check.yml/badge.svg)](https://github.com/skorks/acute/actions/workflows/check.yml)

Plain-English date and time parsing for Ruby: a successor to [chronic](https://github.com/mojombo/chronic).

```ruby
require "acute"

r = Acute.parse("next friday at 3pm", now: "2026-10-17T14:00", zone: "America/New_York")
r.time  # => 2026-10-23 15:00:00 -0400
```

`r.time` is a plain Ruby `Time` at the offset of the zone you asked for, here New York's -04:00. `parse` returns nil when the text isn't a time, and `parse!` raises.

Ruby's own `Time.parse` reads formats, not phrases: it takes "next tuesday at 3pm" as 3pm today. chronic reads phrases, but it is unmaintained, has one global time zone, and silently guesses at words it doesn't know. acute is a rewrite from scratch: every call takes its own `now` and zone, daylight saving is handled properly, it reads a wide range of phrases (checked against more than 18,000 cases), it says which reading it chose and why, and it runs 20–100× faster ([measured](#performance)). Why, with examples, and the name: [docs/chronic.md](docs/chronic.md#why-acute-exists).

### When to use something else

- Your input is always ISO 8601 or one fixed format: Ruby's `Time.iso8601` and `Time.strptime` read it, with nothing to install.
- You need languages other than English: acute reads English only. Its locales (en-US, en-GB, en-AU…) set date order, week start and holidays, not the words.
- You want a best guess at vague or garbled text: acute fails rather than guess. "soon", "the day after the meeting", "mon, wed and fri" and "satterday" return nil; it corrects only a small table of common misspellings, with no fuzzy matching. Everything it won't read: [gotchas](docs/gotchas.md#soon-gave-nil).
- You need meaning beyond dates, times, lengths and repeats, such as intents or places: that's a job for an NLP library or an LLM, which can call acute for the dates ([agents](docs/agents.md)).
- You need chronic's answers exactly: acute differs where chronic is wrong or ambiguous ([the differences](docs/chronic.md#moving-over)).

## Installation

<!-- no-doc-test -->
```ruby
gem "acute"
```

Or `gem install acute`. acute needs Ruby 3.3 or later and has no runtime dependencies. Its zone data is IANA 2026e, shipped with the gem (`Acute::TZDATA`).

What each kind of release may change: [docs/stability.md](docs/stability.md).

## Usage

The examples pin `now:` to Saturday 17 October 2026, 14:00, in New York. `now:` takes a Time or an ISO 8601 string, and without it acute uses the clock. Every call takes the same options (`now:`, `zone:`, `context:`, `locale:`, `strict:`, `dst:`…) and checks them, and `Acute.with` checks them once and returns a frozen parser to share across threads and Ractors. Every call, option and result field: [docs/usage.md](docs/usage.md).

```ruby
now = "2026-10-17T14:00"
zone = "America/New_York"

r = Acute.parse("tomorrow", now:, zone:)   # nil when the text isn't a time
r.begin    # => 2026-10-18 00:00:00 -0400
r.end      # => 2026-10-19 00:00:00 -0400
Acute.parse("tomorrow 3pm PST", now:, zone:).time  # => 2026-10-18 19:00:00 -0400
```

A phrase means the whole period it names: `time` is its start, and `end` is the first moment after it. A zone written in the text wins, and the answer comes back in yours. Without `zone:` acute falls back to the zone of `now:` (a TimeWithZone's, or a Time's fixed offset), Rails' `Time.zone`, then the system's; on a server, pass the zone you mean. Daylight saving and the options: [docs/usage.md](docs/usage.md#time-zones).

Times are plain `Time` values with a fixed offset, even when `now:` is a `TimeWithZone`; under Rails, `r.time.in_time_zone(r.zone)` before adding days ([why](docs/usage.md#time-zones)). Answers people trip on, such as "next friday", midnight, two-digit years and daylight saving, are on [the gotchas page](docs/gotchas.md).

### Ambiguity

When a phrase can be read more than one way, acute settles it with a numbered rule, records the rule, and keeps the other readings. Said at 14:00, "at 9" is 9am tomorrow by rule D4, and 9pm tonight is the alternative:

```ruby
r = Acute.parse("at 9", now:, zone:)
r.time                         # => 2026-10-18 09:00:00 -0400
r.alternatives.map(&:time)     # => [2026-10-17 21:00:00 -0400]
r.assumptions.map(&:code)      # => [:bare_hour_window, :next_occurrence]
r.assumptions.first.rule       # => "D4"
```

Every rule is on [the rules page](docs/rules.md).

### Failures

```ruby
Acute.parse!("tomorow at 3", now:, zone:)
# Acute::ParseError: unknown word "tomorow"
#   e.code => :unknown_word, e.hint => "did you mean \"tomorrow\"?"

Acute.parse("meet bob tuesday", now:, zone:)                 # => nil
Acute.parse("meet bob tuesday", now:, zone:, strict: false)  # => #<Acute::Result Tue, Oct 20, 2026, all day>
```

`parse` returns nil, and `parse!` raises. Both errors, and skipping unknown words: [docs/usage.md](docs/usage.md#failures).

### Durations and dates inside text

```ruby
Acute.duration("1h 30m").iso8601  # => "PT1H30M"

x = Acute.extract("Lunch with Sam next friday at noon, then a 2 hour review", now:, zone:)
x.mentions.map { [_1.offset, _1.value.to_s] }
# => [[15...34, "Fri, Oct 23, 2026, 12pm EDT"], [43...49, "2h"]]
x.remainder  # => "Lunch with Sam, then a review"
```

More: [durations](docs/usage.md#durations), [extract](docs/usage.md#dates-inside-other-text).

### Writing and checking dates

`describe` writes a time as the most natural phrase that reads back to it exactly. `verify` checks a time something else worked out, such as an LLM, with a message to pass straight back:

```ruby
Acute.describe(Time.new(2026, 10, 20, 15, 0, 0, "-04:00"), now:, zone:)
# => "Tuesday at 3pm"

Acute.verify("next friday at noon", "2026-10-24T12:00", now:, zone:).message
# => "\"next friday at noon\" is Fri 23 Oct, 12pm, not Sat 24 Oct, 12pm."
```

More: [docs/usage.md](docs/usage.md#writing-and-checking-dates).

### Repeating times

```ruby
r = Acute.recurrence("every weekday at 9am", now:, zone:)
r.rrule  # => "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYHOUR=9;BYMINUTE=0"
r.cron   # => "0 9 * * 1-5"
r.next   # => 2026-10-19 09:00:00 -0400
r.next(2)
# => [2026-10-19 09:00:00 -0400, 2026-10-20 09:00:00 -0400]
```

iCalendar rules, their occurrences and cron: [docs/recurrence.md](docs/recurrence.md).

### Command line

```
$ acute --now 2026-10-17T14:00 --zone America/New_York "next friday at 3pm"
Fri, Oct 23, 3pm EDT

$ acute --now 2026-10-17T14:00 --zone America/New_York --json "next friday at 3pm"
{"kind":"time","text":"next friday at 3pm","time":"2026-10-23T15:00:00-04:00","begin":"2026-10-23T15:00:00-04:00","end":"2026-10-23T15:01:00-04:00","grain":"minute","zone":"America/New_York","assumptions":[],"alternatives":[]}
```

Without `--json` it prints the reading for people to read, in `describe`'s calendar style; with it, the Result's `to_json` for scripts. Every option, stdin and failures: [docs/cli.md](docs/cli.md).

### Agents and LLMs

```
$ claude mcp add acute -- acute mcp --zone America/New_York    # an MCP server over stdio
```

```ruby
require "acute/tool"
tool = Acute::Tool.new(now:, zone:)   # the app sets the zone and now, never the model
tool.definitions(:anthropic).map { _1[:name] }   # or :openai, for any SDK
# => ["parse", "duration", "recurrence", "extract", "verify", "describe", "now"]
tool.call("parse", { "text" => "next friday at 3pm" })
# => {"kind" => "time", "time" => "2026-10-23T15:00:00-04:00", "end" => "2026-10-23T15:01:00-04:00", "grain" => "minute", "zone" => "America/New_York"}
```

The tools, their failures and how zone and now are set: [docs/agents.md](docs/agents.md). With RubyLLM it is `chat.with_tools(*tool.ruby_llm)`: [docs/agents.md#rubyllm](docs/agents.md#rubyllm).

## Coming from chronic

`require "acute/chronic"` gives you chronic's API, `Chronic.parse` with chronic's options, answered by acute; `require "acute/chronic_duration"` does the same for chronic_duration. A few answers differ, following acute's rules: [docs/chronic.md](docs/chronic.md#moving-over).

## Performance

Over ten everyday phrases on Ruby 4.0.7, acute takes 5–19 µs a parse to chronic 0.10.2's 260–490 µs, 20–100× faster (median about 50×), and 1.5–8 µs under YJIT, 80–300× faster. `bin/bench-chronic` measures it on your machine: [docs/chronic.md](docs/chronic.md#performance).

## Documentation

- [docs/usage.md](docs/usage.md): every call, option and result field, with examples.
- [docs/recurrence.md](docs/recurrence.md): repeating times as iCalendar rules, their occurrences, and cron.
- [docs/cli.md](docs/cli.md): the `acute` command and its options.
- [docs/agents.md](docs/agents.md): acute as tools for an LLM, through `Acute::Tool` or `acute mcp`.
- [docs/chronic.md](docs/chronic.md): why acute exists, moving from chronic, and speed.
- [docs/gotchas.md](docs/gotchas.md): the answers people don't expect, why, the option that changes each, and what acute won't read.
- [docs/rules.md](docs/rules.md): every convention acute follows, by topic, with examples.
- [docs/stability.md](docs/stability.md): what SemVer covers, and what a minor or patch release may change.
- [schema/](schema): JSON Schemas for the JSON of a Result, Duration, Extraction and Verdict, and for the agent tools.

## Contributing

`bin/check` runs everything: lint, unit tests, the phrase corpus, chronic's tests, fuzzing, coverage and speed. To add a phrase, see [test/cases/FORMAT.md](test/cases/FORMAT.md).

## License

MIT; see [LICENSE](LICENSE). The test suite draws on other projects' work, credited in [NOTICE](NOTICE).
