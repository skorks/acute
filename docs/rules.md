# Rules

Many date phrases can be read more than one way. "at 9" could be morning or evening; "1/2/2015" could be January or February. acute settles each of these with a fixed, numbered rule, so the same phrase always means the same thing.

## How to read this page

**A rule** is a numbered convention, such as D4 for a time without am/pm. The main rules have their own heading ("D4."). Smaller rules are bullets tagged with their number ("**D44.**"). Finding times in text has E-rules, and repeating times R-rules. Several bullets can share a number. The gaps in the numbering are rules that were retired.

**An assumption** is a record that a rule made a choice for you. Each result lists the assumptions its parse made. Each one has:
- a `code`, a stable Symbol you can match on;
- a `rule`, the number of the rule on this page;
- a `message`, a sentence for a person.

```ruby
r = Acute.parse("at 9", now: "2026-10-17T10:00", zone: "America/New_York")
r.time                     # => 2026-10-18 09:00:00 -0400
r.alternatives.map(&:time) # => [2026-10-17 21:00:00 -0400]
r.assumptions.map(&:code)  # => [:bare_hour_window, :next_occurrence]
r.assumptions.first.rule   # => "D4"
```

When a rule leaves another reasonable reading, that reading is an **alternative**, and the result's `alternatives` list holds it. The first reading is the one acute thinks most likely. The [assumptions table](#assumptions) at the end lists every code.

**The examples** are said on Saturday 17 October 2026 at 14:00 in New York (`America/New_York`, so en-US), unless they say otherwise. "→" gives the answer. A range of clock times leaves out its end: "17:00–21:00" stops as 21:00 begins. A range of days, months or years includes its end: "Monday to Wednesday", "1990–1999". In a Result, `end` is always the first moment after the span.

## Defaults

### D23. Future context, two-digit years, whole units, arithmetic and DST

- **Future context.** A phrase that could mean a past or a future time means the future one. "at 3pm" said at 16:00 → tomorrow 15:00 (`next_occurrence`). `context: :past` reverses this: "at 3pm" said at 10:00 → yesterday 15:00 (`previous_occurrence`).
- **Two-digit years** fall in the 100 years that start 50 years before now. Said in 2026, "1/2/75" → 2075 and "1/2/76" → 1976. `year_bias:` sets how many years back the window starts.
- **Whole units.** A phrase means the whole unit it names. "tomorrow" is the whole day, "october" the whole month. A Result's `time` is the start; `begin` and `end` give the span.
- **Arithmetic:**
  - years and months move on the calendar, and a day past the month's end becomes its last day: "1 month after jan 31" → 28 February;
  - weeks and days move on the wall clock, so "in 1 day" across a clock change keeps the time of day;
  - hours, minutes and seconds count elapsed time. "in 3 hours" said at 23:30 on 31 October 2026 → 01:30 EST on 1 November, three real hours later.
- **DST.** A wall time the clocks repeat takes the earlier instant (`dst_repeated_time`). A wall time the clocks skip moves forward by the gap (`dst_skipped_time`). "march 8 2026 2:30am" → 03:30 EDT.
- **D47.** `dst: :earlier` or `dst: :later` takes that instant instead, and records no assumption. `dst: :reject` makes a skipped or repeated wall time a failure, with the code `:dst_skipped_time` or `:dst_repeated_time`, and drops alternatives that are such times.
- **D47.** `year_bias:` defaults to 50.
- **D47.** `now` is taken to the whole second.

### D27. One locale drives the regional conventions

- **The locale sets four things:**
  - the order of numeric dates (D10);
  - the built-in holidays (D15);
  - the first day of the week (D19);
  - the hemisphere for seasons (D3).
- **Without `locale:`,** the locale comes from the zone's country. `Australia/Sydney` gives en-AU; `America/New_York` gives en-US.
- **UTC, and zones with no country,** fall back to en-US. A server running in UTC gets US date order unless it passes `locale:`.
- **Options win over the locale:** `week_start:` and `hemisphere:`.
- **D42.** A zone's country is its primary country in the tz database, also for zones that several countries share.
- **D44.** A zone the tz database turned into a link keeps its own country: `Europe/Oslo` is Norway.
- **D43.** The locale follows the zone passed, or `locale:`. A zone or offset written in the text never changes it.

### D39. Locale data comes from CLDR

Each country's week start and date order come from the Unicode CLDR data, the same data JavaScript's `Intl` uses. For example:
- China starts weeks on Monday.
- India, Pakistan, Japan, Brazil and Nepal start on Sunday.
- Canada starts on Sunday and writes dates year first.

## Times of day

### D4. A time of day without am/pm

Examples: "at 9", "5:30".

- **Hours 6 to 11 are am. Hours 12 and 1 to 5 are pm.** The other half of the day is always an alternative (`bare_hour_window`).
- **If that time has passed today, it means tomorrow's** (D23).

| Said at | Phrase | First reading | Alternative |
|---|---|---|---|
| 10:00 | at 3 | today 15:00 | tomorrow 03:00 |
| 10:00 | at 9 | tomorrow 09:00 | today 21:00 |
| 20:00 | at 9 | tomorrow 09:00 | today 21:00 |

- **These are always 24-hour:**
  - a leading zero: "09:30";
  - an hour of 13 or more: "15:30";
  - a time after an ISO date: "2026-10-23 11:00".
- **D40.** When the window reading is still to come but the other half has passed, the window reading comes first, then the other half's next occurrence.
- **D40.** When the day and the am/pm are both ambiguous, the day ranks first. "tomorrow at 7:15" said at 02:00 (see D35) gives:
  1. today 07:15;
  2. today 19:15;
  3. tomorrow 07:15;
  4. tomorrow 19:15.
- **D41.** A phrase that is only a one- or two-digit number is an hour: "5" → 17:00, with 05:00 as the alternative. Inside a longer phrase, a bare number needs "at" or a day word to be a time.
- **D44.** A bare number before a part of day or a day word is an hour: "7 tonight", "8 this evening", "9 tomorrow". So is one before "in the morning" or "at night".
- **D46.** So is a bare number before "on" and a day: "5 on friday" → Friday 17:00, alternative 05:00.
- **D18.** "next 3pm" and "last 3pm" are the nearest 15:00 after now and before now.

### D29. Times that look machine-written

Examples: "10:36:22", "8:00:00 -04:00", "10:00 GMT-05:00".

A time with seconds or a numeric UTC offset is 24-hour, with no am/pm alternative (`machine_time`). A zone name alone doesn't count: "8:00 gmt" still follows D4.

- **D40.** An option the caller sets beats this. In the chronic layer, `hours24: false` reads "today at 02:00:00" as 14:00.
- **D44.** Morning, afternoon and evening still fix am or pm: "afternoon 7:00:05" → 19:00:05.

### D30. The 12 o'clock hour

Any time in the 12 o'clock hour without am/pm is pm, with no alternative (`twelve_oclock`): "12:03", "at 12", "half past twelve", "twelve oh three".

- "12 in the morning" → 00:00.
- "12 at night" and "12 in the evening" → midnight at the end of that day, as in D6.
- **D40.** This beats the part-of-day rule: "12 in the evening" is not noon.

### D5. A bare four-digit number

Four digits are a year unless something marks them as a time:
- "at" in front: "at 1530";
- a suffix: "1530h", "1530 hrs", "0600 hours";
- a leading zero: "0600";
- am or pm after them: "1140 a.m." (**D44.**)

So "christmas 2015" → 25 December 2015, "tomorrow at 1530" → 15:30, and "1530" alone → the year 1530.

- **D44.** Three digits are a time only when am or pm follows them, or "at" or a part of day comes before them: "330 p.m.", "at 730 in the evening", "tonight 815". "134 this afternoon" → nil.
- **D48.** A 24-hour clock before "hours" is that clock: "06:00 hours", "18:30 hours". "1:30 hours" is not read, since it could be a length.

### D6. Midnight with a day

"monday midnight" → Tuesday 00:00, the end of Monday (`midnight_end_of_day`). The start of Monday is the alternative.

- "00:00" and "12am" written out mean the start of the day.
- **D44.** "at the start of" a day is its first moment; "at the end of" a day is its last.
- **D44.** "24:00" and "24 o'clock" are the end of the day. "24:01" → nil.
- **D44.** Hour 0 with am is midnight: "monday 0am". "0pm" → nil.
- **D44.** "mid day" and "mid night" are midday and midnight.

### D36. A time equal to now

A time or period that starts exactly at now has not passed, so it means now (`equal_to_now`). Said at exactly 00:00:
- "midnight" and "00:00" → now.
- "tonight at midnight" → only the end of tonight. The start of today is not tonight, so it is dropped.
- **D44.** "sunday at noon" said at noon on Sunday → now, then next Sunday at noon.

### D14. Approximate times

"around 1pm", "noonish" and "about 3" give the exact time, with the `approximate` assumption. The span is not widened.

- **D44.** "around", "about", "approx", "circa" or "ish" anywhere in the phrase makes it approximate: "tomorrow around 10am", "3pm approximately", "in about 5 hours".
- **D44.** "ish" joined to a word of three letters or more is that word: "noonish", "tenish". "dish" and "wish" stay unknown. "11ish" alone is an hour.
- **D48.** "3ish pm" is about 15:00.
- **D48.** "around" after "beginning of" is approximate too: "beginning of around next week".

