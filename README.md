# acute

[![check](https://github.com/skorks/acute/actions/workflows/check.yml/badge.svg)](https://github.com/skorks/acute/actions/workflows/check.yml)

Plain-English date and time parsing for Ruby: a successor to [chronic](https://github.com/mojombo/chronic).

```ruby
require "acute"

Acute.parse("next tuesday at 3pm", now: "2026-10-17T14:00", zone: "America/New_York").time
# => 2026-10-20 15:00:00 -0400
```

Ruby's own `Time.parse` reads formats, not phrases: it takes "next tuesday at 3pm" as 3pm today. chronic reads phrases, but it is unmaintained, has one global time zone, and silently guesses at words it doesn't know. acute is a rewrite from scratch: every call takes its own `now` and zone, daylight saving is handled properly, it reads a wide range of phrases (checked against more than 18,000 cases), it says which reading it chose and why, and it runs tens of times faster. Why, with examples, and the name: [docs/chronic.md](docs/chronic.md#why-acute-exists).

## Installation

<!-- no-doc-test -->
```ruby
gem "acute"
```

Or `gem install acute`. acute needs Ruby 3.3 or later and has no runtime dependencies. Its zone data is IANA 2026e, shipped with the gem (`Acute::TZDATA`).

## Usage

The examples pin `now:` to Saturday 17 October 2026, 14:00, in New York. `now:` takes a Time or an ISO 8601 string, and without it acute uses the clock. Every call takes the same options (`now:`, `zone:`, `context:`, `locale:`, `strict:`, `dst:`…), and `Acute.with` checks them once and returns a frozen parser to share across threads and Ractors. Every call, option and result field: [docs/usage.md](docs/usage.md).

```ruby
now = "2026-10-17T14:00"
zone = "America/New_York"

r = Acute.parse("tomorrow", now:, zone:)   # nil when the text isn't a time
r.begin    # => 2026-10-18 00:00:00 -0400
r.end      # => 2026-10-19 00:00:00 -0400
Acute.parse("tomorrow 3pm PST", now:, zone:).time  # => 2026-10-18 19:00:00 -0400
```

A phrase means the whole period it names: `time` is its start, and `end` is the first moment after it. A zone written in the text wins, and the answer comes back in yours. Without `zone:` acute falls back to the zone of `now:`, Rails' `Time.zone`, then the system's; on a server, pass the zone you mean. Daylight saving and the options: [docs/usage.md](docs/usage.md#time-zones).

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
r.next(2, after: Time.new(2026, 10, 17, 14, 0, 0, "-04:00"))
# => [2026-10-19 09:00:00 -0400, 2026-10-20 09:00:00 -0400]
```

iCalendar rules, their occurrences and cron: [docs/recurrence.md](docs/recurrence.md).

### Command line

```
$ acute --zone America/New_York "next friday 3pm"
Fri, Oct 23, 3pm EDT
```

Every option, stdin and `--json`: [docs/cli.md](docs/cli.md).

### Agents and LLMs

```
$ claude mcp add acute -- acute mcp --zone America/New_York    # an MCP server over stdio
```

```ruby
require "acute/tool"
tool = Acute::Tool.new(now:, zone:)   # the app sets the zone and now, never the model
tool.definitions(:anthropic).map { _1[:name] }   # or :openai, for any SDK
# => ["parse", "duration", "recurrence", "extract", "verify", "describe", "now"]
tool.call("parse", { "text" => "next friday 3pm" })
# => {"kind" => "time", "time" => "2026-10-23T15:00:00-04:00", "end" => "2026-10-23T15:01:00-04:00", "grain" => "minute", "zone" => "America/New_York"}
```

The tools, their failures and how zone and now are set: [docs/agents.md](docs/agents.md). With RubyLLM it is `chat.with_tools(*tool.ruby_llm)`: [docs/agents.md#rubyllm](docs/agents.md#rubyllm).

## Coming from chronic

`require "acute/chronic"` gives you chronic's API, `Chronic.parse` with chronic's options, answered by acute; `require "acute/chronic_duration"` does the same for chronic_duration. A few answers differ, following acute's rules: [docs/chronic.md](docs/chronic.md#moving-over).

## Performance

Over ten everyday phrases on Ruby 4.0.7, acute takes 9–16 µs a parse to chronic's 210–450 µs, about 20–25× faster, and 3.5–4 µs under YJIT, about 50–100×. The measurements: [docs/chronic.md](docs/chronic.md#performance).

## Documentation

- [docs/usage.md](docs/usage.md): every call, option and result field, with examples.
- [docs/recurrence.md](docs/recurrence.md): repeating times as iCalendar rules, their occurrences, and cron.
- [docs/cli.md](docs/cli.md): the `acute` command and its options.
- [docs/agents.md](docs/agents.md): acute as tools for an LLM, through `Acute::Tool` or `acute mcp`.
- [docs/chronic.md](docs/chronic.md): why acute exists, moving from chronic, and speed.
- [docs/rules.md](docs/rules.md): every convention acute follows, by topic, with examples.
- [schema/](schema): JSON Schemas for the JSON of a Result, Duration, Extraction and Verdict, and for the agent tools.

## Contributing

`bin/check` runs everything: lint, unit tests, the phrase corpus, chronic's tests, fuzzing, coverage and speed. To add a phrase, see [test/cases/FORMAT.md](test/cases/FORMAT.md).

## License

MIT; see [LICENSE](LICENSE). The test suite draws on other projects' work, credited in [NOTICE](NOTICE).
