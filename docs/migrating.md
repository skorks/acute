# acute and other gems

Read this if you use one of these gems, or want to keep one and give it English input: what acute reads in place of each, and how to hand its answers to the ones you keep.

The examples are said on Saturday 17 October 2026 at 14:00 in New York, with the versions named in each section on Ruby 4.0.7:

```ruby
require "acute"
now = "2026-10-17T14:00"
zone = "America/New_York"
```

## gitlab-chronic and gitlab_chronic_duration

GitLab's forks need no layer of their own. `require "acute/chronic"` takes gitlab-chronic 0.10.6's options too, such as `hours24:` and `week_start:`. `require "acute/chronic_duration"` takes gitlab_chronic_duration 0.12.0's, such as a per-call `days_per_month:`, which also sets the week, as the fork does:

```ruby
require "acute/chronic_duration"
ChronicDuration.parse("1 month", days_per_month: 20)   # => 1728000
ChronicDuration.parse("1 week", days_per_month: 20)    # => 432000
```

Each layer also stands in for the fork's own `require "gitlab-chronic"` or `require "gitlab_chronic_duration"`. Which to require first, and what happens otherwise: [Moving over](chronic.md#moving-over).

## cronex: a cron line in English

`Acute::Rule.from_cron` reads a cron line as a rule, and `to_s` says it in words:

```ruby
Acute::Rule.from_cron("0 9 * * 1-5").to_s         # => "every weekday at 9am"
Acute::Rule.from_cron("*/15 9-17 * * 1-5").to_s   # => "every 15 minutes from 9am to 6pm on weekdays"
Acute::Rule.from_cron("0 0 * 3 *").to_s           # => "every day in March, every year, at 12am"
```

The words read back to the same rule, and so to the same line:

```ruby
Acute.recurrence("every 15 minutes from 9am to 6pm on weekdays", now:, zone:).cron   # => "*/15 9-17 * * 1-5"
```

acute reads standard 5-field cron, as Vixie cron does. cronex also describes a seconds field and Quartz's `L`, `W`, `#` and `?`; acute returns nil for them, and `from_cron!` says why:

```ruby
Acute::Rule.from_cron("0 0 9 * * 1-5")   # => nil
Acute::Rule.from_cron!("0 9 L * *")
# Acute::ParseError: "L" is not standard cron: no L, W, # or ?
```