### More clock forms

- **D42.** A glued "a" is am ("8a"), as a glued "p" is pm.
- **D42.** "N to M" with digits is a range ("5 to 9" → 17:00–21:00). With the minutes as a word it is minutes to the hour: "five to 9" → 08:55. After "from" or "between" it is a range again.
- **D44.** Minutes "after", "before" or "prior to" an hour are a clock: "10 after 2", "twenty before noon". Noon and midnight can be the hour: "a quarter to midnight" → 23:45.
- **D44.** Digits "to noon" are minutes when a range would end before it began: "15 to noon" → 11:45. "10 to noon" stays a range.
- **D44.** "three hours past noon" → 15:00.
- **D44.** An "h" between hours and minutes is a 24-hour clock: "15h30", "06:00h". "15h" alone is a count of hours, so it is nil as a time; "at 16h" is 16:00.
- **D44.** Numbers joined by a dot before am or pm are a clock ("9.30pm"), and so are two after "at" ("at 6.45"). Otherwise they are a dotted date (D10).
- **D44.** After "at", an hour, a space and two digits up to 59 are its minutes: "at 3 15" → 15:15.
- **D44.** An hour word, then "oh", "o" or "zero", then a digit word is a clock: "twelve oh three" → 12:03.
- **D44.** "am" or "pm" after "in the" belongs to the clock: "3 in the AM".
- **D47.** A written fraction of a second is kept exactly, as a Rational: "01:00:00.100" → 01:00:00.1. The grain stays `:second`. Only an instant keeps it; a range between two such clocks is whole seconds. ISO 8601 and JSON show the fewest digits that give it exactly.
- **D47.** A colon before three or more digits after the seconds is a fraction: "15:30:30:000536".
- **D48.** A decimal comma or compact digits also give a fraction: "10:49:41,502", "T104941.5".
- **D48.** "half" before an hour is half past it: "half three" → 15:30, alternative 03:30.
- **D48.** Minutes to or past a clock with its own minutes count from it: "three mins to five thirty" → 05:27, under D4.
- **D48.** A dotted clock is read where no date fits ("18.20") and after a weekday or "at" ("last fri 9.30").
- **D48.** A meridiem before a 12-hour clock after a date belongs to it: "2020/10/9 PM 2:26".
- **D48.** Prime marks are minutes and seconds when the number is under 60: "in 15'" → in 15 minutes.

## Parts of the day

### D1. Part-of-day words

Each word means a range. The result also carries a single point, for a caller that needs one Time (`part_of_day_point`).

| Word | Range | Point |
|---|---|---|
| early morning | 04:00–08:00 | 06:00 |
| morning | 06:00–12:00 | 09:00 |
| noon, midday | a point | 12:00 |
| afternoon | 12:00–17:00 | 15:00 |
| evening | 17:00–21:00 | 19:00 |
| night | 21:00–04:00 next day | 22:00 |
| tonight | 17:00–04:00 next day | 22:00 |
| last night | 17:00 yesterday–04:00 today | 22:00 yesterday |
| late night | 22:00–04:00 next day | 23:00 |

- **"this morning" is today's morning,** even once it has passed. A bare "morning" means the next one, unless one is in progress (D35).
- **A clock time with a part of day only picks am or pm.** "4 in the morning" → 04:00, "8 in the evening" → 20:00, "2 at night" → 02:00. The ranges don't bound the stated time.

### D35. Parts of the day, in detail

| Phrase | Range | Point |
|---|---|---|
| lunch, lunchtime | 12:00–14:00 | 12:30 |
| early hours, small hours | 00:00–04:00 | 02:00 |
| early afternoon | 12:00–14:30 | 12:00 |
| late afternoon | 14:30–17:00 | 14:30 |
| early evening | 17:00–19:00 | 17:00 |
| late evening | 19:00–21:00 | 19:00 |
| mid-morning | 08:00–10:00 | 08:00 |
| mid-afternoon | 13:40–15:20 | 13:40 |

- **"early" and "late" split a part of day into halves,** with the half's start as its point. Early morning and late night keep their D1 ranges.
- **D40.** "mid" takes the middle third (D2).
- **A part of day in progress means the current one.** "morning" said at 10:00 → this morning. Said at 14:00 → tomorrow's.
- **A clock with a part of day takes the am or pm that keeps it inside.** If neither is inside, it takes the closer one. "tonight at 4:59" → 16:59; "five thirty in the night" → 05:30.
- **D40.** A word that fixes am or pm wins over that. Morning fixes am; afternoon and evening fix pm. "this evening at 2" → 14:00, "this afternoon at 11" → 23:00, "this morning at 12" → 00:00, "one in the morning" → 01:00.
- **D44.** Lunch fixes neither: "at lunchtime 11 o'clock" → 11:00.
- **D42.** A clock inside the early hours is am.
- **D44.** "early" or "late" before a part of day adds nothing beside a clock: "early morning at 8:00" → 08:00.
- **D18.** "tonight at 2" → 02:00 tomorrow, inside tonight's range.

**Said between 00:00 and 04:00:**
- **"tonight" is the night in progress.** At 01:00, "tonight" → Friday 17:00 to Saturday 04:00.
- **D42.** At exactly 00:00, "tonight" → [00:00, 04:00) first, then the coming tonight.
- **D51.** At exactly 00:00, "last night" is the calendar yesterday's: 17:00 yesterday to 04:00 today, as D41 reads "tomorrow".
- **D40.** A clock in "tonight" counts in the night under way only if it is now or later. At 02:00: "tonight at 4" → 04:00 today, "tonight at 9" → 21:00 today, "tonight at midnight" → the coming midnight.
- **D40.** "tomorrow" is today first, then the calendar tomorrow (`tomorrow_after_midnight`). "yesterday" stays literal.
- **D41.** That window starts at 00:00:01. At exactly 00:00:00, "tomorrow" is the calendar tomorrow, so `now: Date.today` behaves as expected.

**More:**
- **D40.** "next night" → tomorrow night.
- **D44.** "early tomorrow evening" is "tomorrow early evening".
- **D46.** A part of day counts like a weekday: "5 mornings ago" is the fifth morning before now, today's not counted unless it is over. "mornings" alone → nil.

## Days and named periods

### D11. A named period on its own

A weekday, month, quarter, season or holiday named alone means the current one if it isn't over, otherwise the next one.
- "q1" said in November → Q1 next year.
- "november" said in November → this November.
- "friday" said on Saturday → next Friday.

**Said on that day:**
- **D40.** A bare weekday or a bare day of the month said on that day gives today, then the next one (`same_day_or_next`). "the 17th" on the 17th → today, then 17 November.
- **D44.** A date with its month ("october 17", "11/11", "christmas") or an nth weekday ("the third saturday of the month") said on that day is today alone.
- **D44.** A weekday with a time or part of day said on that day is read the same way. Once today's has ended, next week's comes first and today's second: "sunday morning" said on Sunday at 20:00 → next Sunday's morning, then today's.
- **D44.** A weekday with a day of the month picks whichever of the two readings it fits: "Sat 16th" said on Wednesday the 16th → next month's 16th, a Saturday.

**Under way:**
- A range of dates or months already under way is the current one, with the coming one as the alternative (`range_under_way`). "from september to november" said in October → this one, then next year's. A range that starts today is today's alone. (**D44.**)
- **D44.** A range of weekdays isn't affected: "monday to friday" said on Saturday → next Monday to Friday.

**In past context:**
- **D44.** A weekday or day of the month said on that day is today's, then the one before. Until today's has begun, the one before comes first.
- **D44.** A period under way ("october" in October, "Q3" in Q3) is the current one, then the one before.

**Other:**
- "coming week" and "upcoming week" are the next calendar week.
- **D42.** Only a date skips the cycles it doesn't exist in. "feb 29" → 2028, and "the 31st" → the next month that has one. "5th tuesday in may" → nil when this May has none.
- **D42.** "first" alone is not a date.
- **D44.** A plural day alone ("fridays") → nil: it is a rule (R6).

### D20. "next friday"

"next <weekday>" can mean the coming one or the one after. Both are given, the coming one first (`next_two_readings`).

D32 says when there are two. The coming Friday and next week's Friday must differ, so it depends on the week start (D19):

| Said on (en-US) | "next friday" |
|---|---|
| Sunday to Thursday | the coming Friday, then the one a week later |
| Friday | a week today, one answer (D40) |
| Saturday | the coming Friday, one answer |

"next sunday" said on a Wednesday is the coming Sunday alone in en-US, where it already starts next week. In en-GB it has two readings.

### D21. "this friday" once Friday has passed

"this friday" said on Saturday → next week's Friday first, then the one that has passed (`this_passed`). Before Friday, it is this week's Friday, one answer.

- "this saturday at noon" said on Saturday at 14:00 → next Saturday at noon first, then today's (`this_passed`). Said before noon, it is today's.

### D32. next, this and last with any named period

D20 and D21 apply to every named period: weekdays, months, seasons, holidays, quarters and week numbers.

- **"next X"** is the coming X, then the X in the next enclosing period: the next week for weekdays, the next year for the rest. If those are the same, there is one answer. "next march" said in October → March 2027 alone; said in January → March this year, then next year.
- **"this X"** is the one in the current period. If it is over, the next one comes first and the passed one second. If it is in progress or today, it is the current one.
- **"last X"** is the most recent one that is over.
- **A bare X** follows D11.

