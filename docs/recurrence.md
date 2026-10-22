# Repeating times

acute reads "every weekday at 9am" as an iCalendar rule (RFC 5545), lists its occurrences, and writes it as a cron line when cron can say it. The conventions are the R-rules on [the rules page](rules.md#recurrence); the JSON form is [schema/rule.json](../schema/rule.json).

The examples are said on Saturday 17 October 2026 at 14:00 in New York:

```ruby
now = "2026-10-17T14:00"
zone = "America/New_York"
```

## Reading a rule

```ruby
r = Acute.recurrence("every weekday at 9am", now:, zone:)   # nil when the text isn't a rule
r.to_s     # => "every weekday at 9am"
r.rrule    # => "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYHOUR=9;BYMINUTE=0"
r.dtstart  # => 2026-10-19 09:00:00 -0400
puts r.to_ical
# DTSTART;TZID=America/New_York:20261019T090000
# RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYHOUR=9;BYMINUTE=0
```

`Acute.recurrence!` raises an `Acute::ParseError` instead of returning nil. `Acute.read` tries a rule first, so it returns an `Acute::Rule` for these phrases. `Acute.parse` returns nil for them. Every option from [usage](usage.md#the-calls) works.

DTSTART is the first occurrence on or after now ([R2](rules.md#recurrence)). A rule with no clock is of whole days: its DTSTART is a Date, and its occurrences are Dates.

A Rule has:

| Method | Gives |
|---|---|
| `rrule`, `dtstart`, `to_ical` | the RRULE value, the first occurrence, and all the iCalendar lines (DTSTART, RRULE, any EXDATE) |
| `to_s` | the rule in words, which reads back to the same rule |
| `cron`, `cron_reason` | a cron line, or nil and why; see [cron](#cron) |
| `next`, `between`, `each` | the occurrences; see below |
| `zone` | the zone its wall times are in |
| `to_h`, `to_json`, `as_json` | the JSON form, [schema/rule.json](../schema/rule.json) |

```ruby
puts r.to_json
# {"kind":"rule","text":"every weekday at 9am","rrule":"FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYHOUR=9;BYMINUTE=0","dtstart":"2026-10-19T09:00:00-04:00","zone":"America/New_York","ical":"DTSTART;TZID=America/New_York:20261019T090000\nRRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYHOUR=9;BYMINUTE=0","cron":"0 9 * * 1-5","cron_reason":null}
```

## Occurrences

```ruby
r.next(3, after: Time.new(2026, 10, 17, 14, 0, 0, "-04:00"))
# => [2026-10-19 09:00:00 -0400, 2026-10-20 09:00:00 -0400, 2026-10-21 09:00:00 -0400]

r.between(Time.new(2026, 10, 19, 0, 0, 0, "-04:00"), Time.new(2026, 10, 21, 0, 0, 0, "-04:00"))
# => [2026-10-19 09:00:00 -0400, 2026-10-20 09:00:00 -0400]

r.each.first(2)   # lazy; stops when the rule ends
# => [2026-10-19 09:00:00 -0400, 2026-10-20 09:00:00 -0400]
```

- `next(n = 1, after: Time.now)` gives the next `n` after `after`. Fewer come back when the rule ends.
- `between(from, to)` gives those from `from` up to `to`, leaving `to` out, so windows laid end to end list each occurrence once. A Date stands for its whole day.
- `each(after: nil)` lists every occurrence, lazily, from DTSTART or after `after`.

For a rule of whole days they are Dates: `Acute.recurrence("every monday", now:, zone:).next(2, after: Date.new(2026, 10, 17))` gives `[#<Date: 2026-10-19>, #<Date: 2026-10-26>]`.

One call to `next` or `between` gives at most 1,000 occurrences and takes at most 100,000 steps. Past either it returns nil. `next!` and `between!` raise a `ParseError` with the code `:occurrence_limit` or `:step_limit`, which says why. `each` has no cap on how many it lists, so take what you need from it ([R19](rules.md#recurrence)).

## Daylight saving

Clock changes don't change the rule. "Every weekday at 9am" is 9:00 in EDT and in EST. A wall time that is skipped or repeated follows `dst:`, as a one-off time does ([D23](rules.md#d23-future-context-two-digit-years-whole-units-arithmetic-and-dst)): by default a skipped time moves forward by the gap and a repeated one is the earlier.

```ruby
r = Acute.recurrence("every day at 2:30am", now: "2027-03-10T12:00", zone:)
r.between(Time.new(2027, 3, 13, 0, 0, 0, "-05:00"), Time.new(2027, 3, 16, 0, 0, 0, "-04:00"))
# => [2027-03-13 02:30:00 -0500, 2027-03-14 03:30:00 -0400, 2027-03-15 02:30:00 -0400]
```

The 14th, whose 2:30 doesn't exist, comes back at 3:30. With `dst: :reject` that occurrence is left out and doesn't count towards a COUNT ([R18](rules.md#recurrence)):

```ruby
r = Acute.recurrence("every day at 2:30am", now: "2027-03-10T12:00", zone:, dst: :reject)
# the same window => [2027-03-13 02:30:00 -0500, 2027-03-15 02:30:00 -0400]
```

## Cron

`cron` writes the rule as a standard 5-field line. `cron_reason` says why there isn't one:

```ruby
Acute.recurrence("every weekday at 9am", now:, zone:).cron   # => "0 9 * * 1-5"

r = Acute.recurrence("every other friday", now:, zone:)
r.cron          # => nil
r.cron_reason   # => "cron can't express \"every other\""
```

Cron has no zone: the line is the wall time in the rule's zone, so run it with `CRON_TZ=America/New_York` or on a host in that zone. The CLI prints it that way.

Cron can't express:

- a start, an end or an exception: "until", a count, "starting", "in july", "except" ([R21](rules.md#cron));
- seconds;
- intervals that don't divide their field: "every 40 minutes", "every other day", "every other friday" ([R23](rules.md#cron));
- a weekday counted in its month or a day counted from its end: "every second tuesday", "the last friday", "the last day of every month" ([R24](rules.md#cron)).

`Acute::Rule.from_cron(line, now:, zone:)` goes the other way. It reads a Vixie cron line as wall time in `zone:` and gives a Rule, or nil when the line isn't cron or has no rule's equivalent. `from_cron!` raises a `ParseError` with a code (`invalid_cron`, `unsupported_cron` or `too_long`) and the position of the field at fault.

```ruby
c = Acute::Rule.from_cron("*/15 9-17 * * 1-5", now:, zone:)
c.to_s       # => "every 15 minutes from 9am to 6pm on weekdays"
c.rrule      # => "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR;BYHOUR=9,10,11,12,13,14,15,16,17;BYMINUTE=0,15,30,45"
c.dtstart    # => 2026-10-19 09:00:00 -0400

Acute::Rule.from_cron("nope")   # => nil
Acute::Rule.from_cron!("0 0 30 2 *")
# Acute::ParseError: the line never runs
#   e.code => :invalid_cron
```

What it reads, and the lines it can't hold: [R25 and R26](rules.md#cron).

## Rules in extract

`extract` finds rules in longer text. A mention has `kind` `:rule`, and its `value` is a Rule:

```ruby
x = Acute.extract("Standup every weekday at 9am, and lunch next friday at noon", now:, zone:)
x.mentions.map { [_1.kind, _1.text, _1.value.to_s] }
# => [[:rule, "every weekday at 9am", "every weekday at 9am"], [:time, "lunch next friday at noon", "Fri, Oct 23, 2026, 12pm EDT"]]
x.remainder   # => "Standup, and"
```

A lone frequency word such as "daily" is a rule only when a rule's words go with it. Where mentions begin and end: the [E-rules](rules.md#extraction).

## What isn't a rule

These return nil from `recurrence`, as [R15](rules.md#recurrence) says:

```ruby
Acute.recurrence("twice a week", now:, zone:)    # => nil: a count per period, with no day
Acute.recurrence("every morning", now:, zone:)   # => nil: a part of the day, with no clock
Acute.recurrence("next friday", now:, zone:)     # => nil: a one-off time
```

So is "every day at 9am and 5:30pm": BYHOUR and BYMINUTE would add 9:30 and 17:00, and one rule can't hold only the two ([R4](rules.md#recurrence)).

`recurrence!` raises on all of these: `:vague_rule` ("\"twice a week\" says how often, not when") for a count per period or a part of the day with no clock, `:not_rule` ("not a repeating time") for a one-off time, and another code where the words fail first, such as `:invalid_date` for "every 0 days". A rule that ends before it starts, such as "every monday until last week", raises `:no_occurrence`.
