# Changelog

## Unreleased

- **Fixed:** a rule on a range of weekdays had no reading: "every Monday through Friday at 19:20" was nil and `extract` split it into "every Monday" and a time. It is now weekly on Monday to Friday at 19:20, as "every monday to friday" and "every mon-fri" are; "every friday through monday" wraps to Friday, Saturday, Sunday and Monday, where it read as Fridays until Monday (R6).
- **Fixed:** `Rule.from_cron` gave nil for a line with a month field: `0 9 * 3 *` was nil. A month field is BYMONTH, with numbers, names, lists, ranges and steps: "every day in March at 9am" (R25).
- **Fixed:** a rule's description listed every clock of a cron line: `5,10 * * * *` was 48 times. Hours against minutes read as one phrase, "every hour at :05 and :10", and `0-10 11 * * *` is "every minute from 11am to 11:11am", not "every 1 minutes" (R27).
- **Changed:** digits beside a part of day are a clock that part allows: "1140 in the morning" → 11:40 and "tonight 1140" → 23:40, not the year 1140; "815 in the morning" and "134 this afternoon" read too. "2027 in the morning" and "christmas 2015 in the evening" stay years (D5, D52).
- **Added:** `require "acute/numerizer"` gives numerizer's `Numerizer.numerize`, answered by acute (D46).
- **Changed:** the `acute/chronic_duration` layer reads through acute's lexer and duration grammar, not the gems' tokeniser (D46). It skips what it can't read, as `strict: false` does, and `raise_exceptions` raises only for text acute can't read. "1 hour 30" is 5400, not 3630 (D44). `output(format: :chrono, weeks: true)` returns the clock form, where the gems raise. Differences from the gems are listed in `test/chronic_duration/differences.yml`.
- **Added:** "plus" joins the parts of a duration: "3 weeks plus 2 days" (D44).
- **Added:** billion, trillion, ordinals up to trillionth, and the misspellings fourty, fourtieth, ninteen and nineth (D18).
- **Fixed:** a month before the fiscal year's start month had no reading: "march FY2027" with `fiscal_year_start: 7` was nil. It is now March 2027, inside the fiscal year (D38).
- **Fixed:** word order changed a clock range's day: "monday 3-5pm in march" ran from the coming Monday 15:00 to 1 March 17:00. A day before the range and a longer period after it are now both ends', so it is 1 March 15:00–17:00, as "3-5pm monday in march" is (D44).
- **Fixed:** a clock in brackets was not read: "[5pm]" was nil, and `extract` of "meet [5pm] tomorrow" mentioned "5pm] tomorrow". Brackets around a clock are dropped, as around a word, and a mention across a bracket takes both (D48).
- **Fixed:** `extract` found nothing between curly quotes or single quotes: "he said “3 days” then" and "'for 3 days'" were []. Curly double quotes are quotes as '"' is, and a single quote around a word is a quote, not an apostrophe (D48).
- **Fixed:** noon or midnight after a clock in the 12 o'clock hour was nil, and in a rule a second time: "12:15 noon" was nil and "every day at 12:15 noon" ran at 12pm and 12:15pm. The named hour now fixes pm or am, as a meridiem does: "12:15 noon" → 12:15pm, "12:30 midnight" → 00:30 (D30).
- **Fixed:** a signed shift followed by a clock was nil: "+2 days at 5pm" now gives 5pm two days on, as "in 2 days at 5pm" does, and so do "-1 day at noon" and "+1 week at 9am" (D44).

## 1.0.1

- **Changed:** the gem includes the README, CHANGELOG and docs/, so they can be read offline beside the code.
- **Fixed:** a `now:` with only an offset, such as `Time.new(2026, 10, 17, 14, 0, 0, "-04:00")`, was read in the system zone, though the docs promise the zone of `now:`. Without `zone:`, its offset is now the zone (D45).
- **Fixed:** the `acute` command printed a failure's hint only with `--json`. Its plain output now adds it as `hint: …`, naming the command's flag, as the JSON does: a line of its own after `acute: <reason>`, or after three spaces on an `error:` line from stdin.
- **Fixed:** two rules with the same iCal were `==`, with one hash, though they listed or read differently: under another `dst:` policy or read in another zone, or one saying "starting" where the other didn't. Equality now covers all of these, and still not the text or the `now:` (only the default `after:` for `next`), so two phrasings of one rule stay equal.

## 1.0.0

The first release. From here on, what may change in a minor or patch release is in [docs/stability.md](docs/stability.md).

- **Parsing.** `Acute.parse`, `parse!` and `Acute.with` read a date, time or period in plain English against the `now:` and `zone:` each call is given, with daylight saving handled, and say which reading they chose and why: its assumptions, each tagged with its rule, and the alternatives. A failure is a value with a code and a hint; `parse!` raises it. `Acute.duration` reads lengths of time. [docs/usage.md](docs/usage.md), [docs/rules.md](docs/rules.md)
- **Recurrence.** `Acute.recurrence` reads a repeating time as an `Acute::Rule`, with its occurrences (`next`, `between`, `each`), iCalendar RRULE text, and cron lines both ways. [docs/recurrence.md](docs/recurrence.md)
- **Extract.** `Acute.extract` finds the dates, times, durations and rules inside longer text, in time linear in its length. [docs/usage.md](docs/usage.md#dates-inside-other-text)
- **Writing and checking dates.** `Acute.describe` writes a time, duration or rule back in English; `Acute.verify` checks a claim such as "next friday is the 23rd". [docs/usage.md](docs/usage.md#writing-and-checking-dates)
- **Agents.** `Acute::Tool` gives the calls to an LLM as tools with JSON schemas, and `acute mcp` serves them over MCP; the app, not the model, fixes the zone and now. [docs/agents.md](docs/agents.md)
- **The `acute` command** parses phrases from arguments or stdin, for people or as JSON Lines. [docs/cli.md](docs/cli.md)
- **chronic compatibility.** `require "acute/chronic"` and `"acute/chronic_duration"` keep those gems' APIs, answered by acute. [docs/chronic.md](docs/chronic.md)
- **No runtime dependencies.** IANA zone data (2026e, `Acute::TZDATA`) ships with the gem, so there is no tzinfo dependency. Ruby 3.3 or later.
- **Hardening.** Every entry point's cost is bounded (512 bytes a phrase, budgets on occurrences and business days), the inputs were probed against a threat model, and messages escape what they echo. The gem is published from GitHub by trusted publishing with a build provenance attestation. [SECURITY.md](SECURITY.md)

- **Fixed:** Cairo kept standard time all year after 2076. Its summer, which ends at 24:00 on the last Thursday of October, now carries on to 2200 (D47).
- **Fixed:** an hourly or finer rule kept an excepted time: "every hour except october 17 at 4pm" still listed 4pm. A time is now that instant, and a date leaves out each of the rule's occurrences that day; one needing more than 24 is `:conflict` (R12).
- **Fixed:** "week before last" and "the month before last" were incomplete; they are now the one before last week or month (D44). `extract` found only "fri" in "mon, wed and fri": a weekday in a list of weekdays is now a day, though "mon" and "wed" are also words (D18).
