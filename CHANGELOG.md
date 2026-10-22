# Changelog

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
