# acute and chronic

Read this if you use chronic: why acute replaces it, how to move over, and how much faster it is.

## Why acute exists

chronic made parsing "next tuesday at 3pm" a one-liner for more than a decade, and it has over 130 million downloads. But it has stood still:

- **It is unmaintained.** There has been no release since 0.10.2 in 2013, and more than 120 issues are open.
- **It doesn't really do time zones.** The zone is one global setting, `Chronic.time_class`, so there is no per-call zone and no thread-safe way to change it (its top open issue, [#182](https://github.com/mojombo/chronic/issues/182)). It also assumes every day has 24 hours, which breaks around daylight-saving changes.
- **It guesses silently.** Words it doesn't know are skipped, so "a banana" parses as a time and "4/32" as a date in 2032.
- **It isn't comprehensive enough.** Many everyday phrases return nil or raise.

Said on Saturday 17 October 2026 at 14:00 in New York:

| Phrase | chronic 0.10.2 | acute |
|---|---|---|
| "a banana" | today 13:00 | nil |
| "4/32" | 16 April 2032 | nil |
| "last 14 days" | yesterday 14:00 | 3 Oct 14:00 to 17 Oct 14:00 |
| "2nd thursday of june" | nil | 10 June 2027 |
| "christmas eve" | nil | 24 December 2026 |
| "1 year, 7 months ago" | raises NoMethodError | 17 March 2025, 14:00 |
| "1 day from now", at noon on 31 Oct | 11:00 on 1 Nov (24 hours across the clock change) | 12:00 on 1 Nov |
| "march 8 2026 2:30am" (skipped by DST) | 01:30 EST | 03:30 EDT |

acute is a rewrite from scratch, with a different design:

- every call takes its own `now` and zone, and daylight saving is handled properly;
- it reads a wide range of phrases, checked against more than 18,000 cases gathered from chronic and a dozen other date parsers;
- when a phrase could mean more than one thing, it says which reading it chose, and why;
- it runs 20–100× faster than chronic, 80–300× under YJIT ([measured](#performance)).

**About the name.** In medicine, a *chronic* condition lingers for years, and an *acute* one is short and sharp. chronic has lingered since 2013. acute is short, sharp and over in a few microseconds.

## Moving over

`require "acute/chronic"` gives you chronic's API, `Chronic.parse` with chronic's options, answered by acute. `require "acute/chronic_duration"` does the same for chronic_duration, and `require "acute/numerizer"` for numerizer.

```ruby
require "acute/chronic"

Chronic.parse("tomorrow 3pm", now: Time.now)
```

Each layer marks the real gem as loaded, so a gem that does `require "chronic"` (`gitlab-chronic`, `chronic_duration` or `gitlab_chronic_duration`, `numerizer`, likewise) afterwards gets acute's and doesn't replace it. If the real gem was loaded first, the layer warns once to require the layer first, or drop the gem; acute's methods override the gem's either way. The layer must be on `$LOAD_PATH`, as it is when installed.

The answers follow acute's rules, so a few differ from chronic's. chronic's own test suite runs against this layer, and every place it disagrees is listed, with its rule, in [test/chronic/differences.yml](../test/chronic/differences.yml). The [compatibility notes](rules.md#compatibility-layers) explain how each option is read.

## Performance

`bin/bench-chronic` times chronic 0.10.2, the gem itself, and acute on ten everyday phrases ("tomorrow", "next tuesday 3pm", "3 days ago", "27/5/1979"…), in CPU time per parse, best of five rounds. Run it with `ruby bin/bench-chronic`, then `ruby --yjit bin/bench-chronic`; it needs `gem install chronic -v 0.10.2`. On Ruby 4.0.7 on an i5-13600K:

| | chronic 0.10.2 | acute | faster by |
|---|---|---|---|
| interpreter | 260–490 µs | 5–19 µs | 20–100×, median about 50× |
| YJIT | 350–650 µs | 1.5–8 µs | 80–300×, median about 150× |

The machine was busy, so read the ratios rather than the last digit; runs moved them by about 20%. Roughly, chronic manages two or three thousand parses a second per core, and acute around a hundred thousand, or several hundred thousand with YJIT. acute's own speed budget is checked on every commit.