More:
- **D40.** "next X" said while X is today or under way is the one after, one answer. "next friday" on a Friday → +7 days; "next october" in October → 2027; "next christmas" on Christmas Day → next year's.
- **D40.** "first <weekday> of the month" once this month's has passed is next month's, one answer. **D42.** "of the month" always means the coming one.
- **D40.** "this weekday" said at a weekend is the coming Monday. **D44.** On a weekday it is today.
- **D42.** "this coming X" is the first X after now, with no alternative.
- **D44.** "this past X" is "last X". **D48.** "this last" is "this past": "this last hour" is the hour before now.
- **D44.** Looking back, a "this X" that is over is the one just passed: "since this august" said in November → from 1 August this year.
- **D44.** "following" is "next". "current" is "this".
- **D44.** "<X> after next" is the one after "next X", for each of its readings: "friday after next" said on a Tuesday → next week's Friday or the one after. "before last" is the one before "last X".
- **D44.** "the day after tomorrow" and "the day before yesterday" are one day from the day named.
- **D44.** "<X> after/before <a day>" is the first X past it: "the monday before christmas".
- **D44.** "<weekday|part of day|holiday> of <period>" is the one inside it: "tuesday of next week", "morning of xmas", "labor day of last year". **D48.** So is "sunday from last week", and a possessive: "last week's sunday".
- **D44.** "last <weekday> in <month>" is the last one of that month. **D48.** "last tuesday this month" is the last Tuesday of this month.
- **D44.** "final" is "last" as an ordinal: "final thursday in april". **D48.** "nth last" counts from the end: "the fifth last day of May" → 27 May.
- **D48.** "the nth closest X to Y" counts Xs by distance from Y's start, either side; a tie goes to the earlier. "nearest" is the same.
- **D48.** "last 9/11" is the most recent 11 September.

## Weeks

### D19. Week start

- **en-US** starts weeks on Sunday. So do UTC and zones with no country.
- **Australia, the UK, Europe and most other locales** start on Monday.
- **`week_start:`** overrides the locale.
- **Week numbers** always start on Monday (D13).

"this week" → Sunday 11 to Saturday 17 October in New York, Monday 12 to Sunday 18 in London.

- **D44.** "the week of X" is the calendar week that holds X: "the week of october 7th" in en-US → Sunday 6 to Saturday 12 October. "the month of X" is likewise the month that holds it. **D51.** So is "the year of X": "the year of 2008".
- **D44.** "the week beginning february 4" and "w/c feb 4" (**D48.**) are seven days from the 4th.
- **D48.** The working week is Monday to Friday: "next working week", "work week", "business week". "monday to friday last week" is the same span.
- **D48.** "all week" is this week. "the rest of the week" runs from now to the week's end.
- **D38.** "beginning of week" is the first day of the locale's week. **D40.** A bare one is the current week's.

### D13. Week numbers

"week 42", "W42" and "2026-W42" are ISO 8601 weeks, Monday to Sunday, whatever the locale's week start.

- **D44.** "week 53" of a year with 52 weeks → nil. A bare "week 53" is the next year that has one.
- **D44.** "2026-W42-3" is the ISO day of the week, Monday being 1, so Wednesday. "W481" is week 48, day 1.
- **D32.** "week 10" once it has passed is week 10 next year.

### D8. Weekend

The weekend is Saturday 00:00 to Monday 00:00. The same weekend from Friday 18:00 is an alternative (`weekend_friday_evening`).
- "this weekend" said on Saturday or Sunday is the current one.
- "next weekend" said on a weekday follows D20. **D38.** The alternatives come in this order:
  1. the coming weekend;
  2. the following weekend;
  3. the Friday-evening version of each.
- **D40.** "next weekend" said at the weekend is the following weekend, then its Friday-evening version.
- **D44.** The last weekend of a month is the one whose Saturday is in it.
- **D48.** "<holiday> weekend" is the long weekend the holiday makes. The weekend nearest it is stretched to take in a Monday or Friday holiday. "labor day weekend" 2013 → Saturday 31 August to Monday 2 September, then the same from Friday 18:00.

## Seasons

### D3. Seasons

Seasons are meteorological: three whole months (`meteorological_season`).

| Season | Northern | Southern |
|---|---|---|
| spring | Mar–May | Sep–Nov |
| summer | Jun–Aug | Dec–Feb |
| autumn, fall | Sep–Nov | Mar–May |
| winter | Dec–Feb | Jun–Aug |

- **The hemisphere follows the locale** (D27); `hemisphere:` overrides it. "summer" in Sydney is December to February.
- **A season belongs to the year it starts in.** "winter 2026" → December 2026 to February 2027. The winter ending in 2026 is the alternative (`season_year`).

### D33. Seasons relative to now

- "this", "next" and "last" with a season follow D32. "next summer" said during summer → next year's; "last winter" said in January 2027 → December 2025 to February 2026.
- A bare season follows D11: the current one if it is under way, otherwise the next.
- **D40.** "this summer" said during summer is the one in progress.
- **D44.** A season takes "of" and a year like a month: "spring of 2028".
- **D48.** "season" is a three-month unit starting in December, March, June or September. "this season" said in February → December to February. A counted season counts like a weekday: "three summers ago" said in November 2011 → summer 2009.

## Years, decades and centuries

### D12. Centuries and decades

- **Centuries run from the 00 year:** "the 15th century" → 1400–1499. 1401–1500 is the alternative (`century_from_00`).
- **Decades:** "the 90s" → 1990–1999, in D23's window. "the 2000s" → the decade 2000–2009, with the century as the alternative (`decade_or_century`).
- **D44.** "last/this/next century" are whole centuries from the 00 year, with the 01 reading as the alternative. "last century" → 1900–1999.
- **D44.** "this coming decade" is the next whole decade alone.
- **D44.** "30s" before ago, hence, later, from, after or before, or after "in", is thirty seconds.
- **D42.** Early, mid and late split a decade too (D2).

**Years:**
- **D44.** Two digits after a day and month are its year, in D23's window: "3 jan 10", "may 27 79". Not when a meridiem, "o'clock", a unit or a range follows: "may 27 10am".
- **D44.** After a month with no day, two digits past 31 are its year: "dec 79", "august 32" → August 2032.
- **D44.** An apostrophe before two digits marks a year: "may '01", "the '90s".
- **D44.** "the year 1980" → 1980. **D48.** Three digits after "year" are the year as written: "year 247".
- **D44.** Two number words are a year when they can't be a clock: "nineteen ninety five", "twenty ten". From thirteen to twenty-three, other than eighteen to twenty, the second must be over 59, so "fourteen thirty" → nil.
- **D44.** "two thousand", "two thousand and eighteen" and "the year two thousand" are years.
- **D44.** "AD", "A.D." and "CE" after a year make it that year as written: "10 August 88 AD" → the year 88.
- **D48.** "BE" after a year from 2400 is the Buddhist era, 543 years ahead: "August 10 2555 BE" → 10 August 2012. Below 2400, "BE" is not read.
- **D18.** Year 0 and BC are out of scope; they return nil.
- **D44.** "the first half of 2027" and "H1 2027" → January to June. "H2" is July to December. "the first 9 months of 1997" counts from its start.
- **D44.** "first quarter" and "2nd quarter" are Q1 and Q2. **D48.** "18q4" → the fourth quarter of 2018.
- **D48.** "calendar" before a unit is that unit: "calendar year 2008".
- **D48.** "leap year" and "leap day" are named like holidays: "next leap year" → 2028. "leap day 2027" → nil.
- **D40.** "this day 1800" is today's date in 1800.

## Written dates

### D10. Numeric dates

Examples: "1/2/2015", "1.2.2015".

- **Slashed and dashed dates follow the locale's order** (D27). en-US is month first; en-GB and en-AU are day first.
- **Dotted dates are always day first.**
- **The other order is an alternative when it is also a valid date** (`numeric_date_order`). "13/2/2015" can only be read one way, so it has no alternative.

| Phrase | New York | Sydney |
|---|---|---|
| 1/2/2015 | 2 Jan, then 1 Feb | 1 Feb, then 2 Jan |
| 1.2.2015 | 1 Feb, then 2 Jan | 1 Feb, then 2 Jan |
| 13/2/2015 | 13 Feb | 13 Feb |

### D37. Numeric dates, in detail

- **A weekday that fits only one reading picks it.** "Friday 7/6" said on Friday 6 July 2018 → 6 July alone.
- **D44.** A weekday that fits both orders picks the locale's.
- **D43.** A weekday that fits no reading gives way to the date (`weekday_mismatch`). "Sat, Sep 21" said in October 2026 → Tuesday 21 September 2027. No other year is searched. "monday the 31st" → the coming 31st, flagged.
- **D43.** Before that, the weekday may pick the date just gone, one cycle back. "Thu Aug 10" said on Wednesday 16 August 2006 → Thursday 10 August 2006.
- **D40.** The weekday is checked against this year's date before a passed date moves to next year.
- **Year-first locales** (en-CA, Japan, China) read n/n/yyyy month first. A year-first reading needs a four-digit first number: "2026/1/2" → 2 January in Toronto.
- **Space-separated numbers** follow the slashed rules: "10 12 2011". **D44.** One of the end numbers must be a four-digit year. Number words are not read this way.
- **When the date and the am/pm are both ambiguous, the date order ranks first.** "8:43 on 6/12/2008" gives:
  1. 12 June 08:43;
  2. 12 June 20:43;
  3. 6 December 08:43;
  4. 6 December 20:43.
