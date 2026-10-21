# Case format

Each file in `test/cases/` holds test cases for acute, one JSON object per line. `test/corpus.rb` runs every case in every `*.jsonl` file here, and `bin/check` runs it as the corpus stage. Blank lines are skipped. A file name is a theme or a source, such as `generated-dst.jsonl` or `duckling.jsonl`.

```json
{"id":"generated-weekday-0042","text":"tomorrow at 4pm","now":"2013-02-12T04:30:00","tz":"America/New_York","expect":{"time":"2013-02-13T16:00:00","grain":"minute"},"source":"generated:weekday","tags":["relative-day"]}
```

## Adding a case

`bin/case` writes a case from acute's current answer:

```sh
bin/case "tomorrow at 4pm" --now 2026-10-17T14:00 --zone America/New_York [--context past] [--to FILE]
```

It appends the case to `test/cases/new.jsonl` (or FILE) with an id like `new-0001` and prints it. The answer is acute's, not a checked one. Correct it from [docs/rules.md](../../docs/rules.md), then move the case to the file for its theme and give it that file's id.

A case starts counting once it is in the ratchet. Run `bin/check`, then `bin/check --record` to add the newly passing ids to `test/corpus/passing.txt`. A case in the ratchet that stops passing fails the check as a regression.

## Fields

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Unique across all files. Prefix it with the file name: `duckling-0042`. |
| `text` | yes | The input, exactly as a person would type it. |
| `now` | yes | The reference time, as the wall time in `tz`: `YYYY-MM-DDTHH:MM:SS`, with no offset. |
| `tz` | yes | An IANA zone name: `UTC`, `America/New_York`, `Europe/London`, `Etc/GMT+2`. It is acute's `zone:`. |
| `options` | no | Options for `Acute.parse`. Leave it out for the defaults. |
| `expect` | yes | The answer, in one of the kinds below. |
| `source` | yes | Where the case came from: `chronic#222`, `duckling:<path>`, `generated:dst`, `bin/case`, or `hand` for one written from the rules. |
| `tags` | no | Short labels: `dst`, `strict`, `range`, `nth-weekday`. A tag like `D20` names a rule. |
| `note` | no | Anything a reviewer needs, such as the rule applied. |

`bin/check --rule D20` runs the cases that name D20 in a tag or anywhere in the note. It takes E- and R-rules too: `--rule R3`.

## Expected values

A time in `expect` is a wall time in `tz`, like `now`, with optional fractional seconds: `2012-01-03T01:00:00.1`. Add an offset or `Z` only where the wall time alone names another instant, such as the repeated hour when clocks go back: `2026-11-01T01:30:00-05:00`.

A wall time is turned into an instant with the system's zoneinfo, independently of acute's own zone tables. A repeated wall time takes the earlier instant; a skipped one moves forward by the gap. This matches acute's default `dst: :compatible`.

`expect` holds one of these:

**`time` and `grain`.** The answer is one unit long, from `time`:

```json
{"time":"2026-10-18T00:00:00","grain":"day"}
```

- The grain is one of `second`, `minute`, `hour`, `day`, `week`, `month`, `quarter` or `year`. It defaults to `second`.
- It is the precision of what was said: "tomorrow" is `day`, "4pm" is `minute`, "next month" is `month`, "4:30:15pm" is `second`.
- Seconds, minutes and hours add elapsed time. A day or longer steps the written wall date, so "the day the clocks change" is that whole day, 23 or 25 hours long.

**`span`.** An explicit range, `[begin, end)`, with the end left out:

```json
{"span":["2026-10-19T00:00:00","2026-10-22T00:00:00"]}
```

Either end may be `null` for an open end: "before friday" is `[null, "<friday 00:00>"]`, "after 3pm" is `["<15:00>", null]`.

**`alternatives`.** A list of `time`/`grain` or `span` expects. The first is acute's answer; the rest are its `alternatives`, in order. All of them must match, and no others may be returned. Use it only where a rule says a phrase has more than one reading.

**`nil`.** `{"nil": true}`: the phrase must not parse. Use it for text that isn't a time and for invalid dates ("feb 30", "4/32").

**`duration`.** An ISO 8601 duration, compared with `Acute.duration(text).iso8601`: `{"duration":"PT1H30M"}`. `now` and `tz` are still written, but don't change the answer.

**`extract`.** The mentions `Acute.extract` should find, with character offsets, `end` exclusive:

```json
{"extract":[{"start":13,"end":23,"time":"2015-08-12T00:00:00","grain":"day"}]}
```

