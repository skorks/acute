# Changelog

## Unreleased

- **Fixed:** a `now:` with only an offset, such as `Time.new(2026, 10, 17, 14, 0, 0, "-04:00")`, was read in the system zone, though the docs promise the zone of `now:`. Without `zone:`, its offset is now the zone (D45).
- **Fixed:** Cairo kept standard time all year after 2076. Its summer, which ends at 24:00 on the last Thursday of October, now carries on to 2200 (D47).
- **Fixed:** an hourly or finer rule kept an excepted time: "every hour except october 17 at 4pm" still listed 4pm. A time is now that instant, and a date leaves out each of the rule's occurrences that day; one needing more than 24 is `:conflict` (R12).
- **Fixed:** "week before last" and "the month before last" were incomplete; they are now the one before last week or month (D44). `extract` found only "fri" in "mon, wed and fri": a weekday in a list of weekdays is now a day, though "mon" and "wed" are also words (D18).
- **Fixed:** the `acute` command printed a failure's hint only with `--json`. Its plain output now adds it as `hint: …`, naming the command's flag, as the JSON does: a line of its own after `acute: <reason>`, or after three spaces on an `error:` line from stdin.
- **Fixed:** two rules with the same iCal were `==`, with one hash, though they listed or read differently: under another `dst:` policy, read in another zone or at another now, or one saying "starting" where the other didn't. Equality now covers all of these, and still not the text, so two phrasings of one rule stay equal.

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