- **A dotted date with no valid day-first reading** takes the other: "11.23.2026" → 23 November.

**Other written forms:**
- **D18.** Invalid dates are nil. "feb 30" and "4/32" don't roll over. **D48.** `parse!` says what is out of range: "June has 30 days", "2027 is not a leap year", "there is no hour 25", "there is no hour 13 on a 12-hour clock". Otherwise the message is `"<text>" is not a valid time`.
- **D42.** A year-first date needs four digits: "2026-10-23" is year first, "26-10-23" is not. A five-digit year is invalid.
- **D44.** A first number of four digits is the year, whatever the separator: "2026/11/23", "2026.11.23".
- **D44.** Two numbers, one of four digits, are a month and its year: "11/2026".
- **D42.** "N-M" is a date when either number is over 12, and a clock range otherwise: "9-5" → 09:00–17:00.
- **D48.** Two padded numbers joined by a dash before a time are a date: "05-06 at noon" → 6 May at noon.
- **D43.** ISO ordinal dates: "2026-001" is 1 January. "2026-366" → nil.
- **D44.** Eight digits are a compact ISO date ("20261123"), optionally followed by a T and a time ("20030925T104941"). Twelve or fourteen digits are a date and its time ("199709020908").
- **D44.** A time has the grain of the finest unit written: "07:00:00" is second grain, and "2003-09-25T10" is hour grain.
- **D44.** A dash with no space either side joins one written date: "20-Apr", "30-Mar-11", "Sep-25-2003", "Apr-20" (April 20), "Sep-2012", "5-2020" (May 2020). A first number past 31 is the year.
- **D44.** A slash joins a written month the same way: "25/Sep/2003", "2024/August". A log's time follows a colon: "06/Nov/2023:06:36:02 +0200".
- **D44.** A hyphen straight after a month or weekday name is a range: "jun-aug", "mon-fri".
- **D44.** A clock joined by a dash to a numeric date is its time: "05/31/2024-14:15". **D48.** So is one joined by a dot or colon: "05/31/2024.14:15".
- **D44.** A two-digit year comes first when an apostrophe marks it or it is past 31: "'69-5-31", "78-12-22".
- **D44.** A dot after a day or month joins a date even with spaces around it: "11. 12. 2014". Not after a month's name.
- **D44.** Two dotted numbers beside a written date are its clock: "29.02.2020 13.12".
- **D46.** EXIF dates: "2012:05:25 22:06:50" → 25 May 2012, 22:06:50.
- **D48.** "the 29th day of November" → 29 November. "the 24" and "the 3 of next month" are days of the month.
- **D44.** A number of a month is its day: "15 of february", "20 of next month".
- **D48.** "Sep.25.2003" and "[Sept] 04, 2014" are read.

## Ranges

### D9. Where ranges end

- **Days or larger include the end.** "mon to wed", "mon–wed", "mon through wed" and "until wed" all end at Thursday 00:00.
- **With clock times, the end is the stated time.** "2 to 4pm" → 14:00–16:00. "11 to 2pm" starts at 11:00.
- **"up to <date>" leaves the date out:** "up to wed" ends at Wednesday 00:00.
- **"between X and Y"** follows the same rules.

**Clock ranges:**
- **D40.** A clock range already under way is today's, one answer: "9-5" said at noon → today 09:00–17:00.
- **D44.** One that runs past midnight and began yesterday is under way until it ends: "from 23 to 3pm" said at 13:37 starts at last night's 23:00.
- **D44.** Atoms before or after a clock range belong to both ends: "monday 8-9am", "9:30 - 11:00 CST".
- **D44.** A range after a day is within it: "tomorrow from 2 to 4pm", "Friday between 1PM and 4 PM". "tomorrow from 9am" is incomplete, as "from 9am" is.
- **D51.** A zone after it is the day's too: "Friday, between 9-6 PT" is 09:00 to 18:00 Pacific on Friday. Only after a weekday: a numeric date keeps its readings.
- **D48.** A clock range, then "of" and a date, is on that date: "from 5 to 6pm of April 22".

**Date ranges:**
- **D42.** "june 3-7" is 3 to 7 June.
- **D44.** A bare day at either end takes its month from the other: "13 to 15 july", "the ninth to the seventeenth of april".
- **D44.** A year said only at the end belongs to the start too, or the year before if the start would come after the end: "Aug 10 - Nov 12, 2013", "December to May 2025" (from December 2024).
- **D44.** Both ends of a numeric date range are read in the same order: "5/1-5/7, 2020" → 1 to 7 May, then 5 January to 5 July.
- **D44.** "12-14 June" is 12 to 14 June. Number word ordinals work too: "eighth to eleventh May", "april ninth through seventeenth".
- **D44.** Two four-digit numbers joined by a dash or "~" are a range of years: "2014-2018". Not with a leading zero ("0900-1700").
- **D44.** A range to a day with more than one reading gives a range for each: "noon yesterday through midnight today" ends at today's end, then at its start.
- **D44.** A dash with a space after it, after a machine-written clock, is a range: "2014-04-18 13:00 - 16:00". "13:00-05:00" stays an offset.
- **D48.** An ISO 8601 interval with a slash is a range: "2007-03-01T13:00:00Z/2008-05-11T15:30:00Z".
- **D48.** "up to" and "in between" join a range as "to" and "between" do.
- **D51.** After "from", "and" joins a range as "to" does: "from 2015 and 2016" is 2015 to the end of 2016.
- **D48.** "first to last day of 2008" is all of 2008.
- **D48.** "friday to monday next week" starts on that week's Friday and ends with the Monday after it, as a range to an earlier weekday does without the week: Friday to Monday inclusive.
- **D48.** "today and tomorrow", and any day then the next, is both days. Other pairs are not joined.

**Lengths:**
- **D44.** "starting X", "commencing X" and "beginning X" are open from X's start: "starting next week".
- **D44.** A count of units starting X runs that long from X's start: "3 days starting next monday" → Monday to Wednesday.
- **D44.** "for 3 days from today" and "for 2 hours starting 3pm" are that long from the start.
- **D48.** "from <time> for <length>" lasts that long: "from 18th Dec for 10 days" → 18 to 27 December, "from 4pm for thirty minutes" → 16:00–16:30.

## Open ends

### D16. Open-ended phrases

"before friday", "after 3pm", "since monday" and "until june" give a range with one open end.
- **"since X"** closes at now: "since monday" → Monday 00:00 to now.
- **"until X"** opens at now and includes X: "until wed" → now to Thursday 00:00.
- **"before X"** ends when X starts: "before friday" → open to Friday 00:00.
- **"after X"** starts when X ends: "after friday" → from Saturday 00:00.

More:
- **D42.** "after <clock>" starts at the clock: "after 3pm" → from 15:00.
- **D44.** "until 23:59" ends at 23:59, but "by EOD" ends at midnight: until a day's last second is until the day's end.
- **D44.** "later than X" and "greater than X" are "after X". "earlier than", "sooner than" and "in advance of" are "before X".
- **D44.** "on or after X", "X or later", "X onwards" and "X and later" start when X starts. **D48.** So does "X and after".
- **D51.** Before "than", "or later" is "or" and then "later than": "between 2015 and 2018 or later than 2020" is two.
- **D44.** "on or before X" and "X or earlier" end when X ends, with no start. A clock ends at itself.
- **D44.** "or after" and "or before" only end a phrase: "before 2010 or after 2018" → nil.
- **D44.** "no later than X" is "by X". "through X" alone is "until X".
- **D44.** "after X but before Y" is a range when both are clocks. With days it is nil.
- **D44.** An open span that would run backwards is nil: "until 2014", "until yesterday", "since tomorrow". Of several readings, the backwards ones are dropped.
- **D48.** "the rest of <period>" runs from now to its end: "rest of the week", "remainder of the month".
- **D48.** "anytime" and "sometime" before "before" or "after" are dropped.
- **D48.** A day, then "before" or "after" a clock, is that part of the day: "tomorrow before 4pm" → tomorrow 00:00–16:00, "monday after 5pm" → Monday 17:00 to midnight.

### D34. Open-ended phrases, in detail

- **"after <period>"** starts when it ends: "after may" → from 1 June 2027.
- **"before <period>"** ends when it starts.
- **"since X"** looks back. X is its most recent occurrence: "since 2pm" said at 10:00 → from yesterday 14:00. "since yesterday" → yesterday 00:00 to now.
- **A date without a year** follows the direction: "since" looks back; "until", "before" and "after" look forward. "until june" → now to 1 July 2027.
- **D40.** "after the start of november" → from 2 November, as "after <day>" is.
- **D42.** "after <holiday>" keeps this year's once it has passed: "after christmas" said on 27 December → from 26 December. Other periods move on: "after january" said in October → from February next year.
- **D44.** A look back takes the most recent one, with no alternative: "since saturday" said on a Saturday → from today.

## Rolling windows

### D7. last, past, next and within N units