An entry may hold `span` or `alternatives` in place of `time` and `grain`. The corpus compares the `time` mentions `Acute.extract` returns, in order, with these entries: same offsets and the same readings as a normal case (`alternatives` included). Durations acute finds are ignored, because the sources don't list them. Scoring uses the usual statuses: `nil` when mentions were expected and none found, `garbage` when `"extract": []` and some were found, `alt_differs` when offsets and every first reading match but alternatives differ, `wrong` otherwise. The speed stage also times them.

**`rrule`.** An RFC 5545 rule, as `Acute.recurrence(text).to_ical` gives it: a DTSTART line, an RRULE line and any EXDATE line, joined by `\n`.

```json
{"rrule":"DTSTART;TZID=America/New_York:20261019T090000\nRRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYHOUR=9;BYMINUTE=0"}
```

- The lines, the RRULE's parts and any comma-separated values may come in any order. Everything else is compared exactly. Put every excepted date on one EXDATE line.
- DTSTART is the wall time in `tz`, with `TZID=<tz>`, or `VALUE=DATE` for a rule of whole days. UNTIL is a date, or a UTC time ending in `Z` when DTSTART has a clock. Work them out from the R-rules in [docs/rules.md](../../docs/rules.md#recurrence), with tzinfo for UTC.
- `{"rrule": null}`: `Acute.recurrence` must return nil. Use it for phrases that aren't rules ("twice a week", "next friday") and rules that never occur ("every feb 30").
- Until acute has `Acute.recurrence`, every rule case is `rule_pending`. After that they score `pass`, `wrong`, `nil`, `garbage` or `raises` as time cases do, and a passing one must come back from `Acute.read` as a Rule.

A passing time case must also come back from `Acute.read` as a Result, and a passing duration case as a Duration. Otherwise the run prints `MISREAD` and fails.

## Options

Options are passed to `Acute.parse` as keywords. `context` is turned into a Symbol.

| Option | Values |
|---|---|
| `context` | `"future"` (default) or `"past"` |
| `locale` | `"en-AU"`, `"en-GB"`, `"en-CA"`… |
| `week_start` | `"sunday"` or `"monday"` |
| `hemisphere` | `"north"` or `"south"` |
| `fiscal_year_start` | the first month, e.g. `7` |
| `ambiguous_year_future_bias` | chronic's name for `year_bias:` |

Cases using chronic's `endian_precedence`, `hours24` or `ambiguous_time_range` are not run against `Acute.parse`. They count as `chronic_option`.

## Statuses

`ruby test/corpus.rb --list STATUS` prints the cases with a status.

| Status | Meaning |
|---|---|
| `pass` | every reading matches |
| `alt_differs` | the first reading matches, the alternatives don't |
| `wrong` | the first reading doesn't match |
| `nil` | acute returned nil where a time was expected |
| `garbage` | acute returned a time where `nil` was expected |
| `raises` | acute raised |
| `chronic_option` | the case uses an option only the chronic layer has |
| `rule_pending` | an `rrule` case, while acute has no `Acute.recurrence` |

Other flags: `--grep TEXT` runs the cases whose text contains TEXT, `--file NAME` the files whose name contains NAME, and `--rule D20` the cases that name the rule (D, E or R). `--record` refuses to run with any of them.

## Conventions

Expected values follow [docs/rules.md](../../docs/rules.md). The ones that come up most:

- **Future by default.** A time that has passed today means tomorrow's (D23).
- **Whole units.** "tomorrow" is the whole day; "october" is the whole month (D23).
- **Arithmetic.** Days keep the wall time across a clock change; hours are elapsed. Months clamp to the month's end (D23).
- **No am/pm.** Hours 6 to 11 are am, 12 and 1 to 5 are pm, with the other half as an alternative (D4). The 12 o'clock hour is pm with no alternative (D30). Seconds or an offset make a time 24-hour (D29).
- **Four digits** are a year unless marked as a time: "at 1530", "1530h", "0600" (D5).
- **Locale.** Numeric date order, week start, holidays and hemisphere come from `locale`, or the zone's country, or en-US (D27). The other numeric order is an alternative when valid (D10).
- **Ranges** of days include the last day; with clocks the end is the stated time (D9).
- **Weekdays.** "next friday" has two readings when the coming Friday is in this week (D20, D32). "this friday" once passed is next week's first (D21).
- **Parts of the day** have fixed ranges (D1, D35).
- **Rolling windows** come first, then whole units (D7, D31).
- **Strict.** Text with words that aren't about dates is `nil` (D22). Invalid dates, year 0, BC and lists are `nil` (D18).
- **Rules.** DTSTART is the first occurrence on or after now (R2). A clock is in BYHOUR and BYMINUTE too (R4). "until" includes its end (R10).

When a case comes from another library whose convention differs, write the value these rules give, or leave the case out. Don't guess: a wrong expected value is worse than a missing case.
