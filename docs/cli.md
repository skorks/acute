# The acute command

`acute` reads phrases in a shell or a script and prints when they are. The examples are said on Saturday 17 October 2026 at 14:00; add `--now 2026-10-17T14:00` to get the same answers.

```
$ acute --zone America/New_York "next friday 3pm"
Fri, Oct 23, 3pm EDT

$ acute --json < phrases.txt    # one JSON line per phrase

$ acute --zone America/New_York --next 2 "every weekday at 9am"
every weekday at 9am
DTSTART;TZID=America/New_York:20261019T090000
RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYHOUR=9;BYMINUTE=0
cron: 0 9 * * 1-5 (CRON_TZ=America/New_York)
Mon, Oct 19, 9am EDT
Tue, Oct 20, 9am EDT
```

`acute PHRASE` prints the reading in describe's calendar style, with the zone's abbreviation, then any alternatives as "(also: …)". A duration prints as "1h 30m". A repeating time prints its words, its iCalendar lines (DTSTART, RRULE and any EXDATE) and its cron line when cron can express it, in the zone's wall time. `--next N` adds the rule's first N occurrences, from DTSTART on; N is 1 to 1,000, and a phrase that isn't a rule fails. With no phrase, it reads one phrase per line from stdin and prints exactly one line for each, a rule's lines joined by three spaces. A failure prints `error: <reason>`; with `--json`, a JSON line `{"kind":"error",...}`. The JSON of a reading is that of `to_json`: [schema/result.json](../schema/result.json), [schema/duration.json](../schema/duration.json) or [schema/rule.json](../schema/rule.json), and `--next` adds a `next` array of ISO 8601 times, or dates for a rule of whole days.

Exit codes: 0 when everything parsed, 1 when a phrase failed, 2 for bad options.

## Options

The options are those of [the library](usage.md#options), with dashes:

| Option | Sets |
|---|---|
| `--json` | print JSON (JSON Lines for stdin) |
| `--next N` | a rule's first N occurrences, 1–1,000 |
| `--now TIME` | now, in ISO 8601 (default: the clock) |
| `--zone ZONE` | an IANA zone or offset (default: the system's) |
| `--locale LOCALE` | en-US, en-GB, en-AU… (default: from the zone) |
| `--context CONTEXT` | future or past |
| `--week-start DAY` | sunday or monday |
| `--hemisphere SIDE` | north or south, for seasons |
| `--fiscal-year-start MONTH` | 1–12 |
| `--lenient` | skip unknown words (`strict: false`) |
| `--dst POLICY` | compatible, earlier, later or reject |
| `--holidays REGION` | a holidays-gem region, such as us (needs the gem) |
| `--year-bias YEARS` | two-digit years: the 100 from this many years ago (default 50) |
| `-v`, `--version` | the version |
| `-h`, `--help` | the usage |

## acute mcp

`acute mcp [options]` serves acute's tools to an MCP client over stdio, one JSON-RPC message per line. It takes `--zone`, `--locale`, `--context` and `--week-start`; see [agents.md](agents.md#over-mcp-acute-mcp).