- **A window counted from now** (`rolling_window`): "past 7 days" → now − 7 days to now; "next 3 days" → now to now + 3 days.
- **D50.** "this" takes no count: "this 5 years" is nil, so "he said this 5 years ago" mentions "5 years ago".
- **Whole calendar days are the alternatives.** "past 7 days" → the rolling window, then 11–17 October (ending today), then 10–16 October.
- **Seconds, minutes and hours** are rolling only: "past 24 hours".
- **"last week"** with no number is the previous calendar week.
- **D42.** "next second" has no rolling reading. It is the next calendar second.
- **D38.** "next hour" and "last minute" with no number give the rolling one first, then the next or previous clock hour or minute. When the two are the same, there is one answer.

### D31. Windows of weeks, months, quarters and years

- **Rolling comes first.** The calendar alternatives are whole units of the size named.
- **For "past":** the N units ending with the current one, then the N units before it. "past 3 months" in October → the rolling window, then August–October, then July–September.
- **For "next":** the N units starting with the next one.
- **A fortnight is 2 weeks.** "next fortnight" is "next 2 weeks".
- **"within N units" is "next N units".** **D44.** So is "within the next N units".
- **"past week" is "past 1 week",** so the rolling 7 days come first. "last week" stays the previous calendar week.
- **D40.** Decades are included: "last decade" → the rolling ten years, then 2010–2019.
- **D40.** A fraction becomes the next smaller unit: "within half a year" is "next 6 months".
- **D44.** "2 upcoming weeks", "10 previous weeks" and "5 past minutes" are windows when the unit is plural. "3 next week" → nil.
- **D44.** "end of past week" and "beginning of past week" are the edges of last week, not of the window.

## Positions inside a period

### D2. Start, end, early, mid and late

- **"start" or "beginning of <period>"** is its first day: of month → the 1st.
- **"end of <period>"** is its last day: of month → the last day; of year → 31 December.
- **"end of week" is Friday,** in every locale. It is the current week's Friday, even once it has passed: said on Saturday, it is yesterday.
- **"end of day" and "EOD"** are 23:59:59. **D44.** "EOD tomorrow" and "end of day friday" are that day's end.
- **D44.** EOM, EOY, BOM and BOY are the end or start of this month or year.
- **Early, mid and late split a period into thirds:**

| Period | early | mid | late |
|---|---|---|---|
| month | 1st–10th | 11th–20th | 21st–end |
| year | Jan–Apr | May–Aug | Sep–Dec |
| decade | 1990–1993 | 1994–1996 | 1997–1999 |
| week | Mon–Tue | Wed–Thu | Fri–Sat |

- **"mid-month"** is the 11th to the 20th. **"midweek"** is Wednesday.
- A bare position follows D11: "early october" said on 17 October → October 2027, since this one's early part is over.
- **D42.** With a part of day, the part is picked inside the fuzzy span.
- **D44.** "middle" is "mid", and "mid" joins a word: "midmorning", "midsummer".
- **D44.** "early friday evening" said on a Friday has next Friday's as the alternative.

## Shifts and counts

- **D44.** Several counts are applied one by one, in the order said: "2 years 4 months ago" moves 2 years back, then 4 months.
- **D44.** A signed count is a shift: "+2 days", "-3y", "-2hr5min", "2023-12-29 -10days". A sign carries to the counts after it.
- **D44.** "m" after a count is minutes, never months.
- **D44.** Decimal counts are fractions: "in 2.5 hours" → 16:30. **D47.** They are written without spaces: "1. 5 hours" → nil.
- **D44.** "half an hour" and "half a year" are a half. **D47.** "half" takes a unit or an article, not a count: "half 3 hours" → nil. **D48.** "½" is "half".
- **D44.** "in" takes any length a duration does: "in an hour and a half", "in 1 hour 30".
- **D44.** "a couple of" and "a pair of" are two, before a unit only.
- **D44.** A shift in hours, minutes or seconds from an anchor counts elapsed time from it, at a grain no coarser than the unit: "two seconds before 1:00 PM" → 12:59:58.
- **D44.** A shift in days or longer from a longer anchor counts from its start: "1 day before next month" → the last day of this month. From a day or less it keeps the anchor's length: "a month from today" → 17 November, one day.
- **D44.** A span whose start the clocks skipped keeps its length.
- **D44.** A shift from now beside a fixed day moves that day: "3 years ago tomorrow".
- **D47.** A recurring day beside a shift looks in its own cycle: "3 months ago saturday at 5:00 pm" said on 16 August 2006 → Saturday 20 May, in the week three months back. Only an ordinal looks in the shift's unit: "first monday in 2 months" → the first Monday of that month.
- **D44.** A count of a recurring day is the nth one: "3 fridays from now" → 6 November, today's not counted. "2 thursdays ago" counts back among those over. "2nd monday before may 25" counts from the anchor.
- **D44.** "weekday" is a business day: "8 weekdays ago", "next weekday".
- **D44.** "back" after a count is "ago". **D48.** "out" after a length is "hence": "15 minutes out".
- **D44.** "now - 2 hours" is two hours ago.
- **D44.** "this time tomorrow" and "same time next week" keep the time of day.
- **D44.** "a week today", "tomorrow week" and "a week on tuesday" are that day a week on. "in 3 weeks' time" is "in 3 weeks". **D51.** So is "in a fortnight's time".
- **D44.** "1 quarter ago" is an instant, three months back.
- **D47.** Counts in words past ninety-nine are read: "fifteen hundred seconds", "a hundred days", "two million eight hundred thousand seconds from now". **D48.** "and" follows only hundred, thousand or million. A bare "hundred", "thousand" or "million" is one of them.
- **D47.** "5400s" before "ago", "from now", "later", "after" or "before" is that many seconds. Alone it is a decade or a year.
- **D50.** A decade written with an apostrophe or in words is never seconds: "in 70's" and "in nineties" are the decades; "in 30s" is still 30 seconds.
- **D48.** "after" with several lengths is a shift: "after 2 days, 3 hours and 1 minute".
- **D48.** A length after a date with nothing joining them is not a shift: "2004-05-05 12:00:00 CEST 6 months" → nil.

## Holidays

### D15. Holidays

- **Built in: holidays whose date is a formula,** chosen by the locale (D27). They never go out of date.
- **Without a `holidays:` option,** holidays outside the built-in set return nil. That includes lunar holidays ("chinese new year") and state holidays.
- **D47.** `holidays:` takes a region of the `holidays` gem (a Symbol, a String or an Array), or an object that answers `holiday?(date)` and `named(name, year)`.
  - `named` is asked first, with acute's Symbol (`:thanksgiving`), and returns a Date or nil. nil falls back to the built-in formulas.
  - A region loads the gem when it is first used. Without the gem installed, the option raises OptionError.
  - A gem holiday matches by its English name, with or without "Day".

### D28. Which holidays are built in

A holiday is built in if its date is a formula for the locale:
- a fixed date: Christmas, Juneteenth, Halloween;
- the nth weekday of a month: MLK Day, Thanksgiving, Memorial Day;
- an offset from Easter: Good Friday, Ash Wednesday, Pentecost;
- an offset from another holiday: Black Friday, Cyber Monday.

Holidays whose date isn't a formula stay out: lunar and Hebrew calendars, dates a government declares, and observed days. **D40.** Tax Day is out, since it moves off weekends and holidays.

- **The locale picks the formula:** "thanksgiving" → 26 November in New York, the second Monday of October in Toronto.
- **D44.** A holiday of one country resolves only in its locale. Elsewhere it is nil; `locale:` reaches it.

| Holiday | Locales |
|---|---|
| Australia Day, Melbourne Cup | AU |
| Anzac Day | AU, NZ |
| Canada Day, Victoria Day, Vimy Ridge Day | CA |
| Mothering Sunday | GB, IE |
| Guy Fawkes Night | GB |
| Day of Reconciliation, Kruger Day | ZA |
| Rizal Day | PH |
| Indian Arrival Day | TT |
| Garifuna Settlement Day | BZ |

- **D44.** In GB and IE, "mother's day" is Mothering Sunday, three weeks before Easter.
- **D48.** May Day is the first Monday of May in GB and IE, and 1 May elsewhere. International Workers' Day is 1 May everywhere.
- **D44.** Fixed dates also built in: Boss's Day (16 October), Flag Day (14 June), Patriot Day (11 September), Earth Day (22 April), Groundhog Day (2 February).
- **D40.** Election Day is the first Tuesday from 2 November.
- **D48.** Also built in: Administrative Professionals' Day, Grandparents' Day, Military Spouse Day, Lincoln's Birthday, Law Day, Loyalty Day, Siblings Day, World Vegan Day, Kwanzaa and the Ides of March.
- **D48.** Other names for these are read: "fourth of july", "st paddy's day", "civil rights day", "washington's birthday", "decoration day", "pancake day" and more.
- **D48.** A holiday of several days names its first day, then all of them: "kwanzaa" → 26 December, then 26 December to 1 January.

## Business days and fiscal years

### D17. Business days and fiscal years