More on cron, both ways: [Cron](recurrence.md#cron).

## ice_cube, montrose and rrule: English in

`Acute.recurrence` reads "every other friday at 3pm" as an iCalendar rule. These gems can take it from there. Tried with ice_cube 0.17.0, montrose 0.18.0 and rrule 0.8.0:

```ruby
r = Acute.recurrence("every other friday at 3pm", now:, zone:)
puts r.to_ical
# DTSTART;TZID=America/New_York:20261023T150000
# RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=FR;BYHOUR=15;BYMINUTE=0
```

What each keeps:

| | Zone and DST | COUNT, UNTIL | EXDATE ("except") | Rules of whole days |
|---|---|---|---|---|
| rrule | yes | yes | no | yes |
| montrose | yes | yes | yes | no: raises |
| ice_cube, `from_ical` | the process's zone, not the rule's | yes | yes | as Times at midnight |
| ice_cube, built from `dtstart` and `rrule` | yes | yes | no | as Times at midnight |

### rrule

Pass the RRULE, the first occurrence and the zone:

<!-- no-doc-test -->
```ruby
require "rrule"
RRule.parse(r.rrule, dtstart: r.dtstart, tzid: r.zone).first(3)
# => [2026-10-23 15:00:00.000000000 EDT -04:00, 2026-11-06 15:00:00.000000000 EST -05:00, 2026-11-20 15:00:00.000000000 EST -05:00]
```

A rule of whole days gives Dates. An "except" is lost: it is an EXDATE line in `to_ical`, and `rrule` holds only the RRULE.

### montrose

montrose reads the whole of `to_ical`, exceptions too, and gives ActiveSupport times in the rule's zone. Version 0.18 uses Forwardable without requiring it, so require it first:

<!-- no-doc-test -->
```ruby
require "forwardable"
require "montrose"
Montrose::Recurrence.from_ical(r.to_ical).take(3)
# => [2026-10-23 15:00:00.000000000 EDT -04:00, 2026-11-06 15:00:00.000000000 EST -05:00, 2026-11-20 15:00:00.000000000 EST -05:00]
```

It can't read a rule of whole days. "every monday" starts `DTSTART;VALUE=DATE:20261019`, and montrose takes `DATE` for a zone:

<!-- no-doc-test -->
```ruby
Montrose::Recurrence.from_ical(Acute.recurrence("every monday", now:, zone:).to_ical)
# ArgumentError: Invalid Timezone: DATE
```

### ice_cube

`IceCube::Schedule.from_ical` reads every line but drops the zone: it takes DTSTART's wall time in the process's own zone. It is right when the two match, here with `TZ=America/New_York`:

<!-- no-doc-test -->
```ruby
require "ice_cube"
x = Acute.recurrence("every day at 9am except christmas", now:, zone:)
s = IceCube::Schedule.from_ical(x.to_ical)
s.occurrences_between(Time.new(2026, 12, 24), Time.new(2026, 12, 27))
# => [2026-12-24 09:00:00 -0500, 2026-12-26 09:00:00 -0500]
```

On a server in another zone, the same lines give 9am there. To keep the rule's zone, build the schedule from an ActiveSupport time. This drops any "except":

<!-- no-doc-test -->
```ruby
require "active_support/time"
s = IceCube::Schedule.new(r.dtstart.in_time_zone(r.zone))
s.add_recurrence_rule(IceCube::Rule.from_ical(r.rrule))
s.first(3)
# => [2026-10-23 15:00:00.000000000 EDT -04:00, 2026-11-06 15:00:00.000000000 EST -05:00, 2026-11-20 15:00:00.000000000 EST -05:00]
```

acute lists occurrences itself too, with the zone and exceptions kept: [Occurrences](recurrence.md#occurrences).

## business and business_time: business days

acute's `business_days:` option takes any object that answers `business_day?(date)`. A `Business::Calendar` from business 3.1.0 does, as it is. Here Monday 19 October is a holiday:

<!-- no-doc-test -->
```ruby
require "business"
calendar = Business::Calendar.new(working_days: %w[mon tue wed thu fri], holidays: ["2026-10-19"])
Acute.parse("in 3 business days", now:, zone:, business_days: calendar).date.to_s   # => "2026-10-22"
Acute.parse("next business day", now:, zone:, business_days: calendar).date.to_s    # => "2026-10-20"
Acute.parse("in 3 business days", now:, zone:).date.to_s                            # => "2026-10-21"
```

business_time 0.13.0 keeps its calendar in `BusinessTime::Config` and answers `workday?`, so it takes one method to adapt:

<!-- no-doc-test -->
```ruby
require "business_time"
BusinessTime::Config.holidays << Date.new(2026, 10, 19)
workdays = Object.new
def workdays.business_day?(date) = date.workday?
Acute.parse("in 3 business days", now:, zone:, business_days: workdays).date.to_s   # => "2026-10-22"
```

The gems count from a weekend differently. Both move a Saturday on to the next business day before they count, so their own sums land a day later:

<!-- no-doc-test -->
```ruby
calendar.add_business_days(Date.new(2026, 10, 17), 3).to_s   # => "2026-10-23"
3.business_days.after(Date.new(2026, 10, 17)).to_s          # => "2026-10-23"
```

acute counts the business days after now, whatever day now is ([D17](rules.md#d17-business-days-and-fiscal-years)). From a weekday they agree. The calendar object is kept as given, so a parser holding one is shareable across Ractors only when the object is ([D45](rules.md#with)).

## nickel: times in a message

nickel 0.1.6 splits a message into its text and its times. `Acute.extract` does the same, and gives the times as Results, Rules and Durations:

```ruby
e = Acute.extract("call mom every tuesday at 6pm", now:, zone:)
e.mentions.map { [_1.kind, _1.text, _1.value.to_s] }
# => [[:rule, "every tuesday at 6pm", "every Tuesday at 6pm"]]
e.remainder   # => "call mom"
```

Some answers differ. For "lunch with sam next friday at noon", nickel's date is 30 October; acute's is the coming Friday, 23 October ([D20](rules.md#d20-next-friday)):

```ruby
Acute.extract("lunch with sam next friday at noon", now:, zone:).mentions.map { [_1.text, _1.value.to_s] }
# => [["next friday at noon", "Fri, Oct 23, 2026, 12pm EDT"]]
```

More on `extract`: [Dates inside other text](usage.md#dates-inside-other-text).

## tickle: repeating times

tickle 1.2.0 reads a repeating phrase and returns a Hash with its next time. `Acute.recurrence` returns a Rule: its RRULE, every occurrence, and a cron line when cron can say it:

```ruby
l = Acute.recurrence("the last friday of every month", now:, zone:)
l.rrule                  # => "FREQ=MONTHLY;BYDAY=-1FR"
l.next(2).map(&:to_s)    # => ["2026-10-30", "2026-11-27"]
```

tickle takes no zone or `now`: it counts from the clock and refuses a start before today. Asked on 24 October 2026, it gave Saturday 4 September 2027 as the next "last friday of every month".

Everything a Rule does: [Repeating times](recurrence.md).