- **Business days** are Monday to Friday. **D47.** A `holidays:` option also takes its holidays out. A `business_days:` object that answers `business_day?(date)` decides instead. The built-in holidays only name days; they are not days off.
- **D38.** "in N business days" keeps the time of day: "in 3 business days" → Wednesday 14:00.
- **D49.** More than 10,000 business days (about 40 years) in one call is a failure, not a long wait: "in 10001 business days" → nil, and `parse!` says so. Every count in a call draws on the 10,000, so in one `extract` of "in 6000 business days or in 6000 business days" the second is not a time. So is a `business_days:` object that says 10,000 days in one call are not business days. Days and weeks are plain arithmetic and have no limit.
- **Fiscal years** need `fiscal_year_start:`, the month the year starts. Without it, "FY27" → nil.
- **D38.** "FY27" is the fiscal year that ends in 2027: with `fiscal_year_start: 7` → 1 July 2026 to 30 June 2027.
- **D44.** "this/next/last fiscal year" (or "financial year") count from the fiscal year holding today.

## Time zones

### D18. Zones and offsets in the text

- **A zone or offset in the text wins over the zone given** (`fixed_offset`). "3pm +02:00" is that instant.
- **An offset runs up to 23:59 either way,** in the text and in `zone:`. "3pm +24:00", "+05:75" and "JST+23:00" are nil, and `zone: "+24:00"` is an unknown zone.
- **Abbreviations are fixed offsets,** whatever DST is in force (**D40.**). "3pm EST" is −05:00 even in summer.

| Abbreviations | Offset |
|---|---|
| UTC, GMT, Z | +00:00 |
| EST, EDT | −05:00, −04:00 |
| CST, CDT | −06:00, −05:00 (always US Central) |
| MST, MDT | −07:00, −06:00 |
| PST, PDT | −08:00, −07:00 |
| CET, CEST | +01:00, +02:00 |
| JST | +09:00 |

- **D44.** Also fixed: AEST/AEDT, MSK, HST, AKST/AKDT, EET/EEST, NZST/NZDT, ACST/ACDT, AWST, SGT, HKT and KST. WET and WEST are not read; they are English words.
- **D44.** "ET", "eastern", "eastern time", and likewise CT, MT, PT, central, mountain, pacific, "alaska time" and "hawaii time", are the US zones with their clock changes. "Eastern Daylight Time" and the other full names are fixed.
- **D44.** An IANA name after a time is that zone, with its clock changes: "12:59:59 America/New_York". **D47.** Its repeated and skipped wall times are reported as D23's are.
- **D44.** A zone in the text also reckons the day: "tomorrow, 10pm pacific" said at 00:30 in New York is tomorrow in California.
- **D44.** A sign after a zone name is its offset when joined on one side ("GMT-1", "UTC +8"). With spaces on both sides it is a range.
- **D44.** A zone in brackets is the zone: "9 am (BST)". A second zone after one only labels it, so "GMT+0800 (CST)" is +08:00.
- **D42.** A dash offset follows a clock when it has a space before it and none after: "15:45 -0800". "3:00 - 5:00" stays a range.

### D38. Ambiguous zone abbreviations

An abbreviation that names more than one zone gives each one's offset as a reading, in order (`ambiguous_zone`).

| Abbreviation | Readings |
|---|---|
| IST | India (+05:30), Ireland (+01:00), Israel (+02:00) |
| BST | in GB: British Summer Time alone; elsewhere: British (+01:00), then Bangladesh (+06:00) |

**Zone data:**
- **D43.** Zone tables start in 1800. Before standard time, a zone uses local mean time: "1530" in New York starts at −04:56:02.
- **D47.** Clock changes continue to 2200, past where the shipped data stops, for zones whose yearly rule is regular. "2079-07-04 12:00" in New York is −04:00. A zone whose changes stopped stays as it ends.
- **D43.** A wall time the clocks repeat keeps its side when it comes from an instant: "in 3 hours" said at 23:30 on 31 October 2026 in New York is the second 01:30 (EST), and "2026-11-01 01:30 EST" is that one too.
- **D43.** Retired: a zone once had to be loaded in the main Ractor before another Ractor used it. The zone data now ships with acute, so any Ractor can use any zone.

## Words and strictness

### D22. Strict by default

Text with words acute doesn't know returns nil. "meet bob tuesday" → nil; extraction is a separate call.

- **D47.** `strict: false` returns the first time in the text, found as `extract` finds it, with `unknown_words_skipped`. "meet bob tuesday" → Tuesday. `text` is the input and `matched` the part used. It applies only when there is an unknown word: a phrase acute knows every word of and refuses for its meaning stays nil.
- **D18.** Misspellings come from a small fixed table ("tommorow", "wensday", "febuary", "untill"). There is no fuzzy matching.
- **D18.** Lists of dates ("mon, wed and fri") → nil. Extraction finds each one.
- **D43.** Words have no length limit. A number keeps its first nine digits.
- **D44.** "right now", "just now", "at the moment" and "at present" are now. **D48.** "ATM" is not.
- **D44.** Unicode spaces and dashes are spaces and dashes: "8 pm" with a narrow no-break space, "tue – thu".
- **D51.** A curly apostrophe is an apostrophe: "in a fortnight’s time".
- **D44.** "Tu" and "Fr" are Tuesday and Friday. In extraction they need a date beside them. **D48.** "mon" is Monday, not the month.
- **D44.** "qtr", "wkend", "oclock" and "lunch time" are spellings of quarter, weekend, o'clock and lunch.
- **D44.** "!" or "?" at the end is dropped.
- **D48.** A possessive reads as its word: "tomorrow's", "this year's summer".
- **D48.** "for" and "during" before a time are dropped: "for the past month", "during March". Before a length, "for" makes a duration (E2).
- **D48.** Brackets around a word are dropped.

## Extraction

`Acute.extract` finds the times in a longer text. Each mention has its start and end offsets, and `remainder` is the text left over.

- **E2.** A duration's mention includes its "for": "for 2 hours". "4pm for 30 mins" is two mentions, a time and a duration. As one phrase to `parse` it is nil.
- **E3.** A mention needs something beyond plain lowercase English words. "may" in "this may or may not work" is not a date, and a lone number is not a mention.
  - A capital at the start of a sentence doesn't count: "Lunch with Sam" has no mention, but "May 3" does.
  - **D48.** "during" doesn't start a mention.
  - The remainder drops an "on", "at", "for", "by" or "in" left dangling before a mention: "flight back on the 30th" leaves "flight back".
  - **D50.** Numbers written as words with no time word beside them are plain English: "two to four people", "One may ask", "The first free fish", "the twenty second". A numeric ordinal still counts ("the 5th"), and so do written numbers that read as a time together or with a month: "eight forty", "fourth of may".
  - **D50.** An ordinal before "time" or "times" counts occasions: "17th times", "the 5th time".
  - **D50.** "Good morning", "Good night" are greetings: a part of the day right after "good" is no mention.
  - **D50.** Nothing starts right after a currency sign: "$12 December 27" mentions "December 27", and "$DEC" is a ticker.
  - **D50.** Nothing is found inside a word or an id: a mention whose first or last character touches a letter or digit, as "3am" in "~.~3am3ioY", is none.
  - **D50.** The same number at both ends is no range: "a 1-1 meeting".
  - **D50.** A month abbreviation alone right before another month is a name: "Angie Mar November 2019" mentions "November 2019".
  - **D50.** "start" and "end" in lower case are verbs unless "of" follows: "Let's start 3 minutes from now" mentions "3 minutes from now", "it will end two months after next Friday" "two months after next Friday"; "end of May" is one mention.
  - **D51.** A lone year joined by "and", "or" or "not" to a mention that ends in a year is a year too: "in 2007 and 2009", "before 2000 but not 1998". "sales of 2007 and 2009" has none, as nothing comes before.
  - **D51.** A month after "in" is a month: "It may be in may" mentions "in may".
  - **D51.** A number right after a noun that numbers things labels it: "building 4 this afternoon" mentions "this afternoon". The nouns are building, room, floor, level, gate, platform, terminal, suite, unit, table, track, bay, page and chapter.
  - **D51.** Three dotted numbers with a one-digit day or month and a two-digit year are a version: "1.5.30 - 2015-09-24" mentions only "2015-09-24". Alone, as one phrase to `parse`, "3.5.79" is still a date.
- **E4.** A mention starts at its first word that changes the reading. "the" belongs to the phrase, as a determiner, and stays: "the 30th", "the day before yesterday", "the weekend". A leading "in", a preposition that introduces the phrase, is left out when the rest reads the same: the same begin and end for every reading, and the same alternatives. "She is leaving in August" mentions "August", and "in the morning" is "the morning". It stays when dropping it changes or breaks the reading: "in 3 days" is a shift, and "in 2016" without its "in" is a lone number.
  - "on" and "at" never start a mention: "on Tuesday" is "Tuesday", "at 4 a.m." is "4 a.m.". Where what follows is no mention by itself, nothing is found ("at 6.45", as in "at 6.45 percent").
  - Words that change the reading by meaning stay: "from", "between", "within", "after", "before", "since", "until", "by", "about", "around".
  - **D50.** The leading "in" is also left out when the rest reaches further: "in 2 days from today" is "2 days from today". A meal right before "at" is left out the same way: "LUNCH AT 12:30 PM" is "12:30 PM", while "lunchtime 12 o'clock" keeps it.
  - **D50.** A mention doesn't end in a word that only introduces what follows ("on", "the", "at", "and", "of", "to", "in", "for", "by"): "May 6th 2004, the customer" mentions "May 6th 2004".
  - **D51.** "about" and "within" are left out too when the rest reaches further: "How about year 2016 and greater" is "year 2016 and greater", "within 2 weeks before yesterday" is "2 weeks before yesterday".
  - **D51.** A "for" that makes a span from a start belongs to the mention: "set OOO for 3 days, from today" is "for 3 days, from today", three days from today, where "3 days from today" alone is a shift.
  - **D51.** A bare number at a mention's end goes with what follows when it starts a mention that reaches further: "11/20, 12 of Nov" is "11/20" and "12 of Nov".
- **E5.** A dot right after a month, weekday or meridiem ends its abbreviation, not the sentence: "Oct. 2", "Dec. 2021", "1p.m. to 4" are one mention each, unless a capital follows. A meridiem written with dots keeps its last one ("4 a.m.", "3 p . m ."), and a decade its apostrophe ("'40s").
- **D43.** A malformed clock ("4:3") is one unknown word, so the rest of the text is still searched.
- **D44.** No mention starts inside a written number: nothing in "123-12-1234".
- **D44.** A mention includes its "this", "next" or "last": "this Q3".
- **D38.** A mention can carry alternatives, like a Result.

## Durations

`Acute.duration` reads a length of time.

- **D42.** A Duration keeps its calendar parts. `seconds` raises for months, years and business days, which have no fixed length.
- **D42.** A weeks-only duration stays `PnW` in ISO 8601: "2 weeks" → P2W. Beside other parts, weeks become days (**D44.**): "2 weeks and 3 days" → P17D.
- **D42.** Business days have no ISO form, so `iso8601` returns nil.
- **D44.** A fraction goes to the next smaller unit: "1.5 hours" → 1h 30m, "3.5 years" → 3y 6mo. A fraction of a second stays: "123.45 sec" → PT123.45S.
- **D44.** A bare number last, after hours or minutes, is the next smaller unit: "1 hour thirty", "2 minutes 30". Not after days: "2 days 5" → nil.
- **D44.** "for" before a duration, and "more", "extra" or "additional" after its count, change nothing: "2 more minutes". So does a dash: "3-min".
- **D45.** "5400s" is 5400 seconds as a length, whatever the digits.
- **D47.** `Acute.duration!` raises the ParseError that `duration` returns nil for, with the same codes as `parse!`.
- **D47.** `Duration#after(time)` is the Time "<duration> from <time>" reads as: years and months on the calendar first, then weeks and days on the wall clock, then hours to seconds elapsed (D23). Business days skip weekends and a `holidays:` given. `seconds(from: time)` is the seconds between them.

## Recurrence

`Acute.recurrence` reads a repeating time as an iCalendar rule (RFC 5545). It comes in 0.3: the corpus holds these rules already, and acute doesn't read rules yet. Where iCalendar has its own meaning, the rule keeps it.

- **R1.** A rule is a DTSTART, an RRULE and any EXDATE. `rrule` is the RRULE value alone; `to_ical` gives all three lines. With a clock, DTSTART is `DTSTART;TZID=<zone>:<wall time>`, the zone given, UTC too; without one, the rule is of whole days: `DTSTART;VALUE=DATE:20261019`. EXDATE takes DTSTART's form, and UNTIL a date or, with a clock, a UTC time.
- **R2.** DTSTART is the first occurrence on or after now. A day under way counts and a passed clock doesn't: "every saturday" said on Saturday starts today, "every saturday at 10am" said at 14:00 next Saturday. A clock equal to now is now (D36).
- **R3.** A rule that names no day starts today: "weekly" → DTSTART today, FREQ=WEEKLY. One finer than a day, with no clock, starts at now to the second: "every 15 minutes" said at 14:07:31 → 14:07:31.
- **R4.** A clock is also BYHOUR and BYMINUTE, so `rrule` stands alone: "every day at 9am" → FREQ=DAILY;BYHOUR=9;BYMINUTE=0. It is read as D4, D30 and D35 read it, first reading only, as a rule has no alternatives: "every day at 9" is 9am, "every evening at 7" 19:00. Several clocks with the same minute are listed ("at 8:30 and 17:30" → BYHOUR=8,17;BYMINUTE=30). Otherwise they need two rules, so nil: "every day at 9am and 5:30pm".
- **R5.** Frequency words and intervals. "daily", "weekly", "monthly", "annually", "hourly"; "once a week" is weekly. "quarterly" is every 3 months, "semi-annually" every 6 (iCalendar has no quarter). "biweekly" and "fortnightly" are every 2 weeks, "bimonthly" every 2 months, not twice. "every other X" and "every second day" are INTERVAL=2: an ordinal with a unit is an interval.
- **R6.** A weekday repeats weekly: "every monday", "mondays", "on mondays" → FREQ=WEEKLY;BYDAY=MO. A plural weekday alone is a rule ("fridays"), where `parse` gives nil (D44). "weekdays" is Monday to Friday and "weekends" Saturday and Sunday (D8). A list keeps them all: "every monday and wednesday" → BYDAY=MO,WE. A rule that picks weekdays is weekly, even after "every day": "every day except sundays" → FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR,SA.
- **R7.** "every other friday" counts from the first Friday on or after now (R2), every 2 weeks: said on a Friday, from today.
- **R8.** An ordinal with a weekday is within the month: "every first monday" → FREQ=MONTHLY;BYDAY=1MO, "the 2nd and 4th tuesday" → BYDAY=2TU,4TU. "every second tuesday" is the month's second Tuesday; every two weeks is "every other". "the last friday" is -1FR, "the second to last" -2FR. "the last day of every month" → BYMONTHDAY=-1. "the last weekday of every month" → BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1, the first BYSETPOS=1.
- **R9.** A day of the month repeats monthly, a date yearly: "19th of every month" → FREQ=MONTHLY;BYMONTHDAY=19; "every january 1st" → FREQ=YEARLY;BYMONTH=1;BYMONTHDAY=1. Months or years without the day are skipped, as iCalendar does and as D42 skips one-off dates: "every 31st", "every feb 29" (from 2028). A date that never occurs is nil: "every feb 30".
- **R10.** "until" includes its end, as D9 does: "every monday until december" → UNTIL=20261231. With a clock, UNTIL is the last second of that day, in UTC: "every day at 9am until friday" → UNTIL=20261024T035959Z. "until 5pm" is that instant, and an occurrence at it counts: UNTIL is inclusive in iCalendar. "through" is "until" (D16). A date without a year looks forward (D34).
- **R11.** A count is COUNT, from DTSTART: "every other friday 5 times" → COUNT=5. A length runs from DTSTART, its end left out, as UNTIL: "every monday for 6 weeks" → six Mondays, UNTIL=20261129. A length in days or longer ends on a whole day (R10); "every 10 minutes for an hour" ends a second before the hour is up.
- **R12.** An excepted weekday leaves BYDAY: "every weekday except fridays" → BYDAY=MO,TU,WE,TH. An excepted date, read as a one-off (D23), is an EXDATE: "every monday except november 2" → EXDATE;VALUE=DATE:20261102. "every day at 9am except halloween" → EXDATE;TZID=America/New_York:20261031T090000.
- **R13.** "starting X" moves DTSTART to the first occurrence on or after X begins: "every monday starting november" → 2 November. "in X" also ends the rule with X: "weekends in july" → 3 July 2027 to UNTIL=20270731.
- **R14.** Clock changes don't change the rule. DTSTART is the wall time said, even in a repeated hour or a gap ("every day at 2:30am" from 14 March 2027); iCalendar moves a gap's time forward by the gap, as `dst: :compatible` does (D23). UNTIL takes the offset in force at its own instant: "every day at 9am until november 15" → DTSTART in EDT, UNTIL=20261116T045959Z in EST.
- **R15.** These are no rule, so nil: a count per period with no days or times ("twice a week", "3 times a day"); a part of the day with no clock ("every morning"); "every 0 days"; and one-off times ("next friday", "this weekend", "3 days", "each of us at 3pm").

## The API

### read

- **D45.** Text that is both a time and a length is the time, and the Result carries `also_duration`: "1530 hrs", "15h30", "70s". `Acute.duration` gives the length.

### JSON

- **D45.** A Duration's JSON is `kind`, `parts`, `iso8601` and `seconds`. `seconds` is null when a part has no fixed length.
- **D45.** `as_json` gives String keys on every value object.
- **D45.** The schemas are [schema/result.json](../schema/result.json), [duration.json](../schema/duration.json), [extraction.json](../schema/extraction.json) and [verdict.json](../schema/verdict.json). The others in [schema/](../schema) are for the [agent tools](agents.md).

### describe

- **D45.** `describe` writes the most natural phrase that acute reads back to the same value with no alternatives. It tries, in order:
  1. words relative to now: "now", "today", "tomorrow at 9am", "Friday", "last Friday", "this week", "next month";
  2. the date: "Sun, Oct 18, 9am";
  3. then with the year, the zone's abbreviation, and the offset;
  4. ISO 8601, which always reads back.
- **D45.** `style: :calendar` never uses words relative to now. Day-first locales write "Sun 18 Oct, 9am".
- **D45.** A Result with no `zone:` given is described in its own zone.
- **D45.** What reads back is an instant's moment, or a span's begin and end. Grain is not kept.
- **D45.** A Range of Times ends where it says. A Range of Dates includes its last day unless it uses `...`. A range with no ends, an empty or backwards range, or a day the zone skipped raises ArgumentError.
- **D45.** A clock range on one day drops the first meridiem when both share it: "today, 2–5pm".
- **D45.** A Duration's hours, minutes and seconds carry upward, never into days: 5400s → "1h 30m", 48h stays "48h".

### verify

- **D45.** The value may be a Time, a Date, a Range of either, or an ISO 8601 string. A string is read in the same zone: "2026-10-23T15:00" is 3pm there.
- **D45.** A date is checked by its days, a time by its instant. "2026-10-23" matches "next friday 3pm".
- **D45.** The statuses, checked in this order:

| Status | Meaning | `ok?` |
|---|---|---|
| `:match` | the first reading is the value | true |
| `:inside` | the value lies within the first reading | true |
| `:alternative` | the value matches or lies within a later reading | true |
| `:mismatch` | anything else | false |
| `:unparsed` | the text can't be read | false |

- **D45.** Messages write days as "Fri 23 Oct" whatever the locale, and add the year only when it isn't now's.
- **D45.** A Verdict's JSON is `kind`, `text`, `status`, `ok`, `message` and `expected`.

### with

- **D45.** `Acute.with(**options)` checks its options once, so a bad zone or option raises when the parser is made. Unknown options raise ArgumentError everywhere, and a bad value for a known option raises `Acute::OptionError` (an ArgumentError that names the `option` and `value`).
- **D45.** Options given to a call override the parser's. `Parser#with(**more)` makes a new parser.
- **D45.** A `now:` that carries a zone (a TimeWithZone, or a Time made with a TZInfo zone) gives the parser that zone. With no `now:` and no `zone:`, the zone is inferred on each call (`zone_inferred`).
- **D45.** A `TZInfo::Timezone`, given as `zone:` or carried by `now:` or Rails' `Time.zone`, is read by its name from acute's own data, so every way into a zone gives the same answer. Only a name acute doesn't ship is built from the zone's own transitions. acute never loads tzinfo.
- **D45.** The parser is frozen and Ractor-shareable. **D47.** A `holidays:` or `business_days:` object is kept as given, so the parser is shareable only when that object is.
- **D47.** `duration`, `extract` and `describe` take every option, and ignore those that can't change their answer.

### The command line

- **D45.** `acute "next friday 3pm"` prints the reading in describe's calendar style, with the zone's abbreviation, then any alternatives as "(also: …)". A Duration prints as "1h 30m".
- **D45.** With no arguments, it reads one phrase per line from stdin and prints exactly one line for each. A failure prints `error: <reason>`; with `--json`, a JSON line `{"kind":"error",...}`.
- **D45.** Exit codes: 0 when everything parsed, 1 when a phrase failed, 2 for bad options.
- **D45.** The options are the context options with dashes (`--now`, `--zone`, `--locale`, `--context`, `--week-start`, `--hemisphere`, `--fiscal-year-start`, `--dst`, `--holidays`, `--year-bias`), plus `--lenient` for `strict: false` and `--json`. They are all in [cli.md](cli.md).

## Compatibility layers

`require "acute/chronic"` and `require "acute/chronic_duration"` give the APIs of those gems, read by acute.

**The chronic layer:**
- **D46.** `guess: true` and `:middle` take the middle of the span on the wall clock, so a day's guess is noon. **D47.** A clock time someone said stays its instant: "4pm", "monday 3pm". Every other span is guessed, so "next hour" at 14:00 is 14:30.
- **D46.** `guess: false` always returns a Span.
- **D46.** Any `context` but `:past` is future.
- **D46.** `week_start` defaults to the locale (D19). `endian_precedence` reorders numeric dates only when given. **D37.** The other order is still an alternative.
- **D46.** Words acute doesn't know are skipped, as `strict: false` does (D22). A phrase acute knows every word of and refuses stays nil.
- **D46.** `hours24: true` reads a bare hour as written. `ambiguous_time_range` sets D4's window. A leading-zero hour is 24-hour either way (D29).
- **D46.** `ambiguous_year_future_bias` is acute's `year_bias:`.
- **D46.** A fraction of a second written in the text is kept (D47).
- **D46.** Not read: a dot between a clock's minutes and seconds ("5:32.19pm"), and "10 to" or "10 till" with no hour.
- **D46.** Misspellings outside acute's table ("satterday") → nil.

**The ChronicDuration layer:**
- **D46.** Every phrase either gem reads gives the same seconds, at the gems' fixed lengths: a 365.25-day year, a 30-day month, a 7-day week, a 24-hour day.
- **D46.** Where the gem would skip a word, acute reads it: "half an hour" → 1800, "1 fortnight" → two weeks.
- **D46.** `raise_exceptions` raises only when acute can't read the text either.
- **D46.** A clock group counts wherever it stands: "2 days, 4:13:02".
- **D46.** `days_per_week` and `days_per_month` are both settable; the one set last counts.
- **D46.** `output(format: :chrono, weeks: true)` returns the clock form.
- **D46.** Neither `parse` nor `output` changes the options passed.

## Assumptions

Every code a result can carry. `rule` is nil only for `zone_inferred`, which records a fact rather than a convention.

| Code | Rule | Message |
|---|---|---|
| `bare_hour_window` | [D4](#d4-a-time-of-day-without-ampm) | no am/pm given: 6-11 read as am, 12 and 1-5 as pm; the other half of the day is an alternative |
| `next_occurrence` | [D23](#d23-future-context-two-digit-years-whole-units-arithmetic-and-dst) | that time has passed today, so it means the next one |
| `previous_occurrence` | [D23](#d23-future-context-two-digit-years-whole-units-arithmetic-and-dst) | that time is still to come today, so in past context it means the previous one |
| `equal_to_now` | [D36](#d36-a-time-equal-to-now) | that time is now |
| `twelve_oclock` | [D30](#d30-the-12-oclock-hour) | a time in the 12 o'clock hour without am/pm is read as pm |
| `midnight_end_of_day` | [D6](#d6-midnight-with-a-day) | midnight with a day means the end of that day; its start is an alternative |
| `machine_time` | [D29](#d29-times-that-look-machine-written) | seconds were given, so the time is read as 24-hour |
| `tomorrow_after_midnight` | [D35](#d35-parts-of-the-day-in-detail) | "tomorrow" said before 04:00 means the coming day first; the calendar tomorrow is an alternative |
| `dst_repeated_time` | [D23](#d23-future-context-two-digit-years-whole-units-arithmetic-and-dst) | that wall time happens twice as clocks go back; the earlier one is used |
| `dst_skipped_time` | [D23](#d23-future-context-two-digit-years-whole-units-arithmetic-and-dst) | that wall time doesn't exist as clocks go forward; it is moved forward by the gap |
| `approximate` | [D14](#d14-approximate-times) | the time was given as approximate; the exact time is returned |
| `fixed_offset` | [D18](#d18-zones-and-offsets-in-the-text) | the text names a zone or offset, which wins over the zone given |
| `ambiguous_zone` | [D38](#d38-ambiguous-zone-abbreviations) | the zone abbreviation names more than one zone; each one's offset is a reading, in order |
| `numeric_date_order` | [D10](#d10-numeric-dates) | a numeric date is read in the locale's order; the other order is an alternative |
| `part_of_day_point` | [D1](#d1-part-of-day-words) | a part of the day is a range; its time is a representative point |
| `weekend_friday_evening` | [D8](#d8-weekend) | the weekend is Saturday 00:00 to Monday 00:00; from Friday 18:00 is an alternative |
| `meteorological_season` | [D3](#d3-seasons) | seasons are meteorological (three whole months) for the locale's hemisphere |
| `century_from_00` | [D12](#d12-centuries-and-decades) | a century runs from its 00 year, as most people count it; the 01-to-00 reading is an alternative |
| `decade_or_century` | [D12](#d12-centuries-and-decades) | a decade at a century's start ("the 2000s") is the decade; the whole century is an alternative |
| `season_year` | [D3](#d3-seasons) | a season that runs over New Year belongs to the year it starts in; the one ending in that year is an alternative |
| `range_under_way` | [D11](#d11-a-named-period-on-its-own) | the range is under way, so it means the current one; the coming one is an alternative |
| `same_day_or_next` | [D11](#d11-a-named-period-on-its-own) | that day is today, so it means today; the next one is an alternative |
| `same_day_passed` | [D11](#d11-a-named-period-on-its-own) | that day is today but today's has passed (or, said looking back, has not come yet), so the other one comes first; today's is an alternative |
| `next_two_readings` | [D20](#d20-next-friday) | "next" can mean the coming one or the one after; both are given, the coming one first |
| `this_passed` | [D21](#d21-this-friday-once-friday-has-passed) | that one has passed in the current period, so the next one comes first; the passed one is an alternative |
| `rolling_window` | [D31](#d31-windows-of-weeks-months-quarters-and-years) | a span counted from now; whole calendar units are alternatives |
| `zone_inferred` | none, see [with](#with) | no zone was given; the zone comes from now, Time.zone or the system |
| `weekday_mismatch` | [D37](#d37-numeric-dates-in-detail) | the weekday given doesn't fall on that date, so the date is used |
| `also_duration` | [D45](#read) | the text also reads as a length of time, which Acute.duration gives; read takes the time |
| `unknown_words_skipped` | [D22](#d22-strict-by-default) | strict: false skipped words acute doesn't know; this is the first time in the rest of the text |
